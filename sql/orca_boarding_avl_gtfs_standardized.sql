/*----- DATA PREPROCESSING -----*/

/* --------- Part 1: ORCA Boardings within specific time window from GTFS --------- */

-- create a view for GTFS route that have the valid start and end date for each route
	  -- for the routes with the same trac_agency_id, route_short_name, route_long_name, start_date, and end_date
	  -- we choose the routes with the higher feed_id, as it's more updated
CREATE VIEW _test.latest_gtfs_feeds_20240413 AS (
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
			 				 , r.route_id
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
		   , latest_feed_rank
	FROM latest_feed
	WHERE latest_feed_rank = 1
);


SELECT *
FROM _test.latest_gtfs_feeds_20240413
WHERE route_short_name IS NULL; 

SELECT *
FROM trac.route_name_lookup;

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
			 				 , r.route_id
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
	SELECT min(feed_id) feed_id1
		   , max(feed_id) feed_id2
		   , route_id
		   , start_date
		   , end_date
	FROM latest_feed
	GROUP BY route_id
		   , start_date
		   , end_date
	HAVING COUNT(*) > 1;
	
SELECT count(*) FROM  _test.latest_gtfs_feeds_20240413; -- 1679



-- test with transactions within April 2023
	-- txn must have device_location NOT null OR stop_code NOT NULL
		-- for txn where BOTH stop_code and device_location is NULL, we cant verify this kind of data or standardize it
	-- when joining ORCA with GTFS there might be several matched as the date could be overlapping
	  	-- if this is the case, then we do ROW_NUMBER to only take mopt updated option
-- Old table: 5,016,712 rows
-- New table: 
---- ** New Orca extract with 2 new columns added ** ----
CREATE TABLE _test.boarding_april23_20240413 AS (
	WITH orca_with_latest_feed AS (
		SELECT   gtfs.feed_id
			   , gtfs.route_id -- we would use route_id, feed_id, and trac_agency_id TO JOIN btw orca AND gtfs later
			   , gtfs.trac_agency_id 
			   , orca.*
			   , EXTRACT(DOW FROM orca.business_date) AS txn_dow
			   , CASE 
					WHEN date_trunc('day', orca.device_dtm_pacific) > orca.business_date
						THEN TO_CHAR(orca.device_dtm_pacific, 'HH24:MI:SS')::INTERVAL + '24 hours'
					ELSE TO_CHAR(orca.device_dtm_pacific, 'HH24:MI:SS')::INTERVAL
				 END AS device_dtm_interval
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
		JOIN _test.latest_gtfs_feeds_20240413 gtfs -- gtfs route valid START and END date
			ON (gtfs.route_short_name = orca.route_number
				OR COALESCE(gtfs.route_short_name, gtfs.route_long_name) ILIKE lookup.gtfs_route_name
				OR gtfs.route_id = orca.route_number ) -- New change 20240427: ALSO JOIN ON route_number
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
SELECT * FROM orca.v_boardings
WHERE (device_location IS NULL AND stop_code IS NULL)
	  AND business_date BETWEEN '2023-04-01' AND '2023-04-30'; --203,282


SELECT DISTINCT device_mode_id 
FROM orca.v_boardings
WHERE (direction_id IS NOT NULL OR stop_code IS NOT NULL)
	  AND business_date BETWEEN '2023-04-01' AND '2023-04-30';
	 
SELECT *
FROM _test.boarding_april23_20240413 april
WHERE ;



-- why only 5,016,712 get into the table??
SELECT DISTINCT og.source_agency_id, og.service_agency_id, og.route_number, count(*)
FROM orca.v_boardings og
LEFT JOIN trac.route_name_lookup lookup
	ON og.route_number = lookup.route_number
		AND og.service_agency_id = lookup.service_agency_id
LEFT JOIN _test.boarding_april23_20240413 april
	ON og.txn_id = april.txn_id
WHERE (og.device_location IS NOT NULL OR og.stop_code IS NOT NULL)
	  AND og.business_date BETWEEN '2023-04-01' AND '2023-04-30'
	  AND april.txn_id IS NULL
GROUP BY og.source_agency_id, og.service_agency_id, og.route_number;





/* --------- Part 2: GTFS direction processing --------- */

-- In this step, we need figure out the cartisan direction of each route for each distinct TRIP_ID and SHAPE_ID,
-- Do this by getting the coordinates of the LAST stop of the minus the FIRST stop in the trip
CREATE TABLE _test.gtfs_route_trip_direction_20240413 AS (
	SELECT DISTINCT r.feed_id
					, r.route_id
					, r.trac_agency_id
					, t.shape_id
					, t.trip_id
					, t.service_id
					, t.direction_id
					, FIRST_VALUE(st.arrival_time) OVER (
						PARTITION BY r.feed_id
									, r.route_id
									, r.trac_agency_id
									, t.shape_id
									, t.trip_id
						ORDER BY st.stop_sequence ) AS first_stop_time
					, LAST_VALUE(st.departure_time) OVER (
				      	PARTITION BY r.feed_id
									, r.route_id
									, r.trac_agency_id
									, t.shape_id
									, t.trip_id
				      	ORDER BY st.stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_stop_time
					, ARRAY_AGG(st.stop_id) OVER (
						PARTITION BY r.feed_id
									, r.route_id
									, r.trac_agency_id
									, t.shape_id
									, t.trip_id
						ORDER BY st.stop_sequence ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS stops_arr
					, array[
						  CASE
							WHEN (
							      LAST_VALUE(s.stop_lat::numeric) OVER (
							      	PARTITION BY r.feed_id
												, r.route_id
												, r.trac_agency_id
												, t.shape_id
												, t.trip_id
							      	ORDER BY st.stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
							    - FIRST_VALUE(s.stop_lat::numeric) OVER (
							    	PARTITION BY r.feed_id
												, r.route_id
												, r.trac_agency_id
												, t.shape_id
												, t.trip_id
									ORDER BY st.stop_sequence) -- delta-y
							    ) > 0
								THEN 4::INT2 -- North
							ELSE 5::INT2 -- South
						  END
						, CASE
							WHEN (
								  LAST_VALUE(s.stop_lon::numeric) OVER (
								  	PARTITION BY r.feed_id
												, r.route_id
												, r.trac_agency_id
												, t.shape_id
												, t.trip_id
								  	ORDER BY st.stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
								- FIRST_VALUE(s.stop_lon::numeric) OVER (
									PARTITION BY r.feed_id
												, r.route_id
												, r.trac_agency_id
												, t.shape_id
												, t.trip_id
									ORDER BY st.stop_sequence) -- delta-x
								) > 0
								THEN 6::INT2 -- East
							ELSE 7::INT2 -- West
						  END ] AS alt_direction_id
						, monday
						, tuesday
						, wednesday
						, thursday
						, friday
						, saturday
						, sunday
	FROM _test.latest_gtfs_feeds_20240413 r -- this IS the TABLE we need FOR the route information
	JOIN  _test.real_transitland_trips t
		ON  r.feed_id = t.feed_id
			AND t.route_id = r.route_id
	JOIN _test.real_transitland_stop_times st
		ON st.feed_id = r.feed_id
			AND st.trip_id = t.trip_id
	JOIN _test.real_transitland_stops s
		ON s.feed_id = r.feed_id
			AND s.stop_id = st.stop_id
	LEFT JOIN _test.real_transitland_calendar c
		ON t.feed_id = c.feed_id 
			AND c.service_id = t.service_id
); -- 1,303,799





-- !! Special Case: Pierce Transit (trac_agency_id = 6) !!
-- This is the case where the direction in AVL is either Inbound (1) or Outbound (2)
-- Therefore, we want to add the 1 and 2 into the alt_direction_id for direction_id of 1 and 0, respectively
-- At the same time, we also need to remove the contrasting elements if:
     -- the gtfs direction_id = 1 (inbound)
     	-- then we should only have the cartisian direction of 4 and 6
     		-- remove any 5 or 7 if it has
UPDATE _test.gtfs_route_trip_direction_20240413 original
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
WHERE original.trac_agency_id = 6; -- 3,806


CREATE INDEX stop_arr_indx
	ON _test.gtfs_route_trip_direction_20240413
	USING GIN(stops_arr);




-- Create a table with route, trip, shape, and stop, stop sequence information
-- This also includes the information of when the trip takes place in a week
CREATE TABLE _test.gtfs_route_trip_stop_sequence_20240413 AS (
	SELECT DISTINCT t.feed_id
					, t.route_id
					, t.trac_agency_id
					, t.trip_id
					, t.shape_id
					, t.direction_id
					, t.alt_direction_id
					, c.monday
					, c.tuesday
					, c.wednesday
					, c.thursday
					, c.friday
					, c.saturday
					, c.sunday
					, st.arrival_time
					, st.departure_time
					, st.stop_id
					, st.stop_sequence
					, s.stop_location
					, r.start_date
					, r.end_date
	FROM _test.gtfs_route_trip_direction_20240413 t
	JOIN _test.latest_gtfs_feeds_20240413 r
		ON r.feed_id = t.feed_id 
			AND r.route_id = t.route_id
	JOIN _test.real_transitland_stop_times st
		ON st.feed_id = t.feed_id
			AND st.trip_id = t.trip_id
	JOIN _test.real_transitland_stops s
		ON s.feed_id = t.feed_id
			AND s.stop_id = st.stop_id
	LEFT JOIN _test.real_transitland_calendar c
		ON t.feed_id = c.feed_id 
			AND c.service_id = t.service_id
	ORDER BY t.feed_id, t.trac_agency_id, t.route_id, t.trip_id, t.shape_id, st.stop_sequence ASC
); -- 5,789,505 




CREATE INDEX stop_loc_indx
	ON _test.gtfs_route_trip_stop_sequence_20240413
	USING gist(stop_location);

CREATE INDEX alt_dir_id_indx
	ON _test.gtfs_route_trip_stop_sequence_20240413
	USING GIN(alt_direction_id);


-- This returns the feed, route, trac_agency_id, shape, direction, date of service and exception type
	-- useful for the join between orca and gtfs
	-- because we want to make sure the date of the txn matches the date of service and extra service
CREATE TABLE _test.gtfs_route_service_exception_20240413 AS (
	SELECT DISTINCT r.feed_id
					, r.route_id
					, r.trac_agency_id
					, t.trip_id
					, cd.date
					, cd.exception_type
	FROM _test.latest_gtfs_feeds r -- this IS the TABLE we need FOR the route information
	JOIN  _test.real_transitland_trips t
		ON  r.feed_id = t.feed_id
			AND t.route_id = r.route_id
	JOIN _test.real_transitland_calendar c
		ON t.feed_id = c.feed_id 
			AND c.service_id = t.service_id
	JOIN _test.real_transitland_calendar_dates cd
		ON c.feed_id = cd.feed_id 
			AND c.service_id = cd.service_id
	ORDER BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id ASC
); -- 512,439


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
CREATE VIEW _test.txn_correct_april23_20240413  AS (
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
				AND b1.device_id = b2.device_id -- same tapping device
				AND b1.coach_number = b2.coach_number -- same vehicle
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
CREATE TABLE _test.boarding_avl_april23_20240413 AS (
	SELECT    orca.txn_id
		    , orca.route_number
		    , orca.business_date
		    , orca.txn_dow
		    , orca.device_mode_id
		    , orca.device_dtm_pacific
		    , orca.device_dtm_interval
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
	FROM _test.boarding_april23_20240413 orca
	LEFT JOIN agency.v_avl avl
		ON avl.agency_id = orca.source_agency_id AND -- agency
		   avl.vehicle_id = orca.coach_number AND -- vehicle number
		   avl.stop_id = orca.stop_code AND -- orca stop code
		   abs_interval(avl.departure_dtm_pacific - orca.device_dtm_pacific) <= INTERVAL '5 minutes' -- WITHIN 5 minutes INTERVAL
	LEFT JOIN _test.txn_correct_april23 cd
		ON cd.txn_id = orca.txn_id
	ORDER BY orca.txn_id
); -- 5,247,126


SELECT *
FROM _test.boarding_avl_april23_20240413
WHERE route_number IN ('160', '161', '168');

-- now, only select the first case
CREATE TABLE _test.boarding_avl_april23_filtered_20240413 AS (
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
		FROM _test.boarding_avl_april23_20240413 )
	SELECT txn_id
			, route_number
			, business_date
			, txn_dow
			, device_mode_id
			, device_dtm_pacific
			, device_dtm_interval
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
	FROM ranked_avl_code
	WHERE ranked_avl = 1
	ORDER BY txn_id
); -- 5,016,712


CREATE INDEX device_location_indx_20240413 ON _test.boarding_avl_april23_filtered_20240413 USING gist(device_location);


-- quick summary of avl_check_code
SELECT avl_check_code, count(*)
FROM _test.boarding_avl_april23_filtered_20240413
GROUP BY avl_check_code;


SELECT DISTINCT txn_dow
FROM _test.boarding_avl_april23_filtered_20240413;



/* --------- Part 3: ORCA-GTFS INTERGRATION (TRAC stop process) based on route_name & direction --------- */
-- tables from ORCA:
     --   _test.boarding_avl_april23_filtered_20240413
     
-- table from GTFS:
	-- _test.gtfs_route_trip_stop_sequence_20240413


SELECT *
FROM _test.gtfs_route_trip_stop_sequence_20240413;
     


-- first, left join ORCA with GTFS based on route name and direction
	-- also, for the avl_check_code = 1.2, we will use the avl_direction instead of orca's
	-- we would join orca with gtfs based on route_short_name AND ARRAY[direction_descr] <@ gtfs.shape_direction
	-- we define the trac_check_code as:
		-- (1) when orca's stop_code equals to trac's stop_id
		-- (2) when orca's stop_code NOT equals to trac's stop_id
		-- (3) when orca's stop_code is NULL
		-- (4) when trac's stop_id is NULL --> no route/direction matched

CREATE TABLE _test.boarding_avl_trac_april23_20240413_raw AS (
	SELECT    txn_id
		    , route_number
			, business_date
			, txn_dow
			, device_mode_id
			, device_dtm_pacific
			, device_dtm_interval
			, source_agency_id
			, service_agency_id
			, coach_number
			, trip_ranked.direction_id
			, orca_updated_direction
			, stop_code
			, device_location
			, trip_ranked.feed_id
			, trip_ranked.route_id
			, trip_ranked.trac_agency_id
			, avl_route
			, avl_direction
			, avl_stop
	        , avl_departure_dtm
	        , avl_check_code
	        , trac_trip_id
	        , trac_direction_ids
		    , gtfs.stop_id AS trac_stop_id
		    , abs_interval(gtfs.departure_time - trip_ranked.device_dtm_interval) AS trac_time_difference
		    , gtfs.stop_location AS trac_stop_location
		    , ST_Distance(st_transform(trip_ranked.device_location, 32610), gtfs.stop_location) AS distance_trac_orca
		    , CASE
				WHEN (gtfs.stop_id = stop_code) IS TRUE
					THEN 1 -- trac stop agree WITH orca stop
				WHEN (gtfs.stop_id = stop_code) IS FALSE
					THEN 2 -- trac stop agree WITH orca stop
				WHEN stop_code IS NULL AND gtfs.stop_id IS NOT NULL
					THEN 3 -- orca stop_code NOT EXISTS but we still have trac matched
				WHEN gtfs.stop_id IS NULL
					THEN 4 -- NO trac matched
			  END AS trac_check_code
			, ROW_NUMBER() OVER (
					PARTITION BY trip_ranked.txn_id
					-- choosing the shortest wait time trip for each shape id
					ORDER BY
						CASE
							WHEN (gtfs.stop_id = stop_code) IS TRUE
								THEN 1 -- trac stop agree WITH orca stop
							WHEN (gtfs.stop_id = stop_code) IS FALSE
								THEN 2 -- trac stop agree WITH orca stop
							WHEN stop_code IS NULL AND gtfs.stop_id IS NOT NULL
								THEN 3 -- orca stop_code NOT EXISTS but we still have trac matched
							WHEN gtfs.stop_id IS NULL
								THEN 4 -- NO trac matched
						  END ASC 
						, abs_interval(gtfs.departure_time - trip_ranked.device_dtm_interval) ASC
				  ) AS trac_rank
	FROM (
		SELECT
		      orca.*
		    , gtfs.trip_id AS trac_trip_id
		    , gtfs.alt_direction_id AS trac_direction_ids
		    , CASE
					WHEN ARRAY[orca.stop_code] <@ gtfs.stops_arr -- prioritizing matching stop id 
						 THEN 1
					ELSE 2
			  END stop_exist
		    , ROW_NUMBER() OVER (
					PARTITION BY orca.txn_id
					-- choosing the shortest wait time trip for each shape id
					ORDER BY
						CASE
							WHEN ARRAY[orca.stop_code] <@ gtfs.stops_arr -- prioritizing matching stop id 
								 THEN 1
							ELSE 2
						END ASC
						, CASE
							WHEN ARRAY[orca.stop_code] <@ gtfs.stops_arr -- prioritizing matching stop id 
								THEN 
									abs_interval(
										( -- Calculate estimated arrival time for the stop based on sequence position and trip duration
											-- estimate the time of arrival for a stop code based on the sequence of stops and the start and end time of the trip
											(gtfs.first_stop_time - INTERVAL '3 minutes' + gtfs.last_stop_time + INTERVAL '15 minutes')
											/array_length(gtfs.stops_arr, 1) -- Divide this duration by the number of stops to get the average time between stops
										)  
										* array_position(gtfs.stops_arr, orca.stop_code) --Multiply the average time between stops by the position of the stop code within the sequence to estimate the arrival time for that stop.
									    - orca.device_dtm_interval) -- Subtract the estimated arrival time for the stop from the ORCA device timestamp to get the estimated time difference.
							ELSE
								abs_interval( ((gtfs.first_stop_time - INTERVAL '3 minutes' + gtfs.last_stop_time + INTERVAL '15 minutes')/2) - orca.device_dtm_interval)
						END
				  ) AS ranked
		FROM _test.boarding_avl_april23_filtered_20240413 orca
		LEFT JOIN _test.gtfs_route_service_exception_20240413 exc -- EXCEPTION service dates for the route/shape
			ON exc.feed_id = orca.feed_id
			   AND exc.trac_agency_id = orca.trac_agency_id
			   AND exc.route_id = orca.route_id
			   AND orca.business_date = exc.date
		LEFT JOIN _test.gtfs_route_trip_direction_20240413 gtfs
    		ON 	orca.feed_id = gtfs.feed_id
    			AND orca.route_id = gtfs.route_id
    			AND orca.trac_agency_id = gtfs.trac_agency_id
    			AND orca.device_dtm_interval BETWEEN
    				gtfs.first_stop_time - INTERVAL '3 minutes' AND gtfs.last_stop_time + INTERVAL '15 minutes'-- txn must be WITHIN the FIRST AND LAST stop time
				AND ( -- JOIN ON direction
					(ARRAY[COALESCE(orca.orca_updated_direction, orca.direction_id)] <@ gtfs.alt_direction_id 
						AND orca.avl_check_code != 1.2)
					OR
					(ARRAY[orca.avl_direction] <@ gtfs.alt_direction_id
						AND orca.avl_check_code = 1.2)
				  )
	            AND
				CASE
		            WHEN orca.txn_dow = 0 -- SUNDAY
		            	THEN
		            		   (gtfs.sunday = 1 AND exc.exception_type IS NULL)
		            		OR (gtfs.sunday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
		            		OR (gtfs.sunday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
		            		OR (gtfs.sunday IS NULL)
		            WHEN orca.txn_dow = 1 -- MONDAY
		            	THEN
		            		   (gtfs.monday = 1 AND exc.exception_type IS NULL)
		            		OR (gtfs.monday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
		            		OR (gtfs.monday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
		            		OR (gtfs.monday IS NULL)
		            WHEN orca.txn_dow = 2 -- TUESDAY
		            	THEN
		            		   (gtfs.tuesday = 1 AND exc.exception_type IS NULL)
		            		OR (gtfs.tuesday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
		            		OR (gtfs.tuesday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
		            		OR (gtfs.tuesday IS NULL)
		            WHEN orca.txn_dow = 3 -- WEDNESDAY
		            	THEN
		            		   (gtfs.wednesday = 1 AND exc.exception_type IS NULL)
		            		OR (gtfs.wednesday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
		            		OR (gtfs.wednesday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
		            		OR (gtfs.wednesday IS NULL)
		            WHEN orca.txn_dow = 4 -- THURSDAY
		            	THEN
		            		   (gtfs.thursday = 1 AND exc.exception_type IS NULL)
		            		OR (gtfs.thursday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
		            		OR (gtfs.thursday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
		            		OR (gtfs.thursday IS NULL)
		            WHEN orca.txn_dow = 5 -- FRIDAY
		            	THEN
		            		   (gtfs.friday = 1 AND exc.exception_type IS NULL)
		            		OR (gtfs.friday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
		            		OR (gtfs.friday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
		            		OR (gtfs.friday IS NULL)
		            WHEN orca.txn_dow = 6 -- SATURDAY
		            	THEN
		            		   (gtfs.saturday = 1 AND exc.exception_type IS NULL)
		            		OR (gtfs.saturday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
		            		OR (gtfs.saturday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)  
		            		OR (gtfs.saturday IS NULL)
			  END
		) AS trip_ranked
	LEFT JOIN _test.gtfs_route_trip_stop_sequence_20240413 gtfs
	ON 	trip_ranked.feed_id = gtfs.feed_id
		AND trip_ranked.route_id = gtfs.route_id
		AND trip_ranked.trac_agency_id = gtfs.trac_agency_id
		AND trip_ranked.trac_trip_id = gtfs.trip_id
		AND CASE -- JOIN ON time OF txn time
	   		WHEN trip_ranked.device_mode_id = 10 OR trip_ranked.device_mode_id = 11 -- lightrail OR sounder
	   			THEN
	   				gtfs.departure_time BETWEEN
	   					trip_ranked.device_dtm_interval + INTERVAL '1 minutes' -- AFTER tap, allow upto 1 min TO GET TO the lightrail/sounder BY stairs/elevators
	   					AND trip_ranked.device_dtm_interval + INTERVAL '45 minutes' -- AFTER tap, might need TO wait upto 30 mins BEFORE the lightrail/sounder depart
	   		ELSE -- bus
	   			gtfs.departure_time BETWEEN
	   				trip_ranked.device_dtm_interval - INTERVAL '2 minutes' -- bus arriving 2 minutes early from the schedule
	   				AND trip_ranked.device_dtm_interval + INTERVAL '45 minutes' -- bus arriving 30 minutes late from the schedule
	   	    END
	   	AND CASE 
	   		WHEN stop_exist = 1 
	   			THEN
	   				gtfs.stop_id =  trip_ranked.stop_code
	   		ELSE TRUE 
	   	    END
	WHERE ((ranked = 1 AND stop_exist = 2)
		  OR (ranked <= 3 AND stop_exist = 1))); --  22,827,175

		
SELECT COUNT(DISTINCT txn_id)
FROM _test.boarding_avl_trac_april23_20240413_raw;


<<<<<<< Updated upstream
CREATE TABLE _test.boarding_avl_trac_april23_20240413 AS (
	SELECT *
	FROM _test.boarding_avl_trac_april23_20240413_raw
	WHERE trac_rank = 1
); -- 5,016,712
=======
	
	
SELECT DISTINCT direction_id, orca_updated_direction, avl_direction, trac_direction_ids
FROM _test.boarding_avl_trac_april23
WHERE trac_agency_id = 6;



SELECT DISTINCT trac_agency_id, direction_id, alt_direction_id FROM _test.gtfs_route_direction_april23;
>>>>>>> Stashed changes


-- quick summary of avl_check_code and trac_check_code	
SELECT  avl_check_code
		, trac_check_code
		, COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage_overall
FROM _test.boarding_avl_trac_april23_20240413
GROUP BY avl_check_code, trac_check_code;







--- now join on the GTFS with the ORCA route name and stop_code


-- gtfs_check_code: check if the stops serve the route in this specified orca_direction
	-- Case 1: Where this stop_code do serve this route:
		-- (1.1) if orca direction is contained within gtfs_combined_direction
		-- (1.2) if orca direction NOT contained within gtfs_combined_direction
		-- 			BUT AVL is 
		-- (1.3) GTFS does not agree to both orca AND avl OR avl is null 
	-- Case 2: Where this stop_code do NOT serve this route -- No GTFS matched:
		-- (2) 
CREATE TABLE _test.boarding_avl_trac_gtfs_april23_20240413 AS (
	WITH gtfs_ranked AS (
		SELECT DISTINCT 
			  orca.*
			, gtfs.trip_id AS gtfs_trip_id
			, gtfs.stop_location AS gtfs_stop_location
			, abs_interval(gtfs.departure_time - orca.device_dtm_interval) AS gtfs_time_difference
			, ST_Distance(st_transform(orca.device_location, 32610), st_transform(gtfs.stop_location, 32610)) AS distance_gtfs_orca
			, gtfs.alt_direction_id AS gtfs_alt_direction_id
			, CASE 
				WHEN (ARRAY[COALESCE(orca.orca_updated_direction, orca.direction_id)] <@ gtfs.alt_direction_id)
					THEN 1.1 -- WHEN orca matched
				WHEN (ARRAY[orca.avl_direction] <@ gtfs.alt_direction_id)
					THEN 1.2 -- WHEN orca does not matched but avl matched
				WHEN gtfs.alt_direction_id IS NOT NULL
					THEN 1.3 -- the stop serve the route but none of direction matched
				WHEN gtfs.alt_direction_id IS NULL
					THEN 2  -- WHEN this orca stop does NOT serve this route AT all
			  END AS gtfs_check_code
			, ROW_NUMBER() OVER (
				PARTITION BY orca.txn_id
				ORDER BY
					CASE 
						WHEN (ARRAY[COALESCE(orca.orca_updated_direction, orca.direction_id)] <@ gtfs.alt_direction_id)
							  OR (ARRAY[orca.avl_direction] <@ gtfs.alt_direction_id)
							THEN 1 -- WHEN orca/avl direction matched
						WHEN gtfs.alt_direction_id IS NOT NULL
							THEN 2 -- the stop serve the route but none of direction matched
						WHEN gtfs.alt_direction_id IS NULL
							THEN 3 -- WHEN this orca stop does NOT serve this route AT all
					END ASC -- FIRST, ORDER BY the direction
					, abs_interval(gtfs.departure_time - orca.device_dtm_interval) ASC -- THEN BY the time difference
			  ) AS gtfs_rank
		FROM _test.boarding_avl_trac_april23_20240413 orca
		LEFT JOIN _test.gtfs_route_service_exception_20240413 exc -- EXCEPTION service dates for the route/shape
			ON exc.feed_id = orca.feed_id
			   AND exc.trac_agency_id = orca.trac_agency_id
			   AND exc.route_id = orca.route_id
			   AND orca.business_date = exc.date
		LEFT JOIN _test.gtfs_route_trip_stop_sequence_20240413 gtfs
	    		ON 	orca.feed_id = gtfs.feed_id
	    			AND orca.route_id = gtfs.route_id
	    			AND orca.trac_agency_id = gtfs.trac_agency_id
	    			AND orca.stop_code = gtfs.stop_id -- JOIN ON stop id
	    			AND CASE -- JOIN ON time OF txn time
				   		WHEN orca.device_mode_id = 10 OR orca.device_mode_id = 11 -- lightrail OR sounder
				   			THEN
				   				gtfs.departure_time BETWEEN
				   					orca.device_dtm_interval - INTERVAL '1 minutes' -- AFTER tap, allow upto 1 min TO GET TO the lightrail/sounder BY stairs/elevators
				   					AND orca.device_dtm_interval + INTERVAL '45 minutes' -- AFTER tap, might need TO wait upto 30 mins BEFORE the lightrail/sounder depart
				   		ELSE -- bus
				   			gtfs.departure_time BETWEEN
				   				orca.device_dtm_interval - INTERVAL '2 minutes' -- bus arriving 2 minutes early from the schedule
				   				AND orca.device_dtm_interval + INTERVAL '45 minutes' -- bus arriving 30 minutes late from the schedule
				   	    END
					AND -- JOIN ON service day
					   CASE
				            WHEN orca.txn_dow = 0 -- SUNDAY
				            	THEN
				            		   (gtfs.sunday = 1 AND exc.exception_type IS NULL)
				            		OR (gtfs.sunday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
				            		OR (gtfs.sunday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
				            		OR (gtfs.sunday IS NULL)
				            WHEN orca.txn_dow = 1 -- MONDAY
				            	THEN
				            		   (gtfs.monday = 1 AND exc.exception_type IS NULL)
				            		OR (gtfs.monday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
				            		OR (gtfs.monday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
				            		OR (gtfs.monday IS NULL)
				            WHEN orca.txn_dow = 2 -- TUESDAY
				            	THEN
				            		   (gtfs.tuesday = 1 AND exc.exception_type IS NULL)
				            		OR (gtfs.tuesday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
				            		OR (gtfs.tuesday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
				            		OR (gtfs.tuesday IS NULL)
				            WHEN orca.txn_dow = 3 -- WEDNESDAY
				            	THEN
				            		   (gtfs.wednesday = 1 AND exc.exception_type IS NULL)
				            		OR (gtfs.wednesday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
				            		OR (gtfs.wednesday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
				            		OR (gtfs.wednesday IS NULL)
				            WHEN orca.txn_dow = 4 -- THURSDAY
				            	THEN
				            		   (gtfs.thursday = 1 AND exc.exception_type IS NULL)
				            		OR (gtfs.thursday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
				            		OR (gtfs.thursday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
				            		OR (gtfs.thursday IS NULL)
				            WHEN orca.txn_dow = 5 -- FRIDAY
				            	THEN
				            		   (gtfs.friday = 1 AND exc.exception_type IS NULL)
				            		OR (gtfs.friday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
				            		OR (gtfs.friday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)
				            		OR (gtfs.friday IS NULL)
				            WHEN orca.txn_dow = 6 -- SATURDAY
				            	THEN
				            		   (gtfs.saturday = 1 AND exc.exception_type IS NULL)
				            		OR (gtfs.saturday = 1 AND exc.trip_id = gtfs.trip_id AND exc.exception_type != 2)
				            		OR (gtfs.saturday = 0 AND exc.trip_id = gtfs.trip_id AND exc.exception_type = 1)  
				            		OR (gtfs.saturday IS NULL)
					  END
	)
	SELECT *
	FROM gtfs_ranked
	WHERE gtfs_rank = 1
); -- 5,016,712


-- quick summary of avl_check_code,  trac_check_code, gtfs_check_code
SELECT  avl_check_code
		, trac_check_code
		, gtfs_check_code
		, COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage_overall
FROM _test.boarding_avl_trac_gtfs_april23_20240413
GROUP BY avl_check_code, trac_check_code, gtfs_check_code;

SELECT  avl_check_code
		, trac_check_code
		, gtfs_check_code
		, COUNT(*) / SUM(COUNT(*)) OVER () AS percentage_overall
FROM _test.boarding_avl_trac_gtfs_april23_20240413_test
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
CREATE TABLE _test.boarding_action_final_april23_20240413 AS (
	SELECT    txn_id
			, coach_number
			, feed_id
			, route_id AS gtfs_route_id
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR (trac_check_code = 4 
							AND gtfs_check_code = 2)
					THEN NULL -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN gtfs_trip_id
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN gtfs_trip_id
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN trac_trip_id
				WHEN (avl_check_code < 2 AND gtfs_check_code = 1.3) -- gtfs-orca
					 OR (avl_check_code = 3 AND trac_check_code = 4 AND gtfs_check_code = 1.3)
					THEN gtfs_trip_id --'gtfs'
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 
					THEN CASE 
						WHEN gtfs_time_difference < trac_time_difference -- gtfs-orca
							THEN gtfs_trip_id --'gtfs'
						WHEN gtfs_time_difference >= trac_time_difference -- orca-trac
							THEN trac_trip_id
						ELSE '-99' -- extra case, this IS FOR double checking
					END
			END AS gtfs_trip_id
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
						OR (trac_check_code = 4 
							AND gtfs_check_code = 2)
					THEN NULL -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN COALESCE(orca_updated_direction, direction_id)
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN avl_direction
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN COALESCE(orca_updated_direction, direction_id)
				WHEN (avl_check_code < 2 AND gtfs_check_code = 1.3) -- gtfs-orca
					 OR (avl_check_code = 3 AND trac_check_code = 4 AND gtfs_check_code = 1.3)
					THEN CASE 
						WHEN COALESCE(orca_updated_direction, direction_id) = 4 THEN 5
						WHEN COALESCE(orca_updated_direction, direction_id) = 5 THEN 4
						WHEN COALESCE(orca_updated_direction, direction_id) = 6 THEN 7
						WHEN COALESCE(orca_updated_direction, direction_id) = 7 THEN 6
					END
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- other-other
					THEN CASE 
						WHEN gtfs_time_difference < trac_time_difference
							THEN CASE -- gtfs-orca
								WHEN COALESCE(orca_updated_direction, direction_id) = 4 THEN 5
								WHEN COALESCE(orca_updated_direction, direction_id) = 5 THEN 4
								WHEN COALESCE(orca_updated_direction, direction_id) = 6 THEN 7
								WHEN COALESCE(orca_updated_direction, direction_id) = 7 THEN 6
							END 
						WHEN gtfs_time_difference >= trac_time_difference
							THEN COALESCE(orca_updated_direction, direction_id) -- orca-trac
						ELSE -99 -- extra case
					END
			END AS direction_final
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR (trac_check_code = 4 
							AND gtfs_check_code = 2)
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
						WHEN orca_updated_direction IS NOT NULL 
							THEN 2 --'orca updated'
						ELSE 1 --'orca'
					END
				WHEN (avl_check_code < 2 AND gtfs_check_code = 1.3) -- gtfs-orca
					 OR (avl_check_code = 3 AND trac_check_code = 4 AND gtfs_check_code = 1.3)
					THEN 4 --'gtfs'
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 
					THEN CASE 
						WHEN gtfs_time_difference < trac_time_difference -- gtfs-orca
							THEN 4 --'gtfs'
						WHEN gtfs_time_difference >= trac_time_difference -- orca-trac
							THEN CASE -- either orca updated direction, OR orca original !!
								WHEN orca_updated_direction IS NOT NULL 
									THEN 2 --'orca updated'
								ELSE 1 --'orca'
							END
						ELSE -99 -- extra case, this IS FOR double checking
					END
			END AS direction_note
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR (trac_check_code = 4 
							AND gtfs_check_code = 2)
					THEN NULL -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN stop_code
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN stop_code
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN trac_stop_id
				WHEN (avl_check_code < 2 AND gtfs_check_code = 1.3) -- gtfs-orca
					 OR (avl_check_code = 3 AND trac_check_code = 4 AND gtfs_check_code = 1.3)
					THEN stop_code
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- other-other
					THEN CASE 
						WHEN gtfs_time_difference < trac_time_difference
							THEN stop_code -- gtfs-orca
						WHEN gtfs_time_difference >= trac_time_difference
							THEN trac_stop_id -- orca-trac
						ELSE '-99' -- extra case, this IS FOR doublechecking
					END
			END AS stop_final
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR (trac_check_code = 4 
							AND gtfs_check_code = 2)
					THEN -1 -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN 1 -- orca
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN 1 -- orca
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN 5 -- trac
				WHEN (avl_check_code < 2 AND gtfs_check_code = 1.3) -- gtfs-orca
					 OR (avl_check_code = 3 AND trac_check_code = 4 AND gtfs_check_code = 1.3)
					THEN 1 -- orca
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3
					THEN CASE 
						WHEN gtfs_time_difference < trac_time_difference -- gtfs-orca
							THEN 1 -- orca
						WHEN gtfs_time_difference >= trac_time_difference  -- orca-trac
							THEN 5 -- trac
						ELSE -99 -- this IS FOR doublechecking
					END
			END AS stop_note
			, CASE
				WHEN avl_check_code = 2.1
						OR avl_check_code = 2.2
						OR (trac_check_code = 4 
							AND gtfs_check_code = 2)
					THEN NULL -- cant locate
				WHEN gtfs_check_code = 1.1 -- orca-orca
					THEN gtfs_stop_location
				WHEN gtfs_check_code = 1.2 -- avl-orca
					THEN gtfs_stop_location
				WHEN gtfs_check_code = 2 -- orca-trac
					THEN trac_stop_location
				WHEN (avl_check_code < 2 AND gtfs_check_code = 1.3) -- gtfs-orca
					 OR (avl_check_code = 3 AND trac_check_code = 4 AND gtfs_check_code = 1.3)
					THEN gtfs_stop_location
				WHEN avl_check_code = 3 AND trac_check_code = 2 AND gtfs_check_code = 1.3 -- other-other
					THEN CASE 
						WHEN gtfs_time_difference < trac_time_difference
							THEN gtfs_stop_location -- gtfs-orca
						WHEN gtfs_time_difference >= trac_time_difference
							THEN trac_stop_location -- orca-trac
						ELSE NULL -- extra case
					END
			END AS stop_location
	FROM _test.boarding_avl_trac_gtfs_april23_20240413
); -- 5,016,712





 

-- check if there are cases where we did not consider and they have 9999 code
SELECT *
FROM _test.boarding_action_final_april23_20240413
WHERE direction_final = -99 OR stop_final = '-99';





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
     , COUNT(*) FILTER (
     	WHERE og.device_location IS NULL
     ) AS null_location
     , COUNT(*) FILTER (
     	WHERE og.device_location IS NULL
     		  AND fixed.stop_location IS NOT NULL
     ) AS fixed_location
     , COUNT(*) FILTER (
     	WHERE og.stop_code IS NULL
     ) AS null_stop_code
     , COUNT(*) FILTER (
     	WHERE og.stop_code IS NULL
     		  AND fixed.stop_final IS NOT NULL
     ) AS fixed_stop_code
FROM  _test.boarding_action_final_april23_20240413 fixed
JOIN _test.boarding_april23_20240413 og
ON fixed.txn_id = og.txn_id;



SELECT fixed.*
FROM  _test.boarding_action_final_april23_20240413 fixed
JOIN _test.boarding_april23_20240413 og
ON fixed.txn_id = og.txn_id
WHERE og.route_number = '217';



