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

-- Create a linestring for the shape given the set of points
CREATE TABLE shapes_linestring AS (
	SELECT shape_id, ST_MakeLine(geom ORDER BY shape_pt_sequence) AS geom
	FROM shapes
	GROUP BY shape_id
);

SELECT COUNT (DISTINCT shape_id)
FROM shapes