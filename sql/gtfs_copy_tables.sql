/*---- CREATE TABLE ----*/
-- real_gtfs_extra_files
CREATE TABLE _test.real_gtfs_extra_files
	AS TABLE gtfs_test.real_gtfs_extra_files;

--real_gtfs_files
CREATE TABLE _test.real_gtfs_feeds
	AS TABLE gtfs_test.real_gtfs_feeds;

--real_transitland_agency
CREATE TABLE _test.real_transitland_agency
	AS TABLE gtfs_test.real_transitland_agency;

--real_transitland_areas
CREATE TABLE _test.real_transitland_areas
	AS TABLE gtfs_test.real_transitland_areas;

--real_transitland_attributions
CREATE TABLE _test.real_transitland_attributions
	AS TABLE gtfs_test.real_transitland_attributions;

--real_transitland_calendar
CREATE TABLE _test.real_transitland_calendar
	AS TABLE gtfs_test.real_transitland_calendar;

--real_transitland_calendar_dates
CREATE TABLE _test.real_transitland_calendar_dates
	AS TABLE gtfs_test.real_transitland_calendar_dates;
	
--real_transitland_fare_attributes
CREATE TABLE _test.real_transitland_fare_attributes
	AS TABLE gtfs_test.real_transitland_fare_attributes;
	
--real_transitland_fare_leg_rules
CREATE TABLE _test.real_transitland_fare_leg_rules
	AS TABLE gtfs_test.real_transitland_fare_leg_rules;
	
--real_transitland_fare_media
CREATE TABLE _test.real_transitland_fare_media
	AS TABLE gtfs_test.real_transitland_fare_media;
	
--real_transitland_fare_products
CREATE TABLE _test.real_transitland_fare_products
	AS TABLE gtfs_test.real_transitland_fare_products;

--real_transitland_fare_rules
CREATE TABLE _test.real_transitland_fare_rules
	AS TABLE gtfs_test.real_transitland_fare_rules;
	
--real_transitland_fare_transfer_rules
CREATE TABLE _test.real_transitland_fare_transfer_rules
	AS TABLE gtfs_test.real_transitland_fare_transfer_rules;
	
--real_transitland_feed_info
CREATE TABLE _test.real_transitland_feed_info
	AS TABLE gtfs_test.real_transitland_feed_info;

--real_transitland_frequencies
CREATE TABLE _test.real_transitland_frequencies
	AS TABLE gtfs_test.real_transitland_frequencies;
	
--real_transitland_levels
CREATE TABLE _test.real_transitland_levels
	AS TABLE gtfs_test.real_transitland_levels;
	
--real_transitland_networks
CREATE TABLE _test.real_transitland_networks
	AS TABLE gtfs_test.real_transitland_networks;

--real_transitland_pathways
CREATE TABLE _test.real_transitland_pathways
	AS TABLE gtfs_test.real_transitland_pathways;

--real_transitland_route_networks
CREATE TABLE _test.real_transitland_route_networks
	AS TABLE gtfs_test.real_transitland_route_networks;
	
--real_transitland_routes
CREATE TABLE _test.real_transitland_routes
	AS TABLE gtfs_test.real_transitland_routes;
	
--real_transitland_shapes
CREATE TABLE _test.real_transitland_shapes
	AS TABLE gtfs_test.real_transitland_shapes;
	
--real_transitland_stop_areas
CREATE TABLE _test.real_transitland_stop_areas
	AS TABLE gtfs_test.real_transitland_stop_areas;
	
--real_transitland_stop_times
CREATE TABLE _test.real_transitland_stop_times
	AS TABLE gtfs_test.real_transitland_stop_times;
	
--real_transitland_stops
CREATE TABLE _test.real_transitland_stops
	AS TABLE gtfs_test.real_transitland_stops;
	
--real_transitland_timeframes
CREATE TABLE _test.real_transitland_timeframes
	AS TABLE gtfs_test.real_transitland_timeframes;
	
--real_transitland_transfers
CREATE TABLE _test.real_transitland_transfers
	AS TABLE gtfs_test.real_transitland_transfers;
	
--real_transitland_translations
CREATE TABLE _test.real_transitland_translations
	AS TABLE gtfs_test.real_transitland_translations;

--real_transitland_trips
CREATE TABLE _test.real_transitland_trips
	AS TABLE gtfs_test.real_transitland_trips;



SELECT * FROM _test.real_transitland_routes;
SELECT * FROM _test.real_gtfs_feeds;

/*---- DROP TABLE ----*/


-- real_gtfs_extra_files
DROP TABLE _test.real_gtfs_extra_files;

--real_gtfs_files
DROP TABLE _test.real_gtfs_feeds;

--real_transitland_agency
DROP TABLE _test.real_transitland_agency;

--real_transitland_areas
DROP TABLE _test.real_transitland_areas;

--real_transitland_attributions
DROP TABLE _test.real_transitland_attributions;

--real_transitland_calendar
DROP TABLE _test.real_transitland_calendar;

--real_transitland_calendar_dates
DROP TABLE _test.real_transitland_calendar_dates;
	
--real_transitland_fare_attributes
DROP TABLE _test.real_transitland_fare_attributes;
	
--real_transitland_fare_leg_rules
DROP TABLE _test.real_transitland_fare_leg_rules;
	
--real_transitland_fare_media
DROP TABLE _test.real_transitland_fare_media;
	
--real_transitland_fare_products
DROP TABLE _test.real_transitland_fare_products;

--real_transitland_fare_rules
DROP TABLE _test.real_transitland_fare_rules;
	
--real_transitland_fare_transfer_rules
DROP TABLE _test.real_transitland_fare_transfer_rules;
	
--real_transitland_feed_info
DROP TABLE _test.real_transitland_feed_info;

--real_transitland_frequencies
DROP TABLE _test.real_transitland_frequencies;
	
--real_transitland_levels
DROP TABLE _test.real_transitland_levels;
	
--real_transitland_networks
DROP TABLE _test.real_transitland_networks;

--real_transitland_pathways
DROP TABLE _test.real_transitland_pathways;

--real_transitland_route_networks
DROP TABLE _test.real_transitland_route_networks;
	
--real_transitland_routes
DROP TABLE _test.real_transitland_routes;
	
--real_transitland_shapes
DROP TABLE _test.real_transitland_shapes;
	
--real_transitland_stop_areas
DROP TABLE _test.real_transitland_stop_areas;
	
--real_transitland_stop_times
DROP TABLE _test.real_transitland_stop_times;
	
--real_transitland_stops
DROP TABLE _test.real_transitland_stops;
	
--real_transitland_timeframes
DROP TABLE _test.real_transitland_timeframes;
	
--real_transitland_transfers
DROP TABLE _test.real_transitland_transfers;
	
--real_transitland_translations
DROP TABLE _test.real_transitland_translations;

--real_transitland_trips
DROP TABLE _test.real_transitland_trips;
