

SELECT *
FROM 
	(SELECT t.trip_id
	FROM _test.real_transitland_trips t
	JOIN _test.real_transitland_routes r
		ON t.feed_id = r.feed_id AND t.route_id = r.route_id
	WHERE r.route_short_name = '5' AND r.agency_id = '1'
		AND r.feed_id = 315351) t5
JOIN (SELECT t.trip_id
	FROM _test.real_transitland_trips t
	JOIN _test.real_transitland_routes r
		ON t.feed_id = r.feed_id AND t.route_id = r.route_id
	WHERE r.route_short_name = '21' AND r.agency_id = '1'
		AND r.feed_id = 315351) t21
ON t5.trip_id = t21.trip_id;

SELECT * FROM orca.v_linked_transactions vlt LIMIT 10;


 
 


-- general process for alighting processing:
/*
if light rail OR sounder:
  if there is an alight_txn_id in v_linked_transactions:
    ?verify that orca.transactions stop_id is along gtfs route?
    use orca.transactions stop_id and device_dtm_pacific for alighting info
    also get disance from stop to next boarding stop
  if no alight_txn_id: this becomes like the bus tapoff estimate
    use gtfs data to get next light rail stop within 1/3 mile of next boarding
if bus and route not 44444 or 22222:
  use next boarding stop location to find any stops along current route within 1/3 mile
if bus and route 44444 or 22222:
  use process written on paper
*/

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

/*-------------------- PRE-PROCESSING 44444/22222 --------------------*/
-- first, extract the data in aprol
CREATE TABLE _test.extracted_44444_april23 AS (
	SELECT *
		   , EXTRACT(DOW FROM business_date) AS txn_dow
		   , CASE 
				WHEN date_trunc('day', device_dtm_pacific) > business_date
					THEN TO_CHAR(device_dtm_pacific, 'HH24:MI:SS')::INTERVAL + '24 hours'
				ELSE TO_CHAR(device_dtm_pacific, 'HH24:MI:SS')::INTERVAL
			 END AS device_dtm_interval
	FROM orca.v_boardings 
	WHERE (route_number = '44444' OR route_number = '22222')
		  AND business_date BETWEEN '2023-04-01' AND '2023-04-30');
	  

-- fill in the missing information - device location and stop code
WITH ModifiedData AS (
	SELECT DISTINCT null_data.txn_id, non_null.device_location AS updated_device_location, non_null.stop_code AS updated_stop_code
	FROM _test.extracted_44444_april23 non_null
	JOIN _test.extracted_44444_april23 AS null_data
		ON null_data.source_agency_id = non_null.source_agency_id
			AND null_data.device_id = non_null.device_id
			AND non_null.device_location IS NOT NULL
		  	AND non_null.stop_code IS NOT NULL
		  	AND (null_data.device_location IS NULL OR null_data.stop_code IS NULL)
)
UPDATE _test.extracted_44444_april23 original
SET device_location = ModifiedData.updated_device_location
	, stop_code = ModifiedData.updated_stop_code
FROM ModifiedData
WHERE original.txn_id = ModifiedData.txn_id;


-- this view contains the shape/direction/stop/stop sequence for each feed/route with valid start/end date
-- this also includes the day-of-week columns
CREATE VIEW _test.gtfs_route_stop_sequence AS (
	SELECT DISTINCT r.feed_id
					, r.route_id
					, r.trac_agency_id
					, t.shape_id
					, t.direction_id
					, FIRST_VALUE(c.monday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, t.direction_id, st.stop_id, st.stop_sequence ORDER BY c.monday DESC) AS monday
					, FIRST_VALUE(c.tuesday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, t.direction_id, st.stop_id, st.stop_sequence ORDER BY c.tuesday DESC) AS tuesday
					, FIRST_VALUE(c.wednesday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, t.direction_id, st.stop_id, st.stop_sequence ORDER BY c.wednesday DESC) AS wednesday
					, FIRST_VALUE(c.thursday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, t.direction_id, st.stop_id, st.stop_sequence ORDER BY c.thursday DESC) AS thursday
					, FIRST_VALUE(c.friday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, t.direction_id, st.stop_id, st.stop_sequence ORDER BY c.friday DESC) AS friday
					, FIRST_VALUE(c.saturday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, t.direction_id, st.stop_id, st.stop_sequence ORDER BY c.saturday DESC) AS saturday
					, FIRST_VALUE(c.sunday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, t.direction_id, st.stop_id, st.stop_sequence ORDER BY c.sunday DESC) AS sunday
					, st.stop_id
					, st.stop_sequence
					, s.stop_location
					, r.start_date
					, r.end_date
	FROM _test.latest_gtfs_feeds r -- this IS the TABLE we need FOR the route information
	JOIN  _test.real_transitland_trips t
		ON  r.feed_id = t.feed_id
			AND t.route_id = r.route_id
	JOIN _test.real_transitland_stop_times st
		ON st.feed_id = r.feed_id
			AND st.trip_id = t.trip_id
	JOIN _test.real_transitland_calendar c
		ON t.feed_id = c.feed_id 
			AND c.service_id = t.service_id
	JOIN _test.real_transitland_stops s
		ON s.feed_id = r.feed_id
			AND s.stop_id = st.stop_id
	ORDER BY r.feed_id, r.trac_agency_id, r.route_id, t.shape_id, st.stop_sequence ASC
);


--- NEW approach:
	-- This is the view where we have all different kind of trips and the arrival time for each stop
	--  also for each route, we have the valid start and end date, which help with the join
CREATE VIEW _test.gtfs_route_trip_stop_sequence AS (
	SELECT DISTINCT r.feed_id
					, r.route_id
					, r.trac_agency_id
					, t.trip_id
					, t.shape_id
					, t.direction_id
					, FIRST_VALUE(c.monday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id ORDER BY c.monday DESC) AS monday
					, FIRST_VALUE(c.tuesday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id ORDER BY c.tuesday DESC) AS tuesday
					, FIRST_VALUE(c.wednesday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id ORDER BY c.wednesday DESC) AS wednesday
					, FIRST_VALUE(c.thursday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id ORDER BY c.thursday DESC) AS thursday
					, FIRST_VALUE(c.friday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id ORDER BY c.friday DESC) AS friday
					, FIRST_VALUE(c.saturday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id ORDER BY c.saturday DESC) AS saturday
					, FIRST_VALUE(c.sunday) OVER (PARTITION BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id ORDER BY c.sunday DESC) AS sunday
					, st.arrival_time
					, st.departure_time
					, st.stop_id
					, st.stop_sequence
					, s.stop_location
					, r.start_date
					, r.end_date
	FROM _test.latest_gtfs_feeds r -- this IS the TABLE we need FOR the route information
	JOIN  _test.real_transitland_trips t
		ON  r.feed_id = t.feed_id
			AND t.route_id = r.route_id
	JOIN _test.real_transitland_stop_times st
		ON st.feed_id = r.feed_id
			AND st.trip_id = t.trip_id
	JOIN _test.real_transitland_calendar c
		ON t.feed_id = c.feed_id 
			AND c.service_id = t.service_id
	JOIN _test.real_transitland_stops s
		ON s.feed_id = r.feed_id
			AND s.stop_id = st.stop_id
	ORDER BY r.feed_id, r.trac_agency_id, r.route_id, t.trip_id, t.shape_id, st.stop_sequence ASC
);




-- This returns the feed, route, trac_agency_id, shape, direction, date of service and exception type
	-- useful for the join between orca and gtfs
	-- because we want to make sure the date of the txn matches the date of service and extra service
CREATE VIEW _test.gtfs_route_service_exception AS (
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
);



-------------------------------

-- To link between orca and gtfs:
	-- for each stop_code from orca, we join with gtfs
		-- and pick the latest feed option if the same route, same shape, same direction
	-- also join orca with the exception service dates
		-- to narrow down the option we have
		-- we have to make sure the txn takes place in the date of the scheduled service.
CREATE TABLE _test.extracted_44444_gtfs_april23 AS (
	WITH orca_latest_feed AS (
		SELECT DISTINCT 
			     orca.txn_id
			   , orca.txn_dow
			   , orca.stop_code
			   , orca.device_location
			   , orca.business_date
			   , orca.device_dtm_pacific
			   , orca.device_dtm_interval
			   , orca.direction_id
			   , gtfs_t.feed_id
			   , gtfs_t.route_id
			   , gtfs_t.trac_agency_id
			   , gtfs_t.trip_id
			   , gtfs_t.shape_id
			   , gtfs_t.direction_id AS gtfs_direction_id
			   , gtfs_t.stop_sequence
			   , gtfs_t.stop_location
			   , (gtfs_t.departure_time - orca.device_dtm_interval) AS est_wait_time -- estimate waiting time AFTER the tap
			   , ROW_NUMBER() OVER (
			   		PARTITION BY orca.txn_id, gtfs_t.route_id, gtfs_t.trac_agency_id, gtfs_t.shape_id, gtfs_t.direction_id
			   		ORDER BY gtfs_t.feed_id DESC, abs_interval(gtfs_t.departure_time - orca.device_dtm_interval) ASC ) AS latest_gtfs
		FROM _test.extracted_44444_april23 orca -- orca
		LEFT JOIN trac.agencies trac -- lookup TABLE for agency_id BETWEEN orca AND gtfs
			ON trac.orca_agency_id = orca.source_agency_id 
		JOIN _test.gtfs_route_trip_stop_sequence gtfs_t
			ON orca.business_date BETWEEN gtfs_t.start_date AND gtfs_t.end_date -- ORCA txn must between valid START and END date
			   AND gtfs_t.trac_agency_id = trac.agency_id
			   AND gtfs_t.stop_id = orca.stop_code -- must MATCH stop_id
			   AND (gtfs_t.departure_time - orca.device_dtm_interval) BETWEEN '-00:00:30' AND '00:45:00' -- orca tap time should be WITHIN -00:30 and 45:00 mins WINDOW OF the scheduled arrival time
		LEFT JOIN _test.gtfs_route_service_exception exc -- EXCEPTION service dates for the route/shape
			ON exc.feed_id = gtfs_t.feed_id
			   AND exc.trac_agency_id = gtfs_t.trac_agency_id
			   AND exc.route_id = gtfs_t.route_id
			   AND exc.trip_id = gtfs_t.trip_id
			   AND orca.business_date = exc.date
		WHERE CASE 
	            WHEN orca.txn_dow = 0 -- SUNDAY
	            	THEN
	            		(gtfs_t.sunday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL)) 
	            		OR (gtfs_t.sunday = 0 AND exc.exception_type = 1)
	            WHEN orca.txn_dow = 1 -- MONDAY
	            	THEN
	            		(gtfs_t.monday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.monday = 0 AND exc.exception_type = 1)
	            WHEN orca.txn_dow = 2 -- TUESDAY
	            	THEN
	            		(gtfs_t.tuesday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.tuesday = 0 AND exc.exception_type = 1)
	            WHEN orca.txn_dow = 3 -- WEDNESDAY
	            	THEN
	            		(gtfs_t.wednesday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.wednesday = 0 AND exc.exception_type = 1)
	            WHEN orca.txn_dow = 4 -- THURSDAY
	            	THEN
	            		(gtfs_t.thursday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.thursday = 0 AND exc.exception_type = 1)
	            WHEN orca.txn_dow = 5 -- FRIDAY
	            	THEN
	            		(gtfs_t.friday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.friday = 0 AND exc.exception_type = 1)
	            WHEN orca.txn_dow = 6 -- SATURDAY
	            	THEN 
	            		(gtfs_t.saturday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.saturday = 0 AND exc.exception_type = 1)
		      END
		ORDER BY txn_id ASC
	)
 	SELECT *
	FROM orca_latest_feed
	WHERE latest_gtfs = 1
); -- 54,398



-- Sanity check:
	-- how many distinct txn_id AFTER joining with GTFS: 6,451
SELECT COUNT(DISTINCT txn_id)
FROM _test.extracted_44444_gtfs_april23;



-- How many distinct txn_id we originally have? 6,458
SELECT COUNT(DISTINCT txn_id)
FROM _test.extracted_44444_april23;

--- SAVE this for SANITY CHECK
	-- this returns the location and the distance between orca and gtfs for each stop code 
	-- we would use the gtfs stop_location!
SELECT stop_code, device_location, stop_location, MIN(ST_Distance(st_transform(device_location, 32610), stop_location)), MAX(ST_Distance(st_transform(device_location, 32610), stop_location)), count(*)
FROM _test.extracted_44444_gtfs_april23
GROUP BY stop_code, device_location, stop_location;


---------------------------
-- now get the next txn from these extracted 44444/22222 txn
-- get NEXT boarding stop for all 44444 boardings
CREATE TABLE _test.next_boarding_locations_apr23_44444 AS (
	SELECT DISTINCT nx.txn_id
			, nx.route_number
			, nx.service_agency_id
			, nx.source_agency_id
			, nx.business_date
			, nx.device_dtm_pacific
			, CASE 
				WHEN date_trunc('day', nx.device_dtm_pacific) > nx.business_date
					THEN TO_CHAR(nx.device_dtm_pacific, 'HH24:MI:SS')::INTERVAL + '24 hours'
				ELSE TO_CHAR(nx.device_dtm_pacific, 'HH24:MI:SS')::INTERVAL
			  END AS device_dtm_interval
			, EXTRACT(DOW FROM nx.business_date) AS txn_dow
			, FIRST_VALUE(COALESCE(nb.feed_id, nb4.feed_id)) OVER (PARTITION BY nx.txn_id ORDER BY COALESCE(nb.feed_id, nb4.feed_id) DESC) AS feed_id
			, coalesce(nb.stop_final, nx.stop_code) AS stop_code
			, FIRST_VALUE(COALESCE(nb.stop_location, nb4.stop_location)) OVER (PARTITION BY nx.txn_id ORDER BY COALESCE(nb.feed_id, nb4.feed_id) DESC) AS stop_location -- we need to standardize the stop location (we would trust the stop_code for now) this would be NULL IF we don't yet have it IN our boarding_action_final
	  FROM  _test.extracted_44444_april23 e
	  JOIN  orca.v_linked_transactions vlt
	  	ON vlt.txn_id = e.txn_id
	  JOIN  orca.v_boardings nx
	  	ON nx.txn_id = vlt.next_txn_id
	  LEFT JOIN _test.boarding_action_final_april23 nb
	  	ON nb.txn_id = vlt.next_txn_id
	  		AND nb.stop_final IS NOT NULL 
	  LEFT JOIN _test.extracted_44444_gtfs_april23 nb4
	  	ON nb4.txn_id = vlt.next_txn_id ); --6257

	  
	  
SELECT COUNT(*)
FROM _test.next_boarding_locations_apr23_44444
WHERE stop_location IS NULL AND stop_code IS NOT NULL; --1015


-- we can update the stop_location for all the txn_id with NO stop_location
	-- we need to trust orca's stop code, and route_number (if exists -- not 44444/22222)
WITH ModifiedData AS (
	SELECT DISTINCT
			 orca.txn_id
		   , gtfs_s.feed_id
		   , gtfs_s.stop_location
		   , ROW_NUMBER() OVER (
		   		PARTITION BY orca.txn_id
		   		ORDER BY
		   			CASE
			            WHEN gtfs_rn.route_id IS NOT NULL THEN 1 -- prioritize matching route names
			            ELSE 2 -- prioritize by feed_id if no match
			        END ASC,
			        gtfs_s.feed_id DESC
		   		) AS latest_gtfs
	FROM _test.next_boarding_locations_apr23_44444 orca -- orca
	LEFT JOIN trac.route_name_lookup lookup
		ON orca.route_number = lookup.route_number
			AND orca.service_agency_id = lookup.service_agency_id -- the lookup uses service_agency_id INSTEAD OF SOURCE
	LEFT JOIN trac.agencies trac -- lookup TABLE for agency_id BETWEEN orca AND gtfs
		ON trac.orca_agency_id = orca.source_agency_id
			OR trac.agency_id = lookup.trac_agency_id
	JOIN _test.latest_gtfs_feeds gtfs_rn -- this IS FOR the cases WHERE the route_name NOT 44444/22222, because we want TO make sure the route/stop must match if it exists 
		ON orca.business_date BETWEEN gtfs_rn.start_date AND gtfs_rn.end_date -- WITHIN START AND END date 
		   AND gtfs_rn.trac_agency_id = trac.agency_id
		   AND (
		   		CASE 
			   		WHEN orca.route_number = '44444' OR orca.route_number = '22222' -- This is added to always evaluate to TRUE, so it won't affect the join
			   			THEN TRUE
			   		ELSE -- WHEN the route_name EXISTS, THEN we need TO double check
			   			(gtfs_rn.route_short_name ILIKE orca.route_number
						OR COALESCE(gtfs_rn.route_short_name, gtfs_rn.route_long_name) ILIKE lookup.gtfs_route_name) 
		   		END )
	JOIN _test.gtfs_route_stop_sequence gtfs_s
		ON gtfs_s.stop_id = orca.stop_code -- must MATCH stop_id
		   AND gtfs_s.trac_agency_id = trac.agency_id
		   AND (
		   		CASE 
			   		WHEN orca.route_number = '44444' OR orca.route_number = '22222' -- This is added to always evaluate to TRUE, so it won't affect the join
			   			THEN TRUE
			   		ELSE
					    gtfs_s.route_id = gtfs_rn.route_id
					    AND gtfs_s.feed_id = gtfs_rn.feed_id
			   	END )
	WHERE orca.stop_location IS NULL
		  AND orca.stop_code IS NOT NULL -- this make sure that ONLY the CASE WHERE the stop_location IS NULL AND stop_code NOT NULL ARE considered
	ORDER BY orca.txn_id ASC, latest_gtfs DESC
)
UPDATE _test.next_boarding_locations_apr23_44444 original
SET feed_id = ModifiedData.feed_id
	, stop_location = ModifiedData.stop_location
FROM ModifiedData
WHERE original.txn_id = ModifiedData.txn_id
	  AND ModifiedData.latest_gtfs = 1; -- 958
	 

-- how much left after the update?
SELECT *
FROM _test.next_boarding_locations_apr23_44444
WHERE stop_location IS NULL AND stop_code IS NOT NULL; --57



-- NOTE: This is because it fails joining the stop_id between ORCA and GTFS!
	-- the stop_id that ORCA provides does not exist in GTFS, at least for the txn within the valid date range of GTFS
WITH ModifiedData AS (
	SELECT DISTINCT
			 orca.txn_id
		   , gtfs_s.feed_id
		   , gtfs_s.stop_location
		   , ROW_NUMBER() OVER (
		   		PARTITION BY orca.txn_id
		   		ORDER BY
		   			CASE
			            WHEN gtfs_rn.route_id IS NOT NULL THEN 1 -- prioritize matching route names
			            ELSE 2 -- prioritize by feed_id if no match
			        END ASC,
			        gtfs_s.feed_id DESC
		   		) AS latest_gtfs
	FROM _test.next_boarding_locations_apr23_44444 orca -- orca
	LEFT JOIN trac.route_name_lookup lookup
		ON orca.route_number = lookup.route_number
			AND orca.service_agency_id = lookup.service_agency_id -- the lookup uses service_agency_id INSTEAD OF SOURCE
	LEFT JOIN trac.agencies trac -- lookup TABLE for agency_id BETWEEN orca AND gtfs
		ON trac.orca_agency_id = orca.source_agency_id
			OR trac.agency_id = lookup.trac_agency_id
	JOIN _test.latest_gtfs_feeds gtfs_rn -- this IS FOR the cases WHERE the route_name NOT 44444/22222, because we want TO make sure the route/stop must match if it exists 
		ON orca.business_date BETWEEN gtfs_rn.start_date AND gtfs_rn.end_date -- WITHIN START AND END date 
		   AND gtfs_rn.trac_agency_id = trac.agency_id
		   AND (
		   		CASE 
			   		WHEN orca.route_number = '44444' OR orca.route_number = '22222' -- This is added to always evaluate to TRUE, so it won't affect the join
			   			THEN TRUE
			   		ELSE -- WHEN the route_name EXISTS, THEN we need TO double check
			   			(gtfs_rn.route_short_name ILIKE orca.route_number
						OR COALESCE(gtfs_rn.route_short_name, gtfs_rn.route_long_name) ILIKE lookup.gtfs_route_name) 
		   		END )
	JOIN _test.gtfs_route_stop_sequence gtfs_s
		ON gtfs_s.stop_id = orca.stop_code -- must MATCH stop_id
		   AND gtfs_s.trac_agency_id = trac.agency_id
		   AND (
		   		CASE 
			   		WHEN orca.route_number = '44444' OR orca.route_number = '22222' -- This is added to always evaluate to TRUE, so it won't affect the join
			   			THEN TRUE
			   		ELSE
					    gtfs_s.route_id = gtfs_rn.route_id
					    AND gtfs_s.feed_id = gtfs_rn.feed_id
			   	END )
	WHERE orca.stop_location IS NULL
		  AND orca.stop_code IS NOT NULL -- this make sure that ONLY the CASE WHERE the stop_location IS NULL AND stop_code NOT NULL ARE considered
	ORDER BY orca.txn_id ASC, latest_gtfs DESC)
SELECT COUNT(*)
FROM ModifiedData
WHERE ModifiedData.latest_gtfs = 1;


-- how much of the data that we can't use in total?
SELECT COUNT(*)
FROM _test.next_boarding_locations_apr23_44444
WHERE stop_location IS NULL; --180



------------------------------------------

-- get all the later stops from the boardings for that feed/route/shape
-- within 1/3 miles (536.5m) of each nxt txn stop:
CREATE VIEW _test.alight_stop_april23_44444 AS (
	WITH nxt_boarding_ranked AS (
		SELECT  b.txn_id
			    , b.txn_dow
				, b.business_date
				, b.device_dtm_pacific
				, b.device_dtm_interval
				, b.stop_code
				, b.feed_id
				, b.route_id
				, b.trac_agency_id
				, b.shape_id
				, b.gtfs_direction_id
				, b.stop_sequence
				, b.stop_location
				, b.est_wait_time
				, ns.feed_id AS alight_feed_id
				, ns.stop_id AS alight_stop_id
				, ns.stop_sequence AS alight_stop_sequence
				, ns.stop_location AS alight_stop_location
				, (b.business_date + ns.arrival_time) AS alight_dtm_pacific
				, ST_Distance(ns.stop_location, nb.stop_location) AS nxt_stop_dist_m
				, ROW_NUMBER() OVER (
					PARTITION BY nb.txn_id, b.txn_id
					-- choosing the shortest wait time over shortest walk time
					ORDER BY abs_interval(b.est_wait_time), ST_Distance(ns.stop_location, nb.stop_location) ASC
				  ) AS distance_rank
		FROM _test.extracted_44444_gtfs_april23 b -- **first** boarding
		JOIN _test.gtfs_route_trip_stop_sequence ns	-- ALL possible stops AFTER the **first** boarding
			ON b.feed_id = ns.feed_id
				AND b.route_id = ns.route_id
				AND b.trac_agency_id = ns.trac_agency_id
				AND b.trip_id = ns.trip_id
				AND b.shape_id = ns.shape_id
				AND b.stop_sequence < ns.stop_sequence -- NEXT stop SEQUENCE must be greater than the **FIRST** boarding stop
		JOIN  orca.v_linked_transactions vlt -- linked txn
			ON vlt.txn_id = b.txn_id
		JOIN _test.next_boarding_locations_apr23_44444 nb -- processed nxt boardings
			ON nb.txn_id = vlt.next_txn_id 
				AND nb.stop_location IS NOT NULL 
				AND CASE -- the arrival time OF the alighting txn (minus 5:00 mins) must be less than the NEXT boarding time
						WHEN b.business_date = nb.business_date 
							THEN (ns.arrival_time - '00:05:00') < nb.device_dtm_interval -- we allowing 5min because the gtfs bus scheduled could arrive early
						ELSE TRUE
					END
				AND ST_DWithin(ns.stop_location, nb.stop_location, 536.448) -- WITHIN 1/3 a mile
		)
	SELECT *
	FROM nxt_boarding_ranked
	WHERE distance_rank = 1
);
	


SELECT trac_agency_id, route_id, stop_code, gtfs_direction_id, COUNT(*) 
FROM _test.alight_stop_april23_44444
GROUP BY trac_agency_id, route_id, stop_code, gtfs_direction_id;



SELECT COUNT(DISTINCT txn_id)
FROM _test.alight_stop_april23_44444; -- 4,450 OUT OF 6,451 (44444 with identified stop_location) identified 


SELECT COUNT(*)
FROM _test.alight_stop_april23_44444; -- 4,450



SELECT trac_agency_id, gtfs_route_id, direction_final, COUNT(*)
FROM _test.boarding_action_final_april23
WHERE direction_final IS NOT NULL AND trac_agency_id = 4
GROUP BY trac_agency_id, gtfs_route_id, direction_final;




-- insert into the boarding table
INSERT INTO _test.boarding_action_final_april23 (
	SELECT  txn_id
			, NULL AS coach_number
			, feed_id
			, route_id
			, trac_agency_id
			, NULL AS avl_route -- could look FOR avl DATA IN the future
			, NULL AS avl_stop
			, NULL AS avl_direction
			, NULL AS avl_departure_dtm
			, NULL AS avl_check_code
			, NULL AS trac_check_code
			, NULL AS gtfs_check_code
			, gtfs_direction_id AS direction_final -- IN future, GET the cardinal direction
			, 6 AS direction_note -- 6: original gtfs direction id (inbound - 1 /outbound - 0)
			, stop_code AS stop_final
			, 1 AS stop_note
			, stop_location
	FROM _test.alight_stop_april23_44444 );




----------------------------------

-- alighting locations for april
CREATE TABLE _test.alight_location_april23 (
    txn_id bigint PRIMARY KEY
    ,trac_agency_id smallint NOT NULL
    ,feed_id bigint NOT NULL
    ,stop_id text NOT NULL
    ,alight_dtm_pacific timestamp without time zone     -- tapoff time (if lrt or sounder and they tapped off) or time of AVL bus arrival/departure, OR gtfs scheduled arrival time
    ,interline_route_id text DEFAULT NULL               -- interline route id when alighting route differs from boarding route
    ,tapoff_txn_id bigint DEFAULT NULL                  -- if there is an orca tap off txn
    ,nxt_stop_dist_m real                               -- store in table since joins to computer are slow
    --,location_source_id smallint
    ,updated_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);



-- INSERT the alighting stops OF the 44444 boardings
INSERT INTO _test.alight_location_april23(txn_id, trac_agency_id, feed_id, stop_id, alight_dtm_pacific, nxt_stop_dist_m) (
	SELECT txn_id
			, trac_agency_id
			, alight_feed_id
			, alight_stop_id
			, alight_dtm_pacific
			, nxt_stop_dist_m
	FROM _test.alight_stop_april23_44444
); --4450



---------------------------------
-- Now processing the rest of the identified boardings (those not 44444/22222)
-- from _test.boarding_action_final_april23

CREATE TABLE _test.boarding_locations_apr23 AS (
	SELECT  b_april.txn_id ---- should we CREATE a TABLE WITH ALL the information like this?
			, b_all.route_number
			, b_all.service_agency_id
			, b_all.source_agency_id
			, b_all.business_date
			, b_all.device_dtm_pacific
			, b_all.device_mode_id
			, CASE 
				WHEN date_trunc('day', b_all.device_dtm_pacific) > b_all.business_date
					THEN TO_CHAR(b_all.device_dtm_pacific, 'HH24:MI:SS')::INTERVAL + '24 hours'
				ELSE TO_CHAR(b_all.device_dtm_pacific, 'HH24:MI:SS')::INTERVAL
			  END AS device_dtm_interval
			, EXTRACT(DOW FROM b_all.business_date) AS txn_dow
	  FROM  _test.boarding_action_final_april23 b_april
	  JOIN  orca.v_boardings b_all
	  	ON b_april.txn_id = b_all.txn_id
	  		AND b_april.stop_location IS NOT NULL
	  		AND b_april.direction_note != 6 -- EXCLUDING 44444 boardings
); -- 4,955,026

SELECT trac_agency_id, gtfs_route_id, route_number, device_mode_id, count(*)
FROM _test.boarding_locations_apr23
GROUP BY trac_agency_id, gtfs_route_id, route_number, device_mode_id;


-- next boardings of all boardings that are not 44444/22222
CREATE TABLE _test.next_boarding_locations_apr23 AS (
	SELECT DISTINCT nx.txn_id
			, nx.route_number
			, nx.service_agency_id
			, nx.source_agency_id
			, nx.business_date
			, nx.device_dtm_pacific
			, CASE 
				WHEN date_trunc('day', nx.device_dtm_pacific) > nx.business_date
					THEN TO_CHAR(nx.device_dtm_pacific, 'HH24:MI:SS')::INTERVAL + '24 hours'
				ELSE TO_CHAR(nx.device_dtm_pacific, 'HH24:MI:SS')::INTERVAL
			  END AS device_dtm_interval
			, EXTRACT(DOW FROM nx.business_date) AS txn_dow
			, FIRST_VALUE(COALESCE(nb.feed_id, nb4.feed_id)) OVER (PARTITION BY nx.txn_id ORDER BY COALESCE(nb.feed_id, nb4.feed_id) DESC) AS feed_id
			, coalesce(nb.stop_final, nx.stop_code) AS stop_code
			, FIRST_VALUE(COALESCE(nb.stop_location, nb4.stop_location)) OVER (PARTITION BY nx.txn_id ORDER BY COALESCE(nb.feed_id, nb4.feed_id) DESC) AS stop_location -- we need to standardize the stop location (we would trust the stop_code for now) this would be NULL IF we don't yet have it IN our boarding_action_final
	  FROM  _test.boarding_locations_apr23 b
	  JOIN  orca.v_linked_transactions vlt
	  	ON vlt.txn_id = b.txn_id
	  JOIN  orca.v_boardings nx
	  	ON nx.txn_id = vlt.next_txn_id
	  LEFT JOIN _test.boarding_action_final_april23 nb
	  	ON nb.txn_id = vlt.next_txn_id
	  		AND nb.stop_final IS NOT NULL 
	  LEFT JOIN _test.extracted_44444_gtfs_april23 nb4
	  	ON nb4.txn_id = vlt.next_txn_id ); -- 4,927,234


SELECT COUNT(*)
FROM _test.next_boarding_locations_apr23
WHERE stop_location IS NULL AND stop_code IS NOT NULL; -- 287,974


-- we can update the stop_location for all the txn_id with NO stop_location
	-- we need to trust orca's stop code, and route_number (if exists -- not 44444/22222)
WITH ModifiedData AS (
	SELECT DISTINCT
			 orca.txn_id
		   , gtfs_s.feed_id
		   , gtfs_s.stop_location
		   , ROW_NUMBER() OVER (
		   		PARTITION BY orca.txn_id
		   		ORDER BY
		   			CASE
			            WHEN gtfs_rn.route_id IS NOT NULL THEN 1 -- prioritize matching route names
			            ELSE 2 -- prioritize by feed_id if no match
			        END ASC,
			        gtfs_s.feed_id DESC
		   		) AS latest_gtfs
	FROM _test.next_boarding_locations_apr23 orca -- orca
	LEFT JOIN trac.route_name_lookup lookup
		ON orca.route_number = lookup.route_number
			AND orca.service_agency_id = lookup.service_agency_id -- the lookup uses service_agency_id INSTEAD OF SOURCE
	LEFT JOIN trac.agencies trac -- lookup TABLE for agency_id BETWEEN orca AND gtfs
		ON trac.orca_agency_id = orca.source_agency_id
			OR trac.agency_id = lookup.trac_agency_id
	JOIN _test.latest_gtfs_feeds gtfs_rn -- this IS FOR the cases WHERE the route_name NOT 44444/22222, because we want TO make sure the route/stop must match if it exists 
		ON orca.business_date BETWEEN gtfs_rn.start_date AND gtfs_rn.end_date -- WITHIN START AND END date 
		   AND gtfs_rn.trac_agency_id = trac.agency_id
		   AND (
		   		CASE 
			   		WHEN orca.route_number = '44444' OR orca.route_number = '22222' -- This is added to always evaluate to TRUE, so it won't affect the join
			   			THEN TRUE
			   		ELSE -- WHEN the route_name EXISTS, THEN we need TO double check
			   			(gtfs_rn.route_short_name ILIKE orca.route_number
						OR COALESCE(gtfs_rn.route_short_name, gtfs_rn.route_long_name) ILIKE lookup.gtfs_route_name) 
		   		END )
	JOIN _test.gtfs_route_stop_sequence gtfs_s
		ON gtfs_s.stop_id = orca.stop_code -- must MATCH stop_id
		   AND gtfs_s.trac_agency_id = trac.agency_id
		   AND (
		   		CASE 
			   		WHEN orca.route_number = '44444' OR orca.route_number = '22222' -- This is added to always evaluate to TRUE, so it won't affect the join
			   			THEN TRUE
			   		ELSE
					    gtfs_s.route_id = gtfs_rn.route_id
					    AND gtfs_s.feed_id = gtfs_rn.feed_id
			   	END )
	WHERE orca.stop_location IS NULL
		  AND orca.stop_code IS NOT NULL -- this make sure that ONLY the CASE WHERE the stop_location IS NULL AND stop_code NOT NULL ARE considered
	ORDER BY orca.txn_id ASC, latest_gtfs DESC
)
UPDATE _test.next_boarding_locations_apr23 original
SET feed_id = ModifiedData.feed_id
	, stop_location = ModifiedData.stop_location
FROM ModifiedData
WHERE original.txn_id = ModifiedData.txn_id
	  AND ModifiedData.latest_gtfs = 1; -- 223,346

	  	
/*
(1) if bus and route 44444 or 22222 (DONE!!)
  use process written on paper
(2) if bus and route not 44444 or 22222: (CURRENT STEP: )
  use next boarding stop location to find any stops along current route within 1/3 mile
(3) if light rail OR sounder: !!! What is the identifier to know if it's lightrail or sounder? !!!
  (3.1) if there is an alight_txn_id in v_linked_transactions:
    ?verify that orca.transactions stop_id is along gtfs route?
    use orca.transactions stop_id and device_dtm_pacific for alighting info
    also get disance from stop to next boarding stop
  (3.2) if no alight_txn_id: this becomes like the bus tapoff estimate
    use gtfs data to get next light rail stop within 1/3 mile of next boarding
*/

--	txn_id bigint PRIMARY KEY
--    ,trac_agency_id smallint NOT NULL
--    ,stop_id text NOT NULL
--    ,alight_dtm_pacific timestamp without time zone     -- tapoff time (if lrt or sounder and they tapped off) or time of AVL bus arrival/departure, OR gtfs scheduled arrival time
--    ,interline_route_id text DEFAULT NULL               -- interline route id when alighting route differs from boarding route
--    ,tapoff_txn_id bigint DEFAULT NULL                  -- if there is an orca tap off txn
--    ,nxt_stop_dist_m real                               -- store in table since joins to computer are slow
 
	  
	  
	  
	  
-- select avl data into a table to run faster
CREATE TABLE _test.x_avl_april23 AS (
	SELECT *
	FROM agency.v_avl
	WHERE departure_dtm_pacific BETWEEN '2023-04-01' AND '2023-05-01 05:00:00'
);	  -- 13,437,834




-- we are going to identify the alighting for boardings with AVL and original ORCA stop_code (stop_note = 1)
CREATE VIEW _test.alight_stop_april23_avl AS (
	WITH nxt_boarding_ranked AS (
		SELECT b.txn_id
				, b_avl.trac_agency_id
				, b_avl.feed_id
				, n_avl.stop_id
				, COALESCE(n_avl.arrival_dtm_pacific, n_avl.departure_dtm_pacific) AS alight_dtm_pacific
				, CASE
					WHEN n_avl.route_id != b_avl.avl_route
						THEN n_avl.route_id
					ELSE NULL
				  END AS interline_route_id
				, ST_Distance(n_gtfs_stop.stop_location, nb.stop_location) AS nxt_stop_dist_m
				, ROW_NUMBER() OVER (
					PARTITION BY nb.txn_id, b.txn_id
					-- choosing the shortest wait time over shortest walk time
					ORDER BY ST_Distance(n_gtfs_stop.stop_location, nb.stop_location) ASC
				  ) AS distance_rank
				, n_gtfs_stop.stop_location
		FROM _test.boarding_locations_apr23 b
		JOIN _test.boarding_action_final_april23 b_avl -- this TABLE has ALL the avl information
			ON b.txn_id = b_avl.txn_id
				AND b_avl.avl_check_code BETWEEN 1.1 AND 1.4 -- these ARE the records WITH avl
				AND b_avl.stop_note = 1 -- these ARE the records that we use original ORCA stop_code
		JOIN _test.x_avl_april23 n_avl -- (we first identify next stop of the txn with AVL)
			ON n_avl.agency_id = b.source_agency_id  -- agency
				AND n_avl.vehicle_id = b_avl.coach_number  -- vehicle number
				AND n_avl.direction_id = b_avl.avl_direction -- direction
				AND n_avl.departure_dtm_pacific > b_avl.avl_departure_dtm -- departure time OF next avl > boarding avl departure time
		        AND n_avl.departure_dtm_pacific < (b_avl.avl_departure_dtm + interval '90 minutes') -- but it should ONLY be WITHIN 90 mins OF the **FIRST** boarding
		JOIN _test.gtfs_route_stop_sequence n_gtfs_stop -- we need this join to get the gtfs-standardized location
			ON n_gtfs_stop.feed_id = b_avl.feed_id
			   AND n_gtfs_stop.trac_agency_id = b_avl.trac_agency_id
			   AND n_gtfs_stop.stop_id = n_avl.stop_id
		JOIN  orca.linked_transactions vlt -- linked txn
			ON vlt.txn_id = b.txn_id
		JOIN _test.next_boarding_locations_apr23 nb -- processed nxt boardings
			ON nb.txn_id = vlt.next_txn_id 
				AND nb.stop_location IS NOT NULL 
				AND (COALESCE(n_avl.arrival_dtm_pacific, n_avl.departure_dtm_pacific) - INTERVAL '5 minutes') < nb.device_dtm_pacific			
				AND ST_DWithin(n_gtfs_stop.stop_location, nb.stop_location, 536.448) -- WITHIN 1/3 a mile
	)
	SELECT DISTINCT 
		txn_id
		, trac_agency_id
		, feed_id
		, stop_id
		, alight_dtm_pacific
		, interline_route_id
		, nxt_stop_dist_m
	FROM nxt_boarding_ranked
	WHERE distance_rank = 1
);




SELECT COUNT(*) AS total_alight_txn -- 2,565,557
		, COUNT(DISTINCT txn_id) AS distinct_alight_txn -- 2,565,557
		, COUNT(*) FILTER (WHERE device_mode_id != 30) AS count_not_bus -- 0
		, COUNT(*) FILTER (WHERE interline_route_id IS NOT NULL) AS interline_route_id -- 84,733
FROM _test.alight_stop_april23_avl; 




-- INSERT the alighting stops OF the bus boardings with AVL data
INSERT INTO _test.alight_location_april23(txn_id, trac_agency_id, feed_id, stop_id, alight_dtm_pacific, interline_route_id, nxt_stop_dist_m) (
	SELECT txn_id
			, trac_agency_id
			, feed_id
			, stop_id
			, alight_dtm_pacific
			, interline_route_id -- route_id FROM avl
			, nxt_stop_dist_m
	FROM _test.alight_stop_april23_avl
); -- 2,565,557



/*
(1) if bus and route 44444 or 22222 (DONE!!)
  use process written on paper
(2) if bus and route not 44444 or 22222: (DONE!!) 
  use next boarding stop location to find any stops along current route within 1/3 mile
(3) if light rail OR sounder: !!! What is the identifier to know if it's lightrail or sounder? !!! 
  (3.1) if there is an alight_txn_id in v_linked_transactions: (CURRENT STEP)
    ?verify that orca.transactions stop_id is along gtfs route?
    use orca.transactions stop_id and device_dtm_pacific for alighting info
    also get disance from stop to next boarding stop
  (3.2) if no alight_txn_id: this becomes like the bus tapoff estimate
    use gtfs data to get next light rail stop within 1/3 mile of next boarding
*/

-- how many identified alighting txn in total for boardings in april?
SELECT COUNT(*)
  FROM  _test.boarding_locations_apr23 b
  JOIN  orca.linked_transactions vlt
  	ON vlt.txn_id = b.txn_id
  JOIN _test.boarding_action_final_april23 b_gtfs -- this TABLE has ALL the gtfs information
	ON b.txn_id = b_gtfs.txn_id
  JOIN  orca.v_alightings alght
  	ON alght.txn_id = vlt.alight_txn_id; -- 601,077


--- get all the alighting txn for the boardings in April of Sounder and Lightrail
--	   txn_id bigint PRIMARY KEY 						  -- boarding txn_id
--    ,trac_agency_id smallint NOT NULL
--	  ,feed_id bigint NOT NULL							  -- gtfs feed_id
--    ,stop_id text NOT NULL							  -- alighting stop_id
--    ,alight_dtm_pacific timestamp without time zone     -- tapoff time (if lrt or sounder and they tapped off) or time of AVL bus arrival/departure, OR gtfs scheduled arrival time
--    ,interline_route_id text DEFAULT NULL               -- interline route id when alighting route differs from boarding route
--    ,tapoff_txn_id bigint DEFAULT NULL                  -- if there is an orca tap off txn
--    ,nxt_stop_dist_m real                               -- store in table since joins to computer are slow

CREATE VIEW _test.alight_stop_april23_snder_lghtr AS (
	SELECT DISTINCT b.txn_id
				, b_gtfs.trac_agency_id
				, b_gtfs.feed_id
				, alght.stop_code AS stop_id
				, alght.device_dtm_pacific AS alight_dtm_pacific
				, alght.txn_id AS tapoff_txn_id
				, ST_Distance(al_location.stop_location, nb.stop_location) AS nxt_stop_dist_m
	  FROM  _test.boarding_locations_apr23 b
	  JOIN  orca.linked_transactions vlt
	  	ON vlt.txn_id = b.txn_id
	  JOIN _test.boarding_action_final_april23 b_gtfs -- this TABLE has ALL the gtfs information
		ON b.txn_id = b_gtfs.txn_id
	  JOIN  orca.v_alightings alght
	  	ON alght.txn_id = vlt.alight_txn_id
	  JOIN _test.gtfs_route_stop_sequence al_location -- we need this join to get the gtfs-standardized location
		ON al_location.feed_id = b_gtfs.feed_id -- we would expect the alight'feed_id would be the same AS the boarding
		   AND al_location.trac_agency_id = b_gtfs.trac_agency_id
		   AND al_location.route_id = b_gtfs.gtfs_route_id -- assuming the tap-OFF route IS the same AS the boarding route FOR sounder AND lightrail
		   AND al_location.stop_id = alght.stop_code -- this make sure that the alighting stop_code actually EXISTS along the route, AND we would GET the GTFS stop_location based ON this
	  JOIN _test.next_boarding_locations_apr23 nb -- processed nxt boardings
			ON nb.txn_id = vlt.next_txn_id 
				AND nb.stop_location IS NOT NULL
); -- 569,051




INSERT INTO _test.alight_location_april23(txn_id, trac_agency_id, feed_id, stop_id, alight_dtm_pacific, tapoff_txn_id, nxt_stop_dist_m) (
	SELECT txn_id
			, trac_agency_id
			, feed_id
			, stop_id
			, alight_dtm_pacific
			, tapoff_txn_id
			, nxt_stop_dist_m
	FROM _test.alight_stop_april23_snder_lghtr
); -- 569,051





/*
(1) if bus and route 44444 or 22222 (DONE!!)
  use process written on paper
(2) if bus and route not 44444 or 22222: (DONE!!) 
  use next boarding stop location to find any stops along current route within 1/3 mile
(3) if light rail OR sounder: !!! What is the identifier to know if it's lightrail or sounder? !!! 
  (3.1) if there is an alight_txn_id in v_linked_transactions: (DONE!!)  
    ?verify that orca.transactions stop_id is along gtfs route?
    use orca.transactions stop_id and device_dtm_pacific for alighting info
    also get disance from stop to next boarding stop
  (3.2) if no alight_txn_id: this becomes like the bus tapoff estimate (CURRENT STEP)
    use gtfs data to get next light rail stop within 1/3 mile of next boarding
*/

-- first, identify the gtfs trip in service for each remaining boardings:
	-- given feed_id, trac_agency_id, gtfs_route_id, and stop_id
CREATE TABLE _test.trip_stop_april23_remaining AS (
	WITH boarding_trip_ranked AS (
		SELECT  b.txn_id
			    , b.txn_dow
				, b.business_date
				, b.device_dtm_pacific
				, b.device_dtm_interval
				, b_gtfs.stop_final
				, b_gtfs.feed_id
				, b_gtfs.gtfs_route_id
				, b_gtfs.trac_agency_id
				, gtfs_t.trip_id
				, gtfs_t.shape_id
				, gtfs_t.direction_id
				, gtfs_t.stop_sequence
				, gtfs_t.stop_location
				, ROW_NUMBER() OVER (
					PARTITION BY b.txn_id, gtfs_t.shape_id 
					-- choosing the shortest wait time trip for each shape id
					ORDER BY abs_interval(gtfs_t.departure_time - b.device_dtm_interval) ASC
				  ) AS trip_ranked
		FROM  _test.boarding_locations_apr23 b
		LEFT JOIN _test.alight_location_april23 df_alght -- DEFINED alight FOR boardings
			ON df_alght.txn_id = b.txn_id
		JOIN  orca.linked_transactions vlt -- make sure we ONLY need TO process those EXISTS IN linked txn
		  	ON vlt.txn_id = b.txn_id
		JOIN _test.boarding_action_final_april23 b_gtfs -- this TABLE has ALL the gtfs information
			ON b.txn_id = b_gtfs.txn_id						
		JOIN _test.gtfs_route_trip_stop_sequence gtfs_t
			ON gtfs_t.feed_id = b_gtfs.feed_id -- MATCH feed_if
			   AND gtfs_t.trac_agency_id = b_gtfs.trac_agency_id -- MATCH agency
			   AND gtfs_t.route_id = b_gtfs.gtfs_route_id -- MATCH route
			   AND gtfs_t.stop_id = b_gtfs.stop_final -- must MATCH stop_id
			   AND CASE 
			   		WHEN b.device_mode_id = 10 OR b.device_mode_id = 11
			   			THEN
			   				gtfs_t.departure_time - b.device_dtm_interval >= INTERVAL '1 minutes'
			   				AND gtfs_t.departure_time < b.device_dtm_interval + INTERVAL '45 minutes'
			   		ELSE 
			   			gtfs_t.departure_time - INTERVAL '5 minutes' <= b.device_dtm_interval 
			   			AND gtfs_t.departure_time < b.device_dtm_interval + INTERVAL '45 minutes'
			   	END
		LEFT JOIN _test.gtfs_route_service_exception exc -- EXCEPTION service dates for the route/shape
			ON exc.feed_id = gtfs_t.feed_id
			   AND exc.trac_agency_id = gtfs_t.trac_agency_id
			   AND exc.route_id = gtfs_t.route_id
			   AND exc.trip_id = gtfs_t.trip_id
			   AND b.business_date = exc.date
		WHERE
			df_alght.txn_id IS NULL 
			AND CASE 
	            WHEN b.txn_dow = 0 -- SUNDAY
	            	THEN
	            		(gtfs_t.sunday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL)) 
	            		OR (gtfs_t.sunday = 0 AND exc.exception_type = 1)
	            WHEN b.txn_dow = 1 -- MONDAY
	            	THEN
	            		(gtfs_t.monday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.monday = 0 AND exc.exception_type = 1)
	            WHEN b.txn_dow = 2 -- TUESDAY
	            	THEN
	            		(gtfs_t.tuesday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.tuesday = 0 AND exc.exception_type = 1)
	            WHEN b.txn_dow = 3 -- WEDNESDAY
	            	THEN
	            		(gtfs_t.wednesday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.wednesday = 0 AND exc.exception_type = 1)
	            WHEN b.txn_dow = 4 -- THURSDAY
	            	THEN
	            		(gtfs_t.thursday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.thursday = 0 AND exc.exception_type = 1)
	            WHEN b.txn_dow = 5 -- FRIDAY
	            	THEN
	            		(gtfs_t.friday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.friday = 0 AND exc.exception_type = 1)
	            WHEN b.txn_dow = 6 -- SATURDAY
	            	THEN 
	            		(gtfs_t.saturday = 1 AND (exc.exception_type != 2 OR exc.exception_type IS NULL))
	            		OR (gtfs_t.saturday = 0 AND exc.exception_type = 1)
		      END	
		)
	SELECT *
	FROM boarding_trip_ranked
	WHERE trip_ranked = 1
); -- 2,393,935





SELECT *
FROM _test.trip_stop_april23_remaining; -- 1,813,277



-- get all the later stops from the remaining boardings
-- within 1/3 miles (536.5m) of each nxt txn stop:


CREATE TABLE _test.alight_stop_april23_remaining AS (
	WITH nxt_boarding_ranked AS (
		SELECT  b.txn_id
			    , b.trac_agency_id
				, b.feed_id
				, ns.stop_id AS stop_id
				, (b.business_date + ns.arrival_time) AS alight_dtm_pacific
				, ST_Distance(ns.stop_location, nb.stop_location) AS nxt_stop_dist_m
				, ROW_NUMBER() OVER (
					PARTITION BY b.txn_id, nb.txn_id
					-- choosing the shortest walking distance
					ORDER BY ST_Distance(ns.stop_location, nb.stop_location) ASC
				  ) AS distance_rank
		FROM  _test.trip_stop_april23_remaining b -- **FIRST** boardings
		JOIN  orca.linked_transactions vlt
		  	ON vlt.txn_id = b.txn_id
		JOIN _test.gtfs_route_trip_stop_sequence ns	-- ALL possible stops AFTER the **first** boarding
			ON b.feed_id = ns.feed_id
				AND b.gtfs_route_id = ns.route_id
				AND b.trac_agency_id = ns.trac_agency_id
				AND b.trip_id = ns.trip_id
				AND b.shape_id = ns.shape_id
				AND b.stop_sequence < ns.stop_sequence -- NEXT stop SEQUENCE must be greater than the **FIRST** boarding stop
		JOIN _test.next_boarding_locations_apr23 nb -- processed nxt boardings
			ON nb.txn_id = vlt.next_txn_id 
				AND nb.stop_location IS NOT NULL 
				AND CASE -- the arrival time OF the alighting txn (minus 5:00 mins) must be less than the NEXT boarding time
						WHEN b.business_date = nb.business_date 
							THEN (ns.arrival_time - INTERVAL '5 minutes') < nb.device_dtm_interval -- we allowing 5min because the gtfs bus scheduled could arrive early
						ELSE TRUE
					END
				AND ST_DWithin(ns.stop_location, nb.stop_location, 536.448) -- WITHIN 1/3 a mile
		)
	SELECT *
	FROM nxt_boarding_ranked
	WHERE distance_rank = 1
); -- 728,490



INSERT INTO _test.alight_location_april23(txn_id, trac_agency_id, feed_id, stop_id, alight_dtm_pacific, nxt_stop_dist_m) (
	SELECT txn_id
			, trac_agency_id
			, feed_id
			, stop_id
			, alight_dtm_pacific
			, nxt_stop_dist_m
	FROM _test.alight_stop_april23_remaining
); -- 728,490




SELECT COUNT(*)
FROM _test.alight_location_april23; -- 3,867,548



-- how many identified boardings (where stop_final is not null)
-- that has a linked txn and the nxt boarding's stop location is also not null?
SELECT COUNT(*)
FROM _test.boarding_action_final_april23 b
JOIN  orca.linked_transactions vlt
	ON vlt.txn_id = b.txn_id
		AND b.stop_final IS NOT NULL
JOIN _test.next_boarding_locations_apr23 nb -- processed nxt boardings
	ON nb.txn_id = vlt.next_txn_id 
		AND nb.stop_location IS NOT NULL; -- 4,768,898
		

-- how many linked txn for boardings in total
SELECT COUNT(*)
FROM _test.boarding_action_final_april23 b
JOIN  orca.linked_transactions vlt
	ON vlt.txn_id = b.txn_id; -- 5,021,162 