CREATE EXTENSION postgis;

/* ADD CONSTRAINTS */

ALTER TABLE stops
ADD CONSTRAINT PK_stopid PRIMARY KEY (stop_id);


ALTER TABLE routes 
ADD CONSTRAINT PK_routeid PRIMARY KEY (route_id);


ALTER TABLE trips 
	ADD CONSTRAINT PK_tripid PRIMARY KEY (trip_id),
	ADD CONSTRAINT FK_routeid FOREIGN KEY (route_id) REFERENCES routes(route_id);


ALTER TABLE shapes
	ADD CONSTRAINT PK_shapes PRIMARY KEY (shape_id, shape_pt_sequence);


ALTER TABLE stop_times 
	ADD CONSTRAINT PK_stoptimes PRIMARY KEY (trip_id, stop_sequence),
	ADD CONSTRAINT FK_tripid FOREIGN KEY (trip_id) REFERENCES trips(trip_id),
	ADD CONSTRAINT FK_stopid FOREIGN KEY (stop_id) REFERENCES stops(stop_id);


/* ADD geom COLUMN IN shapes TABLE */
ALTER TABLE shapes
	ADD COLUMN geom geometry;
	
-- Add values for the geom column
UPDATE shapes
SET geom = ST_GeomFromText('POINT(' || shape_pt_lon || ' ' || shape_pt_lat || ')');

-- double check if the values in geom column is added accurately
SELECT COUNT(*)
FROM shapes
WHERE 'POINT(' || shape_pt_lon || ' ' || shape_pt_lat || ')' = ST_AsText(geom);

-- Create a table that contains linestring for the shape given the set of points
CREATE TABLE shapes_linestring AS (
	SELECT shape_id, ST_MakeLine(geom ORDER BY shape_pt_sequence) AS geom
	FROM shapes
	GROUP BY shape_id
);


/*  */
-- For each route (route_id), which trip does the route takes the most? -- trips_count
-- This query gives us the different shape that the route would take and also the frequency that this route would take
SELECT t.route_id, r.route_short_name, r.agency_id, COUNT(t.trip_id) AS trips_count, sl.shape_id, sl.geom
FROM trips t
JOIN shapes_linestring sl 
	ON sl.shape_id = t.shape_id
JOIN routes r
	ON t.route_id = r.route_id 
GROUP BY sl.shape_id, t.route_id, sl.geom, r.route_short_name, r.agency_id
ORDER BY t.route_id ASC, COUNT(t.trip_id) DESC


-- Create a Feature Collection GeoJSON

SELECT 
	json_build_object(
	    'type', 'FeatureCollection',
	    'features', json_agg(ST_AsGeoJSON(t.*)::json)
	)
FROM (
	SELECT t.route_id, r.route_short_name, r.agency_id, COUNT(t.trip_id) AS trips_count, t.shape_id--, sl.geom
	FROM trips t
--	JOIN shapes_linestring sl 
--		ON sl.shape_id = t.shape_id
	JOIN routes r
		ON t.route_id = r.route_id 
	GROUP BY t.shape_id, t.route_id,  r.route_short_name, r.agency_id
	ORDER BY t.route_id ASC, COUNT(t.trip_id) DESC
) AS t;


/* ADD geom COLUMN in stops table */
ALTER TABLE stops
	ADD COLUMN geom geometry;

-- Add values for the geom column
UPDATE stops
	SET geom = ST_GeomFromText('POINT(' || stop_lon || ' ' || stop_lat || ')');


-- double check if the values in geom column is added accurately
SELECT COUNT(*)
FROM stops
WHERE 'POINT(' || stop_lon || ' ' || stop_lat || ')' = ST_AsText(geom);


