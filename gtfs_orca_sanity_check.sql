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


-- TODO: define the direction for the GTFS, so we only choose the closest stop in the same direction
