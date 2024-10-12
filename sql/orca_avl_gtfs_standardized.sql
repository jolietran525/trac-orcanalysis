/*----- DATA PREPROCESSING -----*/

/* --------- Part 1: ORCA Boardings within specific time window from GTFS --------- */

-- create a view for GTFS route that have the valid start and end date for each route
	  -- for the routes with the same trac_agency_id, route_short_name, route_long_name, start_date, and end_date
	  -- we choose the routes with the higher feed_id, as it's more updated
CREATE VIEW _test.latest_gtfs_feeds AS (
	WITH latest_feed AS (
		SELECT DISTINCT
			   f.feed_id
			 , r.route_id
			 , r.route_short_name
			 , r.route_long_name
			 , f.agency_id AS trac_agency_id
			 , min(c.start_date) start_date
			 , max(c.end_date) end_date
			 , ROW_NUMBER() OVER (
			 	PARTITION BY   f.agency_id
			 				 , r.route_short_name
			 				 , r.route_long_name
			 				 , min(c.start_date)
			 				 , max(c.end_date)
			 	ORDER BY f.feed_id DESC
			 ) AS latest_feed_rank
	    FROM _test.real_transitland_routes r 
	    JOIN _test.real_gtfs_feeds f
	    	ON r.feed_id = f.feed_id
	    JOIN _test.real_transitland_trips t
	    	ON t.feed_id = r.feed_id
	    		AND t.route_id = r.route_id
	    JOIN _test.real_transitland_calendar c
	    	ON c.feed_id = t.feed_id
	    		AND c.service_id = t.service_id
	    GROUP BY r.route_id, f.feed_id, f.agency_id, r.route_short_name, r.route_long_name )
	SELECT feed_id
		   , route_id
		   , route_short_name
		   , route_long_name
		   , trac_agency_id
		   , start_date
		   , end_date
	FROM latest_feed
	WHERE latest_feed_rank = 1
);

SELECT DISTINCT(trac_agency_id) FROM _test.latest_gtfs_feeds;

	
	  
	  
-- test with transactions within April 2023
	-- txn must have device_location NOT null OR stop_code NOT NULL
		-- for txn where BOTH stop_code and device_location is NULL, we cant verify this kind of data or standardize it
	-- when joining ORCA with GTFS there might be several matched as the date could be overlapping
	  	-- if this is the case, then we do ROW_NUMBER to only take mopt updated option
CREATE TABLE _test.boarding_april23 AS (
	WITH orca_with_latest_feed AS (
		SELECT   gtfs.feed_id
			   , gtfs.route_id -- we would use route_id, feed_id, and trac_agency_id TO JOIN btw orca AND gtfs later
			   , gtfs.trac_agency_id 
			   , orca.*
			   , ROW_NUMBER() OVER (
			   		PARTITION BY orca.txn_id
			   		ORDER BY gtfs.feed_id DESC ) AS latest_gtfs
		FROM orca.v_boardings orca -- orca
		LEFT JOIN trac.route_name_lookup lookup
			ON orca.route_number = lookup.route_number
				AND orca.service_agency_id = lookup.service_agency_id -- the lookup uses service_agency_id INSTEAD OF source
		JOIN trac.agencies trac -- lookup TABLE for agency_id BETWEEN orca AND gtfs
			ON trac.orca_agency_id = orca.source_agency_id
				OR trac.agency_id = lookup.trac_agency_id
		JOIN _test.latest_gtfs_feeds gtfs -- gtfs route valid START and END date
			ON (gtfs.route_short_name = orca.route_number
				OR COALESCE(gtfs.route_short_name, gtfs.route_long_name) ILIKE lookup.gtfs_route_name)
			   AND orca.business_date BETWEEN gtfs.start_date AND gtfs.end_date
			   AND gtfs.trac_agency_id = trac.agency_id
		WHERE (orca.device_location IS NOT NULL OR orca.stop_code IS NOT NULL) 
			  AND orca.business_date BETWEEN '2023-04-01' AND '2023-04-30'
	)
	SELECT *
	FROM orca_with_latest_feed
	WHERE latest_gtfs = 1
); -- 5,016,712




-- how many transaction in total in April 2023?
SELECT count(*) FROM orca.v_boardings
WHERE (device_location IS NOT NULL OR stop_code IS NOT NULL)
	  AND business_date BETWEEN '2023-04-01' AND '2023-04-30'; --5,025,858

-- how many that we get eliminated because no data available?
SELECT count(*) FROM orca.v_boardings
WHERE (device_location IS NULL AND stop_code IS  NULL)
	  AND business_date BETWEEN '2023-04-01' AND '2023-04-30'; --203,282

-- why only 5,016,712 get into the table??
SELECT DISTINCT og.source_agency_id, og.service_agency_id, og.route_number, count(*)
FROM orca.v_boardings og
LEFT JOIN trac.route_name_lookup lookup
	ON og.route_number = lookup.route_number
		AND og.service_agency_id = lookup.service_agency_id
LEFT JOIN _test.boarding_april23 april
	ON og.txn_id = april.txn_id
WHERE (og.device_location IS NOT NULL OR og.stop_code IS NOT NULL)
	  AND og.business_date BETWEEN '2023-04-01' AND '2023-04-30'
	  AND april.txn_id IS NULL
GROUP BY og.source_agency_id, og.service_agency_id, og.route_number;


-- all the distinct agency and route from gtfs
SELECT DISTINCT trac_agency_id, route_short_name, route_long_name FROM _test.latest_gtfs_feeds;	



/* --------- Part 2: GTFS direction processing --------- */

-- Show the array of all distinct stops along the route for each distinct shape, also show the direction for each shape
-- assume that all of the shape with the same direction_id is the subset of the shape with the most stops
-- Therefore, we can get use the direction of the shape with the most stops as the standard direction (shape_direction)
CREATE TABLE _test.gtfs_route_direction_april23 AS (
	SELECT DISTINCT 
			  feed_id
			, route_id
			, trac_agency_id
			, shape_id
			, direction_id
			, stops_arr
			, FIRST_VALUE(alt_direction_id)  OVER (PARTITION BY feed_id, trac_agency_id, route_id, direction_id ORDER BY stops_count DESC) AS alt_direction_id
	FROM (
		WITH dist AS (
				-- this subquery FOR joining the route, the trips, stops, AND stop_time
				-- we need this for figuring out the direction (N/E/S/W) for each GTFS route
				SELECT DISTINCT r.feed_id
								, r.route_id
								, r.trac_agency_id
								, t.shape_id
								, t.direction_id
								, st.stop_id
								, st.stop_sequence
								, s.stop_lon::numeric --x
								, s.stop_lat::numeric --y
				FROM _test.latest_gtfs_feeds r -- this IS the TABLE we need FOR the route information
				JOIN  _test.real_transitland_trips t
					ON  r.feed_id = t.feed_id
						AND t.route_id = r.route_id
				JOIN _test.real_transitland_stop_times st
					ON st.feed_id = r.feed_id
						AND st.trip_id = t.trip_id
				JOIN _test.real_transitland_stops s
					ON s.feed_id = r.feed_id
						AND s.stop_id = st.stop_id
				ORDER BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, st.stop_sequence ASC
				)
		SELECT DISTINCT
				  feed_id
				, route_id
				, trac_agency_id
				, shape_id
				, direction_id
				, ARRAY_AGG(stop_id) OVER (PARTITION BY feed_id, trac_agency_id, route_id, shape_id, direction_id ORDER BY stop_sequence ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS stops_arr
				, array[
					  CASE
						WHEN (
						      LAST_VALUE(stop_lat) OVER (PARTITION BY feed_id, trac_agency_id, route_id, shape_id, direction_id  ORDER BY stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
						    - FIRST_VALUE(stop_lat) OVER (PARTITION BY feed_id, trac_agency_id, route_id, shape_id, direction_id  ORDER BY stop_sequence) -- delta-y
						    ) > 0
							THEN 4::INT2 -- North
						ELSE 5::INT2 -- South
					  END
					, CASE
						WHEN (
							  LAST_VALUE(stop_lon) OVER (PARTITION BY feed_id, trac_agency_id, route_id, shape_id, direction_id  ORDER BY stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
							- FIRST_VALUE(stop_lon) OVER (PARTITION BY feed_id, trac_agency_id, route_id, shape_id, direction_id  ORDER BY stop_sequence) -- delta-x
							) > 0
							THEN 6::INT2 -- East
						ELSE 7::INT2 -- West
					  END ] AS alt_direction_id
				, COUNT(*) OVER (PARTITION BY feed_id, trac_agency_id, route_id, shape_id, direction_id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS stops_count
		FROM dist ) sub
); --2813
	


--- what if shape_direction of oppsite gtfs_direction_id arrays EVER overlap??
SELECT d0.
FROM _test.gtfs_route_direction_april23 d0
JOIN _test.gtfs_route_direction_april23 d1
ON 	   d0.feed_id = d1.feed_id
   AND d0.route_id = d1.route_id
   AND d0.trac_agency_id = d1.trac_agency_id
   AND d0.direction_id = 0
   AND d1.direction_id = 1
WHERE d0.alt_direction_id && d1.alt_direction_id; 


-- SOLUTION: Remove the common element of alt_direction_id between oppsite gtfs_direction_id with table update
WITH ModifiedData AS (
	SELECT DISTINCT
			  feed_id
			, route_id
			, trac_agency_id
			, shape_id
			, direction_id
			, stops_arr
			, ARRAY (
		        SELECT UNNEST(alt_direction_id)
		        EXCEPT
		        SELECT UNNEST(s2_alt_direction_id)
		    ) AS new_alt_direction_id
	FROM  (
	        SELECT s1.*
	             , s2.alt_direction_id AS s2_alt_direction_id
	        FROM (	SELECT DISTINCT d0.*
					FROM _test.gtfs_route_direction_april23 d0
					JOIN _test.gtfs_route_direction_april23 d1
					ON 	   d0.feed_id = d1.feed_id
					   AND d0.route_id = d1.route_id
					   AND d0.trac_agency_id = d1.trac_agency_id
					   AND d0.direction_id != d1.direction_id
					WHERE d0.alt_direction_id && d1.alt_direction_id
				 ) s1
			JOIN _test.gtfs_route_direction_april23 s2
				ON  s1.feed_id = s2.feed_id 
					AND s1.trac_agency_id = s2.trac_agency_id
					AND s1.route_id = s2.route_id
					AND s1.direction_id != s2.direction_id
			WHERE s1.alt_direction_id && s2.alt_direction_id
		 ) q
)
UPDATE _test.gtfs_route_direction_april23 AS original
SET alt_direction_id = ModifiedData.new_alt_direction_id
FROM ModifiedData
WHERE original.feed_id = ModifiedData.feed_id
	  AND original.route_id = ModifiedData.route_id
	  AND original.trac_agency_id = ModifiedData.trac_agency_id
      AND original.shape_id = ModifiedData.shape_id;



     
     
-- !! Special Case: Pierce Transit (trac_agency_id = 6) !!
-- This is the case where the direction in AVL is either Inbound (1) or Outbound (2)
-- Therefore, we want to add the 1 and 2 into the alt_direction_id for direction_id of 1 and 0, respectively
-- At the same time, we also need to remove the contrasting elements if:
     -- the gtfs direction_id = 1 (inbound)
     	-- then we should only have the cartisian direction of 4 and 6
     		-- remove any 5 or 7 if it has
UPDATE _test.gtfs_route_direction_april23 original
SET alt_direction_id = array_append(
									CASE
										WHEN direction_id = 1 THEN
											CASE 
												WHEN ARRAY[4, 6]::SMALLINT[] <@ alt_direction_id
													THEN alt_direction_id
												WHEN ARRAY[5]::SMALLINT[] <@ alt_direction_id
													THEN array_remove(alt_direction_id, 5)
												WHEN ARRAY[7]::SMALLINT[] <@ alt_direction_id
													THEN array_remove(alt_direction_id, 7)
											END
							            WHEN direction_id = 0 THEN 
							            	CASE 
												WHEN ARRAY[5, 7]::SMALLINT[] <@ alt_direction_id
													THEN alt_direction_id
												WHEN ARRAY[4]::SMALLINT[] <@ alt_direction_id
													THEN array_remove(alt_direction_id, 4)
												WHEN ARRAY[6]::SMALLINT[] <@ alt_direction_id
													THEN array_remove(alt_direction_id, 6)
											END
									END,
                                    CASE
                                        WHEN direction_id = 1 THEN 1
                                        WHEN direction_id = 0 THEN 2
                                    END)
WHERE original.trac_agency_id = 6; -- 128
     
     

-- create the table with only route name, direction, and stop_id, and shape_direction, ignore all the variance of shape.
CREATE TABLE _test.gtfs_route_direction_stop_april23 AS (
	SELECT DISTINCT d.*, s.stop_location
	FROM (
		SELECT DISTINCT
				  feed_id
				, route_id
				, trac_agency_id
				, direction_id
				, UNNEST(stops_arr) AS stop_id
				, alt_direction_id
		FROM _test.gtfs_route_direction_april23 ) d
	JOIN _test.real_transitland_stops s
		ON s.feed_id = d.feed_id
		   AND s.stop_id = d.stop_id ); --35,411


CREATE INDEX stop_location_indx ON _test.gtfs_route_direction_stop_april23 USING gist(stop_location);
CREATE INDEX alt_direction_id_indx ON _test.gtfs_route_direction_stop_april23 USING GIN(alt_direction_id);

/*------------ AVL(Route Name)-TRAC(Direction)-GTFS(Stop ID) Standardization ------------*/
-- In this process, we do some processing to check the integrity of ORCA data
	-- first, create a table that handles txn with direction_id = 3 
	-- then, we do route name check between ORCA and AVL -> comes up with avl_check_code
	-- then, estimate a stop given a route_name and direction -> comes up with trac_check_code
	-- then, do a check to see if the stop_code that ORCA picks exists along the GTFS route -> comes up with gtfs_check_code
	-- finally, do a conditional selection for each combination of check codes to pick the FINAL stop_code for ORCA




-- Handling routes with direction_id = 3 (unknown):
	-- If same business date, same route number, same device id, same coach number
	-- AND the direction_id is 3 (unknown), then we should correct it with the VALID direction_id (NOT unknown) of the closest transaction
	-- and these transactions must be within 30 mins apart 

-- we need this function to calculate the absolute interval between 2 timestamps
CREATE FUNCTION abs_interval(interval) RETURNS interval AS
  $$ select case when ($1<interval '0') then -$1 else $1 end; $$
LANGUAGE sql immutable;
		   

-- create a view of boardings with modified direction
CREATE VIEW _test.txn_correct_april23  AS (
	SELECT txn_id, corrected_direction_id AS direction_id
	FROM (
		SELECT  b1.*
				, b2.stop_code
				, b2.device_location
				, b2.direction_id AS corrected_direction_id
				, ROW_NUMBER() OVER (
						PARTITION BY b1.txn_id
						ORDER BY abs_interval(b1.device_dtm_pacific - b2.device_dtm_pacific)
					) AS ranked
				, abs_interval(b1.device_dtm_pacific - b2.device_dtm_pacific) AS time_difference
		FROM _test.boarding_april23 b1
		JOIN _test.boarding_april23 b2
			ON  	b1.route_number = b2.route_number 
				AND b1.device_id = b2.device_id
				AND b1.coach_number = b2.coach_number
				AND b1.business_date = b2.business_date  
				AND b1.direction_id = 3 
				AND b2.direction_id != 3
		) ranked_data
	WHERE ranked = 1 AND time_difference <= '00:30:00'
);





-- first, compare to AVL data to see if route/vehicle_id/stop matches:
-- - for each txn: join on agency, vehicle_id, orca_stop_id, within 5? minutes. ALSO, join on transaction_updated table to correct the direction_id = 3
--     - there may be multiple records based on start/end of different routes (e.g. 160/161/168)
--       - check for matching route number: 
--         - (1.1) if avl direction matches orca direction, then route, stop, and direction are good 
--         - (1.2) if COALESCE(orca_updated_direction, direction_id) = 3, use AVL direction 
--         - (1.3) if direction does not match, still trust orca stop id 
--           - then use whichever direction that matches gtfs direction in below check
--         - (1.4) if AVL direction does not exists 
--           - then use whichever direction that matches gtfs direction in below check
--     - if there is no matching route, but there are stops, then we suspect route number is wrong
--       - not sure what to do here. some are easy to correct (e.g. 590 -> 594) but not always
--       - theory:
--         - (2.1) if the AVL direction exists, choose this AVL route with this AVL direction
--         - (2.2) if the AVL direction does NOT exist, use closest time match and write that AVL route as corrected route_id
--     - if there is no AVL match, it's likely the stop id is wrong (but could be just bus did not have AVL)
--       - (3) in either case, later checks will fix
CREATE TABLE _test.boarding_avl_april23 AS (
	SELECT    orca.txn_id
		    , orca.route_number
		    , orca.business_date
		    , orca.device_dtm_pacific
		    , orca.source_agency_id
		    , orca.service_agency_id
		    , orca.coach_number
		    , orca.direction_id
		    , cd.direction_id AS orca_updated_direction
		    , orca.stop_code
		    , orca.device_location
		    , orca.feed_id
		    , orca.route_id
		    , orca.trac_agency_id
		    , avl.route_id AS avl_route
		    , avl.stop_id AS avl_stop
		    , avl.departure_dtm_pacific AS avl_departure_dtm
		    , avl.direction_id AS avl_direction
		    , abs_interval(avl.departure_dtm_pacific - orca.device_dtm_pacific) AS orca_avl_time_interval
	FROM _test.boarding_april23 orca
	LEFT JOIN agency.v_avl avl
		ON avl.agency_id = orca.source_agency_id AND -- agency
		   avl.vehicle_id = orca.coach_number AND -- vehicle number
		   avl.stop_id = orca.stop_code AND -- orca stop code
		   abs_interval(avl.departure_dtm_pacific - orca.device_dtm_pacific) <= '300 seconds' -- WITHIN 5 minutes INTERVAL
	LEFT JOIN _test.txn_correct_april23 cd
		ON cd.txn_id = orca.txn_id
	ORDER BY orca.txn_id
); -- 5,247,126




-- now, only select the first case
CREATE TABLE _test.boarding_avl_april23_filtered AS (
	WITH ranked_avl_code AS (
		SELECT *
				, CASE 
					WHEN route_number = avl_route
						THEN CASE
							WHEN COALESCE(orca_updated_direction, direction_id) = avl_direction
								THEN 1.1
							WHEN COALESCE(orca_updated_direction, direction_id) = 3 AND avl_direction IS NOT NULL 
								THEN 1.2 
							WHEN COALESCE(orca_updated_direction, direction_id) != 3 AND COALESCE(orca_updated_direction, direction_id) != avl_direction
								THEN 1.3
							WHEN avl_direction IS NULL
								THEN 1.4
							END
					WHEN route_number != avl_route
						THEN CASE
							WHEN avl_direction IS NOT NULL
								THEN 2.1 -- AVL direction exists
							ELSE 2.2 -- AVL direction does not exist
							END
					WHEN avl_route IS NULL
						THEN 3
				  END AS avl_check_code
				 , ROW_NUMBER () OVER (
				 	PARTITION BY txn_id
				 	ORDER BY
				 		(
					 	  CASE 
							WHEN route_number = avl_route -- WHEN the route number matched
								THEN CASE
									WHEN COALESCE(orca_updated_direction, direction_id) = avl_direction
										THEN 1.1 -- everything IS good
									WHEN COALESCE(orca_updated_direction, direction_id) = 3 AND avl_direction IS NOT NULL 
										THEN 1.2 -- UPDATE the orca direction WITH avl
									WHEN COALESCE(orca_updated_direction, direction_id) != 3 AND COALESCE(orca_updated_direction, direction_id) != avl_direction
										THEN 1.3 -- need GTFS
									WHEN avl_direction IS NULL
										THEN 1.4 -- need GTFS
									END
							WHEN route_number != avl_route -- WHEN the route number does NOT match
								THEN CASE
									WHEN avl_direction IS NOT NULL
										THEN 2.1 -- AVL direction exists
									ELSE 2.2 -- AVL direction does not exist
									END
							WHEN avl_route IS NULL -- WHERE there IS NO AVL match
								THEN 3
						  END
						  , orca_avl_time_interval )
				 ) AS ranked_avl
		FROM _test.boarding_avl_april23 )
	SELECT txn_id
			, route_number
			, business_date
			, device_dtm_pacific
			, source_agency_id
			, service_agency_id
			, coach_number
			, direction_id
			, orca_updated_direction
			, stop_code
			, device_location
			, feed_id
			, route_id
			, trac_agency_id
			, avl_route
			, avl_stop
			, avl_direction
		    , avl_departure_dtm
			, avl_check_code
--		    , orca_avl_time_interval
	FROM ranked_avl_code
	WHERE ranked_avl = 1
	ORDER BY txn_id
); -- 5,016,712


CREATE INDEX device_location_indx ON _test.boarding_avl_april23_filtered USING gist(device_location);

-- quick summary of avl_check_code
SELECT avl_check_code, count(*)
FROM _test.boarding_avl_april23_filtered
GROUP BY avl_check_code;



/* --------- Part 3: ORCA-GTFS INTERGRATION (TRAC stop process) based on route_name & direction --------- */
-- tables from ORCA:
     -- 	  FROM  _test.boarding_avl_april23_filtered
     
-- table from GTFS: _test.gtfs_route_direction_stop_april23
SELECT *
FROM _test.gtfs_route_direction_stop_april23;
     



-- first, left join ORCA with GTFS based on route name and direction
	-- also, for the avl_check_code = 1.2, we will use the avl_direction instead of orca's
	-- we would join orca with gtfs based on route_short_name AND ARRAY[direction_descr] <@ gtfs.shape_direction
	-- we define the trac_check_code as:
		-- (1) when orca's stop_code equals to trac's stop_id
		-- (2) when orca's stop_code NOT equals to trac's stop_id
		-- (3) when orca's stop_code is NULL
		-- (4) when trac's stop_id is NULL --> no route/direction matched

CREATE TABLE _test.boarding_avl_trac_april23 AS (
	SELECT    txn_id
		    , route_number
			, business_date
			, device_dtm_pacific
			, source_agency_id
			, service_agency_id
			, coach_number
			, direction_id
			, orca_updated_direction
			, stop_code
			, device_location
			, feed_id
			, route_id
			, trac_agency_id
			, avl_route
			, avl_direction
			, avl_stop
	        , avl_departure_dtm
	        , avl_check_code
	        , trac_direction_ids
	        , trac_stop_id
		    , trac_stop_location
		    , distance_trac_orca
		    , CASE
				WHEN (trac_stop_id = stop_code) IS TRUE
					THEN 1 -- trac stop agree WITH orca stop
				WHEN (trac_stop_id = stop_code) IS FALSE
					THEN 2 -- trac stop agree WITH orca stop
				WHEN stop_code IS NULL AND trac_stop_id IS NOT NULL
					THEN 3 -- orca stop_code NOT EXISTS but we still have trac matched
				WHEN trac_stop_id IS NULL
					THEN 4 -- NO trac matched
			  END AS trac_check_code
	FROM (
		SELECT
		      orca.*
		    , gtfs.alt_direction_id AS trac_direction_ids
		    , gtfs.stop_id AS trac_stop_id
		    , gtfs.stop_location AS trac_stop_location
		    , ST_Distance(st_transform(orca.device_location, 32610), gtfs.stop_location) AS distance_trac_orca
		    , ROW_NUMBER() OVER (PARTITION BY orca.txn_id ORDER BY ST_Distance(st_transform(orca.device_location, 32610), gtfs.stop_location)) ranked
		FROM
		    _test.boarding_avl_april23_filtered orca
		LEFT JOIN
		    _test.gtfs_route_direction_stop_april23 gtfs
		    		ON 	orca.feed_id = gtfs.feed_id
		    			AND orca.route_id = gtfs.route_id
		    			AND orca.trac_agency_id = gtfs.trac_agency_id
						AND (
							(ARRAY[COALESCE(orca.orca_updated_direction, orca.direction_id)] <@ gtfs.alt_direction_id 
								AND orca.avl_check_code != 1.2)
							OR
							(ARRAY[orca.avl_direction] <@ gtfs.alt_direction_id
								AND orca.avl_check_code = 1.2)
						)
		) AS t
	WHERE ranked = 1 ); -- 5,016,712



	
SELECT DISTINCT direction_id, orca_updated_direction, avl_direction, trac_direction_ids
FROM _test.boarding_avl_trac_april23
WHERE trac_agency_id = 6;



SELECT DISTINCT trac_agency_id, direction_id, alt_direction_id FROM _test.gtfs_route_direction_april23;


-- quick summary of avl_check_code and trac_check_code	
SELECT  avl_check_code
		, trac_check_code
		, COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage_overall
FROM _test.boarding_avl_trac_april23
GROUP BY avl_check_code, trac_check_code;




-- for each GTFS stop that serves a route, what are the direction that that stop belongs to?
WITH tb AS (
	SELECT DISTINCT COALESCE(s1.feed_id, s2.feed_id) AS feed_id
					, COALESCE(s1.route_id, s2.route_id) AS route_id
					, COALESCE(s1.trac_agency_id, s2.trac_agency_id) AS trac_agency_id
					, COALESCE(s1.stop_id, s2.stop_id) AS stop_id
					, COALESCE(s1.stop_location, s2.stop_location) AS stop_location
					, array_cat(s1.alt_direction_id, s2.alt_direction_id) AS combined_alt_direction_id
					, array_length(array_cat(s1.alt_direction_id, s2.alt_direction_id), 1) AS arr_length
					, ROW_NUMBER() OVER (
						PARTITION BY COALESCE(s1.feed_id, s2.feed_id)
									, COALESCE(s1.route_id, s2.route_id) 
									, COALESCE(s1.trac_agency_id, s2.trac_agency_id)
									, COALESCE(s1.stop_id, s2.stop_id)
						ORDER BY array_length(array_cat(s1.alt_direction_id, s2.alt_direction_id), 1) DESC
					  ) AS ranked_number
			FROM _test.gtfs_route_direction_stop_april23 s1
			FULL OUTER JOIN _test.gtfs_route_direction_stop_april23 s2 
				ON 	s1.feed_id = s2.feed_id 
					AND s1.route_id = s2.route_id
					AND s1.trac_agency_id = s2.trac_agency_id
					AND s1.stop_id = s2.stop_id 
					AND s1.direction_id = 0
					AND s2.direction_id = 1
)
SELECT feed_id, route_id, stop_id, stop_location, combined_alt_direction_id, arr_length
FROM tb
WHERE ranked_number = 1;





--- now join on the GTFS with the ORCA route name and stop_code


-- gtfs_check_code: check if the stops serve the route in this specified orca_direction
	-- Case 1: Where this stop_code do serve this route:
		-- (1.1) if orca direction is contained within gtfs_combined_direction
		-- (1.2) if orca direction NOT contained within gtfs_combined_direction
		-- 			BUT AVL is 
		-- (1.3) GTFS does not agree to both orca AND avl OR avl is null 
	-- Case 2: Where this stop_code do NOT serve this route -- No GTFS matched:
		-- (2) 
CREATE TABLE _test.boarding_avl_trac_gtfs_april23  AS (
	WITH combined_direction AS (
		SELECT DISTINCT COALESCE(s1.feed_id, s2.feed_id) AS feed_id
						, COALESCE(s1.route_id, s2.route_id) AS route_id
						, COALESCE(s1.trac_agency_id, s2.trac_agency_id) AS trac_agency_id
						, COALESCE(s1.stop_id, s2.stop_id) AS stop_id
						, COALESCE(s1.stop_location, s2.stop_location) AS stop_location
						, array_cat(s1.alt_direction_id, s2.alt_direction_id) AS combined_alt_direction_id
						, array_length(array_cat(s1.alt_direction_id, s2.alt_direction_id), 1) AS arr_length
						, ROW_NUMBER() OVER (
							PARTITION BY COALESCE(s1.feed_id, s2.feed_id)
										, COALESCE(s1.route_id, s2.route_id) 
										, COALESCE(s1.trac_agency_id, s2.trac_agency_id)
										, COALESCE(s1.stop_id, s2.stop_id)
							ORDER BY array_length(array_cat(s1.alt_direction_id, s2.alt_direction_id), 1) DESC
						  ) AS ranked_number
				FROM _test.gtfs_route_direction_stop_april23 s1
				FULL OUTER JOIN _test.gtfs_route_direction_stop_april23 s2 
					ON 	s1.feed_id = s2.feed_id 
						AND s1.route_id = s2.route_id
						AND s1.trac_agency_id = s2.trac_agency_id
						AND s1.stop_id = s2.stop_id 
						AND s1.direction_id = 0
						AND s2.direction_id = 1
	)
	SELECT DISTINCT 
			  b.*
			, cd.stop_location AS gtfs_stop_location
			, ST_Distance(st_transform(b.device_location, 32610), st_transform(cd.stop_location, 32610)) AS distance_gtfs_orca
			, combined_alt_direction_id AS gtfs_combined_alt_direction_id
			, CASE 
				WHEN (ARRAY[COALESCE(b.orca_updated_direction, b.direction_id)] <@ combined_alt_direction_id) IS TRUE
					THEN 1.1 -- WHEN orca matched
				WHEN (ARRAY[COALESCE(b.orca_updated_direction, b.direction_id)] <@ combined_alt_direction_id) IS FALSE
						AND (ARRAY[b.avl_direction] <@ combined_alt_direction_id) IS TRUE
					THEN 1.2 -- WHEN orca does not matched but avl matched
				WHEN (ARRAY[COALESCE(b.orca_updated_direction, b.direction_id)] <@ combined_alt_direction_id) IS FALSE
						AND (
							(ARRAY[b.avl_direction] <@ combined_alt_direction_id) IS FALSE
							OR (ARRAY[b.avl_direction] <@ combined_alt_direction_id) IS NULL )
					THEN 1.3 -- the stop serve the route but none of direction matched
				WHEN combined_alt_direction_id IS NULL
					THEN 2 -- WHEN this orca stop does NOT serve this route AT all
			  END AS gtfs_check_code
	FROM _test.boarding_avl_trac_april23 b
	LEFT JOIN combined_direction cd
				ON b.feed_id = cd.feed_id
				   AND b.route_id = cd.route_id
				   AND b.trac_agency_id = cd.trac_agency_id
				   AND b.stop_code = cd.stop_id
				   AND cd.ranked_number = 1
); -- 5,016,712


-- quick summary of avl_check_code,  trac_check_code, gtfs_check_code
SELECT  avl_check_code
		, trac_check_code
		, gtfs_check_code
		, COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage_overall
FROM _test.boarding_avl_trac_gtfs_april23
WHERE trac_agency_id = 6
GROUP BY avl_check_code, trac_check_code, gtfs_check_code;


SELECT * FROM _test.boarding_avl_trac_gtfs_april23
WHERE trac_agency_id = 6
		AND avl_check_code= 3
		AND trac_check_code= 2
		AND gtfs_check_code= 1.3;


	
-- create a look up table for the finalized direction 
CREATE TABLE trac.direction_update_note (
	update_id SMALLINT PRIMARY KEY
	, update_note VARCHAR(50) 
	, update_descr TEXT NOT NULL
);
	
INSERT INTO trac.direction_update_note(update_id, update_note, update_descr) VALUES
  (1, 'orca', 'ORCA original direction')
, (2, 'orca updated', 'for txn with ORCA original direction = 3, estimate the direction based on the direction of trips operated within 30 minutes for the same route/device id')
, (3, 'avl', 'direction suggested by AVL, result from the join on agency_id, vehicle_id, stop_code, and departure_dtm_pacific within 5 minutes of orca device_dtm_pacific')
, (4, 'gtfs', 'direction suggested by GTFS, result from the join on feed_id, route_id and stop_code')
, (6, 'gtfs original', 'original gtfs direction id (inbound - 1 /outbound - 0)')
, (-1, 'none', 'direction unknown')
, (-99, 'extra case', 'extra case that hasnt been considered');

SELECT * FROM trac.direction_update_note;


-- create a look up table for the finalized direction 
CREATE TABLE trac.stop_update_note (
	update_id SMALLINT PRIMARY KEY
	, update_note VARCHAR(50) 
	, update_descr TEXT NOT NULL
);
	

INSERT INTO trac.stop_update_note(update_id, update_note, update_descr) VALUES
  (1, 'orca', 'ORCA original stop')
, (5, 'trac', 'TRAC suggested GTFS stop')
, (-1, 'none', 'stop unknown')
, (-99, 'extra case', 'extra case that hasnt been considered');


SELECT * FROM trac.stop_update_note;

-- finalized table
CREATE TABLE _test.boarding_action_final_april23 AS (
	SELECT    txn_id
			, coach_number
			, feed_id
			, route_id AS gtfs_route_id
			, trac_agency_id
			, avl_route
			, avl_stop
			, avl_direction
			, avl_departure_dtm
			, avl_check_code
			, trac_check_code
			, gtfs_check_code
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR trac_check_code = 4
					THEN NULL -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN COALESCE(orca_updated_direction, direction_id)
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN avl_direction
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN CASE 
						WHEN distance_trac_orca < 100
							THEN COALESCE(orca_updated_direction, direction_id)
						ELSE NULL
					END
				WHEN avl_check_code = 1.4 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- gtfs-orca
					THEN CASE 
						WHEN COALESCE(orca_updated_direction, direction_id) = 4 THEN 5
						WHEN COALESCE(orca_updated_direction, direction_id) = 5 THEN 4
						WHEN COALESCE(orca_updated_direction, direction_id) = 6 THEN 7
						WHEN COALESCE(orca_updated_direction, direction_id) = 7 THEN 6
					END
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- other-other
					THEN CASE 
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca < distance_trac_orca
							THEN CASE -- gtfs-orca
								WHEN COALESCE(orca_updated_direction, direction_id) = 4 THEN 5
								WHEN COALESCE(orca_updated_direction, direction_id) = 5 THEN 4
								WHEN COALESCE(orca_updated_direction, direction_id) = 6 THEN 7
								WHEN COALESCE(orca_updated_direction, direction_id) = 7 THEN 6
							END 
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca > distance_trac_orca
							THEN COALESCE(orca_updated_direction, direction_id) -- orca-trac
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca <= 100
							THEN COALESCE(orca_updated_direction, direction_id) -- orca-trac 
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca > 100
							THEN NULL
						WHEN distance_gtfs_orca IS NULL AND distance_trac_orca IS NULL
							THEN NULL
						ELSE -99 -- extra case
					END
			END AS direction_final
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR trac_check_code = 4
					THEN -1 -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN CASE -- either orca updated direction, OR orca original !!
						WHEN orca_updated_direction IS NOT NULL 
							THEN 2 -- 'orca updated'
						ELSE 1 -- 'orca'
					END
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN 3 -- avl
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN CASE 
						WHEN distance_trac_orca < 100
							THEN CASE -- either orca updated direction, OR orca original !!
								WHEN orca_updated_direction IS NOT NULL 
									THEN 2 --'orca updated'
								ELSE 1 --'orca'
							END
						ELSE -1 -- cant locate
					END
				WHEN avl_check_code = 1.4 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- gtfs-orca
					THEN 4 --'gtfs'
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 
					THEN CASE 
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca < distance_trac_orca -- gtfs-orca
							THEN 4 --'gtfs'
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca > distance_trac_orca -- orca-trac
							THEN CASE -- either orca updated direction, OR orca original !!
								WHEN orca_updated_direction IS NOT NULL 
									THEN 2 --'orca updated'
								ELSE 1 --'orca'
							END
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca <= 100 -- orca-trac
							THEN CASE -- either orca updated direction, OR orca original !!
								WHEN orca_updated_direction IS NOT NULL 
									THEN 2 --'orca updated'
								ELSE 1 --'orca'
							END
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca > 100
							THEN -1 -- cant locate
						WHEN distance_gtfs_orca IS NULL AND distance_trac_orca IS NULL
							THEN -1 -- cant locate
						ELSE -99 -- extra case, this IS FOR double checking
					END
			END AS direction_note
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR trac_check_code = 4
					THEN NULL -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN stop_code
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN stop_code
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN CASE 
						WHEN distance_trac_orca < 100
							THEN trac_stop_id
						ELSE NULL
					END
				WHEN avl_check_code = 1.4 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- gtfs-orca
					THEN stop_code
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- other-other
					THEN CASE 
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca < distance_trac_orca
							THEN stop_code -- gtfs-orca
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca > distance_trac_orca
							THEN trac_stop_id -- orca-trac
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca <= 100
							THEN trac_stop_id -- orca-trac 
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca > 100
							THEN NULL
						WHEN distance_gtfs_orca IS NULL AND distance_trac_orca IS NULL
							THEN NULL
						ELSE '-99' -- extra case, this IS FOR doublechecking
					END
			END AS stop_final
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR trac_check_code = 4
					THEN -1 -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN 1 -- orca
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN 1 -- orca
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN CASE 
						WHEN distance_trac_orca < 100
							THEN 5 -- trac
						ELSE -1 -- cant locate
					END
				WHEN avl_check_code = 1.4 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- gtfs-orca
					THEN 1 -- orca
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3
					THEN CASE 
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca < distance_trac_orca -- gtfs-orca
							THEN 1 -- orca
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca > distance_trac_orca  -- orca-trac
							THEN 5 -- trac
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca <= 100 -- orca-trac 
							THEN 5 -- trac
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca > 100
							THEN -1 -- cant locate
						WHEN distance_gtfs_orca IS NULL AND distance_trac_orca IS NULL
							THEN -1 -- cant locate
						ELSE -99 -- this IS FOR doublechecking
					END
			END AS stop_note
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR trac_check_code = 4
					THEN NULL -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN gtfs_stop_location
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN gtfs_stop_location
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN CASE 
						WHEN distance_trac_orca < 100
							THEN trac_stop_location
						ELSE NULL
					END
				WHEN avl_check_code = 1.4 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- gtfs-orca
					THEN gtfs_stop_location
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- other-other
					THEN CASE 
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca < distance_trac_orca
							THEN gtfs_stop_location -- gtfs-orca
						WHEN distance_gtfs_orca <= 100 AND distance_gtfs_orca > distance_trac_orca
							THEN trac_stop_location -- orca-trac
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca <= 100
							THEN trac_stop_location -- orca-trac 
						WHEN distance_gtfs_orca > 100 AND distance_trac_orca > 100
							THEN NULL
						WHEN distance_gtfs_orca IS NULL AND distance_trac_orca IS NULL
							THEN NULL
						ELSE NULL -- extra case
					END
			END AS stop_location
	FROM _test.boarding_avl_trac_gtfs_april23
); -- 5,016,712



-- check all distinct values
SELECT DISTINCT direction_note, direction_final
FROM _test.boarding_action_final_april23;


SELECT DISTINCT direction_note, stop_note
FROM _test.boarding_action_final_april23;

 

-- check if there are cases where we did not consider and they have 9999 code
SELECT *
FROM _test.boarding_action_final_april23
WHERE direction_final = 9999 OR stop_final = '9999';


SELECT *
FROM _test.boarding_action_final_april23
WHERE direction_note != -1 AND stop_location IS NOT NULL;


SELECT COUNT(*) AS  all_txn
	 , count(*) FILTER (WHERE
	 		stop_note IS NOT NULL
	 		AND direction_note IS NOT NULL
	 		AND (stop_note != 1 OR direction_note != 1)
	 	    ) * 1.0/COUNT(*) AS updated_txn -- 22.9% got changed, either the direction OR stop_id, OR both
	 , count(*) FILTER (WHERE
	 		stop_note = 1
	 		AND direction_note = 1) * 1.0/COUNT(*) AS good_txn -- 75.9% stayed the same
     , count(*) FILTER (WHERE stop_final IS NOT NULL) * 1.0/COUNT(*) AS usable_txn -- 98.8% value can be used
     , count(*) FILTER (WHERE stop_final IS NULL) * 1.0/COUNT(*) AS ignore_txn -- 1.2% will be ignored
FROM  _test.boarding_action_final_april23;



