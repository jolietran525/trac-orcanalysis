-- Create table following Shane's transitland format
-- but import data from KCM 2022-10-18 .csv files
-- 1. Stop table
CREATE TABLE _test.kcm_stops_2022
(LIKE _test.kcm_stops);

CREATE TABLE _test.kcm_routes_2022 AS
(SELECT * FROM  _test.kcm_routes_2022);

CREATE TABLE _test.kcm_shapes_2022 AS
(SELECT * FROM _test.kcm_shapes_2022);

CREATE TABLE _test.kcm_agency_2022 AS
(SELECT * FROM _test.kcm_agency_2022);

CREATE TABLE _test.kcm_trips_2022 AS
(SELECT * FROM _test.kcm_trips_2022);

CREATE TABLE _test.kcm_stop_times_2022 AS
(SELECT * FROM _test.kcm_stop_times_2022);


CREATE TABLE _test.kcm_calendar_2022 (
	service_id TEXT PRIMARY KEY,
	monday TEXT,
	tuesday TEXT,
	wednesday TEXT,
	thursday TEXT,
	friday TEXT,
	saturday TEXT,
	sunday TEXT,
	start_date DATE,
	end_date DATE
);

/*-- ADD CONSTRAINTS --*/

ALTER TABLE _test.kcm_stops_2022
	ADD CONSTRAINT PK_stopid PRIMARY KEY (stop_id);

ALTER TABLE _test.kcm_agency_2022 
	ADD CONSTRAINT PK_agencyid PRIMARY KEY (agency_id);

ALTER TABLE _test.kcm_routes_2022 
	ADD CONSTRAINT PK_routeid PRIMARY KEY (route_id),
	ADD CONSTRAINT FK_agencyid FOREIGN KEY (agency_id) REFERENCES _test.kcm_agency_2022(agency_id);

ALTER TABLE _test.kcm_trips_2022 
	ADD CONSTRAINT PK_tripid PRIMARY KEY (trip_id),
	ADD CONSTRAINT FK_serviceid FOREIGN KEY (service_id) REFERENCES _test.kcm_calendar_2022(service_id),
	ADD CONSTRAINT FK_routeid FOREIGN KEY (route_id) REFERENCES _test.kcm_routes_2022(route_id);


ALTER TABLE _test.kcm_shapes_2022
	ADD CONSTRAINT PK_shapes PRIMARY KEY (shape_id, shape_pt_sequence);


ALTER TABLE _test.kcm_stop_times_2022 
	ADD CONSTRAINT PK_stoptimes PRIMARY KEY (trip_id, stop_sequence),
	ADD CONSTRAINT FK_tripid FOREIGN KEY (trip_id) REFERENCES _test.kcm_trips_2022(trip_id),
	ADD CONSTRAINT FK_stopid FOREIGN KEY (stop_id) REFERENCES _test.kcm_stops_2022(stop_id);



/*-- ADD geom COLUMN IN _test.kcm_shapes_2022 TABLE --*/
ALTER TABLE _test.kcm_shapes_2022
	ADD COLUMN geom geometry;
	
-- Add values for the geom column
UPDATE _test.kcm_shapes_2022
SET geom = ST_GeomFromText('POINT(' || shape_pt_lon || ' ' || shape_pt_lat || ')');

-- double check if the values in geom column is added accurately
SELECT COUNT(*)
FROM _test.kcm_shapes_2022
WHERE 'POINT(' || shape_pt_lon || ' ' || shape_pt_lat || ')' = ST_AsText(geom);

-- Create a table that contains linestring for the shape given the set of points
CREATE TABLE _test.kcm_shapes_linestring_2022 AS (
	SELECT shape_id, ST_MakeLine(geom ORDER BY shape_pt_sequence) AS geom
	FROM _test.kcm_shapes_2022
	GROUP BY shape_id
);



/*-- ADD geom COLUMN in _test.kcm_stops_2022 table --*/
ALTER TABLE _test.kcm_stops_2022
	ADD COLUMN geom geometry;

-- Add values for the geom column
UPDATE _test.kcm_stops_2022
	SET geom = ST_SetSRID(ST_GeomFromText('POINT(' || stop_lon || ' ' || stop_lat || ')'), 4326);


/*  Sanity Check: stop_code from orca vs stop_id from stop_id from gtfs */

-- Sanity check:
	-- for orca_boarding: Only choose KCM (angency = 4) and the date greater than 2022-10-01
SELECT  s.stop_id,
		s.geom AS gtfs_stop, --ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')') AS gtfs_stop,
		b.*,
		ST_Distance(
			st_transform(b.device_location, 32610),
			st_transform(s.geom, 32610))
--			st_transform(ST_SetSRID(ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')'), 4326), 32610))
FROM _test.kcm_stops_2022 s
JOIN (	SELECT stop_code, device_location, route_number, m.mode_descr
		FROM orca.v_boardings b
		JOIN orca.modes m 
		ON m.mode_id = b.device_mode_id
		WHERE stop_code IS NOT NULL AND
			  device_location IS NOT NULL AND
			  source_agency_id = 4 AND
	  		  business_date >= '2022-10-01'
	) b
ON b.stop_code = s.stop_id::TEXT
ORDER BY 7 DESC
LIMIT 1000


-- For a given stop id, see all device location that has the stop_code and stop_id matched, also show the bus_route
CREATE VIEW _test.matched_stop_all AS (
	SELECT  s.stop_id,
			s.geom AS gtfs_stop, --ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')') AS gtfs_stop,
			b.*,
			ST_Distance(
				st_transform(b.device_location, 32610),
				st_transform(s.geom, 32610))
	--			st_transform(ST_SetSRID(ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')'), 4326), 32610))
	FROM _test.kcm_stops_2022 s
	JOIN (	SELECT stop_code, device_location, route_number, m.mode_descr
			FROM orca.v_boardings b
			JOIN orca.modes m 
			ON m.mode_id = b.device_mode_id
			WHERE stop_code IS NOT NULL AND
				  device_location IS NOT NULL AND
				  source_agency_id = 4 AND
		  		  business_date >= '2022-10-01'
		) b
	ON b.stop_code = s.stop_id::TEXT
	WHERE s.stop_id = 11130
	ORDER BY 7 DESC
);

SELECT * FROM _test.matched_stop_all;


-- For the specific stop_id, see the collection of device location that has the stop_code ans stop_id matched, also show the bus_route
CREATE VIEW _test.matched_stop_collection AS (
	SELECT  s.stop_id,
			s.geom AS gtfs_stop, --ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')') AS gtfs_stop,
			b.route_number,
			b.mode_descr,
			MAX(ST_Distance(
				st_transform(b.device_location, 32610),
				st_transform(s.geom, 32610))),
	--			st_transform(ST_SetSRID(ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')'), 4326), 32610))),	
			AVG(ST_Distance(
				st_transform(b.device_location, 32610),
				st_transform(s.geom, 32610))),
	--			st_transform(ST_SetSRID(ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')'), 4326), 32610))),
			MIN(ST_Distance(
				st_transform(b.device_location, 32610),
				st_transform(s.geom, 32610))),
	--			st_transform(ST_SetSRID(ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')'), 4326), 32610))),
			ST_Collect(b.device_location)
	FROM _test.kcm_stops_2022 s
	JOIN (	SELECT stop_code, device_location, route_number, m.mode_descr
			FROM orca.v_boardings b
			JOIN orca.modes m 
			ON m.mode_id = b.device_mode_id
			WHERE stop_code IS NOT NULL AND
				  device_location IS NOT NULL AND
				  source_agency_id = 4 AND
		  		  business_date >= '2022-10-01'
		) b
	ON b.stop_code = s.stop_id::TEXT
	WHERE s.stop_id = 11130
	GROUP BY s.stop_id, s.geom, b.stop_code, b.route_number, b.mode_descr
);


SELECT * FROM _test.matched_stop_collection



-- Count how many stops from orca that have the device location 500 meters further than the stop geom from gtfs
SELECT COUNT(*)
FROM _test.kcm_stops_2022 s
JOIN (	SELECT stop_code, device_location, route_number, m.mode_descr
		FROM orca.v_boardings b
		JOIN orca.modes m 
		ON m.mode_id = b.device_mode_id
		WHERE stop_code IS NOT NULL AND
			  device_location IS NOT NULL AND
			  source_agency_id = 4 AND
	  		  business_date >= '2022-10-01'
	) b
ON b.stop_code = s.stop_id::TEXT 
WHERE ST_Distance(
			st_transform(b.device_location, 32610),
			st_transform(s.geom, 32610)) > 500
--			st_transform(ST_SetSRID(ST_GeomFromText('POINT(' || s.stop_lon || ' ' || s.stop_lat || ')'), 4326), 32610)) > 500


-- show distinct GTFS stops along the GTFS route, with route name:
SELECT DISTINCT ON(t.route_id, st.stop_id) t.route_id, r.route_short_name, st.stop_id, s.geom
FROM _test.kcm_trips_2022 t
JOIN _test.kcm_routes_2022 r
	ON r.route_id = t.route_id
JOIN _test.kcm_stop_times_2022 st 
	ON st.trip_id = t.trip_id
JOIN _test.kcm_stops_2022 s 
	ON s.stop_id = st.stop_id  
ORDER BY t.route_id, st.stop_id 


/* NEW APPROACH: JOIN ON ROUTE NAME, THEN PICK THE CLOSEST DEVICE LOCATION TO THE GTFS FOR EACH TRANSACTION */
-- From above, we cant trust the stop_code, and thus we need to now join base upon the route_number/route_short_name
-- then pick the closest stop (from the device_location) to the gtfs_stop

-- TEST CODE: join on route name between orca and gtfs
-- need to join with pretty_routes table because some of the route_code from orca font match with the route_short_name from gtfs
SELECT o.*, g.*
FROM  ( -- this IS the orca_boarding route data
		SELECT DISTINCT route_number
		FROM orca.v_boardings b
		WHERE -- stop_code IS NOT NULL AND
			  device_location IS NOT NULL AND
			  source_agency_id = 4 AND
	  		  business_date >= '2022-10-01'
	) AS o
LEFT JOIN agency.pretty_routes pr
ON o.route_number = pr.route_number AND pr.service_agency_id = 4
JOIN ( -- this IS the gtfs route data
		SELECT DISTINCT r.route_short_name
		FROM _test.kcm_trips_2022 t
		JOIN _test.kcm_routes_2022 r
			ON r.route_id = t.route_id
		JOIN _test.kcm_stop_times_2022 st 
			ON st.trip_id = t.trip_id
		JOIN _test.kcm_stops_2022 s 
			ON s.stop_id = st.stop_id  
	) AS g
ON g.route_short_name = o.route_number OR g.route_short_name = pr.route_name;



-- Now we can join base on the route name, test with stop_code = '11130'
CREATE VIEW _test.boardings_stops_compared AS (
	SELECT  orca.*,
			gtfs.stop_id AS gtfs_stop_id,
			gtfs.geom AS gtfs_stop, --ST_GeomFromText('POINT(' || gtfs.stop_lon || ' ' || gtfs.stop_lat || ')') AS gtfs_stop,
			ST_Distance(
				st_transform(orca.device_location, 32610),
				st_transform(gtfs.geom, 32610))
	--			st_transform(ST_SetSRID(ST_GeomFromText('POINT(' || gtfs.stop_lon || ' ' || gtfs.stop_lat || ')'), 4326), 32610))
			, RANK() OVER (
				PARTITION BY orca.txn_id 
				ORDER BY ST_Distance(
							st_transform(orca.device_location, 32610),
							st_transform(gtfs.geom, 32610))
				)
	FROM (	SELECT txn_id, stop_code, device_location, route_number, m.mode_descr
			FROM orca.v_boardings b
			JOIN orca.modes m 
			ON m.mode_id = b.device_mode_id
			WHERE -- stop_code IS NOT NULL AND
				  device_location IS NOT NULL AND
				  source_agency_id = 4 AND
		  		  business_date >= '2022-10-01' AND stop_code = '11130' 
		) orca
	LEFT JOIN agency.pretty_routes pr
		ON orca.route_number = pr.route_number AND pr.service_agency_id = 4
	JOIN (  SELECT DISTINCT ON(t.route_id, st.stop_id) t.route_id, r.route_short_name, st.stop_id, s.geom
			FROM _test.kcm_trips_2022 t
			JOIN _test.kcm_routes_2022 r
				ON r.route_id = t.route_id
			JOIN _test.kcm_stop_times_2022 st 
				ON st.trip_id = t.trip_id
			JOIN _test.kcm_stops_2022 s 
				ON s.stop_id = st.stop_id  
			ORDER BY t.route_id, st.stop_id ) gtfs
	ON 	gtfs.route_short_name = orca.route_number OR gtfs.route_short_name = pr.route_name 
	ORDER BY 1, 9 ASC
);

SELECT * FROM _test.boardings_stops_compared
LIMIT 1000;







-- TODO: define the direction for the GTFS that match with orca, so we only choose the closest stop in the same direction

-- all distinct direction
SELECT * FROM orca.directions d 


-- different kind of direction for the boardings of route 2
SELECT d.direction_descr, COUNT(*)
FROM orca.v_boardings vb 
JOIN orca.directions d
ON d.direction_id = vb.direction_id 
WHERE vb.route_number = '2' AND source_agency_id = '4'
GROUP BY d.direction_descr 


-- Show all the routes with more than 2 valid directions 
SELECT vb.source_agency_id, vb.route_number, COUNT(DISTINCT vb.direction_id)
FROM orca.v_boardings vb 
JOIN orca.directions d
ON d.direction_id = vb.direction_id 
WHERE vb.direction_id != 3
GROUP BY vb.source_agency_id, vb.route_number
HAVING COUNT(DISTINCT vb.direction_id) > 2



-- Get all the distinct direction for each route from orca
-- and only get the transactions that are between the start and end date of the service from the gtfs
-- Also create a rank for the count of dir, the count dir with the highest count is rank 1
CREATE VIEW _test.route_dir AS (
	WITH dt AS ( --GET dates FOR EACH route
	    SELECT DISTINCT r.route_id, r.route_short_name, direction_id, min(c.start_date) start_date, max(c.end_date) end_date
	    FROM _test.kcm_routes_2022 r 
	    JOIN _test.kcm_trips_2022 t ON t.route_id = r.route_id
	    JOIN _test.kcm_calendar_2022 c ON c.service_id = t.service_id
	    GROUP BY r.route_id, r.route_short_name, direction_id
	)
	SELECT vb.route_number, dt.route_id, dt.route_short_name, dr.direction_descr, COUNT(*) dir_count,
			RANK() OVER (PARTITION BY vb.route_number, dt.route_id ORDER BY COUNT(*) DESC) AS count_rank
	FROM orca.v_boardings vb 
	JOIN orca.directions dr
		ON dr.direction_id = vb.direction_id
	LEFT JOIN agency.pretty_routes pr
		ON vb.route_number = pr.route_number
	JOIN dt
		ON (dt.route_short_name = vb.route_number OR dt.route_short_name = pr.route_name)
	WHERE     vb.source_agency_id = '4' -- KCM
		  AND vb.direction_id != 3 
		  AND vb.device_dtm_pacific BETWEEN dt.start_date AND dt.end_date
	GROUP BY vb.route_number, dt.route_id, dt.route_short_name, dr.direction_descr
);




-- Get all the percentage of the direction count over the maximum direction count
-- We want to see that so that we can eliminate those direction that appeared with way too low frequency
CREATE VIEW _test.route_dir_portion AS (
	SELECT rd1.route_number, rd1.route_id, rd2.route_short_name, rd2.direction_descr, rd2.dir_count*1.0/rd1.dir_count*100 AS percent_over_max
	FROM _test.route_dir rd1
	JOIN _test.route_dir rd2
		ON rd1.route_number = rd2.route_number
			AND rd1.count_rank <= rd2.count_rank 
	WHERE rd1.count_rank = 1 -- AND rd1.route_number IN ('161', '168', '331', '345', '45', '545', '550', '672', '676', '75') -- these ARE the routes WITH MORE than 2 directions
);

SELECT * FROM _test.route_dir_portion WHERE route_number IN ('161', '168', '331', '345', '45', '545', '550', '672', '676', '75')
	


-- TODO: Making a summary table with the consecutive direction_id
-- then sort them by device date time 
-- https://stackoverflow.com/q/30877926

-- we want final table of route_number, device_id, direction_id, earliest_device_dtm_pacific, latest_device_dtm_pacific, earliest_device_location, latest_device_location, sum_passenger_count

-- first, create a temp table that only contains the route 672 so we have smaller dataset to work with
CREATE TABLE _test.v_boarding_672 AS (
	WITH dt AS ( --GET dates FOR EACH route
		    SELECT DISTINCT r.route_id, r.route_short_name, min(c.start_date) start_date, max(c.end_date) end_date
		    FROM _test.kcm_routes_2022 r 
		    JOIN _test.kcm_trips_2022 t ON t.route_id = r.route_id
		    JOIN _test.kcm_calendar_2022 c ON c.service_id = t.service_id
		    GROUP BY r.route_id, r.route_short_name
		)
	SELECT b.*
	FROM orca.v_boardings b
	LEFT JOIN agency.pretty_routes pr
			ON b.route_number = pr.route_number
	JOIN dt
			ON (dt.route_short_name = b.route_number OR dt.route_short_name = pr.route_name)
	WHERE b.device_location IS NOT NULL AND
		  b.source_agency_id = 4 AND
		  b.route_number = '672' AND 
		  b.device_dtm_pacific BETWEEN dt.start_date AND dt.end_date);
		 
		 
		 
-- final table for the summary of route 672
CREATE VIEW _test.summary_672 AS (
	SELECT *
	FROM (
		SELECT DISTINCT ON (business_date, device_id, direction_id, grp)
		          	  route_number
					, device_id
					, business_date
					, direction_id
					, device_dtm_pacific AS start_time
					, max(device_dtm_pacific) OVER (PARTITION BY business_date, device_id, direction_id, grp) AS end_time
	--				, stop_code
					, FIRST_VALUE(stop_code) OVER (PARTITION BY business_date, device_id, direction_id, grp ORDER BY device_dtm_pacific) AS start_stop_code
	    			, LAST_VALUE(stop_code)  OVER (PARTITION BY business_date, device_id, direction_id, grp ORDER BY device_dtm_pacific ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS end_stop_code
	--    			, device_location
	    			, FIRST_VALUE(device_location)  OVER (PARTITION BY business_date, device_id, direction_id, grp ORDER BY device_dtm_pacific) AS earliest_device_location
	    			, LAST_VALUE(device_location)  OVER (PARTITION BY business_date, device_id, direction_id, grp ORDER BY device_dtm_pacific ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS latest_device_location
	    			, COUNT(*)  OVER (PARTITION BY business_date, device_id, direction_id, grp ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS sum_passenger_count
	--				, grp
		FROM (
			SELECT  route_number
					, device_id
					, business_date
					, device_dtm_pacific
					, direction_id
					, stop_code
					, device_location
					, row_number() OVER (ORDER BY business_date, device_id, device_dtm_pacific)
					, row_number() OVER (PARTITION BY business_date, device_id, direction_id ORDER BY business_date, device_id, device_dtm_pacific)
				    , row_number() OVER (ORDER BY business_date, device_id, device_dtm_pacific)
				    - row_number() OVER (PARTITION BY business_date, device_id, direction_id ORDER BY business_date, device_id, device_dtm_pacific) AS grp
			  FROM  _test.v_boarding_672 ) t
		ORDER BY business_date, device_id, direction_id, grp, device_dtm_pacific ) sub
	ORDER BY start_time);
	  

SELECT *
FROM _test.summary_672


SELECT * FROM orca.directions d 


-- all boardings within the valid dates from gtfs
CREATE TABLE _test.boarding_within_gtfs_date AS (
	WITH dt AS ( --GET dates FOR EACH route
		    SELECT DISTINCT r.route_id, r.route_short_name, min(c.start_date) start_date, max(c.end_date) end_date
		    FROM _test.kcm_routes_2022 r 
		    JOIN _test.kcm_trips_2022 t ON t.route_id = r.route_id
		    JOIN _test.kcm_calendar_2022 c ON c.service_id = t.service_id
		    GROUP BY r.route_id, r.route_short_name
		)
	SELECT b.*
	FROM orca.v_boardings b
	LEFT JOIN agency.pretty_routes pr
			ON b.route_number = pr.route_number
	JOIN dt
			ON (dt.route_short_name = b.route_number OR dt.route_short_name = pr.route_name)
	WHERE b.device_location IS NOT NULL AND
		  b.source_agency_id = 4 AND
		  b.device_dtm_pacific BETWEEN dt.start_date AND dt.end_date);





CREATE TABLE _test.boading_summary_all AS (
	SELECT sub.*, d.direction_descr
	FROM (
		SELECT DISTINCT ON (business_date, device_id, direction_id, grp)
		          	  route_number
					, device_id
					, business_date
					, direction_id
					, device_dtm_pacific AS earliest_dtm_pacific
					, max(device_dtm_pacific) OVER (PARTITION BY business_date, device_id, direction_id, grp) AS latest_dtm_pacific
					, FIRST_VALUE(stop_code) OVER (PARTITION BY business_date, device_id, direction_id, grp ORDER BY device_dtm_pacific) AS earliest_stop_code
	    			, LAST_VALUE(stop_code)  OVER (PARTITION BY business_date, device_id, direction_id, grp ORDER BY device_dtm_pacific ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS latest_stop_code
	    			, FIRST_VALUE(device_location)  OVER (PARTITION BY business_date, device_id, direction_id, grp ORDER BY device_dtm_pacific) AS earliest_device_location
	    			, LAST_VALUE(device_location)  OVER (PARTITION BY business_date, device_id, direction_id, grp ORDER BY device_dtm_pacific ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS latest_device_location
	    			, COUNT(*)  OVER (PARTITION BY business_date, device_id, direction_id, grp ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS sum_passenger_count
		FROM (
			SELECT  route_number
					, device_id
					, business_date
					, device_dtm_pacific
					, direction_id
					, stop_code
					, device_location
					, row_number() OVER (ORDER BY business_date, device_id, device_dtm_pacific)
					, row_number() OVER (PARTITION BY business_date, device_id, direction_id ORDER BY business_date, device_id, device_dtm_pacific)
				    , row_number() OVER (ORDER BY business_date, device_id, device_dtm_pacific)
				    - row_number() OVER (PARTITION BY business_date, device_id, direction_id ORDER BY business_date, device_id, device_dtm_pacific) AS grp
			  FROM  _test.boarding_within_gtfs_date ) t
		ORDER BY business_date, device_id, direction_id, grp, device_dtm_pacific ) sub
	JOIN orca.directions d 
	ON d.direction_id = sub.direction_id
	ORDER BY earliest_dtm_pacific);


SELECT DISTINCT direction_descr 
FROM _test.boading_summary_all
WHERE route_number = '65'

/* --------- GTFS direction processing --------- */

-- Show the array of all distinct stops along the route for each distinct shape, also show the direction for each shape
-- assume that all of the shape with the same direction_id is the subset of the shape with the most stops
-- Therefore, we can get use the direction of the shape with the most stops as the standard direction (shape_direction)
CREATE TABLE _test.gtfs_route_direction AS (
	SELECT DISTINCT 
			  route_id
			, route_short_name
			, shape_id
			, direction_id AS gtfs_direction_id
			, trips_count
			, stops_count
			, stops_arr
			, dir AS og_direction
			, FIRST_VALUE(dir)  OVER (PARTITION BY route_id, direction_id ORDER BY stops_count DESC) AS shape_direction
	FROM (
		WITH dist AS (
				SELECT DISTINCT t.route_id,
								r.route_short_name,
								t.shape_id,
								t.direction_id,
								COUNT(t.trip_id) AS trips_count,
								st.stop_id,
								st.stop_sequence,
								s.stop_lon, --x
								s.stop_lat --y
				FROM _test.kcm_trips_2022 t
				JOIN _test.kcm_routes_2022 r
					ON t.route_id = r.route_id
				JOIN _test.kcm_stop_times_2022 st 
					ON st.trip_id = t.trip_id
				JOIN _test.kcm_stops_2022 s
					ON s.stop_id = st.stop_id
				GROUP BY t.shape_id, r.route_short_name, t.route_id, t.direction_id, st.stop_id, st.stop_sequence, s.stop_lon, s.stop_lat
				ORDER BY t.shape_id, st.stop_sequence ASC
				)
		SELECT DISTINCT  route_id
				, route_short_name
				, shape_id
				, direction_id
				, trips_count
				, ARRAY_AGG(stop_id) OVER (PARTITION BY route_id, shape_id, direction_id ORDER BY stop_sequence ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS stops_arr
				, array[CASE
					WHEN (- FIRST_VALUE(stop_lon) OVER (PARTITION BY route_id, shape_id, direction_id  ORDER BY stop_sequence) --AS start_stop_lon
						+ LAST_VALUE(stop_lon) OVER (PARTITION BY route_id, shape_id, direction_id  ORDER BY stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)) > 0
						THEN 'East'
					ELSE 'West'
				  END 
				, CASE
					WHEN (- FIRST_VALUE(stop_lat) OVER (PARTITION BY route_id, shape_id, direction_id  ORDER BY stop_sequence) --AS start_stop_lat
				    + LAST_VALUE(stop_lat) OVER (PARTITION BY route_id, shape_id, direction_id  ORDER BY stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)) > 0
						THEN 'North'
					ELSE 'South'
				  END] AS dir
	--			, - FIRST_VALUE(stop_lon) OVER (PARTITION BY route_id, shape_id, direction_id  ORDER BY stop_sequence) --AS start_stop_lon
	--				+ LAST_VALUE(stop_lon) OVER (PARTITION BY route_id, shape_id, direction_id  ORDER BY stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS del_lon --end_stop_lon
	--			, - FIRST_VALUE(stop_lat) OVER (PARTITION BY route_id, shape_id, direction_id  ORDER BY stop_sequence) --AS start_stop_lat
	--			    + LAST_VALUE(stop_lat) OVER (PARTITION BY route_id, shape_id, direction_id  ORDER BY stop_sequence ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS del_lat --end_stop_lat
				, COUNT(*) OVER (PARTITION BY route_id, shape_id, direction_id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS stops_count
		FROM dist ) sub
	ORDER BY route_short_name, direction_id ASC, stops_count DESC
);




-- check for similarities of the shape based upon the containment of the stop_id
--SELECT  *, 
--		ARRAY (
--	        SELECT UNNEST(s1_arr)
--	        INTERSECT
--	        SELECT UNNEST(s2_arr)
--	    ) AS overlap_elements,
--	    array_length(
--	    	ARRAY (
--	        SELECT UNNEST(s1_arr)
--	        INTERSECT
--	        SELECT UNNEST(s2_arr)
--	    ), 1)*1.0/s2_stops*100 AS percent_overlap
--FROM  (
--        SELECT s1.route_id
--        	 , s1.shape_id AS s1_shape
--        	 , s2.shape_id AS s2_shape
--        	 , s1.direction_id AS s1_dir
--        	 , s2.direction_id AS s2_dir
--        	 , s1.trips_count AS s1_trips
--        	 , s2.trips_count AS s2_trips
--        	 , s1.stops_count AS s1_stops
--        	 , s2.stops_count AS s2_stops
--        	 , s1.stops_arr @> s2.stops_arr AS containment
--        	 , s1.stops_arr AS s1_arr
--             , s2.stops_arr AS s2_arr
--        FROM _test.stops_shape_array s1
--		JOIN _test.stops_shape_array s2
--		ON  s1.shape_id != s2.shape_id AND
--			s1.stops_count >= s2.stops_count AND 
--			s1.direction_id = s2.direction_id AND 
--			s1.stop_rank = 1
--	 ) q
--WHERE array_length(
--	    	ARRAY (
--	        SELECT UNNEST(s1_arr)
--	        INTERSECT
--	        SELECT UNNEST(s2_arr)
--	    ), 1)*1.0/s2_stops*100 >= 60;
	    
	   


-- sanity check for _test.gtfs_route_direction:
--- 1. If og_direction and shape_direction arrays ALWAYS overlap??
SELECT *
FROM _test.gtfs_route_direction
WHERE NOT og_direction && shape_direction; -- there IS route 22

	-- see why
	SELECT * FROM _test.gtfs_route_direction
	WHERE route_short_name = '22'; -- This IS actually because the sub-shape IS just very short compared TO the standard one

--- 2. If shape_direction of oppsite gtfs_direction_id arrays EVER overlap??
SELECT *
FROM _test.gtfs_route_direction d0
JOIN _test.gtfs_route_direction d1
ON 	   d0.route_id = d1.route_id
   AND d0.gtfs_direction_id = 0
   AND d1.gtfs_direction_id = 1
WHERE d0.shape_direction && d1.shape_direction; -- routes: 121, 65


SELECT *
FROM _test.gtfs_route_direction
WHERE route_short_name IN ('121', '65'); -- 121: East IS the common ELEMENT, 65: east IS common element


SELECT * FROM agency.pretty_routes WHERE service_agency_id = '4'