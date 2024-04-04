----------------------------------------
-- orca_pod.sql
-- Ryan P. Avery <rpavery@uw.edu>
-- queries to support continuous ORCA
----------------------------------------

-- TODO: check elyse's 'CREATE' access to orca_pod and orca?

-- to see current query activity (and get pid):
SELECT * FROM pg_stat_activity WHERE usename='rpavery';
SELECT pid,client_addr,query FROM pg_stat_activity WHERE usename='rpavery';

-- to get distinct connected users:
SELECT DISTINCT usename FROM pg_stat_activity WHERE usename IS NOT NULL;

-- get current database size
SELECT pg_size_pretty(pg_database_size('orca_pod'));

-- get size of a schema:
SELECT pg_size_pretty(sum(pg_total_relation_size(quote_ident(schemaname) ||  '.' || quote_ident(tablename)))::bigint)
FROM pg_tables
WHERE schemaname = 'dz';

-- to cancel a query (first option gracefully):
-- SELECT pg_cancel_backend(<pid>);
-- SELECT pg_terminate_backend(<pid>);

-- get data storage directory:
-- SHOW data_directory;

-- get config file:
-- SHOW config_file;

-- get all run-time parameters:
-- SHOW all;

-- performance tuning:
-- https://wiki.postgresql.org/wiki/Performance_Optimization
-- https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server

-- also consider setting noatime on /store data mount in /etc/fstab?

-- query explain analyzer: https://tatiyants.com/pev/
-- use EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)

/********** GENERAL DESIGN NOTES & SCHEMA BACKUP **********/
-- TODO: change object names to match design below
-- prefix   type
--------------------------------
-- none     regular table
-- e        enumeration table
-- f        function
-- m        materialized view
-- p        procedure
-- v        view

-- data backups throughout file; schema backup here
-- schema only backup, with no owner statments (so anybody can restore)
-- pg_dump -U rpavery -h 10.142.198.115 -O --schema-only orca_pod > ~/dl/yyyymmdd_orca_pod_schema.sql

-- backup basic enumerations
-- TODO: change object names to have a prefix for easy selecting?
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.agencies -t orca.bad_txn_types -t orca.break_types -t orca.directions -t orca.institutions -t orca.location_sources -t orca.modes -t orca.passenger_types -t orca.products -t orca.transaction_types --data-only orca_pod > ~/dl/20221101_orca_enumerations.sql

/* incomplete list of objects to rename:
-- candidates for enum tables:
orca.bad_txn_types
orca.break_types
orca.directions
orca.location_sources
orca.modes
orca.parameters?
orca.passenger_types
orca.transaction_types

-- possible enum tables, or leave as-is:
agency.agencies
orca.institutions
orca.products

-- materialized views:
agency.v_uniq_stop_locations

-- views:
agency.avl
agency.avl_location
agency.bus_schedules
orca.boarding_transfers
orca.boardings
orca.boardings_with_groups
orca.boardings_with_stops
orca.next_boarding

*/

/********** EXTENSIONS & SCHEMAS **********/
-- create extensions
CREATE EXTENSION pgcrypto;
CREATE EXTENSION postgis;

-- create _import schema
-- landing place for data before it's imported to actual tables
-- general format _import.orca_transactions -> orca.transactions
CREATE SCHEMA IF NOT EXISTS _import;
ALTER SCHEMA _import OWNER TO postgres;

-- create _log schema for logging
CREATE SCHEMA IF NOT EXISTS _log;
ALTER SCHEMA _log OWNER TO postgres;

-- create _tmp schema is scratch work
CREATE SCHEMA IF NOT EXISTS _tmp;
ALTER SCHEMA _tmp OWNER TO postgres;

-- create agency schema is for agency date (avl, stops) that 'belongs' to transit agencies
CREATE SCHEMA IF NOT EXISTS agency;
ALTER SCHEMA agency OWNER TO postgres;

-- create devices schema - this is for all work related to matching devices to buses
CREATE SCHEMA IF NOT EXISTS devices;
ALTER SCHEMA devices OWNER TO postgres;

-- create orca schema - this is where orca transactions are, as well as enumerations like modes, passenger types, etc
CREATE SCHEMA IF NOT EXISTS orca;
ALTER SCHEMA orca OWNER TO postgres;

-- create orca_ng schema - this is where new orca data goes temporarily
CREATE SCHEMA IF NOT EXISTS orca_ng;
ALTER SCHEMA orca_ng OWNER TO postgres;

-- create util schema - this a utility schema for some functions and procedures
CREATE SCHEMA IF NOT EXISTS util;
ALTER SCHEMA util OWNER TO postgres;

-- create report schema - this is for most reporting/dashboard features
CREATE SCHEMA IF NOT EXISTS rpt;
ALTER SCHEMA rpt OWNER TO postgres;

-- create zone schema - this is for all zonal work
CREATE SCHEMA IF NOT EXISTS zone;
ALTER SCHEMA zone OWNER TO postgres;

-- create consult schema for custom analysis
CREATE SCHEMA IF NOT EXISTS consult;
ALTER SCHEMA consult OWNER TO postgres;

/********** GENERAL FUNCTIONS **********/
-- function to return time in UTC
CREATE OR REPLACE FUNCTION util.now_utc() RETURNS timestamp AS $$
    SELECT date_trunc('second', clock_timestamp() at time zone 'utc');
$$ LANGUAGE SQL STRICT;

-- function to clean numeric text on import, replacing empty strings with NULL and stripping commas from numbers in text
-- return text so various conversions can be made after the fact
CREATE OR REPLACE FUNCTION util.clean_numeric_text(_val text) RETURNS text AS $$
    SELECT replace(nullif(_val, ''), ',', '');
$$ LANGUAGE SQL STRICT;

-- function to return end of day from a given date
CREATE OR REPLACE FUNCTION util.end_of_day(_start timestamp) RETURNS timestamp AS $$
    SELECT date_trunc('day', _start) + interval '1 day' - interval '1 second';
$$ LANGUAGE SQL STRICT;

-- function to return end of month from a given date
CREATE OR REPLACE FUNCTION util.end_of_month(_start timestamp) RETURNS timestamp AS $$
    SELECT date_trunc('month', _start) + interval '1 month' - interval '1 second';
$$ LANGUAGE SQL STRICT;

-- function to return floor of date time based on an arbitary interval
-- uses integer division to compute floor (could use explicit floor() if desired)
-- based on https://wiki.postgresql.org/wiki/Round_time
CREATE OR REPLACE FUNCTION util.date_floor(_datetime timestamptz, _interval interval) RETURNS timestamptz AS $$
    SELECT to_timestamp((extract(epoch FROM _datetime)::integer) / extract(epoch FROM _interval)::integer * extract(epoch FROM _interval)::integer);
$$ LANGUAGE SQL STRICT;

-- function to return ceiling of a time interval based on arbitrary bin interval
CREATE OR REPLACE FUNCTION util.interval_ceiling(_time interval, _bin interval) RETURNS interval AS $$
    SELECT ceiling(extract(epoch FROM _time) / extract(epoch FROM _bin)) * _bin;
$$ LANGUAGE SQL STRICT;

-- function to hash personally-identifiable information (PII)
-- since this is not a password, no need for 'slow' algorithms like bcrypt
CREATE OR REPLACE FUNCTION util.hash(_data text, _key text) RETURNS text AS $$
    SELECT encode(hmac(_data, _key, 'sha256'), 'hex');
$$ LANGUAGE SQL STRICT IMMUTABLE;

-- general device processing logging table
CREATE TABLE _log.messages (
    msg text
    ,logged_at timestamp without time zone DEFAULT util.now_utc()
);

-- function to get mode of bus or brt boarding
CREATE OR REPLACE FUNCTION orca.get_brt_or_bus_mode_id(_agency_id smallint, _route_id text) RETURNS smallint AS $$
    SELECT  CASE WHEN _agency_id = 2 AND _route_id LIKE '70_' THEN 250::smallint        -- ct swift brt
                 WHEN _agency_id = 4 AND _route_id LIKE '67_' THEN 250::smallint        -- kcm rapid ride brt
                 ELSE 128::smallint END;        -- other bus route
$$ LANGUAGE SQL STRICT IMMUTABLE;

-- time of day periods for analysis from kcm
-- NOTE: times based on start of trip; use same times for weekends as well
--CREATE TABLE orca.time_
-- This field bins trips together based on start time of trip:  
--  AM - 5AM-9AM, MID - 9AM-3PM, PM - 3PM-7PM, XEV - 7PM - 10PM, XNT 10PM - 5AM.  

/********** ORCA TRANSACTION IMPORT **********/
-- csv files with US date format

-- csv header format:
-- "Csn","Institution Id","Institution Name","Business Date","Txn Date","Txn Desc","Upgrade Txn","Product Id","Product Desc","Route Id To","Passenger Type Id","Passenger Type Desc","Mode Id","Number Of Passengers","Udsn","Ceffv","Service Participant Id To","Service Participant Name To","Source Participant Id","Source Participant Name","Transit Operator To","Device Id","Origin Location","Destination Location","Mode Description","Route Direction To"

-- create unlogged import table for holding data
-- import larger integer fields as text since input data might have commas
CREATE UNLOGGED TABLE _import.orca_transactions (
    card_serial_number text
    ,institution_id text
    ,institution_name text
    ,business_date date
    ,txn_dtm_pacific timestamp without time zone
    ,txn_type_descr text
    ,upgrade_indicator text
    ,product_id smallint
    ,product_descr text
    ,route_number text
    ,txn_passenger_type_id smallint
    ,txn_passenger_type_descr text
    ,reader_mode_id smallint
    ,passenger_count smallint
    ,udsn text
    ,ceffv_cents integer
    ,service_agency_id smallint
    ,service_agency_name text
    ,source_agency_id smallint
    ,source_agency_name text
    ,transit_operator_abbrev text
    ,device_id text
    ,origin_location_id text
    ,destination_location_id text
    ,mode_descr text
    ,direction_descr text
    ,PRIMARY KEY (card_serial_number, txn_dtm_pacific, txn_type_descr)
);

-- create institutions table
CREATE TABLE orca.institutions (
    institution_id smallint PRIMARY KEY
    ,institution_name text
);

-- create temp table to store results, including duplicates
CREATE TABLE _tmp.orca_institutions AS
SELECT  nullif(institution_id,'')::smallint AS institution_id
        ,btrim(institution_name) AS institution_name
        ,min(txn_dtm_pacific) AS min_dtm
        ,max(txn_dtm_pacific) AS max_dtm
        ,count(*) AS txn_count
  FROM  _import.orca_transactions
 WHERE  institution_id <> ''
GROUP BY 1, 2
ORDER BY 1;

-- review duplicates
-- 20210521: 2228, 2555, 5867, 5884, 5980
-- 20211211: 1421, 1667, 4653, 5596, 5641, 5645, 5680, 5724, 5866, 6033, 6051, 6111, 6123
-- NOTE: institution name is at time of data pull, so conflicting names align on month for different pulls
--       since latest org is usually the successor org, use the latest variation
-- TODO: consider adding timeframe to institution table; but would need better data from ORCA
SELECT  *
  FROM  _tmp.orca_institutions
 WHERE  institution_id IN
        (SELECT institution_id
           FROM _tmp.orca_institutions
        GROUP BY 1
        HAVING count(*) > 1);

-- also look at differences with existing names
-- 20211211: 110 new recs, 136 total updates
-- 20211212: 12 new recs, 13 total updates
SELECT  count(*), sum(CASE WHEN old_name IS NULL THEN 1 ELSE 0 END) AS new_recs FROM (
SELECT  t.institution_id
        ,t.institution_name
        ,i.institution_name AS old_name
  FROM  _tmp.orca_institutions t
  LEFT  JOIN orca.institutions i ON i.institution_id = t.institution_id
 WHERE  t.institution_name <> coalesce(i.institution_name,'')
) t;

-- 20210521: **MANUAL**
-- manually delete undesired records based on review
DELETE  FROM  _tmp.orca_institutions WHERE  institution_id = '2228' AND institution_name = 'Northwest SEED';            -- Northwest SEED became Spark Northwest
DELETE  FROM  _tmp.orca_institutions WHERE  institution_id = '2555' AND institution_name = 'Cascadian Therapeutics';    -- Seagen Inc. acquired Cascadian Therapeutics
DELETE  FROM  _tmp.orca_institutions WHERE  institution_id = '5867' AND institution_name = '47 Degrees, LLC';           -- use SBI version
DELETE  FROM  _tmp.orca_institutions WHERE  institution_id = '5884' AND institution_name = 'J. Brewster Bede & Casey';  -- use SBI version
DELETE  FROM  _tmp.orca_institutions WHERE  institution_id = '5980' AND txn_count < 20;                                 -- use proper encoding for accent in Alliance Française

-- create transaction types table
-- NOTE: use higher numbers than from 2020 table
CREATE TABLE orca.transaction_types (
    txn_type_id smallint PRIMARY KEY
    ,txn_type_descr text
    ,is_exit boolean
);

INSERT INTO orca.transaction_types VALUES
(10,'Product Purse Use Journey',False),
(11,'Product Pass Use Journey',False),
(12,'Product Multiride Use Journey',False),
(20,'Product Purse Use on Entry',False),
(21,'Product Pass Use on Entry',False),
(22,'Product Multiride Use on Entry',False),
(30,'Product Purse Use on Exit',True),
(31,'Product Pass Use on Exit',True),
(40,'Product Purse Rebate On Exit',True);

-- create product table
CREATE TABLE orca.products (
    product_id smallint PRIMARY KEY
    ,product_descr text
);

-- insert products
INSERT INTO orca.products
SELECT  DISTINCT product_id
        ,btrim(product_descr) AS product_descr
  FROM  _import.orca_transactions
ORDER BY product_id;

-- create passenger types table
CREATE TABLE orca.passenger_types (
    passenger_type_id smallint PRIMARY KEY
    ,passenger_type_descr text
);

-- insert passenger types
INSERT INTO orca.passenger_types
SELECT  DISTINCT txn_passenger_type_id AS passenger_type_id
        ,txn_passenger_type_descr AS passenger_type_descr
  FROM  _import.orca_transactions
ORDER BY txn_passenger_type_id;

-- fix 0 value
UPDATE  orca.passenger_types
   SET  passenger_type_descr = 'Unknown'
 WHERE  passenger_type_id = 0;

-- check agency (use agency.agencies table in queries)
SELECT  DISTINCT source_agency_id
        ,source_agency_name
        ,service_agency_id
        ,service_agency_name
  FROM  _import.orca_transactions
ORDER BY 1,3;

-- create agency table
-- TODO: add agency_id as primary key and add other non-orca gtfs agencies
CREATE TABLE agency.agencies (
    orca_agency_id smallint PRIMARY KEY
    ,gtfs_agency_id smallint UNIQUE
    ,name text
    ,abbrev text
);

-- insert values into agencies
INSERT INTO agency.agencies VALUES
(2,29,'Community Transit','CT'),
(3,97,'Everett Transit','ET'),
(4,1,'King County Metro','KCM'),
(5,NULL,'Kitsap Transit','KT'),
(6,3,'Pierce Transit','PT'),
(7,40,'Sound Transit','ST'),
(8,95,'Washington State Ferries','WSF');
-- (NULL,19,'Intercity Transit','ICT'),
-- (NULL,96,'Seattle Center Monorail','SCM'),
-- (NULL,98,'Seattle Childrens Hospital','SCH'),

-- create modes table
-- 2022-12-21: modified to add range descriptors for zonal work
CREATE TABLE orca.modes (
    mode_id smallint PRIMARY KEY
    ,mode_descr text NOT NULL
    ,mode_abbrev text NOT NULL
    ,range_id smallint NOT NULL DEFAULT 0
    ,range_desc text NOT NULL DEFAULT 'undefined'
);

-- create index on range_id
CREATE INDEX ON orca.modes (range_id);

-- insert into modes table
INSERT INTO orca.modes VALUES
(8,'Ferryboat','Ferry',3,'large'),
(9,'Commuter Rail','CRT',3,'large'),
(128,'Bus','Bus',1,'small'),
(249,'Streetcar','SCT',2,'medium'),
(250,'Bus Rapid Transit','BRT',1,'small'),
(251,'Light Rail','LRT',2,'medium'),
(254,'Demand Response','DRT',0,'undefined');

-- create directions table
CREATE TABLE orca.directions (
    direction_id smallint PRIMARY KEY
    ,direction_descr text
);

-- insert into directions table
INSERT INTO orca.directions VALUES
(1,'Inbound'),
(2,'Outbound');

-- investigate weird future dates:
SELECT  extract(year FROM txn_dtm_pacific) AS year
        ,count(*)
  FROM  _import.orca_transactions
GROUP BY 1;

-- look at difference between business date and txn date
-- txn_dtm_pacific should only be ahead of business date early the next morning (diff = -1)
SELECT  (business_date - txn_dtm_pacific::date) AS diff
        ,count(*)
  FROM  _import.orca_transactions
GROUP BY 1
ORDER BY 1;

-- orca parameters - store as time based since they could change
CREATE TABLE orca.parameters (
    name text
    ,value text
    ,valid_from date
    ,updated_at timestamp with time zone DEFAULT util.now_utc()
    ,PRIMARY KEY (name,valid_from)
);

INSERT INTO orca.parameters(name,value,valid_from) VALUES
('transfer_time','2 hours','1970-01-01'),
('hmac_key','<redacted>','1970-01-01');

-- function to retrieve value from parameters
-- use OUT in definition to reference val in later selects
CREATE OR REPLACE FUNCTION orca.get_parameter(_name text, _asof date DEFAULT util.now_utc()::date, OUT val text) AS $$
    -- use max function to get latest result from all possible results
    SELECT  value
      FROM  (SELECT value
                    ,valid_from
                    ,max(valid_from) OVER (partition BY name) AS max_valid
              FROM  orca.parameters p
             WHERE  name = _name
               AND  _asof >= valid_from
            ) AS v
     WHERE  v.valid_from = v.max_valid
$$ LANGUAGE SQL;

-- create bad txn types table
CREATE TABLE orca.bad_txn_types (
    bad_txn_type_id smallint PRIMARY KEY
    ,bad_txn_descr text
);

-- insert types
INSERT INTO orca.bad_txn_types VALUES
(1, 'suspect dates; txn_dtm_pacific is more than a day after business_date');

-- full transaction table with upgrade and tap-off txns
-- 2022-01-26: txn_id no longer primary key since partition requires partition key and all primary keys and unique fields to be included
--      okay since serial is used for inserts so should still be unique
--      see also: https://alexey-soshin.medium.com/dealing-with-partitions-in-postgres-11-fa9cc5ecf466
CREATE TABLE orca.transactions (
    --txn_id bigserial NOT NULL
    txn_id bigint NOT NULL DEFAULT nextval('orca.transactions_txn_id_seq1'::regclass)
    ,csn_hash text NOT NULL
    ,business_date date NOT NULL
    ,txn_dtm_pacific timestamp without time zone NOT NULL
    ,txn_institution_id smallint
    ,txn_type_id smallint NOT NULL
    ,upgrade_indicator boolean
    ,product_id smallint NOT NULL
    ,txn_passenger_type_id smallint NOT NULL
    ,passenger_count smallint NOT NULL
    ,ceffv_cents integer NOT NULL
    ,service_agency_id smallint NOT NULL
    ,source_agency_id smallint NOT NULL
    ,transit_operator_abbrev text NOT NULL
    ,reader_mode_id smallint NOT NULL
    ,route_number text
    ,direction_id smallint NOT NULL
    ,device_id integer
    ,origin_location_id bigint
    ,destination_location_id bigint
    ,udsn text
    ,bad_txn_flag boolean
    ,bad_txn_type smallint
    ,created_at timestamp with time zone NOT NULL DEFAULT util.now_utc()
) PARTITION BY RANGE (txn_dtm_pacific);

-- create indices:
CREATE INDEX ON orca.transactions (txn_id);
CREATE INDEX ON orca.transactions (txn_dtm_pacific);
CREATE INDEX ON orca.transactions (csn_hash);
CREATE INDEX ON orca.transactions (source_agency_id);
CREATE INDEX ON orca.transactions (reader_mode_id);
CREATE INDEX ON orca.transactions (txn_type_id);
CREATE INDEX ON orca.transactions (txn_passenger_type_id);
CREATE INDEX ON orca.transactions (bad_txn_flag);
CREATE INDEX ON orca.transactions (coalesce(upgrade_indicator, False));   -- used in boardings view
CREATE INDEX ON orca.transactions (origin_location_id);   -- used in boardings_with_stops view 

--CREATE INDEX ON orca.transactions (txn_passenger_type_id);

-- create child partitions:
-- NOTE: could use DEFAULT, but then future date range tables have to be created and attached manually
CREATE TABLE orca.transactions_2019 PARTITION OF orca.transactions FOR VALUES FROM ('2019-01-01') TO ('2020-01-01');
CREATE TABLE orca.transactions_2020 PARTITION OF orca.transactions FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');
CREATE TABLE orca.transactions_2021 PARTITION OF orca.transactions FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');
CREATE TABLE orca.transactions_2022 PARTITION OF orca.transactions FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');
CREATE TABLE orca.transactions_2023 PARTITION OF orca.transactions FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE orca.transactions_2024 PARTITION OF orca.transactions FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orca.transactions_2025 PARTITION OF orca.transactions FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- alter sequence ownership
ALTER SEQUENCE orca.transactions_txn_id_seq1 OWNED BY orca.transactions.txn_id;

-- fields to add? change existing to init_<field>?
-- mode_id and route_number added to AVL table
-- do we update origin and destination ids?
-- also: https://justatheory.com/2012/04/postgres-use-timestamptz/
--    should we convert datetime to UTC? or add time zone?
--    cannot partition on timestamp with time zone either
--    see also https://wiki.postgresql.org/wiki/Don%27t_Do_This

/*############################################################################*/
/*##########                NEW DATA IMPORT PROCESS                 ##########*/
/*############################################################################*/
\copy _import.orca_transactions FROM '~/dl/data/orca/20210101-20210115_fare_payment_passport_kcm.csv' WITH (FORMAT CSV, HEADER);

-- 2022-09-18: import 2021-11-01 thru 2022-05-15 into database
\copy _import.orca_transactions FROM '~/dl/data/orca/20211101-20211115_fare_payment_passport_kcm.csv' WITH (FORMAT CSV, HEADER);

/*
-- duplicate key errors:
-- deleted rows saved to _deleted_fare_payment_passport_kcm.csv

DETAIL:  Key (card_serial_number, txn_dtm_pacific, txn_type_descr)=(11658414, 2021-08-17 19:12:03, Product Pass Use Journey) already exists.
CONTEXT:  COPY orca_transactions, line 226722
 - based on review of travel behavior, delete outbound 7 ride since they seem to ride outbound in AM, inbound in PM

 - new theory: person is tapping on a route, then realizing it's wrong bus and getting on a different bus
 - due to clock drift, taps happen to be at same time; delete the first tap since it is a 'fake' transfer
DETAIL:  Key (card_serial_number, txn_dtm_pacific, txn_type_descr)=(30482088, 2021-12-08 21:15:41, Product Pass Use Journey) already exists.
CONTEXT:  COPY orca_transactions, line 1011101
 - delete boarding on route 21 outbound

-- however, we don't know which is the 'first' tap since file is not in order. so delete whichever seems less likely
DETAIL:  Key (card_serial_number, txn_dtm_pacific, txn_type_descr)=(14799733, 2021-12-21 12:14:56, Product Pass Use Journey) already exists.
CONTEXT:  COPY orca_transactions, line 581722
 - delete boarding on route 3 inbound

DETAIL:  Key (card_serial_number, txn_dtm_pacific, txn_type_descr)=(11849278, 2022-03-16 05:27:32, Product Pass Use Journey) already exists.
CONTEXT:  COPY orca_transactions, line 589023
 - delete boarding on route 930 outbound

*/

-- check for new institutions (see above)

-- check that no new txn types show up in new data
-- 20211211: fine
-- 20211212: fine
-- 20220919: fine
SELECT  o.txn_type_descr
        ,count(*)
  FROM  _import.orca_transactions o
 WHERE  o.txn_type_descr NOT IN (SELECT txn_type_descr FROM orca.transaction_types)
GROUP BY 1;

-- check that no new products show up in new data
-- 20211211: fine
-- 20211212: new products 61 and 391 - [Metro,ST] Monthly Reduced Fare Pass
-- 20220919: new products 63 and 206 - 'Transition R2R' and 'WSF Port Townsend-Coupevill MOnthly Pass'
--INSERT INTO orca.products
SELECT  product_id, product_descr FROM (
SELECT  o.product_id
        ,o.product_descr
        ,count(*)
  FROM  _import.orca_transactions o
 WHERE  o.product_id NOT IN (SELECT product_id FROM orca.products)
GROUP BY 1,2
) t;

-- check that no new passenger types show up in new data
-- 20211211: fine
-- 20211212: fine
-- 20220919: fine
SELECT  o.txn_passenger_type_id
        ,o.txn_passenger_type_descr
        ,count(*)
  FROM  _import.orca_transactions o
 WHERE  o.txn_passenger_type_id NOT IN (SELECT passenger_type_id FROM orca.passenger_types)
GROUP BY 1,2;

-- check that no new service or source agencies show up in new data
-- 20211211: fine
-- 20211212: fine
-- 20220919: fine
SELECT  o.service_agency_id
        ,o.service_agency_name
        ,count(*)
  FROM  _import.orca_transactions o
 WHERE  o.service_agency_id NOT IN (SELECT orca_agency_id FROM agency.agencies)
GROUP BY 1,2;

-- 20211211: fine
-- 20211212: fine
-- 20220919: fine
SELECT  o.source_agency_id
        ,o.source_agency_name
        ,count(*)
  FROM  _import.orca_transactions o
 WHERE  o.source_agency_id NOT IN (SELECT orca_agency_id FROM agency.agencies)
GROUP BY 1,2;

-- check that no new modes show up in new data
-- 20211211: reader mode id 160 shows up once
-- 20211212: fine
-- 20220919: fine
SELECT  o.reader_mode_id
        ,o.mode_descr
        ,count(*)
  FROM  _import.orca_transactions o
 WHERE  o.reader_mode_id NOT IN (SELECT mode_id FROM orca.modes)
GROUP BY 1,2;

SELECT * FROM _import.orca_transactions WHERE reader_mode_id = 160;

-- check that no new directions show up in new data
-- 20211211: fine
-- 20211212: fine
-- 20220919: fine
SELECT  o.direction_descr
        ,count(*)
  FROM  _import.orca_transactions o
 WHERE  o.direction_descr NOT IN (SELECT direction_descr FROM orca.directions)
GROUP BY 1;

-- institutions: replace all conflicts with latest name
-- create temp table to store results, including duplicates
CREATE TABLE _tmp.orca_institutions AS
SELECT  nullif(institution_id,'')::smallint AS institution_id
        ,btrim(institution_name) AS institution_name
        ,min(txn_dtm_pacific) AS min_dtm
        ,max(txn_dtm_pacific) AS max_dtm
        ,count(*) AS txn_count
  FROM  _import.orca_transactions
 WHERE  institution_id <> ''
GROUP BY 1, 2
ORDER BY 1;

-- check count vs distinct institution ids
-- for data pulls at one time, should be no duplicates as name is from date of pull, not date of txn
SELECT count(*), count(DISTINCT institution_id) FROM _tmp.orca_institutions;

-- count new and updated records
-- 20220919: 88 new, 9 updates
SELECT  sum(CASE WHEN o.institution_id IS NULL THEN 1 ELSE 0 END) AS new_count
        ,sum(CASE WHEN o.institution_name <> i.institution_name THEN 1 ELSE 0 END) AS updated_count
        ,sum(CASE WHEN i.institution_name <> coalesce(o.institution_name, '') THEN 1 ELSE 0 END) AS upsert_count
        ,sum(CASE WHEN o.institution_name = i.institution_name THEN 1 ELSE 0 END) AS existing_count
        ,count(*) AS total_count
  FROM  _tmp.orca_institutions i
  LEFT  JOIN orca.institutions o ON o.institution_id = i.institution_id;

-- insert records from transactions
-- 20220919: 97 inserts
INSERT INTO orca.institutions (institution_id, institution_name)
SELECT  i.institution_id
        ,i.institution_name
  FROM  _tmp.orca_institutions i
  JOIN  (SELECT institution_id                  -- use join on max_dtm to get only latest in case of duplicates
                ,max(max_dtm) AS latest_dtm
           FROM _tmp.orca_institutions
        GROUP BY institution_id) j
         ON j.institution_id = i.institution_id
        AND j.latest_dtm = i.max_dtm
  LEFT  JOIN orca.institutions o                -- left join on institutions to get name conflicts
         ON o.institution_id = i.institution_id
 WHERE  i.institution_name <> coalesce(o.institution_name, '')  -- use coalesce to preserve nulls
ORDER BY institution_id
ON CONFLICT (institution_id) DO UPDATE
SET institution_name = excluded.institution_name;

-- clear tmp table
DROP TABLE _tmp.orca_institutions;

-- back table up in case and check record count: 
-- 20211211: 1962 orig + 110 new = 2072
-- 20211212: 2072 orig +  12 new = 2084
-- 20220919: 2084 orig +  88 new = 2172 (9 updates)
SELECT count(*) FROM orca.institutions;
\copy (SELECT * FROM orca.institutions) TO '~/dl/yyyymmdd_orca_institutions.csv' WITH (FORMAT CSV, HEADER);

-- check time bounds of new data
-- 20220919: as expected
SELECT  min(t.txn_dtm_pacific) AS min_dtm
        ,max(t.txn_dtm_pacific) AS max_dtm
  FROM  _import.orca_transactions t;

-- check sequence before and after
-- 20211212: 187586382 > 219889619
-- 20220919: 219889619 > 250676556
--SELECT nextval('orca.transactions_txn_id_seq1');  -- this increments the counter; use below instead
\d+ orca.transactions_txn_id_seq1;

-- if not right, set val (next call will be one higher):
SELECT setval('orca.transactions_txn_id_seq1', SELECT max(txn_id) FROM orca.transactions);

-- insert translated records into full txn table
-- updated 2021-12-11 to account for some instances where numbers include commas
BEGIN;

INSERT INTO orca.transactions(csn_hash,business_date,txn_dtm_pacific,txn_institution_id,txn_type_id,upgrade_indicator
  ,product_id,txn_passenger_type_id,passenger_count,ceffv_cents,service_agency_id,source_agency_id,transit_operator_abbrev
  ,reader_mode_id,route_number,direction_id,device_id,origin_location_id,destination_location_id,udsn,bad_txn_flag,bad_txn_type)
SELECT  util.hash(util.clean_numtext(card_serial_number), k.key) AS csn_hash
        ,business_date
        ,txn_dtm_pacific
        ,util.clean_numtext(institution_id)::smallint AS txn_institution_id
        ,t.txn_type_id
        ,nullif(upgrade_indicator, '')::boolean AS upgrade_indicator
        ,product_id
        ,txn_passenger_type_id
        ,passenger_count
        ,ceffv_cents
        ,service_agency_id
        ,source_agency_id
        ,transit_operator_abbrev
        ,reader_mode_id
        ,nullif(route_number, '') AS route_number
        ,d.direction_id
        ,util.clean_numtext(device_id)::integer AS device_id
        ,util.clean_numtext(origin_location_id)::bigint AS origin_location_id
        ,util.clean_numtext(destination_location_id)::bigint AS destination_location_id
        ,util.clean_numtext(udsn) AS udsn
        ,CASE WHEN (business_date - txn_dtm_pacific::date) < -1 THEN True
              ELSE False
            END AS bad_txn_flag
        ,CASE WHEN (business_date - txn_dtm_pacific::date) < -1 THEN 1
              ELSE NULL
            END AS bad_txn_type
  FROM  _import.orca_transactions o
  JOIN  orca.transaction_types t ON t.txn_type_descr = o.txn_type_descr
  JOIN  orca.directions d ON d.direction_descr = o.direction_descr
  JOIN  (SELECT get_parameter AS key FROM orca.get_parameter('hmac_key')) k ON true
ORDER BY 3;

-- ROLLBACK;
COMMIT;

-- 2021-12-11: inserted 26,832,378 records for 2021-01-01 to 2021-09-30
-- 2021-12-12: inserted  5,470,859 records for 2021-10-01 to 2021-10-31
-- 2022-09-19: inserted 30,786,937 records for 2021-11-01 to 2022-05-15 in 1332s:
--   2021: 32,303,515 +  9,340,747 = 41,644,262 records
--   2022:          2 + 21,446,190 = 21,446,192 records

-- get last value inserted
-- 20211212: 219889619
-- 20220919: 250676556
-- SELECT max(txn_id) FROM orca.transactions; -- slower
\d+ orca.transactions_txn_id_seq1;

/* no longer needed - incorporated into above
-- update bad_txn_flag for unreasonable future txns
UPDATE  orca.transactions
   SET  bad_txn_flag = True
        ,bad_txn_type = 1
 WHERE  (business_date - txn_dtm_pacific::date) < -1;
*/

-- check for duplicate txns?

-- backup import table
\copy (SELECT * FROM _import.orca_transactions) TO '~/dl/2019-2020_raw_orca_transactions.csv' WITH (FORMAT CSV, HEADER);
\copy (SELECT * FROM _import.orca_transactions) TO '~/dl/20210101-20210930_raw_orca_transactions.csv' WITH (FORMAT CSV, HEADER);
\copy (SELECT * FROM _import.orca_oct_transactions) TO '~/dl/20211001-20211031_raw_orca_transactions_alt_format.csv' WITH (FORMAT CSV, HEADER);
\copy (SELECT * FROM _import.orca_transactions_no_seconds) TO '~/dl/20211001-20211031_raw_orca_transactions_no_seconds.csv' WITH (FORMAT CSV, HEADER);
\copy (SELECT * FROM _import.orca_transactions) TO '~/dl/20211101-20220515_raw_orca_transactions.csv' WITH (FORMAT CSV, HEADER);

-- truncate import table
TRUNCATE TABLE _import.orca_transactions;

-- backup final hashed transactions
-- 2019: 149,837,437
-- 2020:  37,748,663
-- 2021:  41,644,262
-- 2022:  21,446,192 (thru May 15)
-- future txns: 2 bad txns

-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.transactions_2019 --data-only orca_pod > ~/dl/orca_transactions_2019.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.transactions_2020 --data-only orca_pod > ~/dl/orca_transactions_2020.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.transactions_2021 --data-only orca_pod > ~/dl/orca_transactions_2021.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.transactions_2022 --data-only orca_pod > ~/dl/orca_transactions_2022_partial.sql

/********** ORCA BOARDINGS & TRANSFERS **********/
/*
-- look at upgrade txns
SELECT DISTINCT t.upgrade_indicator, t.txn_type_id FROM orca.transactions t;

-- true:    1,522,026
-- false:  63,724,893
-- NULL:  154,642,700
SELECT t.upgrade_indicator, count(*) FROM orca.transactions t GROUP BY 1;

-- 1:     1,911
-- 2: 1,520,097
-- 3:        18
SELECT  samtidigt_count
        ,count(*) AS count
--CREATE TABLE _tmp.upgrade_study AS SELECT  *
  FROM  (SELECT t.txn_id
                ,t.csn_hash
                ,t.txn_dtm_pacific
                ,t.upgrade_indicator
                ,count(*) OVER (PARTITION BY t.csn_hash, t.txn_dtm_pacific) AS samtidigt_count
           FROM orca.transactions t
        ) d
 WHERE  upgrade_indicator = true
--   AND  samtidigt_count <> 2;
GROUP BY 1;

-- look at those with three simultaneous txns
-- always [10|11|21], 31, [30|40] with 30 or 40 being upgrade txn
SELECT  *
  FROM  orca.transactions t
 WHERE  (t.csn_hash, t.txn_dtm_pacific) IN (SELECT csn_hash, txn_dtm_pacific FROM _tmp.upgrade_study WHERE samtidigt_count = 3)
ORDER BY t.csn_hash, t.txn_dtm_pacific, t.txn_type_id;

-- look at those with no simultaneous txns
-- 10:  376
-- 20: 1507
-- 30:   10 - exit txn, is okay
-- 40:   18 - exit txn, is okay
SELECT  t.txn_type_id
        ,count(*)
CREATE TABLE _tmp.single_upgrade AS
SELECT  u.*
        ,t.txn_type_id
        ,prv.*
        ,nxt.*
  FROM  orca.transactions t
  JOIN  _tmp.upgrade_study u
         ON u.txn_id = t.txn_id
        AND u.samtidigt_count = 1
  LEFT JOIN LATERAL
        (SELECT p.txn_id AS p_txn_id, p.txn_dtm_pacific AS p_txn_dtm, p.txn_type_id AS p_txn_type_id, p.upgrade_indicator AS p_upgrade
           FROM orca.transactions p
          WHERE p.csn_hash = u.csn_hash
            AND p.txn_dtm_pacific < u.txn_dtm_pacific
         ORDER BY p.txn_dtm_pacific DESC
         FETCH FIRST 1 ROW ONLY
        ) prv ON true
  LEFT JOIN LATERAL
        (SELECT n.txn_id AS n_txn_id, n.txn_dtm_pacific AS n_txn_dtm, n.txn_type_id AS n_txn_type_id, n.upgrade_indicator AS n_upgrade
           FROM orca.transactions n
          WHERE n.csn_hash = u.csn_hash
            AND n.txn_dtm_pacific > u.txn_dtm_pacific
         ORDER BY n.txn_dtm_pacific ASC
         FETCH FIRST 1 ROW ONLY
        ) nxt ON true;
GROUP BY 1;
--ORDER BY t.csn_hash, t.txn_dtm_pacific, t.txn_type_id;

-- max time between previous and txn - ~80 hours
SELECT max(txn_dtm_pacific - p_txn_dtm) FROM _tmp.single_upgrade;

-- look at txns with more than 10 minutes between and upgrade is not an exit txn
SELECT  u.p_txn_dtm, u.txn_dtm_pacific, u.n_txn_dtm, u.p_txn_type_id, u.txn_type_id, u.n_txn_type_id
--SELECT  t.reader_mode_id, count(*)
  FROM  _tmp.single_upgrade u
  JOIN  orca.transactions t ON t.txn_id = u.txn_id
 WHERE  (u.txn_dtm_pacific - u.p_txn_dtm) > interval '10 minutes'
-- WHERE  u.p_txn_dtm IS NULL
   AND  u.txn_type_id < 30
GROUP BY 1;

-- distinct txn_id types
SELECT DISTINCT p_txn_type_id, txn_type_id FROM _tmp.single_upgrade ORDER BY 1,2;

-- TODO: also check that all simultaneous txns have only one boarding txn that is not an upgrade

-- clean up
DROP TABLE _tmp.upgrade_study;
*/

-- create views for boardings and alightings
-- remove exit txns, bad txns, and upgrade txns (these are duplicates)
-- TODO: redefine without join
CREATE OR REPLACE VIEW orca.boardings AS
SELECT  o.*
  FROM  orca.transactions o
  JOIN  orca.transaction_types t
         ON t.txn_type_id = o.txn_type_id
-- WHERE  o.txn_type_id < 30      -- not an exit txn
 WHERE  NOT t.is_exit           -- not an exit txn
   AND  NOT o.bad_txn_flag      -- not a bad txn
   AND  NOT coalesce(o.upgrade_indicator, False);   -- not an upgrade txn

-- TODO: also look at de-duped alightings from orca_analysis.sql
/*CREATE OR REPLACE VIEW orca.alightings AS
SELECT  o.*
  FROM  orca.transactions o
  JOIN  orca.transaction_types t
         ON t.txn_type_id = o.txn_type_id
 WHERE  t.is_exit;
*/

-- build txn lookup table:
-- NOTE: partition on txn_id instead of date since there is no date in this table
--       txn_ids generally increase with date so this is okay; plus, bad txns (which are the exception) are not put in this table
--       also need to have process to update if late txns come in and reprocess affected txns (or does materialized view do this?)
-- TODO: drop veh_trip_id and created_at columns; veh_trip info is in board_locations and created_at is not needed
-- ALTER TABLE orca.boarding_groups DROP COLUMN veh_trip_id, DROP COLUMN created_at;
CREATE TABLE orca.boarding_groups (
    txn_id bigint PRIMARY KEY
    ,prev_txn_id bigint -- UNIQUE       -- previous txn, regardless of within transfer window (can't specify unique when partitioning)
    ,is_transfer boolean NOT NULL       -- flag whether txn is a transfer or not
    ,grp_first_txn_id bigint NOT NULL   -- first txn within group
    ,grp_prev_txn_id bigint             -- previous txn within group
    ,veh_trip_id bigint DEFAULT NULL    -- vehicle trip id, previously in orca data
    ,created_at timestamptz DEFAULT util.now_utc()
    ,updated_at timestamptz DEFAULT util.now_utc()  
) PARTITION BY RANGE (txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.boarding_groups (prev_txn_id);
CREATE INDEX ON orca.boarding_groups (grp_first_txn_id);

-- create child partitions
CREATE TABLE orca.boarding_groups_100m PARTITION OF orca.boarding_groups FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.boarding_groups_200m PARTITION OF orca.boarding_groups FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.boarding_groups_300m PARTITION OF orca.boarding_groups FOR VALUES FROM (200000000) TO (300000000);

-- view to get next txn instead of previous
-- TODO: look into issue with simultaneous transactions?
CREATE OR REPLACE VIEW orca.next_boarding AS
SELECT  p.txn_id
        ,n.txn_id AS next_txn_id
  FROM  orca.boarding_groups p
  JOIN  orca.boarding_groups n ON n.prev_txn_id = p.txn_id;

-- view to join boardings with boarding groups
CREATE OR REPLACE VIEW orca.boardings_with_groups AS
SELECT  b.*
        ,g.prev_txn_id
        ,g.is_transfer
        ,g.grp_first_txn_id
        ,g.grp_prev_txn_id
        ,g.veh_trip_id
  FROM  orca.boardings b
  JOIN  orca.boarding_groups g
    ON  g.txn_id = b.txn_id;

-- backup existing boarding_groups
\copy (SELECT * FROM orca.boarding_groups) TO '~/dl/2019-2020_orca_boarding_groups_with_upgrade_txns.csv' WITH (FORMAT CSV, HEADER);
\copy (SELECT * FROM orca.boarding_groups) TO '~/dl/20190101-20211031_orca_boarding_groups.csv' WITH (FORMAT CSV, HEADER);

-- table of latest boarding txn_id up to a given datetime for each hashed csn
-- okay to use txn_id instead of strictly checking on txn_dtm_pacific since inserts into orca.transactions are 
--   ordered by txn_dtm_pacific (checked) and the only misordered txns are bad txns excluded from boardings
-- NOTE: do not need to store as-of dates since we can get latest datetime dynamically
CREATE TABLE orca.latest_txn_by_csn (
    csn_hash text PRIMARY KEY NOT NULL
    ,latest_txn_id bigint NOT NULL
);

-- materialized view to get latest update time
CREATE MATERIALIZED VIEW orca.m_latest_txn_by_csn_asof AS
SELECT  max(b.txn_dtm_pacific) AS asof_dtm
  FROM  orca.latest_txn_by_csn c
  JOIN  orca.boardings b ON b.txn_id = c.latest_txn_id;

-- initial run - fill table as-of 2021-01-01 03:00:00
INSERT INTO orca.latest_txn_by_csn
SELECT  b.csn_hash
        ,max(b.txn_id) AS latest_txn_id
  FROM  orca.boardings b
 WHERE  b.txn_dtm_pacific < '2021-01-01 03:00:00'::timestamp
GROUP BY b.csn_hash;

-- procedure to update lastest txn_id by csn_hash
CREATE OR REPLACE PROCEDURE orca.update_latest_txn_by_csn(_upto_dtm timestamp without time zone)
LANGUAGE SQL AS $$
    -- insert or update new values since last run
    INSERT INTO orca.latest_txn_by_csn
    SELECT  b.csn_hash
            ,max(b.txn_id) AS latest_txn_id
      FROM  orca.boardings b
     WHERE  b.txn_dtm_pacific > (SELECT asof_dtm FROM orca.m_latest_txn_by_csn_asof)    -- only boardings since last update
       AND  b.txn_dtm_pacific < _upto_dtm                                               -- only boardings up to current limit
    GROUP BY b.csn_hash
    ON CONFLICT (csn_hash) DO UPDATE
    SET latest_txn_id = excluded.latest_txn_id;

    -- refresh materialized view after update
    REFRESH MATERIALIZED VIEW orca.m_latest_txn_by_csn_asof;
$$;

-- manually call to update if needed
CALL orca.update_latest_txn_by_csn('2021-11-01 03:00:00'::timestamp);

-- procedure to build txn groups
-- pull data from orca.transactions using provided txn_dtm_cutoff date
-- can't use txns not in boarding_groups since non-boarding txns aren't inserted anyways
-- TODO: add logging statements once logger is built
-- NOTE: could also select based on txn_id instead of txn_dtm_pacific
CREATE OR REPLACE PROCEDURE orca.build_boarding_groups(_after_dtm timestamp without time zone)
LANGUAGE plpgsql AS $$
DECLARE
    _xfer_window interval;
    _rec record;
    _csn text := '';
    _dtm timestamp;
    _prev_txn bigint;
    _grp_first_txn bigint;
    _grp_prev_txn bigint;
    _xfer boolean;
BEGIN
    -- ensure that _after_dtm is greater than latest txn dtm in latest_txn_by_csn table
    IF _after_dtm < (SELECT asof_dtm FROM orca.m_latest_txn_by_csn_asof) THEN
        -- raise warning and exit
        RAISE WARNING 'latest txn_dtm from latest_txn_by_csn exceeds input datetime; exiting';
        RETURN;
    ELSE
        -- update latest_txn_by_csn to be asof after_dtm
        CALL orca.update_latest_txn_by_csn(_after_dtm);
    END IF;
    -- get transfer time from parameters
    SELECT val::interval FROM orca.get_parameter('transfer_time') INTO _xfer_window;
    -- iterate through boardings by card serial number and time
    FOR _rec IN
        SELECT  b.txn_id
                ,b.csn_hash
                ,b.txn_dtm_pacific
          FROM  orca.boardings b
         WHERE  b.txn_dtm_pacific >= _after_dtm
        ORDER BY b.csn_hash
                ,b.txn_dtm_pacific
    LOOP
        -- check for new hashed csn
        IF _csn IS DISTINCT FROM _rec.csn_hash THEN
            -- set new _csn
            _csn := _rec.csn_hash;
            -- get prev txn, grp first txn, initial boarding time (if it exists) for this hashed csn
            -- used to check if new txns should still be within xfer window of last boarding txn_id
            -- NULLs are returned if there is no match, as expected
            SELECT  t.latest_txn_id     -- previous boarding txn
                    ,g.grp_first_txn_id -- initial group txn
                    ,o.txn_dtm_pacific  -- initial group boarding datetime
              INTO  _prev_txn, _grp_first_txn, _dtm
              FROM  orca.latest_txn_by_csn t
              JOIN  orca.boarding_groups g ON g.txn_id = t.latest_txn_id        -- group of last boarding
              JOIN  orca.boardings o ON o.txn_id = g.grp_first_txn_id           -- first boarding of that group
             WHERE  t.csn_hash = _csn;
            -- update dtm to add transfer window, unless NULL then set to unix epoch
            _dtm := coalesce(_dtm + _xfer_window, '1970-01-01');
        END IF;
        -- check if new txn dtm is within transfer window
        IF _rec.txn_dtm_pacific > _dtm THEN
            -- transfer time window has passed; update transfer window and set _xfer, new _grp_first_txn, and _grp_prev_txn
            _dtm := _rec.txn_dtm_pacific + _xfer_window;
            _xfer := false;
            _grp_first_txn := _rec.txn_id;
            _grp_prev_txn := NULL;
        ELSE
            -- mark as a transfer and set _grp_prev_txn to _prev_txn
            _xfer := true;
            _grp_prev_txn := _prev_txn;
        END IF;
        -- insert record into tracking table - on conflict do nothing since boarding groups should never need to be updated
        INSERT INTO orca.boarding_groups(txn_id,prev_txn_id,is_transfer,grp_first_txn_id,grp_prev_txn_id) VALUES
        (_rec.txn_id, _prev_txn, _xfer, _grp_first_txn, _grp_prev_txn)
        ON CONFLICT (txn_id) DO NOTHING;
        -- set _prev_txn_id for next record
        _prev_txn := _rec.txn_id;
    END LOOP;
END $$;

-- call procedure
BEGIN;
CALL orca.build_boarding_groups('2019-01-01 03:00:00');
CALL orca.build_boarding_groups('2021-11-01 03:00:00');
-- ROLLBACK;
COMMIT;

-- expected number of inserts:
-- 20220919: 26,696,315
SELECT count(*) FROM orca.boardings WHERE txn_dtm_pacific >= '2021-11-01 03:00:00';

-- after completion, records in boarding_groups:
-- 20211212: 197,877,725
-- 20220919: 224,574,040  (as expected)
SELECT count(*) FROM orca.boarding_groups;

-- also check new max value of txn_id
-- 20211212: 219889619
-- 20220919: 250676556

-- back up data
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.boarding_groups_100m --data-only orca_pod > ~/dl/orca_boarding_groups_100m.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.boarding_groups_200m --data-only orca_pod > ~/dl/orca_boarding_groups_200m.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.boarding_groups_300m --data-only orca_pod > ~/dl/orca_boarding_groups_300m_partial.sql

/********** historical issue now resolved **********
-- removal of upgrade txns from Dmitri's boardings_avl
-- backup rows in boardings_avl that are upgrade_txns
-- 217,327 out of 99,905,818 txns
--       0 out of 99,688,491 txns - 217,327 less, matches
\copy (
CREATE TABLE _tmp.upgrade_boardings AS
SELECT  a.txn_id
--SELECT  count(*)
  FROM  orca.boardings_avl a
  JOIN  orca.transactions o ON o.txn_id = a.txn_id
--  JOIN  orca.boardings o ON o.txn_id = a.txn_id
 WHERE  o.upgrade_indicator = true
) TO '~/dl/2019-2020_boardings_avl_with_upgrade_txn.csv' WITH (FORMAT CSV, HEADER);

DELETE
--SELECT  count(*)
  FROM  orca.boardings_avl a
 WHERE  a.txn_id IN (SELECT * FROM _tmp.upgrade_boardings);

DROP TABLE _tmp.upgrade_boardings;
*/

/********** testing: trips spanning data import window **********
-- 20211212: 3 hashed csns with 6 txns split the run barrier (and txn_ids for checking):        xfer
-- 5179f5e8a59796a3f94f25e91b16d03ae92352ff5ebdaa33dc84ebb3cd770714 2, 187586346, 187586391     yes
-- 64edb8a9bdf54c0f3df02743ed51435079b2c6a1b6912a2d35053fd5cc62c591 2, 187586352, 187586412     yes
-- aa5f96534594c734247e414551ddad596272fd658a3ae649d4352d8957705fbf 2, 187586369, 187586415     yes

-- 20220919: 7 hashed csns with 14 txns split the new run barrier      first_txn  last_txn    suspiction            xfer?
-- 1e19fc79c67337eaceeeb95c3518ccd10f7218c2b4ce0ed84694d4e3659aae7d 2, 219889487, 219889868   not a transfer        no
-- 1f50ae9658d8fa2e59aac8f8e0540f3ae1da8207084affb8e0e8c91d55b72ea1 2, 219889575, 219890135   possibly a transfer   no
-- 5b5a4a8781913450fe6d97b51a645318e1b239d6842991dddd5d9de9a4e10450 2, 219889475, 219890260   not a transfer        no
-- 698ba923513ea54ea564755bb2140768fe63987ba464daabb674b3d8cffe65e5 2, 219889447, 219889639   unlikely a transfer   no
-- 6e9f7e0de9e41350f3ca6228c9c63abd1e036642f694ec954573f6592eb34ea6 2, 219889611, 219889903   probably a transfer   yes
-- 89eb8ecee01601861c70682cb2061b2939dafddc838c406b1b4a29ebe2ff7297 2, 219889556, 219889704   probably a transfer   yes
-- cf045c8ad683c9b6e79934bc15f39e352aa9e3661ec81f7cf8e225d9d4febb2e 2, 219889596, 219889665   probably a transfer   yes
*/
SELECT  csn_hash
        ,count(DISTINCT business_date)
        ,min(txn_id) AS first_txn
        ,max(txn_id) AS last_txn
  FROM  (
SELECT  txn_id
        ,csn_hash
        ,business_date
        ,txn_dtm_pacific
        ,txn_type_id
  FROM  orca.transactions t
 WHERE  t.txn_dtm_pacific BETWEEN '2021-11-01 01:00:00' AND '2021-11-01 05:00:00'
   AND  csn_hash IN (
        SELECT  csn_hash
          FROM  orca.transactions t
         WHERE  t.txn_dtm_pacific BETWEEN '2021-11-01 01:00:00' AND '2021-11-01 05:00:00'
        GROUP BY 1
        HAVING count(*) > 1)
ORDER BY 2,3
) AS t
GROUP BY 1
HAVING count(DISTINCT business_date) > 1;

-- check after boarding groups
SELECT  bg.txn_id, bg.txn_dtm_pacific, bg.grp_first_txn_id, b.txn_dtm_pacific AS grp_first_dtm_pacific
  FROM  orca.boardings_with_groups bg
  JOIN  orca.boardings b ON b.txn_id = bg.grp_first_txn_id
 WHERE  bg.txn_dtm_pacific BETWEEN '2021-11-01 01:00:00' AND '2021-11-01 05:00:00'
   AND  bg.csn_hash = 'cf045c8ad683c9b6e79934bc15f39e352aa9e3661ec81f7cf8e225d9d4febb2e';

-- create view to summarize transfers
-- TODO: may delete this since it does not account for trip_breaks, etc
CREATE OR REPLACE VIEW orca.boarding_transfers AS
SELECT  grp_first_txn_id
        ,(count(*) -1) AS num_transfers
  FROM  orca.boarding_groups
GROUP BY 1;

/********** AGENCY AVL DATA IMPORT **********/
-- ct avl data format: Trip ID,Vehicle ID,Stop ID,Date,Arrival Time (Seconds),Departure Time (Seconds),Route,Direction,ON's,OFF's,Balanced ON's,Balanced OFF's,Load,Lat,Long

-- create table for holding data
CREATE UNLOGGED TABLE _import.agency_avl_ct (
    trip_id text
    ,vehicle_id text
    ,stop_id text
    ,arrival_date date
    ,arrival_time integer   -- seconds elapsed during the day
    ,departure_time integer -- seconds elapsed during the day
    ,route text
    ,direction text
    ,ons smallint
    ,offs smallint
    ,balanced_ons real
    ,balanced_offs real
    ,load smallint
    ,lat float
    ,lng float
    ,batch_no smallint DEFAULT NULL   -- used to identify individual files (e.g. check date ranges) in multiple file imports
);

-- NOTE: can't use primary key or unique constraint since trip_id is NULL in some instances
--       and there can be multiple records due to opening and closing doors several times
CREATE TABLE agency.avl_ct (
    trip_id text
    ,vehicle_id text
    ,stop_id text
    ,arrival_dtm_pacific timestamp without time zone
    ,departure_dtm_pacific timestamp without time zone
    ,route_id text
    ,direction text
    ,ons smallint
    ,offs smallint
    ,balanced_ons real
    ,balanced_offs real
    ,load smallint
    ,lat float
    ,lng float
    ,stop_location geometry(Point,4326)
    --,UNIQUE (trip_id,vehicle_id,stop_id,arrival_dtm_pacific)
) PARTITION BY RANGE (arrival_dtm_pacific);

-- create indices:
CREATE INDEX ON agency.avl_ct (arrival_dtm_pacific);
CREATE INDEX ON agency.avl_ct (stop_id);
CREATE INDEX ON agency.avl_ct (route_id);
CREATE INDEX ON agency.avl_ct (vehicle_id);
CREATE INDEX ON agency.avl_ct (trip_id);

-- create child partitions:
CREATE TABLE agency.avl_ct_2019 PARTITION OF agency.avl_ct FOR VALUES FROM ('2019-01-01') TO ('2020-01-01');
CREATE TABLE agency.avl_ct_2020 PARTITION OF agency.avl_ct FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');
CREATE TABLE agency.avl_ct_2021 PARTITION OF agency.avl_ct FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');
CREATE TABLE agency.avl_ct_2022 PARTITION OF agency.avl_ct FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');

-- import data, converting 'NULL' to NULL
-- \copy _import.agency_avl_ct (trip_id,vehicle_id,stop_id,arrival_date,arrival_time,departure_time,route,direction,ons,offs,balanced_ons,balanced_offs,load,lat,lng) FROM '~/dl/data/ct/20190101-20190331_ct_avl_data_v2.csv' WITH (FORMAT CSV, HEADER, NULL 'NULL');
-- new format, set blank '' to NULL
\copy _import.agency_avl_ct (trip_id,vehicle_id,stop_id,arrival_date,arrival_time,departure_time,route,direction,ons,offs,balanced_ons,balanced_offs,load,lat,lng) FROM '~/dl/data/ct/20220101-20220115_ct_avl_data.csv' WITH (FORMAT CSV, HEADER, NULL '');
UPDATE _import.agency_avl_ct SET batch_no = 1 WHERE batch_no IS NULL;

SELECT batch_no, count(*) FROM _import.agency_avl_ct GROUP BY 1 ORDER BY 1;

-- convert nulls in certain fields to 0
UPDATE _import.agency_avl_ct SET ons = 0 WHERE ons IS NULL;
UPDATE _import.agency_avl_ct SET offs = 0 WHERE offs IS NULL;
UPDATE _import.agency_avl_ct SET balanced_ons = 0 WHERE balanced_ons IS NULL;
UPDATE _import.agency_avl_ct SET balanced_offs = 0 WHERE balanced_offs IS NULL;
UPDATE _import.agency_avl_ct SET load = 0 WHERE load IS NULL;

-- TODO: check for other 'NULL's?
-- e.g., how to deal with NULLS in lat or long?

-- insert data into main table
INSERT INTO agency.avl_ct
SELECT  trip_id
        ,vehicle_id
        ,stop_id
        ,arrival_date + (arrival_time * interval '1 second') AS arrival_dtm_pacific
        ,arrival_date + (departure_time * interval '1 second') AS departure_dtm_pacific
        ,route AS route_id
        ,left(direction, 1) AS direction
        ,ons
        ,offs
        ,balanced_ons
        ,balanced_offs
        ,load
        ,lat
        ,lng
        ,ST_SetSRID(ST_MakePoint(lng, lat), 4326) AS stop_location
  FROM  _import.agency_avl_ct a;

-- clear records from import table
TRUNCATE TABLE _import.agency_avl_ct;

/*

-- ct import issues
range       del   v1        v2        v1 error lines
--------------------------------------------------------
2019-01-01    3   4166750   4110529   505257, 2113429, 3329560
2019-04-01    0   4635399   4635399
2019-07-01    0   4621672   4621672
2019-10-01    1   4680944   4662251   3869450
2020-01-01   12   4685632   4460944   1122302, 1832929, 2020008, 2094866, 2506348, 2917744, 3123562, 3254486, 3778351, 3834485, 4077878, 4396341
2020-04-01    6   3524185   3411991   711134, 879552, 991674, 2038573, 2468203, 3383918
2020-07-01    4   3889719   3814721   1309534, 1478124, 1590464, 2675087
2020-10-01    1   4008731   3989943   2714739
2021-01-01                  3903042
2021-04-01                  4046411
2021-07-01        4064744

*/

/***** king county avl *****/

-- 2022-10-14: new file format has headers, can finally name all fields!
-- "short_name","trip_role","trip_id","pattern_id","blk","long_name","Rte","dir","Sch_St_Min","Sch_Trip_St_Tm","OPERATION_DATE","PCNT_PATT_QUALITY","VEHICLE_ID","stop_id","Stop_Name","STOP_ROLE","apc_veh","doors_open","Ons","Offs","Load","LIFT_DEPLOYMENT","Act_Stop_time","Sch_stop_sec","Act_stop_Arr","act_Stop_dep","dwell_sec","door_open_sec","dist_to_next","dist_to_trip","gps_lat","gps_long"

-- create table for holding data
CREATE UNLOGGED TABLE _import.agency_avl_kcm (
    daycode smallint    -- short_name
    ,trip_role text
    ,trip_id text
    ,pattern_id integer
    ,blk integer
    ,long_block text    -- long_name
    ,route text
    ,dir text
    ,sch_st_min smallint
    ,sch_stop_time time without time zone   -- sch_trip_st_tm
    ,opd_date date              -- operation_date
    ,pattern_quality smallint   -- pcnt_patt_quality
    ,vehicle_id text
    ,stop_id text
    ,stop_name text
    ,stop_role text
    ,apc_veh text       -- boolean
    ,doors_open text    -- boolean
    ,ons smallint
    ,offs smallint
    ,load smallint
    ,lift_deployment smallint
    ,act_stop_time time without time zone
    ,sch_stop_sec integer
    ,act_stop_arr_sec integer
    ,act_stop_dep_sec integer
    ,dwell_sec integer
    ,door_open_sec integer
    ,dist_to_next integer
    ,dist_to_trip integer
    ,gps_lat double precision
    ,gps_long double precision
    ,batch_no smallint DEFAULT NULL   -- used to identify individual files (e.g. check date ranges) in multiple file imports
);

CREATE TABLE agency.avl_kcm (
    daycode smallint
    ,trip_role text
    ,trip_id text
    ,pattern_id integer
    ,block integer
    --,long_block text          -- see info below; matches blk without '/'
    ,route_id text
    ,direction text
    --,sch_st_min smallint          -- redundant with sch_stop_dtm_pacific
    ,sch_stop_dtm_pacific timestamp without time zone
    ,pattern_quality smallint
    ,vehicle_id text
    ,stop_id text
    ,stop_name text
    ,stop_role text
    ,apc_veh boolean
    ,doors_open boolean
    ,ons smallint
    ,offs smallint
    ,load smallint
    ,lift_deployment smallint
    ,arrival_dtm_pacific timestamp without time zone
    ,departure_dtm_pacific timestamp without time zone
    ,sch_stop_sec integer           -- should be redundant but is not!
    --,act_stop_arr_sec integer     -- redundant with arrival_dtm_pacific
    --,act_stop_dep_sec integer     -- redundant with departure_dtm_pacific
    --,dwell_sec integer            -- redundant, equal to departure_dtm_pacific - arrival_dtm_pacific
    ,door_open_sec integer
    ,dist_to_next integer
    ,dist_to_trip integer
    ,gps_lat double precision
    ,gps_long double precision
    ,stop_location geometry(Point,4326)
) PARTITION BY RANGE (arrival_dtm_pacific);

-- create indices:
CREATE INDEX ON agency.avl_kcm (arrival_dtm_pacific);
CREATE INDEX ON agency.avl_kcm (stop_id);
CREATE INDEX ON agency.avl_kcm (route_id);
CREATE INDEX ON agency.avl_kcm (vehicle_id);
CREATE INDEX ON agency.avl_kcm (trip_id);
CREATE INDEX ON agency.avl_kcm (doors_open);

-- create child partitions:
CREATE TABLE agency.avl_kcm_2019h1 PARTITION OF agency.avl_kcm FOR VALUES FROM ('2019-01-01') TO ('2019-07-01');
CREATE TABLE agency.avl_kcm_2019h2 PARTITION OF agency.avl_kcm FOR VALUES FROM ('2019-07-01') TO ('2020-01-01');
CREATE TABLE agency.avl_kcm_2020h1 PARTITION OF agency.avl_kcm FOR VALUES FROM ('2020-01-01') TO ('2020-07-01');
CREATE TABLE agency.avl_kcm_2020h2 PARTITION OF agency.avl_kcm FOR VALUES FROM ('2020-07-01') TO ('2021-01-01');
CREATE TABLE agency.avl_kcm_2021h1 PARTITION OF agency.avl_kcm FOR VALUES FROM ('2021-01-01') TO ('2021-07-01');
CREATE TABLE agency.avl_kcm_2021h2 PARTITION OF agency.avl_kcm FOR VALUES FROM ('2021-07-01') TO ('2022-01-01');
CREATE TABLE agency.avl_kcm_2022h1 PARTITION OF agency.avl_kcm FOR VALUES FROM ('2022-01-01') TO ('2022-07-01');
CREATE TABLE agency.avl_kcm_2022h2 PARTITION OF agency.avl_kcm FOR VALUES FROM ('2022-07-01') TO ('2023-01-01');

-- NOTES:
-- true assertions:
-- blk is same as block with '/' removed:
SELECT blk, block FROM _import.agency_avl_kcm WHERE blk <> replace(block, '/','')::int;
-- act_stop_arr_time + dwell_sec = act_stop_dep_time:
SELECT act_stop_arr_sec, act_stop_dep_sec, dwell_sec FROM _import.agency_avl_kcm WHERE act_stop_arr_sec + dwell_sec <> act_stop_dep_sec;
-- apc_veh is always Y or N:
SELECT DISTINCT apc_veh FROM _import.agency_avl_kcm;
-- doors_open is always Y or N:
SELECT DISTINCT doors_open FROM _import.agency_avl_kcm;
-- mod(sch_stop_min*60,86400) = sch_stop_time
SELECT sch_st_min, sch_stop_time FROM _import.agency_avl_kcm WHERE mod(extract(epoch FROM sch_stop_time)::int,86400) <> mod(sch_st_min*60,86400);

-- false assertions:
-- sch_st_min * 60 = sch_stop_sec? but not always the case!
SELECT sch_st_min, sch_stop_sec FROM _import.agency_avl_kcm WHERE sch_st_min*60 <> sch_stop_sec;
-- mod(sch_stop_sec,86400) = sch_stop_time
SELECT sch_stop_sec, sch_stop_time FROM _import.agency_avl_kcm WHERE mod(extract(epoch FROM sch_stop_time),86400) <> mod(sch_stop_sec,86400);

-- data ranges (data from 2019-01-01 thru 2021-12-31)
SELECT min(pattern_id), max(pattern_id) FROM agency.avl_kcm;            -- 10002001 to 157234791; int
SELECT min(blk), max(blk) FROM agency.avl_kcm;                          -- 101 to 99502; int
SELECT min(lift_deployment), max(lift_deployment) FROM agency.avl_kcm;  -- 0 to 37; smallint
SELECT min(door_open_sec), max(door_open_sec) FROM agency.avl_kcm;      -- -62088 to 30380; int
SELECT min(dist_to_next), max(dist_to_next) FROM agency.avl_kcm;        -- 0 to 58570; int

-- import data, converting 'NULL' to NULL
--\copy _import.agency_avl_kcm (daycode,field1,trip_id,pattern_id,blk,block,route,dir,sch_st_min,sch_stop_time,opd_date,pattern_quality,vehicle_id,stop_id,stop_name,point_role,apc_veh,doors_open,ons,offs,load,field2,act_stop_time,sch_stop_sec,act_stop_arr_sec,act_stop_dep_sec,dwell_sec,door_open_sec,x_time,agg_x_time,gps_lat,gps_long) FROM '~/dl/data/kcm/2021-12_kcm_avl_data_1201-1215.csv' WITH (FORMAT CSV, NULL 'NULL');
--\copy _import.agency_avl_kcm (daycode,trip_role,trip_id,pattern_id,blk,long_block,route,dir,sch_st_min,sch_stop_time,opd_date,pattern_quality,vehicle_id,stop_id,stop_name,stop_role,apc_veh,doors_open,ons,offs,load,lift_deployment,act_stop_time,sch_stop_sec,act_stop_arr_sec,act_stop_dep_sec,dwell_sec,door_open_sec,dist_to_next,dist_to_trip,gps_lat,gps_long) FROM '~/dl/data/kcm/2019-2021_missing_kcm_header_rows.csv' WITH (FORMAT CSV, HEADER, NULL 'NULL');
-- new format 2022-10-14 for data starting 2022-01-01: includes header row, NULLs now empty fields
\copy _import.agency_avl_kcm (daycode,trip_role,trip_id,pattern_id,blk,long_block,route,dir,sch_st_min,sch_stop_time,opd_date,pattern_quality,vehicle_id,stop_id,stop_name,stop_role,apc_veh,doors_open,ons,offs,load,lift_deployment,act_stop_time,sch_stop_sec,act_stop_arr_sec,act_stop_dep_sec,dwell_sec,door_open_sec,dist_to_next,dist_to_trip,gps_lat,gps_long) FROM '~/dl/data/kcm/AVL_2022_0101_0107.csv' WITH (FORMAT CSV, HEADER, NULL '');

UPDATE _import.agency_avl_kcm SET batch_no = 1 WHERE batch_no IS NULL;

SELECT batch_no, count(*) FROM _import.agency_avl_kcm GROUP BY 1 ORDER BY 1;

-- populate agency table
-- NOTE: scheduled time should be opd_date + sch_st_min since sch_st_min can be greater than 1440 (early the next morning)
--       actual times should be opd_date + act_stop_[arr,dep]_sec since seconds can be greater than 86400 (early the next morning)
--       do not use sch_stop_time since it does not account for next day!
--       using SRID 3690 per Dmitri's code, though wonder how this differs from 102348
--       for options, see https://www.spatialreference.org/ref/?search=Washington
--       also check https://epsg.io/
INSERT INTO agency.avl_kcm
SELECT  daycode
        ,trip_role
        ,trip_id
        ,pattern_id
        ,blk AS block
        ,route AS route_id
        ,dir AS direction
        ,opd_date + (sch_st_min * interval '1 minute') AS sch_stop_dtm_pacific
        ,pattern_quality
        ,vehicle_id
        ,stop_id
        ,stop_name
        ,stop_role
        ,CASE WHEN apc_veh = 'Y' THEN true ELSE false END AS apc_veh
        ,CASE WHEN doors_open = 'Y' THEN true ELSE false END AS doors_open
        ,ons
        ,offs
        ,load
        ,lift_deployment
        ,opd_date + (act_stop_arr_sec * interval '1 second') AS arrival_dtm_pacific
        ,opd_date + (act_stop_dep_sec * interval '1 second') AS departure_dtm_pacific
        ,sch_stop_sec
        ,door_open_sec
        ,dist_to_next
        ,dist_to_trip
        ,gps_lat
        ,gps_long
        ,ST_Transform(ST_SetSRID(ST_MakePoint(gps_long, gps_lat), 3690), 4326) AS stop_location
  FROM  _import.agency_avl_kcm;

/*
added:    66111609 >         0
2022h1:       6749 >  66107303
2022h2:          0 >     11055
overall: 420223944 > 486335553
*/

-- clear records from import table
TRUNCATE TABLE _import.agency_avl_kcm;

/***** pierce county avl *****/
-- pierce transit avl equivalent (swiftly on-time-performance data)

-- create table for holding data
CREATE UNLOGGED TABLE _import.agency_swiftly_otp_pt (
    block_id text       -- looks like int
    ,trip_id text       -- looks like int
    ,route_id text
    ,route_short_name text
    ,direction_id text  -- looks like smallint
    ,stop_id text
    ,stop_name text
    ,headsign text
    ,vehicle_id text    -- looks like int
    ,driver_id text     -- looks like int
    ,gtfs_stop_seq int          -- out-of-order from schema
    ,trip_start_time text       -- out-of-order from schema
    ,sched_adherence_secs text  -- looks like float/real
    ,scheduled_date text
    ,scheduled_time text
    ,actual_date text
    ,actual_time text
    ,is_arrival text    -- looks like boolean
);

-- final table
-- NOTE: primary key based on trip, stop, and scheduled time, sched_adherence_secs for later updates
--       block_id, route_id, and direction_id are encapsulated in the trip_id
--       vehicle_id and driver_id are for info
CREATE TABLE agency.swiftly_otp_pt (
    block_id text
    ,trip_id text
    ,route_id text
    ,route_short_name text
    ,direction_id smallint
    ,stop_id text
    ,stop_name text
    ,headsign text
    ,vehicle_id text
    ,driver_id text
    ,gtfs_stop_seq int
    ,trip_start_time time without time zone
    ,sched_adherence_secs real
    ,scheduled_dtm_pacific timestamp without time zone
    ,actual_dtm_pacific timestamp without time zone
    ,is_arrival boolean
    --,PRIMARY KEY (trip_id, stop_id, scheduled_dtm_pacific, sched_adherence_secs)
) PARTITION BY RANGE (actual_dtm_pacific);

-- create indices:
CREATE INDEX ON agency.swiftly_otp_pt (actual_dtm_pacific);
CREATE INDEX ON agency.swiftly_otp_pt (stop_id);
CREATE INDEX ON agency.swiftly_otp_pt (route_id);
CREATE INDEX ON agency.swiftly_otp_pt (vehicle_id);
CREATE INDEX ON agency.swiftly_otp_pt (trip_id);

-- create child partitions:
CREATE TABLE agency.swiftly_otp_pt_2019 PARTITION OF agency.swiftly_otp_pt FOR VALUES FROM ('2019-01-01') TO ('2020-01-01');
CREATE TABLE agency.swiftly_otp_pt_2020 PARTITION OF agency.swiftly_otp_pt FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');
CREATE TABLE agency.swiftly_otp_pt_2021 PARTITION OF agency.swiftly_otp_pt FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');
CREATE TABLE agency.swiftly_otp_pt_2022 PARTITION OF agency.swiftly_otp_pt FOR VALUES FROM ('2022-01-01') TO ('2023-01-01');

-- load data from previous orca database by dumping and importing:
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.pt_swiftly_otp --data-only orca > 20211019_pt_swiftly_data.sql
-- psql -U rpavery -h 10.142.198.115 orca_pod < 20211019_pt_swiftly_data.sql

-- get files from trac_ubuntu (see _orca/agency_data/data_offload_notes.txt)
-- zip files monthly on linux command line:
--//## zip -q -r 2020-07.zip 202007??

-- read records in at command line (also export password)
-- use sed to remove blank lines: https://stackoverflow.com/questions/51293652/
--//## export PGPASSWORD=<pass>
--//## for f in ~/dl/data/pt/*.csv; do psql -U rpavery -h 10.142.198.115 orca_pod -c "\copy _import.agency_swiftly_otp_pt FROM PROGRAM 'sed ''/^\s*$/d'' $f' WITH (FORMAT CSV, HEADER);"; done

-- to count lines in all files and sum: [6107304]
--//## s=0; for f in ~/dl/data/pt/*.csv; do s=$[s + `sed '/^\s*$/d' $f | wc -l` - 1]; done; echo $s

-- 2022-10-15: imported 9929830 rows
-- 2021: 23129394 > 23129394 
-- 2022:        0 >  9929830 -- checks!

-- insert translated records into full txn table
INSERT INTO agency.swiftly_otp_pt
SELECT  block_id
        ,trip_id
        ,route_id
        ,route_short_name
        ,direction_id::smallint AS direction_id
        ,stop_id
        ,stop_name
        ,headsign
        ,vehicle_id
        ,driver_id
        ,gtfs_stop_seq
        ,trip_start_time::time AS trip_start_time
        ,sched_adherence_secs::real AS sched_adherence_secs
        ,to_timestamp(scheduled_date || ' ' || scheduled_time, 'MM-DD-YY HH24:MI:SS')::timestamp AS scheduled_dtm_pacific
        ,to_timestamp(actual_date || ' ' || actual_time, 'MM-DD-YY HH24:MI:SS')::timestamp AS actual_dtm_pacific
        ,is_arrival::boolean AS is_arrival
  FROM  _import.agency_swiftly_otp_pt o;

-- clear records from import table
TRUNCATE TABLE _import.agency_swiftly_otp_pt;

-- insert new schedule change dates
INSERT INTO agency.bus_schedule_change (agency_id, start_date) VALUES
(2,'2022-09-18'),
(4,'2022-09-17'),
(6,'2022-09-18'),
(7,'2022-09-17');

-- back up final avl data files
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_ct_2019 --data-only orca_pod > ~/dl/20221020_agency_avl_ct_data_2019.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_ct_2020 --data-only orca_pod > ~/dl/20221020_agency_avl_ct_data_2020.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_ct_2021 --data-only orca_pod > ~/dl/20221020_agency_avl_ct_data_2021.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_ct_2022 --data-only orca_pod > ~/dl/20221020_agency_avl_ct_data_2022_partial.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_kcm_2019h1 --data-only orca_pod > ~/dl/20221020_agency_avl_kcm_data_2019h1.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_kcm_2019h2 --data-only orca_pod > ~/dl/20221020_agency_avl_kcm_data_2019h2.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_kcm_2020h1 --data-only orca_pod > ~/dl/20221020_agency_avl_kcm_data_2020h1.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_kcm_2020h2 --data-only orca_pod > ~/dl/20221020_agency_avl_kcm_data_2020h2.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_kcm_2021h1 --data-only orca_pod > ~/dl/20221020_agency_avl_kcm_data_2021h1.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_kcm_2021h2 --data-only orca_pod > ~/dl/20221020_agency_avl_kcm_data_2021h2.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_kcm_2022h1 --data-only orca_pod > ~/dl/20221020_agency_avl_kcm_data_2022h1.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.avl_kcm_2022h2 --data-only orca_pod > ~/dl/20221020_agency_avl_kcm_data_2022h2.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.swiftly_otp_pt_2019 --data-only orca_pod > ~/dl/20221020_agency_swiftly_otp_pt_data_2019.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.swiftly_otp_pt_2020 --data-only orca_pod > ~/dl/20221020_agency_swiftly_otp_pt_data_2020.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.swiftly_otp_pt_2021 --data-only orca_pod > ~/dl/20221020_agency_swiftly_otp_pt_data_2021.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.swiftly_otp_pt_2022 --data-only orca_pod > ~/dl/20221020_agency_swiftly_otp_pt_data_2022_partial.sql

---------- GTFS STOPS ----------

-- create table of stops using gtfs files from https://www.soundtransit.org/help-contacts/business-information/open-transit-data-otd/otd-downloads
-- NOTE: unified stop file created by appending gtfs agencies in text order 1,19,29,3,40,95,96,97,98
-- use individual files to import; each has different headers
-- NOTE: okay to use dates instead of datetimes - psql handles correctly for BETWEEN
-- TODO: remove start and end data from import and define on copy into table
CREATE TABLE _import.agency_gtfs_stops (
    stop_id text
    ,stop_name text
    ,stop_lat real
    ,stop_lon real
    ,stop_code text DEFAULT NULL
    ,stop_desc text DEFAULT NULL
    ,zone_id text DEFAULT NULL
    ,stop_url text DEFAULT NULL
    ,location_type text DEFAULT NULL
    ,parent_station text DEFAULT NULL
    ,wheelchair_boarding text DEFAULT NULL
    ,stop_timezone text DEFAULT NULL
    ,gtfs_agency_id smallint DEFAULT NULL
    ,start_date date DEFAULT NULL
    ,end_date date DEFAULT NULL
);

-- use unique stop id
CREATE TABLE agency.gtfs_stops (
    gtfs_stop_id serial PRIMARY KEY
    ,gtfs_agency_id smallint NOT NULL
    ,stop_id text NOT NULL
    ,stop_name text NOT NULL
    ,stop_lat real NOT NULL
    ,stop_lon real NOT NULL
    ,stop_code text
    ,stop_desc text
    ,zone_id text
    ,stop_url text
    ,location_type text
    ,parent_station text
    ,wheelchair_boarding text
    ,stop_timezone text
    ,stop_location geometry(POINT, 4326) NOT NULL
    ,start_date date NOT NULL
    ,end_date date NOT NULL
    ,created_at timestamp with time zone DEFAULT util.now_utc()
    --,PRIMARY KEY (gtfs_agency_id, agency_stop_id, start_date)
);

-- indices
CREATE INDEX ON agency.gtfs_stops (stop_id);
CREATE INDEX gtfs_loc ON agency.gtfs_stops USING GIST (stop_location);
CREATE INDEX agency_stop_id ON agency.gtfs_stops (gtfs_agency_id, stop_id);
CREATE INDEX ON agency.gtfs_stops (start_date, end_date);

-- import original gtfs stop data from orca database
-- \c orca;
-- \copy (SELECT gtfs_agency_id,stop_id,stop_name,stop_lat,stop_lon,stop_code,stop_desc,zone_id,NULL AS stop_url,location_type,parent_station,wheelchair_boarding,stop_timezone,geom AS stop_location,effective_date,created_at FROM agency.gtfs_stops) TO '~/dl/2020_orca_gtfs_stops.csv' WITH (FORMAT CSV, HEADER);

-- now connect to orca_pod and import original gtfs stop data
-- \c orca_pod;
-- \copy agency.gtfs_stops FROM '~/dl/2020_orca_gtfs_stops.csv' WITH (FORMAT CSV, HEADER);


-- import new gtfs stop data from files, using custom columns for each file
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon,stop_code,zone_id,stop_timezone) FROM '~/dl/data/gtfs/1_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 1 WHERE gtfs_agency_id IS NULL;
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon) FROM '~/dl/data/gtfs/19_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 19 WHERE gtfs_agency_id IS NULL;
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon,stop_code,zone_id,location_type,parent_station,stop_timezone) FROM '~/dl/data/gtfs/29_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 29 WHERE gtfs_agency_id IS NULL;
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon,stop_code,zone_id) FROM '~/dl/data/gtfs/3_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 3 WHERE gtfs_agency_id IS NULL;
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon,stop_code,stop_desc,zone_id,stop_url,stop_timezone) FROM '~/dl/data/gtfs/40_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 40 WHERE gtfs_agency_id IS NULL;
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon) FROM '~/dl/data/gtfs/95_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 95 WHERE gtfs_agency_id IS NULL;
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon) FROM '~/dl/data/gtfs/96_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 96 WHERE gtfs_agency_id IS NULL;
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon,stop_code,wheelchair_boarding) FROM '~/dl/data/gtfs/97_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 97 WHERE gtfs_agency_id IS NULL;
\copy _import.agency_gtfs_stops (stop_id,stop_name,stop_lat,stop_lon) FROM '~/dl/data/gtfs/98_stops.txt' WITH (FORMAT CSV, HEADER);
UPDATE _import.agency_gtfs_stops SET gtfs_agency_id = 98 WHERE gtfs_agency_id IS NULL;
-- update date
UPDATE _import.agency_gtfs_stops SET start_date = '2022-01-01'::date;

INSERT INTO agency.gtfs_stops (gtfs_agency_id,stop_id,stop_name,stop_lat,stop_lon,stop_code,stop_desc,zone_id,stop_url,location_type,parent_station,wheelchair_boarding,stop_timezone,stop_location,start_date,end_date)
SELECT  gtfs_agency_id
        ,stop_id
        ,stop_name
        ,stop_lat
        ,stop_lon
        ,stop_code
        ,stop_desc
        ,zone_id
        ,stop_url
        ,location_type
        ,parent_station
        ,wheelchair_boarding
        ,stop_timezone
        ,ST_SetSRID(ST_MakePoint(stop_lon, stop_lat), 4326) AS stop_location
        ,start_date
        ,end_date
  FROM  _import.agency_gtfs_stops;

TRUNCATE TABLE _import.agency_gtfs_stops;

-- back up data
-- pg_dump -U rpavery -h 10.142.198.115 -O -t agency.gtfs_stops --data-only orca_pod > ~/dl/20220302_agency_gtfs_stops.sql

-- select stops by agency
SELECT effective_date, gtfs_agency_id, count(*) FROM agency.gtfs_stops GROUP BY 1,2 ORDER BY 1,2;

-- compare stops - 116 greater than 25m from previous location
SELECT  count(*)
  FROM  agency.gtfs_stops s
  JOIN  agency.gtfs_stops n
         ON n.gtfs_agency_id = s.gtfs_agency_id
        AND n.agency_stop_id = s.agency_stop_id
        AND n.effective_date = '2022-01-01'
 WHERE  s.effective_date = '2020-01-01'
--   AND  (n.stop_lat <> s.stop_lat OR n.stop_lon <> s.stop_lon)
   AND  NOT ST_DWithin(ST_Transform(n.stop_location, 32610), ST_Transform(s.stop_location, 32610), 25);

---------- AVL Processing ----------

-- bus shakeups
CREATE TABLE agency.bus_schedule_change (
    agency_id smallint NOT NULL
    ,start_date date NOT NULL
    ,note text DEFAULT NULL
    ,PRIMARY KEY (agency_id, start_date)
);

-- create view to get start/end date range for each
CREATE OR REPLACE VIEW agency.bus_schedules AS
SELECT  bs.agency_id
        ,bs.start_date
        ,e.end_date
        ,bs.start_date::timestamp + interval '03:00:00' AS start_dtm
        ,e.end_date::timestamp + interval '26:59:59' AS end_dtm
  FROM  agency.bus_schedule_change bs
  JOIN LATERAL
        (SELECT (be.start_date - interval '1 day')::date AS end_date
           FROM agency.bus_schedule_change be
          WHERE bs.agency_id = be.agency_id
            AND bs.start_date < be.start_date
         ORDER BY be.start_date ASC
         FETCH FIRST 1 ROW ONLY
        ) e ON true;

INSERT INTO agency.bus_schedule_change (agency_id, start_date) VALUES
(2,'2018-09-23'),
(4,'2018-09-22'),
(6,'2018-09-23'),
(7,'2018-09-23'),
(2,'2019-03-24'),
(4,'2019-03-23'),
(7,'2019-03-24'),
(2,'2019-09-22'),
(4,'2019-09-21'),
(6,'2019-09-22'),
(7,'2019-09-22'),
(2,'2020-03-22'),
(4,'2020-03-21'),
(6,'2020-03-22'),
(7,'2020-03-22'),
(2,'2020-09-20'),
(4,'2020-09-19'),
(6,'2020-09-20'),
(7,'2020-09-20'),
(2,'2021-03-21'),
(4,'2021-03-20'),
(6,'2021-03-21'),
(7,'2021-03-21'),
(2,'2021-10-03'),
(4,'2021-10-02'),
(6,'2021-09-19'),
(7,'2021-09-19'),
(2,'2022-03-20'),
(4,'2022-03-19'),
(6,'2022-03-20'),
(7,'2022-03-20');

-- create unified view of AVL data
-- do not include stop locations since we can join with geometric median table or gtfs stop location
CREATE OR REPLACE VIEW agency.avl AS   -- kcm data
SELECT  4::smallint AS agency_id
        ,k.vehicle_id
        ,k.route_id
        ,k.trip_id
        ,k.stop_id
        ,k.arrival_dtm_pacific
        ,k.direction            -- in kcm there is N,S,E,W and NULL
  FROM  agency.avl_kcm k
 WHERE  k.doors_open = true     -- do we want to enforce this? doors open less than half the time
UNION ALL   -- ct data
SELECT  2::smallint AS agency_id
        ,c.vehicle_id
        ,c.route_id
        ,c.trip_id
        ,c.stop_id
        ,c.arrival_dtm_pacific
        ,c.direction            -- in ct there is North, South, East, West
  FROM  agency.avl_ct c
UNION ALL   -- pt data
SELECT  6::smallint AS agency_id
        ,p.vehicle_id
        ,p.route_id
        ,p.trip_id
        ,p.stop_id
        ,p.actual_dtm_pacific AS arrival_dtm_pacific    -- this is generally departure time instead of arrival time, except for last stop on route
        ,p.direction_id::text AS direction  -- in pt there is 0 or 1 (look at docs to see which is inbound/outbound)
  FROM  agency.swiftly_otp_pt p
;

-- look for interlined routes in KCM data
-- NOTE: trip_id CHANGES with route_id, so that can't be used to identify interlined routes
SELECT  arrival_dtm_pacific::date
        ,trip_id
        ,vehicle_id
        ,count(DISTINCT route_id) AS route_count
  FROM  agency.avl_kcm_2019h1
GROUP BY 1,2,3
HAVING count(DISTINCT route_id) > 1;

-- view to create stop-pair trips for each bus route
-- use vehicle_id and direction constraints (not route_id) to allow interlining
-- NOTE: enforcing kcm doors open per discussion with Mark 2022-04-22
-- 2022-05-04: changed 3-hour window to 90 minutes since routes really don't last that long
--             also removed route_id and trip_id constraint but added direction constraint
-- 2022-09-16: added direction to selection
-- TODO: change direction to only require same if on same route, otherwise don't allow 'opposite' direction
--       eg, if interlining, direction can change from N to E or W but not S
-- NOTE: using individual tables is *much* faster than using the agency.avl view (3 min vs 7 sec)
CREATE OR REPLACE VIEW agency.v_avl_trips AS
SELECT  4::smallint AS agency_id    -- kcm avl
        ,k.vehicle_id
        ,k.trip_id AS board_trip_id
        ,k.route_id AS board_route_id
        ,k.direction AS board_direction
        ,k.stop_id AS board_stop_id
        ,k.arrival_dtm_pacific AS board_dtm_pacific
        ,n.trip_id AS alight_trip_id
        ,n.route_id AS alight_route_id
        ,n.direction AS alight_direction
        ,n.stop_id AS alight_stop_id
        ,n.arrival_dtm_pacific AS alight_dtm_pacific
  FROM  agency.avl_kcm k
  JOIN  agency.avl_kcm n
         ON n.vehicle_id = k.vehicle_id
        -- AND n.trip_id = k.trip_id
        -- AND n.route_id = k.route_id   -- relax this to allow for interlining?
        AND n.direction = k.direction
        AND n.arrival_dtm_pacific > k.arrival_dtm_pacific
        AND n.arrival_dtm_pacific < k.arrival_dtm_pacific + interval '90 minutes'
        AND k.doors_open = true
        AND n.doors_open = true
UNION ALL
SELECT  2::smallint AS agency_id    -- ct avl
        ,c.vehicle_id
        ,c.trip_id AS board_trip_id
        ,c.route_id AS board_route_id
        ,c.direction AS board_direction
        ,c.stop_id AS board_stop_id
        ,c.arrival_dtm_pacific AS board_dtm_pacific
        ,d.trip_id AS alight_trip_id
        ,d.route_id AS alight_route_id
        ,d.direction AS alight_direction
        ,d.stop_id AS alight_stop_id
        ,d.arrival_dtm_pacific AS alight_dtm_pacific
  FROM  agency.avl_ct c
  JOIN  agency.avl_ct d
         ON d.vehicle_id = c.vehicle_id
        -- AND d.trip_id = c.trip_id
        -- AND d.route_id = c.route_id
        AND d.direction = c.direction
        AND d.arrival_dtm_pacific > c.arrival_dtm_pacific
        AND d.arrival_dtm_pacific < c.arrival_dtm_pacific + interval '90 minutes'
UNION ALL
SELECT  6::smallint AS agency_id    -- pt avl
        ,p.vehicle_id
        ,p.trip_id AS board_trip_id
        ,p.route_id AS board_route_id
        ,p.direction_id::text AS board_direction
        ,p.stop_id AS board_stop_id
        ,p.actual_dtm_pacific AS board_dtm_pacific
        ,q.trip_id AS alight_trip_id
        ,q.route_id AS alight_route_id
        ,q.direction_id::text AS alight_direction
        ,q.stop_id AS alight_stop_id
        ,q.actual_dtm_pacific AS alight_dtm_pacific
  FROM  agency.swiftly_otp_pt p
  JOIN  agency.swiftly_otp_pt q
         ON q.vehicle_id = p.vehicle_id
        -- AND q.trip_id = p.trip_id
        -- AND q.route_id = p.route_id
        AND q.direction_id = p.direction_id
        AND q.actual_dtm_pacific > p.actual_dtm_pacific
        AND q.actual_dtm_pacific < p.actual_dtm_pacific + interval '90 minutes';

CREATE TABLE agency.avl_median_location (
    agency_id smallint NOT NULL
    ,stop_id text NOT NULL
    ,start_dtm timestamp without time zone NOT NULL
    ,end_dtm timestamp without time zone NOT NULL
    ,stop_location geometry(Point,4326)
    ,PRIMARY KEY (agency_id, stop_id, start_dtm)
);

-- create indices
CREATE INDEX ON agency.avl_median_location (agency_id, stop_id);
CREATE INDEX ON agency.avl_median_location (start_dtm, end_dtm);
CREATE INDEX ON agency.avl_median_location USING GIST (stop_location);

-- median avl stop location by stop id and bus schedule
-- pierce transit swiftly data does not include coords, so leave out and use gtfs data instead
-- 2022-10-20: ~50 minutes to refresh 2019-01-01 thru 2022-03 shakeup
-- 2022-10-29: 11 minutes to insert 2022-03 shake-up thru end of June data (to be updated when more AVL data is imported)
--CREATE MATERIALIZED VIEW agency.avl_median_location AS
INSERT INTO agency.avl_median_location
SELECT  a.agency_id
        ,a.stop_id
        ,bs.start_dtm
        ,bs.end_dtm
        ,st_GeometricMedian(st_union(a.stop_location)) AS stop_location
  FROM  agency.bus_schedules bs
  JOIN  (SELECT  4::smallint AS agency_id
                ,k.stop_id::text
                ,k.stop_location
                ,k.arrival_dtm_pacific
          FROM  agency.avl_kcm k
        UNION ALL
        SELECT  2::smallint AS agency_id
                ,c.stop_id::text
                ,c.stop_location
                ,c.arrival_dtm_pacific
          FROM  agency.avl_ct c
        ) AS a
         ON a.agency_id = bs.agency_id
        AND a.arrival_dtm_pacific BETWEEN bs.start_dtm AND bs.end_dtm
 WHERE  bs.end_date > '2022-04-01'
GROUP BY a.agency_id
        ,a.stop_id
        ,bs.start_date
        ,bs.end_date;

--REFRESH MATERIALIZED VIEW agency.avl_median_location;

-- view results
SELECT agency_id, start_dtm, end_dtm, count(*) FROM agency.avl_median_location GROUP BY 1,2,3 ORDER BY 1,2;
SELECT agency_id, max(start_dtm), max(end_dtm) FROM agency.avl_median_location GROUP BY 1 ORDER BY 1;

-- create view to include Pierce Transit location data
CREATE OR REPLACE VIEW agency.v_avl_stop_locations AS
SELECT *, 'median_avl' AS source FROM agency.avl_median_location
UNION ALL
SELECT  6::smallint AS agency_id
        ,p.stop_id
        ,p.start_date::timestamp AS start_dtm
        ,p.end_date:: timestamp + interval '23:59:59' AS end_dtm
        ,p.stop_location
        ,'gtfs' AS source
  FROM  agency.gtfs_stops p
 WHERE  p.gtfs_agency_id = 3;  -- PT only

SELECT agency_id, start_dtm, end_dtm, source, count(*) FROM agency.v_avl_stop_locations GROUP BY 1,2,3,4 ORDER BY 1,2;

-- verify duplicates in devices.brt_stops (expected? some stops may have multiple post assignments?)
SELECT agency_id, stop_id, stop_location, count(*) FROM devices.brt_stops GROUP BY 1,2,3 HAVING count(*) > 1;

-- create view to include off-board reader locations
-- select distinct from offboard posts since some stops have been assigned multiple posts?
CREATE OR REPLACE VIEW agency.v_stop_locations AS
SELECT *, NULL AS restrict_mode_id FROM agency.v_avl_stop_locations
UNION ALL
SELECT  DISTINCT s.agency_id
        ,s.stop_id
        ,'2019-01-01'::timestamp AS start_dtm
        ,'2099-12-31 23:59:59'::timestamp AS end_dtm
        ,s.stop_location
        ,'offboard_posts' AS source
        ,CASE WHEN s.mode_id IN (128,250) THEN NULL ELSE s.mode_id::smallint END AS restrict_mode_id
  FROM  devices.brt_stops s;

SELECT agency_id, start_dtm, end_dtm, source, count(*) FROM agency.v_stop_locations GROUP BY 1,2,3,4 ORDER BY 1,2;

-- unique stop locations (filter out repeated stops in AVL data that duplicates off-board readers)
-- select distinct from offboard posts since some stops have been assigned multiple posts?
-- NOTE: use materialized view for even faster results
CREATE MATERIALIZED VIEW agency.v_uniq_stop_locations AS
SELECT  a.*, NULL AS restrict_mode_id
  FROM  agency.v_avl_stop_locations a
  LEFT  JOIN devices.brt_stops s
          ON s.agency_id = a.agency_id
         AND s.stop_id = a.stop_id
 WHERE  s.stop_id IS NULL
UNION ALL
SELECT  DISTINCT s.agency_id
        ,s.stop_id
        ,'2019-01-01'::timestamp AS start_dtm
        ,'2099-12-31 23:59:59'::timestamp AS end_dtm
        ,s.stop_location
        ,'offboard_posts' AS source
        ,CASE WHEN s.mode_id IN (128,250) THEN NULL ELSE s.mode_id::smallint END AS restrict_mode_id
  FROM  devices.brt_stops s;

-- add indices
-- TODO: do we need both start + end and individual times indices?
CREATE INDEX ON agency.v_uniq_stop_locations (agency_id, stop_id);
CREATE INDEX ON agency.v_uniq_stop_locations (start_dtm, end_dtm);
CREATE INDEX ON agency.v_uniq_stop_locations (start_dtm);
CREATE INDEX ON agency.v_uniq_stop_locations (end_dtm);
CREATE INDEX ON agency.v_uniq_stop_locations (restrict_mode_id);

-- to refresh view
REFRESH MATERIALIZED VIEW agency.v_uniq_stop_locations;

SELECT agency_id, start_dtm, end_dtm, source, count(*) FROM agency.v_uniq_stop_locations GROUP BY 1,2,3,4 ORDER BY 1,2;
-- verify unique: yes
SELECT agency_id, stop_id, start_dtm, end_dtm, count(*) FROM agency.v_uniq_stop_locations GROUP BY 1,2,3,4 HAVING count(*) > 1;

-- create view of unique stops with coordinates
CREATE OR REPLACE VIEW agency.v_uniq_stop_location_coords AS
SELECT  s.*
        ,st_y(stop_location) AS stop_lat
        ,st_x(stop_location) AS stop_lng
  FROM  agency.v_uniq_stop_locations s;

-- compare avl median location to gtfs location
-- which stops are in AVL but not gtfs? 54 for CT, 599 for KCM
SELECT  d.agency_id, count(*) AS stop_count
  FROM  (SELECT DISTINCT m.agency_id, m.stop_id
           FROM agency.avl_median_location m
           JOIN agency.agencies a ON a.orca_agency_id = m.agency_id
          WHERE (a.gtfs_agency_id, m.stop_id) NOT IN (SELECT gtfs_agency_id, agency_stop_id FROM agency.gtfs_stops)
        ) d
GROUP BY 1
ORDER BY 1;

-- how different are avl median locations from gtfs locations?
-- 14,800 are more than  25m apart
--  1,633 are more than  50m apart
--    461 are more than 100m apart
--     89 are more than 250m apart
--     22 are more than 500m apart
SELECT  count(*)
  FROM  agency.avl_median_location m
  JOIN  agency.agencies a ON a.orca_agency_id = m.agency_id
  JOIN  agency.gtfs_stops g
         ON g.gtfs_agency_id = a.gtfs_agency_id
        AND g.agency_stop_id = m.stop_id
 WHERE  NOT ST_DWithin(ST_Transform(m.avl_stop_location, 32610), ST_Transform(g.stop_location, 32610), 25);

-- table of stop proximity
-- NOTE: used to be just for avl median points; now use all stop locations!
CREATE TABLE agency.stop_proximity (
    agency_id smallint NOT NULL
    ,stop_id text NOT NULL
    ,start_dtm timestamp without time zone NOT NULL
    ,end_dtm timestamp without time zone NOT NULL
    ,adjacent_agency_id smallint NOT NULL
    ,adjacent_stop_id text NOT NULL
    ,dist_meters real
    ,PRIMARY KEY (agency_id, stop_id, start_dtm, end_dtm, adjacent_agency_id, adjacent_stop_id)
);

-- add indices
CREATE INDEX ON agency.stop_proximity (agency_id);
CREATE INDEX ON agency.stop_proximity (stop_id);
CREATE INDEX ON agency.stop_proximity (adjacent_agency_id);
CREATE INDEX ON agency.stop_proximity (adjacent_stop_id);
CREATE INDEX ON agency.stop_proximity (dist_meters);
CREATE INDEX ON agency.stop_proximity (start_dtm, end_dtm);

-- test OVERLAPS: https://www.postgresql.org/docs/12/functions-datetime.html; https://stackoverflow.com/a/10171439
-- 2022-10-29: 31 scheudles, 171 with overlaps
SELECT  *
        ,greatest(b.start_dtm, n.start_dtm) AS begin_overlap
        ,least(b.end_dtm, n.end_dtm) AS end_overlap
        ,least(b.end_dtm, n.end_dtm) - greatest(b.start_dtm, n.start_dtm) AS overlap
--SELECT  count(*)
  FROM  agency.bus_schedules b
  JOIN  agency.bus_schedules n
         ON (b.start_dtm, b.end_dtm) OVERLAPS (n.start_dtm, n.end_dtm);

-- for now use 1/3 mile distance for all stops since this is for transfers
-- consider whether larger distance should be used for rail?
-- NOTE: 1/3 mile is 536.448 meters; use 537
--       join with overlapping time frame but ensure different stop location (avoid self-join)
--       use unique stop locations to avoid duplicates with AVL and offboard readers
INSERT INTO agency.stop_proximity
SELECT  a.agency_id
        ,a.stop_id
        ,greatest(a.start_dtm, b.start_dtm) AS start_dtm
        ,least(a.end_dtm, b.end_dtm) AS end_dtm
        ,b.agency_id AS adjacent_agency_id
        ,b.stop_id AS adjacent_stop_id
        ,ST_Distance(ST_Transform(a.stop_location, 32610), ST_Transform(b.stop_location, 32610)) AS dist_meters
  FROM  agency.v_uniq_stop_locations a
  JOIN  agency.v_uniq_stop_locations b
         ON (a.agency_id <> b.agency_id OR a.stop_id <> b.stop_id)
        AND (a.start_dtm, a.end_dtm) OVERLAPS (b.start_dtm, b.end_dtm)
        AND ST_DWithin(ST_Transform(a.stop_location, 32610), ST_Transform(b.stop_location, 32610), 537);

-- import stops from previous effort
-- TODO: use subset of gtfs or unified stops in the future, pulling from previous orca work:
--       agency.[gtfs_stops, trac_st_stops, unified_stops], etc
--       lines ~1000 - 1900 in orca_analysis.sql
\c orca;
\copy (SELECT * FROM orca2020.brt_stops) TO 'dl/orca_brt_stops.csv' WITH (FORMAT CSV, HEADER);

-- now connect to orca_pod and import csns
\c orca_pod;
CREATE TABLE devices.brt_stops (
    agency_id smallint
    ,mode_id integer
    ,mode_abbrev text
    ,direction_id integer
    ,route_number text
    ,device_place_name text
    ,device_place_id text
    ,device_location_descr text
    ,origin_location_id numeric
    ,count integer
    ,stop_id integer
    ,stop_id_2 integer
    ,stop_lat numeric
    ,stop_lon numeric
    ,stop_location geometry(Point,4326)
);

-- indices
CREATE INDEX ON devices.brt_stops (origin_location_id);
CREATE INDEX ON devices.brt_stops (agency_id);
CREATE INDEX ON devices.brt_stops (stop_id);

\copy devices.brt_stops FROM 'dl/orca_brt_stops.csv' WITH (FORMAT CSV, HEADER);

-- look at duplicates in brt stops
\copy (
SELECT * FROM devices.brt_stops 
 WHERE origin_location_id IN (SELECT origin_location_id FROM devices.brt_stops GROUP BY 1 HAVING count(*) > 1)
ORDER BY origin_location_id, count
) TO '~/dl/brt_stop_fixes.csv' WITH ( FORMAT CSV, HEADER);

----- clean up duplicates in brt_stops
CREATE TABLE devices.bad_brt_stops (LIKE devices.brt_stops);

-- move bad records to bad_brt_stops
-- then delete records from brt_stops
BEGIN;

INSERT INTO devices.bad_brt_stops
SELECT  * FROM devices.brt_stops
-- DELETE FROM devices.brt_stops
 WHERE  (origin_location_id = '150994946' AND device_place_id = 'SOTKSS')
    OR  (origin_location_id = '4194312133' AND device_place_id = 'KCMO11')
    OR  (origin_location_id = '4194312161' AND device_place_id IS NULL)
    OR  (origin_location_id = '4194312175' AND stop_id = '400')
    OR  (origin_location_id = '4194312175' AND stop_id = '1690')
    OR  (origin_location_id = '4194312177' AND device_place_id = 'KCMS03')
    OR  (origin_location_id = '4194312178' AND stop_id = '60760')
    OR  (origin_location_id = '4194312191' AND stop_id = '60922')
    OR  (origin_location_id = '4194312228' AND device_place_id = 'KCME15')
    OR  (origin_location_id = '4194312234' AND device_place_id IS NULL)
    OR  (origin_location_id = '4194317163' AND device_place_id IS NULL)
    OR  (origin_location_id = '4194317186' AND device_place_id = 'COTEVT2')
    OR  (origin_location_id = '4194317188' AND stop_id = '2810')
    OR  (origin_location_id = '4194317308' AND stop_id = '14200')
    OR  (origin_location_id = '4194317327' AND stop_id = '3039')
    OR  (origin_location_id = '4211091567' AND device_place_id = 'SOTCAP')
    OR  (origin_location_id = '4211094418' AND device_place_id = 'KCMC27');

COMMIT;

-- TODO: fix stops from de-duping brt_stops table?
-- TODO: for off-board taps, should we allow any boarding within 250-500ft?
SELECT  count(*)
  FROM  orca.brt_route_od
 WHERE  txn_id IN (SELECT txn_id FROM orca.brt_next_boarding WHERE stop_ids @> array['400','605','1690'])
   AND  stop_id IN ('400', '1690');

-- TODO: other issues:
-- stop_id 14200 is Leary/15th, but linked to wrong device place name & id (16th St SE, COTG09)
-- some stops (8) are associated with multiple origin location ids:
-- SELECT stop_id, count(*) FROM devices.brt_stops GROUP BY 1 HAVING count(*) > 1;
SELECT  b.agency_id, b.direction_id, b.device_place_name, b.device_location_descr, b.origin_location_id, b.stop_id, s.stop_name
  FROM  devices.brt_stops b
  JOIN  agency.agencies a ON a.orca_agency_id = b.agency_id
  JOIN  agency.gtfs_stops s ON s.agency_stop_id = b.stop_id::text AND s.gtfs_agency_id = a.gtfs_agency_id AND s.effective_date < '2021-01-01'
 WHERE  b.stop_id IN (SELECT stop_id FROM devices.brt_stops GROUP BY 1 HAVING count(*) > 1)
ORDER BY b.stop_id, b.count;

-- create table for avl processing and to create boardings with stops view
-- TODO: remove this once new process writes directly to board_locations table
CREATE TABLE orca.boardings_avl (
    txn_id integer NOT NULL PRIMARY KEY
    ,vehicle_id text
    ,route_id text
    ,trip_id text
    ,orca_agency_id smallint    -- orca agency_id
    ,stop_id text               -- agency stop id
    --,gtfs_stop_id integer       -- unique gtfs stop id for stop location
    ,arrival_dtm_pacific timestamp
    --,stop_location geometry(Point,4326)
    ,direction text
    ,time_diff integer
    ,avl_error integer
    ,last_processed timestamp
);  --PARTITION BY RANGE (arrival_dtm_pacific);

-- create indices
CREATE INDEX ON orca.boardings_avl (arrival_dtm_pacific);
--CREATE INDEX ON orca.boardings_avl (txn_id);
--CREATE INDEX ON orca.boardings_avl (vehicle_id);
--CREATE INDEX ON orca.boardings_avl (route_id);
--CREATE INDEX ON orca.boardings_avl (trip_id);
--CREATE INDEX ON orca.boardings_avl (stop_id);
--CREATE INDEX ON orca.boardings_avl (gtfs_stop_id);

---------- OD Processing ----------
-- start by getting destination stop for each boarding
-- TODO: create station meta-stops (collections of stops for stations)
--       also should really try to stop using devices.brt_stops in favor of gtfs stops if possible!

-- NOTE: apparently the AVL data has many duplicates (or issues where it can't discern between runs), 
--       so it's good we're using a lateral join to avoid duplicates
--       the trips do have different trip_ids, but we never know these for matching correct trip

-- do multiple routes stop at same stop at same time? yes
SELECT stop_id, arrival_dtm_pacific, count(*) FROM agency.avl_kcm_2019h1 GROUP BY 1,2 HAVING count(*) > 1;

-- do same routes stop at same stop at same time? yes
SELECT route_id, stop_id, arrival_dtm_pacific, count(*) FROM agency.avl_kcm_2019h1 GROUP BY 1,2,3 HAVING count(*) > 1;

-- do same routes stop at same stop at same time? yes
SELECT route_id, stop_id, arrival_dtm_pacific, count(*) FROM agency.avl_kcm_2019h1 GROUP BY 1,2,3 HAVING count(*) > 1;

-- do same vehicles with same route stop at same stop at same time? yes
SELECT vehicle_id, route_id, stop_id, arrival_dtm_pacific, count(*) FROM agency.avl_kcm_2019h1 GROUP BY 1,2,3,4 HAVING count(*) > 1;

-- do same vehicles with same trip_id and route stop at same stop at same time? 2 instances, point_role and sch_stop_sec differ, otherwise are pure duplicates
SELECT vehicle_id, trip_id, route_id, stop_id, arrival_dtm_pacific, count(*) FROM agency.avl_kcm_2019h1 GROUP BY 1,2,3,4,5 HAVING count(*) > 1; -- 2 instances
SELECT vehicle_id, trip_id, stop_id, arrival_dtm_pacific, count(*) FROM agency.avl_kcm_2019h1 GROUP BY 1,2,3,4 HAVING count(*) > 1;             -- 2 instances
SELECT trip_id, stop_id, arrival_dtm_pacific, count(*) FROM agency.avl_kcm_2019h1 GROUP BY 1,2,3 HAVING count(*) > 1;                           -- 13 instances, more differences

/********** UNIFIED TABLES FOR LOCATION DATA **********/
-- location sources
CREATE TABLE orca.location_sources (
    location_source_id smallint PRIMARY KEY
    ,short_code text NOT NULL
    ,description text NOT NULL
);

INSERT INTO orca.location_sources VALUES
(1,'avl','Automated Vehicle Location (AVL) data (including Swiftly)'),
(2,'ob_orig','Off-Board ORCA reader based on origin_location_id'),
(3,'ob_dest','Off-Board ORCA reader based on destination_location_id'),
(4,'prox_stop','Stop selected along route based on proximity to next boarding location'),
(5,'prox_route','Route and stop selected based on boarding wait time and proximity to next boarding location');

-- merge boardings_avl (bus data) and board_alight_st (rail data), plus add brt boardings
-- TODO: convert to gtfs_stop_id so agency_id can be dropped?
--       also requires handling AVL stops not in gtfs
CREATE TABLE orca.board_locations (
    txn_id bigint PRIMARY KEY
    ,agency_id smallint NOT NULL
    ,stop_id text NOT NULL
    ,route_id text NOT NULL
    ,mode_id smallint NOT NULL
    ,avl_vehicle_id text                                    -- avl vehicle id
    ,avl_trip_id text                                       -- avl trip id
    ,avl_direction text                                     -- avl direction
    ,avl_arrival_dtm_pacific timestamp without time zone    -- avl arrival time of bus at boarding location
    ,avl_error smallint                                     -- avl error from Dmitri's processing
    ,location_source_id smallint
    ,updated_at timestamp with time zone NOT NULL DEFAULT util.now_utc()
) PARTITION BY RANGE (txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.board_locations (agency_id, stop_id);

-- create child partitions
CREATE TABLE orca.board_locations_100m PARTITION OF orca.board_locations FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.board_locations_200m PARTITION OF orca.board_locations FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.board_locations_300m PARTITION OF orca.board_locations FOR VALUES FROM (200000000) TO (300000000);

-- merge alightings_avl (bus data) and board_alight_st (rail data)
-- TODO: in future version, consider using gtfs or some unified stop id?
--       also, allow nxt_boarding_stop to be NULL for rail tapoffs with no next boarding yet?
CREATE TABLE orca.alight_locations (
    txn_id bigint PRIMARY KEY
    ,agency_id smallint NOT NULL
    ,stop_id text NOT NULL
    ,exit_dtm_pacific timestamp without time zone       -- tapoff time or time of AVL bus arrival/departure, if available
    ,interline_route_id text DEFAULT NULL               -- interline route id when alighting route differs from boarding route
    ,tapoff_txn_id bigint                               -- if there is an orca tap off txn
    ,nxt_stop_dist_m real                               -- store in table since joins to computer are slow
    ,location_source_id smallint
    ,updated_at timestamp with time zone NOT NULL DEFAULT util.now_utc()
) PARTITION BY RANGE (txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.alight_locations (agency_id, stop_id);
CREATE INDEX ON orca.alight_locations (exit_dtm_pacific);

-- create child partitions
CREATE TABLE orca.alight_locations_100m PARTITION OF orca.alight_locations FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.alight_locations_200m PARTITION OF orca.alight_locations FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.alight_locations_300m PARTITION OF orca.alight_locations FOR VALUES FROM (200000000) TO (300000000);

-- create new boarding view that coalesces corrected info from boarding and alighting locations
CREATE OR REPLACE VIEW orca.v_boardings_with_locations AS
--CREATE MATERIALIZED VIEW orca.m_boardings_with_locations AS
SELECT  b.*
        ,bl.stop_id AS board_stop_id
        ,coalesce(bl.route_id, b.route_number) AS route_id
        ,coalesce(bl.mode_id, b.reader_mode_id) AS mode_id
        ,bl.avl_vehicle_id
        ,bl.avl_trip_id
        ,bl.avl_direction
        ,bl.avl_arrival_dtm_pacific
        ,bl.avl_error
        ,bl.location_source_id AS board_location_source_id
        ,al.stop_id AS alight_stop_id
        ,al.exit_dtm_pacific
        ,al.tapoff_txn_id
        ,al.nxt_stop_dist_m
        ,al.location_source_id AS alight_location_source_id
  FROM  orca.boardings b
  LEFT  JOIN orca.board_locations bl ON bl.txn_id = b.txn_id    -- boarding location info
  LEFT  JOIN orca.alight_locations al ON al.txn_id = b.txn_id;  -- alighting location info

----- temp code to copy result of Dmitri's boardings_avl table to board_locations table
-- from boardings_avl (including mode_id fix for on-board brt taps)
-- 2022-09-16: 114,788,856 records
-- 2022-10-24:  11,309,605 records (434,740 corrected mode_id)
INSERT INTO orca.board_locations
SELECT  a.txn_id
        ,a.orca_agency_id AS agency_id
        ,a.stop_id
        ,a.route_id
        ,CASE WHEN (orca_agency_id = 4 AND route_id LIKE '67_') THEN 250    -- kcm rapid ride route numbers run from 671-676
              WHEN (orca_agency_id = 2 AND route_id LIKE '70_') THEN 250    -- ct swift route numbers run from 701-702
              ELSE 128 END AS mode_id
        ,a.vehicle_id AS avl_vehicle_id
        ,a.trip_id AS avl_trip_id
        ,a.direction AS avl_direction
        ,a.arrival_dtm_pacific AS avl_arrival_dtm_pacific
        ,a.avl_error::smallint AS avl_error
        ,1 AS location_source_id
        ,a.last_processed AS updated_at
  FROM  orca.boardings_avl a;

-- now insert off-board post reads (modes 9,249,250,251)
-- 2022-09-16: 37,286,837 records
-- 2022-10-24:  6,628,476 records (out of 7,022703 possible)
-- NOTE: inner join with brt_stops eliminates NULL origin location ids
-- TODO: fill in AVL information if available from figuring out which bus was boarded
INSERT INTO orca.board_locations
SELECT  b.txn_id
        ,b.source_agency_id AS agency_id
        ,s.stop_id
        ,m.mode_abbrev AS route_id      -- fill in with correct route later
        ,b.reader_mode_id AS mode_id    -- update trips that were not BRT later
        ,NULL AS avl_vehicle_id
        ,NULL AS avl_trip_id
        ,NULL AS avl_direction
        ,NULL AS avl_arrival_dtm_pacific
        ,NULL AS avl_error
        ,2 AS location_source_id
        ,util.now_utc() AS updated_at
  FROM  orca.boardings b
  JOIN  orca.modes m ON m.mode_id = b.reader_mode_id
  JOIN  devices.brt_stops s ON s.origin_location_id = b.origin_location_id
 WHERE  b.reader_mode_id IN (9,249,250,251)   -- offboard tap modes
   AND  b.txn_id > 219889619    -- previous limit for txn import
;

SELECT count(*) FROM orca.boardings WHERE reader_mode_id IN (9, 249, 250, 251) AND txn_id > 219889619;
-- 6,628,476
SELECT  count(*)
  FROM  orca.boardings b 
  JOIN  devices.brt_stops s ON s.origin_location_id = b.origin_location_id
 WHERE  b.reader_mode_id IN (9, 249, 250, 251)
   AND b.txn_id > 219889619;

/*########## WRITE ALIGHT LOCATIONS ##########*/
-- procedure to get boarding stop and distance to next boarding
-- 1. get boarding location info and next stop location
-- 2. get potential stops:
--    128: from AVL along current route
--    250: from AVL for all possible routes
--    9, 251: if tapoff: use destination_location_id; else off-board stops for that mode
-- 3. get min dist stop
--    for BRT, update route, mode, AVL info in boarding location record

-- TODO: adjust to new process when we have tap coordinates
-- TODO: consider minimizing wait time at stop too, since 1/3 mile is not very far...
-- TODO: look into consolidating proximity work in future clean-up (by saving potential stops to table)
--       also add argument to handle ON CONFLICT behavior
CREATE OR REPLACE PROCEDURE util.write_alight_txn(_txn_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    _brt_wait interval;
    _run_time interval;
    _drift interval;
    _b record;  -- boarding location record
    _n record;  -- next boarding location record
    -- alight location fields:
    _stp_id text;
    _xt_dtm timestamp without time zone;
    _tapoff bigint;
    _il_rte text;
    _dist_m real;
    _lc_src smallint;
    -- board_location update fields:
    _veh_id text;
    _trp_id text;
    _dir_id text;
    _bd_dtm timestamp without time zone;
    _rte_id text;
BEGIN
    -- TODO: consider making these parameters; if so, pass as arguments to this procedure
    -- set reasonable wait time for BRT bus; 30 minutes for now
    _brt_wait := '30 minutes';
    -- set reasonable time for route (bus, rail) run time; 90 minutes for now
    _run_time := '90 minutes';
    -- set reasonable time for clock drift; 3 minutes for now
    _drift := '3 minutes';
    -- get boarding and location info
    SELECT  b.*
            ,g.txn_id AS nxt_txn_id
      INTO  _b
      FROM  orca.v_board_locations b
      JOIN  orca.boarding_groups g ON g.prev_txn_id = b.txn_id
     WHERE  b.txn_id = _txn_id;
    -- get next boarding stop time and location
    SELECT  n.*
      INTO  _n
      FROM  orca.v_board_locations n
     WHERE  n.txn_id = _b.nxt_txn_id;
    -- approach to getting potential stops varies by reader_mode_id
    IF _b.reader_mode_id IN (9, 251) THEN    -- sounder (9) AND light rail (251)
        -- get first tap-off (if it exists) along with stop location for same card for sounder, light rail
        -- NOTE: directly calculate distance instead of looking in prox table
        -- TODO: in future, may need to identify route based on board and alight stops (when there are multiple lines)
        SELECT  bs.stop_id
                ,t.txn_dtm_pacific AS exit_dtm_pacific
                ,NULL AS interline_route_id
                ,t.txn_id AS tapoff_txn_id
                ,ST_Distance(ST_Transform(bs.stop_location, 32610), ST_Transform(_n.stop_location, 32610)) AS nxt_stop_dist_m
                ,3 AS location_source_id        -- location source: ob_dest
          INTO  _stp_id, _xt_dtm, _il_rte, _tapoff, _dist_m, _lc_src
          FROM  orca.transactions t
          JOIN  orca.transaction_types tt ON tt.txn_type_id = t.txn_type_id
          JOIN  devices.brt_stops bs ON bs.origin_location_id::bigint = t.destination_location_id
         WHERE  t.csn_hash = _b.csn_hash  -- match csn
           AND  tt.is_exit                -- is an exit transaction
           AND  t.txn_dtm_pacific BETWEEN _b.txn_dtm_pacific AND least(_b.txn_dtm_pacific + _run_time, _n.txn_dtm_pacific)
        ORDER BY t.txn_dtm_pacific LIMIT 1;
        -- reset record _t: https://stackoverflow.com/a/30831679  _t := row(NULL);
        IF _tapoff IS NULL THEN
            -- no tap-off txn; look for any matching mode stop near next boarding
            SELECT  u.stop_id
                    ,NULL AS exit_dtm_pacific   -- no exit time without tapoff since AVL does not contain rail
                    ,NULL AS interline_route_id
                    ,NULL AS tapoff_txn_id
                    ,p.dist_meters AS nxt_stop_dist_m
                    ,4 AS location_source_id    -- location source: prox_stop
              INTO  _stp_id, _xt_dtm, _il_rte, _tapoff, _dist_m, _lc_src
              FROM  agency.v_uniq_stop_locations u
              JOIN  agency.stop_proximity p
                      ON p.agency_id = u.agency_id      -- operated by same agency
                     AND p.stop_id = u.stop_id          -- use avl stop to search for adjacent stops
                     AND (p.start_dtm, p.end_dtm) OVERLAPS (u.start_dtm, u.end_dtm)    -- time period overlap
                     AND p.dist_meters < 536.448        -- within 1/3 mile
                     AND p.adjacent_agency_id = _n.agency_id    -- adjacent agency should match next boarding agency
                     AND p.adjacent_stop_id = _n.stop_id        -- adjacent stop should match next boarding stop
              WHERE u.agency_id = _b.agency_id          -- ensure same agency
                AND u.restrict_mode_id = _b.mode_id     -- for offboard, ensure same mode
            ORDER BY p.dist_meters          -- then sort by minimizing transfer distance
            LIMIT 1;
        END IF;
    ELSIF _b.reader_mode_id = 250 THEN
        -- brt boarding - get all potential routes between boarding and next boarding
        -- use v_avl_trips - run time ~3 sec instead of 3-5 min!
        WITH _stops AS (
            SELECT  a.*
              FROM  agency.v_avl_trips a
             WHERE  a.agency_id = _b.agency_id
               AND  a.board_stop_id = _b.stop_id        -- get avl trips starting at initial boarding stop
               AND  a.board_dtm_pacific BETWEEN _b.txn_dtm_pacific AND _b.txn_dtm_pacific + _brt_wait   -- no need to restrict on next boarding since alight_dtm handles this
               AND  a.alight_dtm_pacific < _n.board_time + _drift       -- must alight before next boarding
        )
        SELECT  a.alight_stop_id AS stop_id
                ,a.alight_dtm_pacific AS exit_dtm_pacific
                ,CASE WHEN a.alight_route_id <> a.board_route_id THEN a.alight_route_id -- set route if differs from boarding
                      ELSE NULL END AS interline_route_id
                ,NULL AS tapoff_txn_id
                ,p.dist_meters AS nxt_stop_dist_m
                ,5 AS location_source_id        -- location source: prox_route
                ,a.vehicle_id  -- additional info in record for updating the boarding location
                ,a.board_trip_id
                ,a.board_direction
                ,a.board_dtm_pacific
                ,a.board_route_id
          INTO  _stp_id, _xt_dtm, _il_rte, _tapoff, _dist_m, _lc_src, _veh_id, _trp_id, _dir_id, _bd_dtm, _rte_id
          FROM  agency.stop_proximity p
          JOIN  _stops a
                 ON a.agency_id = p.agency_id           -- operated by same agency
                AND a.alight_stop_id = p.stop_id        -- use avl stop to search for adjacent stops
                AND a.alight_dtm_pacific BETWEEN p.start_dtm AND p.end_dtm      -- within current shakeup overlap
         WHERE  p.dist_meters < 536.448                 -- within 1/3 mile
           AND  p.adjacent_agency_id = _n.agency_id     -- adjacent agency should match next boarding agency
           AND  p.adjacent_stop_id = _n.stop_id         -- adjacent stop should match next boarding stop
        ORDER BY a.board_dtm_pacific    -- sort by first avl trip at original boarding location
                ,p.dist_meters          -- then sort by minimizing transfer distance
        LIMIT 1;
        -- update boarding record with avl info and correct mode/route_id
        IF _stp_id IS DISTINCT FROM NULL THEN   -- use stop_id for determining avl record since vehicle_id can be blank
            UPDATE  orca.board_locations
               SET  route_id = _rte_id
                    ,mode_id = orca.get_brt_or_bus_mode_id(_b.agency_id, _rte_id)
                    ,avl_vehicle_id = _veh_id
                    ,avl_trip_id = _trp_id
                    ,avl_direction = _dir_id
                    ,avl_arrival_dtm_pacific = _bd_dtm
                    ,updated_at = util.now_utc()
             WHERE  txn_id = _b.txn_id;
        END IF;
    ELSE  -- for all others, use standard avl approach (bus, on-board brt taps)
        WITH _stops AS (
            SELECT  a.agency_id
                    ,a.stop_id
                    ,a.route_id
                    ,a.arrival_dtm_pacific AS exit_dtm_pacific
              FROM  agency.avl a
             WHERE  a.agency_id = _b.agency_id
               AND  a.vehicle_id = _b.avl_vehicle_id
               AND  a.direction = _b.avl_direction
               AND  a.arrival_dtm_pacific BETWEEN _b.avl_arrival_dtm_pacific AND least(_b.avl_arrival_dtm_pacific + _run_time, _n.board_time + _drift)  -- limit avl time points based on run time and next boarding
        )
        SELECT  a.stop_id
                ,a.exit_dtm_pacific
                ,CASE WHEN a.route_id <> _b.route_id THEN a.route_id  -- set route if differs from boarding
                      ELSE NULL END AS interline_route_id
                ,NULL AS tapoff_txn_id
                ,p.dist_meters AS nxt_stop_dist_m
                ,4 AS location_source_id        -- location source: prox_stop
          INTO  _stp_id, _xt_dtm, _il_rte, _tapoff, _dist_m, _lc_src
          FROM  agency.stop_proximity p
          JOIN  _stops a
                 ON a.agency_id = p.agency_id   -- operated by same agency
                AND a.stop_id = p.stop_id       -- use avl stop to search for adjacent stops
                AND a.exit_dtm_pacific BETWEEN p.start_dtm AND p.end_dtm     -- within current shakeup overlap
         WHERE  p.dist_meters < 536.448      -- within 1/3 mile
           AND  p.adjacent_agency_id = _n.agency_id  -- adjacent agency should match next boarding agency
           AND  p.adjacent_stop_id = _n.stop_id      -- adjacent stop should match next boarding stop
        ORDER BY p.dist_meters      -- then sort by minimizing transfer distance
        LIMIT 1;
    END IF;
    -- insert values into alighting locations, but only if there is a stop_id
    IF _stp_id IS DISTINCT FROM NULL THEN
      INSERT INTO orca.alight_locations VALUES (_b.txn_id, _b.agency_id, _stp_id, _xt_dtm, _il_rte, _tapoff, _dist_m, _lc_src);
      --ON CONFLICT (txn_id) DO NOTHING;
    END IF;
END $$;

-- TODO: add flag for overwriting existing info (and add ON CONFLICT to util.write_alight_txn)
--       if flag is not set, then exclude txns already in orca.alight_locations
--       also need to compute alightings for latest boarding by csn_hash before new data
CREATE OR REPLACE PROCEDURE util.write_alight_locations(_start_txn_id bigint, _end_txn_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    _rec record;
BEGIN
    -- iterate through board_locations (TODO: that are also not in alight_locations?)
    FOR _rec IN
        SELECT  b.txn_id
          FROM  orca.board_locations b
         WHERE  b.txn_id BETWEEN _start_txn_id AND _end_txn_id
         --  AND  b.txn_id NOT IN (SELECT txn_id FROM orca.alight_locations)
    LOOP
        -- call procedure to write location for each txn_id
        CALL util.write_alight_txn(_rec.txn_id);
    END LOOP;
END $$;

/*-- current alight_location summary prior to adding new txns:
SELECT agency_id, count(*) FROM orca.alight_locations_300m GROUP BY 1 ORDER BY 1;

| agency_id   | 100m     | 200m     | 300m     |
|-------------+----------|----------|----------|
| 2           |  3469973 |  2915014 |   425943 |
| 4           | 30555251 | 20229892 |  3244649 |
| 7           | 13315434 | 11640212 |  2395307 |

-- totals:      47340658   34785118    6065899

-- after fixing PT and adding new 220-250m txns:

| agency_id   | 100m     | 200m     | 300m     |
|-------------+----------|----------|----------|
| 2           |  3469973 |  2915014 |  1099895 |
| 4           | 30555251 | 20229892 |  7805346 |
| 6           |  2688231 |  2799988 |  1155739 |
| 7           | 13315434 | 11640212 |  6677911 |

-- totals:      50028889 | 37585106 | 16738891 |
*/

CALL util.write_alight_locations(        0,  100000);
CALL util.write_alight_locations(80016350, 80026350);

-- takes 12-20 hours to run 1 million boarding txns

-- NOTE: not enough time to re-write all
-- for now, write alightings for new txns and all pierce transit boardings
-- in future re-write, can use all alightings with updated_at > 2022-11-01

-- get highest current txn in alight_locations and board_locations: 219889282 > 250676556
SELECT max(txn_id) FROM orca.alight_locations_300m;
SELECT max(txn_id) FROM orca.board_locations_300m;

CALL util.write_alight_locations(219889283, 221000000);
CALL util.write_alight_locations(221000001, 222000000);
CALL util.write_alight_locations(222000001, 223000000);
CALL util.write_alight_locations(223000001, 224000000);
CALL util.write_alight_locations(224000001, 225000000);
CALL util.write_alight_locations(225000001, 226000000);
CALL util.write_alight_locations(226000001, 227000000);
CALL util.write_alight_locations(227000001, 228000000);
CALL util.write_alight_locations(228000001, 229000000);
CALL util.write_alight_locations(229000001, 230000000);
CALL util.write_alight_locations(230000001, 231500000);
CALL util.write_alight_locations(231500001, 233000000);
CALL util.write_alight_locations(233000001, 234500000);
CALL util.write_alight_locations(234500001, 236000000);
CALL util.write_alight_locations(236000001, 237500000);
CALL util.write_alight_locations(237500001, 239000000);
CALL util.write_alight_locations(239000001, 240500000);
CALL util.write_alight_locations(240500001, 242000000);
CALL util.write_alight_locations(242000001, 243500000);
CALL util.write_alight_locations(243500001, 245000000);

CALL util.write_alight_locations(245000001, 245500000);
CALL util.write_alight_locations(245500001, 246000000);
CALL util.write_alight_locations(246000001, 246500000);
CALL util.write_alight_locations(246500001, 247000000);
CALL util.write_alight_locations(247000001, 247500000);
CALL util.write_alight_locations(247500001, 248000000);
CALL util.write_alight_locations(248000001, 248500000);
CALL util.write_alight_locations(248500001, 249000000);
CALL util.write_alight_locations(249000001, 249500000);
CALL util.write_alight_locations(249500001, 250000000);
CALL util.write_alight_locations(250000001, 250700000);

-- re-run just Pierce Transit txns from before
CREATE OR REPLACE PROCEDURE util.write_pt_alight_locations(_start_txn_id bigint, _end_txn_id bigint)
LANGUAGE plpgsql AS $$
DECLARE
    _rec record;
BEGIN
    -- iterate through board_locations (TODO: that are also not in alight_locations?)
    FOR _rec IN
        SELECT  b.txn_id
          FROM  orca.board_locations b
         WHERE  b.txn_id BETWEEN _start_txn_id AND _end_txn_id
           AND  b.agency_id = 6
         --  AND  b.txn_id NOT IN (SELECT txn_id FROM orca.alight_locations)
    LOOP
        -- call procedure to write location for each txn_id
        CALL util.write_alight_txn(_rec.txn_id);
    END LOOP;
END $$;

-- 10.6 million PT records between 0 and 219889282 
-- split into slices of 20 million, 11 threads
CALL util.write_pt_alight_locations(        1,  20000000);
CALL util.write_pt_alight_locations( 20000001,  40000000);
CALL util.write_pt_alight_locations( 40000001,  60000000);
CALL util.write_pt_alight_locations( 60000001,  80000000);
CALL util.write_pt_alight_locations( 80000001, 100000000);
CALL util.write_pt_alight_locations(100000001, 120000000);
CALL util.write_pt_alight_locations(120000001, 140000000);
CALL util.write_pt_alight_locations(140000001, 160000000);
CALL util.write_pt_alight_locations(160000001, 180000000);
CALL util.write_pt_alight_locations(180000001, 200000000);
CALL util.write_pt_alight_locations(200000001, 219889282);

/*########## LOCATION VIEWS AND DATA FIX ##########*/
-- v_board_locations to provide actual stop location and boarding time (using uniq stop view)
-- join on transactions rather than boradings since bl already restricts to boardings
CREATE OR REPLACE VIEW orca.v_board_locations AS
SELECT  bl.*
        ,t.csn_hash
        ,t.txn_dtm_pacific
        ,t.reader_mode_id
        ,least(t.txn_dtm_pacific, bl.avl_arrival_dtm_pacific) AS board_time
        ,s.stop_location
        ,s.source
        ,s.restrict_mode_id
  FROM  orca.board_locations bl
  JOIN  orca.transactions t ON t.txn_id = bl.txn_id
  JOIN  agency.v_uniq_stop_locations s
          ON s.agency_id = bl.agency_id
         AND s.stop_id = bl.stop_id
         AND t.txn_dtm_pacific BETWEEN s.start_dtm AND s.end_dtm;

-- TODO: create similar view for alighting location if needed?

/* should now be incorporated into original write of board and alight locations
-- now correct route_id and mode_id in board_locations:
--   set route_id if possible from alighting record
--   fix 1: onboard BRT taps - if mode_id = 128 but route is actually BRT, change mode_id to 250
--   fix 2: offboard bus taps - if mode_id = 250 but route is not BRT (67X, swift?), change mode_id to 128

-- fix 1: change mode_id to 250 for onboard taps to BRT services
-- use underscore to match a single character
-- 5,797,675 overall: 198 for ct, 5,797,477 for kcm
UPDATE  orca.board_locations
   SET  mode_id = 250
        ,updated_at = util.now_utc()
--SELECT  agency_id, route_id, count(*) AS trip_count
--  FROM  orca.board_locations
 WHERE  (agency_id = 4 AND route_id LIKE '67_')   -- kcm rapid ride route numbers run from 671-676 as of 2022-09-16
    OR  (agency_id = 2 AND route_id LIKE '70_')   -- ct swift route numbers run from 701-702 as of 2022-09-16
--GROUP BY 1,2
--ORDER BY 1,2
;

-- fix 2: set correct route_id and change mode_id to 128 for non-BRT routes
-- brt boardings: 4,605,392, all type 3 alight location_source_id, all have matching agency_ids
-- after fix: only 51,897 remaining (should be possible to fix these too?)
SELECT  b.agency_id, b.stop_id, count(*) AS trip_cnt
-- SELECT  count(*)
  FROM  orca.alight_locations a
  JOIN  orca.board_locations b ON b.txn_id = a.txn_id AND b.agency_id = a.agency_id
 WHERE  b.mode_id = 250
   AND  b.route_id = 'BRT'
GROUP BY 1,2 ORDER BY 3 DESC;

-- TODO: check locations for:
-- 4 73227 likely wrong loc
-- 2 3020  likely wrong loc
-- 4 16103 likely wrong loc
-- 2 93006 wrong loc
-- 4 575   wrong loc

SELECT DISTINCT agency_id, route_id FROM orca.board_locations WHERE route_id LIKE '67_' OR route_id LIKE '70_' ORDER BY 1,2;
*/

-- backup:
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.board_locations_100m --data-only orca_pod > ~/dl/orca_board_locations_100m_20221104.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.board_locations_200m --data-only orca_pod > ~/dl/orca_board_locations_200m_20221104.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.board_locations_300m --data-only orca_pod > ~/dl/orca_board_locations_300m_20221104.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.alight_locations_100m --data-only orca_pod > ~/dl/orca_alight_locations_100m_20221104.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.alight_locations_200m --data-only orca_pod > ~/dl/orca_alight_locations_200m_20221104.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.alight_locations_300m --data-only orca_pod > ~/dl/orca_alight_locations_300m_20221104.sql

-- reimport:
-- psql -U rpavery -h 10.142.198.115 -d orca_pod -f ~/dl/orca_alight_locations_100m_20220917.sql
-- psql -U rpavery -h 10.142.198.115 -d orca_pod -f ~/dl/orca_alight_locations_200m_20220917.sql
-- psql -U rpavery -h 10.142.198.115 -d orca_pod -f ~/dl/orca_alight_locations_300m_20220917.sql

/********** TRIP & TRANSFER TABLES **********/
-- create table of financial transfers broken into trips?
-- also create table or view of origin and destination txn_ids

-- trips represent the initial boarding and final alighting locations for travel-making behavior
-- mostly these represent activity within the two-hour transfer time window;
-- however, some new trips result from using the same route within a trip or starting too far from previous alighting

-- create trip table consising of bare minimum records; use join for the rest
-- are modes needed? keep for now
-- preserve location info for fewer joins
CREATE TABLE orca.trips (
    orig_txn_id bigint PRIMARY KEY NOT NULL
    ,dest_txn_id bigint NOT NULL
    ,transfer_count smallint NOT NULL
    ,routes text[]
    ,modes smallint[]
    ,updated_at timestamp with time zone NOT NULL DEFAULT util.now_utc()
) PARTITION BY RANGE (orig_txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.trips (dest_txn_id);
CREATE INDEX ON orca.trips (updated_at);

-- create child partitions
CREATE TABLE orca.trips_100m PARTITION OF orca.trips FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.trips_200m PARTITION OF orca.trips FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.trips_300m PARTITION OF orca.trips FOR VALUES FROM (200000000) TO (300000000);

-- alternate trip table with locations
CREATE TABLE orca.trip_locations (
    orig_txn_id bigint NOT NULL
    ,orig_source_agency_id smallint
    ,orig_stop_id text
    ,dest_txn_id bigint NOT NULL
    ,dest_source_agency_id smallint
    ,dest_stop_id text
    ,dest_dtm_pacific timestamp without time zone
    ,transfer_count smallint NOT NULL
    ,routes text[]
    ,modes smallint[]
    ,updated_at timestamp with time zone
) PARTITION BY RANGE (orig_txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.trip_locations (dest_txn_id);
CREATE INDEX ON orca.trip_locations (updated_at);
CREATE INDEX ON orca.trip_locations (orig_source_agency_id, orig_stop_id);
CREATE INDEX ON orca.trip_locations (dest_source_agency_id, dest_stop_id);

-- create child partitions
CREATE TABLE orca.trip_locations_100m PARTITION OF orca.trip_locations FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.trip_locations_200m PARTITION OF orca.trip_locations FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.trip_locations_300m PARTITION OF orca.trip_locations FOR VALUES FROM (200000000) TO (300000000);

-- populate trip_locations from trips
-- ~25 min for each full partition
INSERT INTO orca.trip_locations
SELECT  t.orig_txn_id
        ,bl.agency_id AS orig_source_agengy_id
        ,bl.stop_id AS orig_stop_id
        ,t.dest_txn_id
        ,al.agency_id AS dest_source_agency_id
        ,al.stop_id AS dest_stop_id
        ,al.exit_dtm_pacific AS dest_dtm_pacific
        ,t.transfer_count
        ,t.routes
        ,t.modes
        ,t.updated_at
  FROM  orca.trips_100m t
  LEFT  JOIN orca.board_locations bl ON bl.txn_id = t.orig_txn_id
  LEFT  JOIN orca.alight_locations al ON al.txn_id = t.dest_txn_id;

-- create view for more trip details
-- NOTE: this is really slow
-- TODO: get institution, product, and pax_type from summary tables when data is cleaned
--       also look into sum of ceffv_cents as trip cost?
-- test if this is correct; should probably use new boardings_full view instead
-- this is *really* slow - use view below instead
/*CREATE OR REPLACE VIEW orca.v_trips AS
SELECT  t.orig_txn_id
        ,o.source_agency_id AS orig_source_agengy_id
        ,o.service_agency_id AS orig_service_agengy_id
        ,o.board_stop_id AS orig_stop_id
        ,o.txn_dtm_pacific AS orig_dtm_pacific
        ,t.dest_txn_id
        ,d.source_agency_id AS dest_source_agency_id
        ,d.service_agency_id AS dest_service_agency_id
        ,d.alight_stop_id AS dest_stop_id
        ,d.exit_dtm_pacific AS dest_dtm_pacific
        ,t.transfer_count
        ,t.routes
        ,t.modes
        ,o.csn_hash
        ,o.txn_institution_id AS institution_id
        ,o.product_id
        ,o.txn_passenger_type_id AS passenger_type_id
        ,o.passenger_count
        ,o.ceffv_cents
        ,t.updated_at
  FROM  orca.trips t
  JOIN  orca.v_boardings_with_locations o ON o.txn_id = t.orig_txn_id
  JOIN  orca.v_boardings_with_locations d ON d.txn_id = t.dest_txn_id;

-- alternate attempt at trips
CREATE OR REPLACE VIEW orca.v_trips AS
SELECT  t.orig_txn_id
        ,coalesce(t.orig_source_agency_id, b.source_agency_id) AS orig_source_agengy_id
        ,b.service_agency_id AS orig_service_agengy_id
        ,t.orig_stop_id
        ,b.txn_dtm_pacific AS orig_dtm_pacific
        ,t.dest_txn_id
        ,coalesce(t.dest_source_agency_id, a.source_agency_id) AS dest_source_agency_id
        ,a.service_agency_id AS dest_service_agency_id
        ,t.dest_stop_id
        ,t.dest_dtm_pacific
        ,t.transfer_count
        ,t.routes
        ,t.modes
        ,b.csn_hash
        ,b.txn_institution_id AS institution_id
        ,b.product_id
        ,b.txn_passenger_type_id AS passenger_type_id
        ,b.passenger_count
        ,b.ceffv_cents
        ,t.updated_at
  FROM  orca.trip_locations t
  JOIN  orca.boardings b ON b.txn_id = t.orig_txn_id
  JOIN  orca.boardings a ON a.txn_id = t.dest_txn_id
;

-- comparison of original vs location view vs detail table:
SELECT  count(*)
  FROM  orca.v_trips_1    -- orig view
--  FROM  orca.v_trips_2    -- view based on trip_location
--  FROM  orca.trip_detail  -- detail table
 WHERE  date_trunc('month', orig_dtm_pacific) = '2019-05-01'
   AND  institution_id = 1285;

v_trips_1:      529,772 in 699 s
v_trips_2:      529,772 in 410 s
trip_detail:    529,772 in  62 s

*/

-- final trip table with locations and boarding data
CREATE TABLE orca.trip_detail (
    orig_txn_id bigint NOT NULL
    ,orig_source_agency_id smallint
    ,orig_service_agency_id smallint
    ,orig_stop_id text
    ,orig_dtm_pacific timestamp without time zone
    ,dest_txn_id bigint NOT NULL
    ,dest_source_agency_id smallint
    ,dest_service_agency_id smallint
    ,dest_stop_id text
    ,dest_dtm_pacific timestamp without time zone
    ,transfer_count smallint NOT NULL
    ,routes text[]
    ,modes smallint[]
    ,csn_hash text
    ,institution_id smallint
    ,product_id smallint
    ,passenger_type_id smallint
    ,passenger_count smallint
    ,ceffv_cents integer
    ,updated_at timestamp with time zone
) PARTITION BY RANGE (orig_txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.trip_detail (dest_txn_id);
CREATE INDEX ON orca.trip_detail (updated_at);
CREATE INDEX ON orca.trip_detail (orig_source_agency_id, orig_stop_id);
CREATE INDEX ON orca.trip_detail (dest_source_agency_id, dest_stop_id);
CREATE INDEX ON orca.trip_detail (institution_id);
CREATE INDEX ON orca.trip_detail (csn_hash);

-- create child partitions
CREATE TABLE orca.trip_detail_100m PARTITION OF orca.trip_detail FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.trip_detail_200m PARTITION OF orca.trip_detail FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.trip_detail_300m PARTITION OF orca.trip_detail FOR VALUES FROM (200000000) TO (300000000);

-- populate trip detail table
INSERT INTO orca.trip_detail
SELECT  t.orig_txn_id
        ,coalesce(t.orig_source_agency_id, b.source_agency_id) AS orig_source_agengy_id
        ,b.service_agency_id AS orig_service_agengy_id
        ,t.orig_stop_id
        ,b.txn_dtm_pacific AS orig_dtm_pacific
        ,t.dest_txn_id
        ,coalesce(t.dest_source_agency_id, a.source_agency_id) AS dest_source_agency_id
        ,a.service_agency_id AS dest_service_agency_id
        ,t.dest_stop_id
        ,t.dest_dtm_pacific
        ,t.transfer_count
        ,t.routes
        ,t.modes
        ,b.csn_hash
        ,b.txn_institution_id AS institution_id
        ,b.product_id
        ,b.txn_passenger_type_id AS passenger_type_id
        ,b.passenger_count
        ,b.ceffv_cents
        ,t.updated_at
  FROM  orca.trip_locations_100m t
  JOIN  orca.boardings b ON b.txn_id = t.orig_txn_id
  JOIN  orca.boardings a ON a.txn_id = t.dest_txn_id;

-- table of break types for broken trips
CREATE TABLE orca.break_types (
    break_type_id smallint PRIMARY KEY
    ,description text NOT NULL
);

INSERT INTO orca.break_types VALUES
(1, 'immediate previous leg of the journey used the same route'),
(2, 'some previous leg of the journey used the same route'),
(3, 'distance between previous alighting stop and boarding exceeds 1/3 mile');

-- create table of trip breaks linking to previous broken trip (can get full financial transfer from boarding_groups)
CREATE TABLE orca.trip_breaks (
    txn_id bigint PRIMARY KEY NOT NULL
    ,break_type_id smallint NOT NULL
    ,prev_orig_txn_id bigint NOT NULL
    ,updated_at timestamp with time zone NOT NULL DEFAULT util.now_utc()
) PARTITION BY RANGE (txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.trip_breaks (prev_orig_txn_id);

-- create child partitions
CREATE TABLE orca.trip_breaks_100m PARTITION OF orca.trip_breaks FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.trip_breaks_200m PARTITION OF orca.trip_breaks FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.trip_breaks_300m PARTITION OF orca.trip_breaks FOR VALUES FROM (200000000) TO (300000000);

-- transfers represent the alighting from one leg to the boarding of the next leg of a trip
-- use stub table with view later to link more info
-- need this to preserve new origin txn for trip_break trips
CREATE TABLE orca.transfers (
    board_txn_id bigint PRIMARY KEY NOT NULL    -- txn_id of boarding
    ,trip_orig_txn_id bigint NOT NULL           -- txn_id of trip origin boarding
    ,alight_txn_id bigint NOT NULL              -- txn_id of previous alighting
    ,updated_at timestamp with time zone NOT NULL DEFAULT util.now_utc()
) PARTITION BY RANGE (board_txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.transfers (trip_orig_txn_id);
CREATE INDEX ON orca.transfers (alight_txn_id);

-- create child partitions
CREATE TABLE orca.transfers_100m PARTITION OF orca.transfers FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.transfers_200m PARTITION OF orca.transfers FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.transfers_300m PARTITION OF orca.transfers FOR VALUES FROM (200000000) TO (300000000);

-- alternate approach with locations
CREATE TABLE orca.transfer_locations (
    board_txn_id bigint PRIMARY KEY NOT NULL    -- txn_id of boarding
    ,trip_orig_txn_id bigint NOT NULL           -- txn_id of trip origin boarding
    ,alight_txn_id bigint NOT NULL              -- txn_id of previous alighting
    ,alight_agency_id smallint
    ,alight_stop_id text
    ,alight_mode_id smallint
    ,alight_route_id text
    ,alight_dtm_pacific timestamp without time zone
    ,board_agency_id smallint
    ,board_stop_id text
    ,board_mode_id smallint
    ,board_route_id text
    ,xfer_dist_meters real
    ,updated_at timestamp with time zone NOT NULL DEFAULT util.now_utc()
) PARTITION BY RANGE (board_txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.transfer_locations (trip_orig_txn_id);
CREATE INDEX ON orca.transfer_locations (alight_txn_id);
CREATE INDEX ON orca.transfer_locations (alight_agency_id, alight_stop_id);
CREATE INDEX ON orca.transfer_locations (board_agency_id, board_stop_id);
CREATE INDEX ON orca.transfer_locations (alight_mode_id);
CREATE INDEX ON orca.transfer_locations (alight_route_id);
CREATE INDEX ON orca.transfer_locations (alight_dtm_pacific);
CREATE INDEX ON orca.transfer_locations (board_mode_id);
CREATE INDEX ON orca.transfer_locations (board_route_id);

-- create child partitions
CREATE TABLE orca.transfer_locations_100m PARTITION OF orca.transfer_locations FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.transfer_locations_200m PARTITION OF orca.transfer_locations FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.transfer_locations_300m PARTITION OF orca.transfer_locations FOR VALUES FROM (200000000) TO (300000000);

-- populate transfer_locations table
INSERT INTO orca.transfer_locations
SELECT  x.board_txn_id
        ,x.trip_orig_txn_id
        ,x.alight_txn_id
        ,al.agency_id AS alight_agency_id
        ,al.stop_id AS alight_stop_id
        ,abl.mode_id AS alight_mode_id
        ,abl.route_id AS alight_route_id
        ,al.exit_dtm_pacific AS alight_dtm_pacific
        ,bl.agency_id AS board_agency_id
        ,bl.stop_id AS board_stop_id
        ,bl.mode_id AS board_mode_id
        ,bl.route_id AS board_route_id
        ,al.nxt_stop_dist_m AS xfer_dist_meters
        ,x.updated_at
  FROM  orca.transfers_100m x
  LEFT  JOIN orca.board_locations bl ON bl.txn_id = x.board_txn_id      -- current boarding location
  LEFT  JOIN orca.alight_locations al ON al.txn_id = x.alight_txn_id    -- previous alighting location
  LEFT  JOIN orca.board_locations abl ON abl.txn_id = x.alight_txn_id;  -- previous boarding location

-- view for expanded transfer information
-- again, slow as heck, use table below instead
/*CREATE OR REPLACE VIEW orca.v_transfers AS
SELECT  x.board_txn_id
        ,x.trip_orig_txn_id
        ,x.alight_txn_id
        ,a.source_agency_id AS from_source_agency_id
        ,a.service_agency_id AS from_service_agency_id
        ,a.alight_stop_id
        ,a.mode_id AS from_mode_id
        ,a.route_id AS from_route_id
        ,a.exit_dtm_pacific AS alight_dtm_pacific
        ,b.source_agency_id AS to_source_agency_id
        ,b.service_agency_id AS to_service_agency_id
        ,b.board_stop_id
        ,b.mode_id AS to_mode_id
        ,b.route_id AS to_route_id
        ,b.txn_dtm_pacific AS board_dtm_pacific
        ,a.nxt_stop_dist_m AS xfer_dist_meters
        ,CASE WHEN a.exit_dtm_pacific IS NOT NULL THEN (b.txn_dtm_pacific - a.exit_dtm_pacific) ELSE NULL END AS xfer_duration
        ,b.csn_hash
        ,b.txn_institution_id AS institution_id
        ,b.product_id
        ,b.txn_passenger_type_id AS passenger_type_id
        ,b.passenger_count
        ,b.ceffv_cents
        ,x.updated_at
  FROM  orca.transfers x
  JOIN  orca.v_boardings_with_locations b ON b.txn_id = x.board_txn_id      -- current boarding
  JOIN  orca.v_boardings_with_locations a ON a.txn_id = x.alight_txn_id;    -- previous alighting

CREATE OR REPLACE VIEW orca.v_transfers AS
SELECT  x.board_txn_id
        ,x.trip_orig_txn_id
        ,x.alight_txn_id
        ,coalesce(x.alight_agency_id, a.source_agency_id) AS from_source_agency_id
        ,a.service_agency_id AS from_service_agency_id
        ,x.alight_stop_id
        ,coalesce(x.alight_mode_id, a.reader_mode_id) AS from_mode_id
        ,coalesce(x.alight_route_id, a.route_number) AS from_route_id
        ,x.alight_dtm_pacific
        ,coalesce(x.board_agency_id, b.source_agency_id) AS to_source_agency_id
        ,b.service_agency_id AS to_service_agency_id
        ,x.board_stop_id
        ,coalesce(x.board_mode_id, b.reader_mode_id) AS to_mode_id
        ,coalesce(x.board_route_id, b.route_number) AS to_route_id
        ,b.txn_dtm_pacific AS board_dtm_pacific
        ,x.xfer_dist_meters
        ,CASE WHEN x.alight_dtm_pacific IS NULL THEN NULL ELSE (b.txn_dtm_pacific - x.alight_dtm_pacific) END AS xfer_duration
        ,b.csn_hash
        ,b.txn_institution_id AS institution_id
        ,b.product_id
        ,b.txn_passenger_type_id AS passenger_type_id
        ,b.passenger_count
        ,b.ceffv_cents
        ,x.updated_at
  FROM  orca.transfer_locations x
  JOIN  orca.boardings b ON b.txn_id = x.board_txn_id   -- current boarding
  JOIN  orca.boardings a ON a.txn_id = x.alight_txn_id; -- previous alighting
*/

CREATE TABLE orca.transfer_detail (
    board_txn_id bigint PRIMARY KEY NOT NULL    -- txn_id of boarding
    ,trip_orig_txn_id bigint NOT NULL           -- txn_id of trip origin boarding
    ,alight_txn_id bigint NOT NULL              -- txn_id of previous alighting
    ,from_source_agency_id smallint
    ,from_service_agency_id smallint
    ,alight_stop_id text
    ,from_mode_id smallint
    ,from_route_id text
    ,alight_dtm_pacific timestamp without time zone
    ,to_source_agency_id smallint
    ,to_service_agency_id smallint
    ,board_stop_id text
    ,to_mode_id smallint
    ,to_route_id text
    ,board_dtm_pacific timestamp without time zone
    ,xfer_dist_meters real
    ,xfer_duration interval
    ,csn_hash text
    ,institution_id smallint
    ,product_id smallint
    ,passenger_type_id smallint
    ,passenger_count smallint
    ,ceffv_cents integer
    ,updated_at timestamp with time zone NOT NULL DEFAULT util.now_utc()
) PARTITION BY RANGE (board_txn_id);

-- create indices (pk index already exists)
CREATE INDEX ON orca.transfer_detail (trip_orig_txn_id);
CREATE INDEX ON orca.transfer_detail (alight_txn_id);
CREATE INDEX ON orca.transfer_detail (from_source_agency_id, alight_stop_id);
CREATE INDEX ON orca.transfer_detail (to_source_agency_id, board_stop_id);
CREATE INDEX ON orca.transfer_detail (from_mode_id);
CREATE INDEX ON orca.transfer_detail (from_route_id);
CREATE INDEX ON orca.transfer_detail (alight_dtm_pacific);
CREATE INDEX ON orca.transfer_detail (to_mode_id);
CREATE INDEX ON orca.transfer_detail (to_route_id);
CREATE INDEX ON orca.transfer_detail (board_dtm_pacific);
CREATE INDEX ON orca.transfer_detail (institution_id);
CREATE INDEX ON orca.transfer_detail (csn_hash);

-- create child partitions
CREATE TABLE orca.transfer_detail_100m PARTITION OF orca.transfer_detail FOR VALUES FROM (0) TO (100000000);
CREATE TABLE orca.transfer_detail_200m PARTITION OF orca.transfer_detail FOR VALUES FROM (100000000) TO (200000000);
CREATE TABLE orca.transfer_detail_300m PARTITION OF orca.transfer_detail FOR VALUES FROM (200000000) TO (300000000);

-- populate transfer_detail table
INSERT INTO orca.transfer_detail
SELECT  x.board_txn_id
        ,x.trip_orig_txn_id
        ,x.alight_txn_id
        ,coalesce(x.alight_agency_id, a.source_agency_id) AS from_source_agency_id
        ,a.service_agency_id AS from_service_agency_id
        ,x.alight_stop_id
        ,coalesce(x.alight_mode_id, a.reader_mode_id) AS from_mode_id
        ,coalesce(x.alight_route_id, a.route_number) AS from_route_id
        ,x.alight_dtm_pacific
        ,coalesce(x.board_agency_id, b.source_agency_id) AS to_source_agency_id
        ,b.service_agency_id AS to_service_agency_id
        ,x.board_stop_id
        ,coalesce(x.board_mode_id, b.reader_mode_id) AS to_mode_id
        ,coalesce(x.board_route_id, b.route_number) AS to_route_id
        ,b.txn_dtm_pacific AS board_dtm_pacific
        ,x.xfer_dist_meters
        ,CASE WHEN x.alight_dtm_pacific IS NULL THEN NULL ELSE (b.txn_dtm_pacific - x.alight_dtm_pacific) END AS xfer_duration
        ,b.csn_hash
        ,b.txn_institution_id AS institution_id
        ,b.product_id
        ,b.txn_passenger_type_id AS passenger_type_id
        ,b.passenger_count
        ,b.ceffv_cents
        ,x.updated_at
  FROM  orca.transfer_locations_100m x
  JOIN  orca.boardings b ON b.txn_id = x.board_txn_id   -- current boarding
  JOIN  orca.boardings a ON a.txn_id = x.alight_txn_id; -- previous alighting

/*
trip and transfer testing
-- search for csns to test on
SELECT  bg.csn_hash, bg.txn_id, al.nxt_stop_dist_m
  FROM  orca.boardings_with_groups bg
  JOIN  orca.alight_locations al ON al.txn_id = bg.prev_txn_id
 WHERE  bg.is_transfer
   AND  al.nxt_stop_dist_m > 537
   AND  csn_hash = '18db433b7841ddbb7ea8c25a33153492357cc927d4a3d4882c7ff1de8c8afb12';
LIMIT 10;

SELECT  bg.grp_first_txn_id, bg.route_number, count(*)
  FROM  orca.boardings_with_groups bg
--  JOIN  orca.board_locations b ON b.txn_id = bg.grp_first_txn_id
 WHERE  bg.is_transfer
   AND  bg.route_number IS NOT NULL
GROUP BY 1,2
HAVING count(*) > 1
LIMIT 10;

SELECT * FROM orca.boarding_groups
WHERE grp_first_txn_id = (SELECT grp_first_txn_id FROM orca.boarding_groups WHERE txn_id = 1759562);

type 1, 4402ac7c70d13bfb88891a276c9a0e57a41ce647b1fd0b482fcd28fce9bfa015, 34 recs
type 1, 591c81dc1ad54e02b6c10db75f59026650bbd9cbe473095b4d41120c8b414a45, 301 recs
type 2, bc2a9ee70b31c902fdfbcd7b828a3760834ec75db8b053cc925d273bd07870b6, 1017 recs
type 3, 18db433b7841ddbb7ea8c25a33153492357cc927d4a3d4882c7ff1de8c8afb12, 442 recs

CALL orca.write_trip_od_txns('4402ac7c70d13bfb88891a276c9a0e57a41ce647b1fd0b482fcd28fce9bfa015');
CALL orca.write_trip_od_txns('591c81dc1ad54e02b6c10db75f59026650bbd9cbe473095b4d41120c8b414a45');
CALL orca.write_trip_od_txns('bc2a9ee70b31c902fdfbcd7b828a3760834ec75db8b053cc925d273bd07870b6');
CALL orca.write_trip_od_txns('18db433b7841ddbb7ea8c25a33153492357cc927d4a3d4882c7ff1de8c8afb12');

-- now check result
SELECT count(*) FROM _tmp.trips;
SELECT count(*) FROM _tmp.trip_breaks;
SELECT count(*) FROM _tmp.transfers;

SELECT t.*, b.break_type_id FROM _tmp.trips t LEFT JOIN _tmp.trip_breaks b ON b.txn_id = t.orig_txn_id ORDER BY 1;
SELECT x.*, t.* FROM _tmp.transfers x JOIN _tmp.trips t ON t.orig_txn_id = x.trip_orig_txn_id ORDER BY 1;

SELECT  sum(t.transfer_count) AS transfer_count
        ,count(*) + sum(t.transfer_count) AS boardings
        ,sum(array_length(t.routes, 1)) AS routes
        ,sum(array_length(t.modes, 1)) AS modes
  FROM  _tmp.trips t;

*/

-- according to Mark, a new trip begins when:
--   boarding is not within two-hour transfer window (already done via boarding groups)
--   boarding is to a route which was already used during the journey (break trip type 1 or 2)
--   boarding is more than 1/3 mile from previous alighting location (break trip type 3)

-- create table of trips by searching through all boardings and checking above rules
-- NOTE: also choosing to break 'BRT' routes where route was not identified
--       only multiple BRT rides on same agency where no leg was identified will be broken
--       this is likely a small number, mostly transfers between C/D/E rapid ride lines
CREATE OR REPLACE PROCEDURE orca.write_trips_transfers(_csn_hash_start text)
LANGUAGE plpgsql AS $$
DECLARE
    _rec record;
    _write boolean;
    _orig_txn bigint := -1;
    _last_txn bigint := NULL;
    _xfers smallint := 0;
    _break smallint := NULL;
    _route text;
    _routes text[];
    _modes smallint[];
BEGIN
    -- iterate through boardings_with_groups by csn_hash and txn_dtm_pacific
    FOR _rec IN
        -- get corrected routes and modes from board_locations first
        SELECT  bg.txn_id, bg.csn_hash, bg.grp_first_txn_id, al.nxt_stop_dist_m
                ,coalesce(bl.agency_id, bg.source_agency_id)::text AS agency_id
                ,coalesce(bl.route_id, bg.route_number) AS route_id
                ,coalesce(bl.mode_id, bg.reader_mode_id) AS mode_id
          FROM  orca.boardings_with_groups bg
          LEFT  JOIN orca.board_locations bl ON bl.txn_id = bg.txn_id
          LEFT  JOIN orca.alight_locations al ON al.txn_id = bg.prev_txn_id   -- alighting from previous boarding
         WHERE  bg.csn_hash LIKE _csn_hash_start
        ORDER BY bg.csn_hash, bg.txn_dtm_pacific, bg.txn_id
    LOOP
        -- create concatenated agency_route; set _write to false and break to null
        _route := concat(_rec.agency_id, '_', _rec.route_id);
        _write := false;

        IF _rec.txn_id = _rec.grp_first_txn_id THEN
            -- first record of new trip based on regular financial transfer rules - set write
            _write := true;
        ELSIF _rec.route_id IS DISTINCT FROM NULL AND _route = _routes[array_length(_routes, 1)] THEN
            -- (non-null) route is same as the previous route - set write and break type
            _write := true;
            _break := 1;
        ELSIF _rec.route_id IS DISTINCT FROM NULL AND ARRAY[_route] <@ _routes THEN
            -- (non-null) route is same as a previous route in the trip - set write and break type
            _write := true;
            _break := 2;
        ELSIF _rec.nxt_stop_dist_m > 537 THEN
            -- distance from previous alighting exceeds 1/3 mile - set write and break type
            _write := true;
            _break := 3;
        ELSE    -- txn is part of same trip; write transfer, increment transfer count and append route and mode
            INSERT INTO orca.transfers (board_txn_id,trip_orig_txn_id,alight_txn_id) VALUES (_rec.txn_id, _orig_txn, _last_txn);
            _xfers := _xfers + 1;
            _routes := _routes || _route;
            _modes := _modes || _rec.mode_id;
        END IF;

        IF _write THEN
            IF _last_txn IS DISTINCT FROM NULL THEN
                -- write previous trip to table (if not first trip, when _last_txn is null)
                -- TODO: add on conflict statement (how should this be handled?)
                INSERT INTO orca.trips (orig_txn_id,dest_txn_id,transfer_count,routes,modes) VALUES (_orig_txn, _last_txn, _xfers, _routes, _modes);
            END IF;

            -- if trip was broken, write break to trip_break table and reset break
            IF _break IS DISTINCT FROM NULL THEN
                INSERT INTO orca.trip_breaks VALUES (_rec.txn_id, _break, _orig_txn);
                _break := NULL;
            END IF;

            -- update paramters for new trip start - reset origin txn, transfer count, break, routes, and modes
            _orig_txn := _rec.txn_id;
            _xfers := 0;
            _routes := array_append(NULL, _route);
            _modes := array_append(NULL, _rec.mode_id);
        END IF;

        -- update last txn processed (can't use prev_txn from record because new csn would write incorrect previous leg)
        _last_txn := _rec.txn_id;
    END LOOP;

    -- write last record after exit (no possibility of being a break trip until more trips for that user are received)
    -- TODO: add on conflict statement (how should this be handled?)
    IF _last_txn IS DISTINCT FROM NULL THEN     -- ensure that some boardings were processed
        INSERT INTO orca.trips (orig_txn_id,dest_txn_id,transfer_count,routes,modes) VALUES (_orig_txn, _last_txn, _xfers, _routes, _modes);
    END IF;
END $$;

-- get count by start of csn_hash
-- really even! lowest has 12,187,728; highest has 12,525,433
SELECT  left(csn_hash, 1) AS csn_hash_start, count(*) AS boarding_count FROM orca.boardings GROUP BY 1 ORDER BY 1;

-- run procedure 0 to f
-- 20221104: re-run for new pt boardings - for 1/16 of 250 million txns, takes ~30 minutes to run
CALL orca.write_trips_transfers('0%');
CALL orca.write_trips_transfers('1%');
CALL orca.write_trips_transfers('2%');
CALL orca.write_trips_transfers('3%');
CALL orca.write_trips_transfers('4%');
CALL orca.write_trips_transfers('5%');
CALL orca.write_trips_transfers('6%');
CALL orca.write_trips_transfers('7%');
CALL orca.write_trips_transfers('8%');
CALL orca.write_trips_transfers('9%');
CALL orca.write_trips_transfers('a%');
CALL orca.write_trips_transfers('b%');
CALL orca.write_trips_transfers('c%');
CALL orca.write_trips_transfers('d%');
CALL orca.write_trips_transfers('e%');
CALL orca.write_trips_transfers('f%');

-- backup data:
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.trips_100m --data-only orca_pod > ~/dl/orca_trips_100m_20221105.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.trips_200m --data-only orca_pod > ~/dl/orca_trips_200m_20221105.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.trips_300m --data-only orca_pod > ~/dl/orca_trips_300m_20221105.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.trip_breaks_100m --data-only orca_pod > ~/dl/orca_trip_breaks_100m_20221105.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.trip_breaks_200m --data-only orca_pod > ~/dl/orca_trip_breaks_200m_20221105.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.trip_breaks_300m --data-only orca_pod > ~/dl/orca_trip_breaks_300m_20221105.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.transfers_100m --data-only orca_pod > ~/dl/orca_transfers_100m_20221105.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.transfers_200m --data-only orca_pod > ~/dl/orca_transfers_200m_20221105.sql
-- pg_dump -U rpavery -h 10.142.198.115 -O -t orca.transfers_300m --data-only orca_pod > ~/dl/orca_transfers_300m_20221105.sql

-- check results:
-- 2022-09-17:
-- trips:       149,701,274 (of which 65,585,983 have orig and dest stop_id)
-- trip_breaks:   8,529,280
-- transfers:    48,176,451

-- this query seems to kill postgres:
SELECT count(*) FROM orca.v_trips t WHERE t.orig_stop_id IS NOT NULL AND t.dest_stop_id IS NOT NULL;

-- instead try:
SELECT  count(*)
  FROM  orca.trips t
  JOIN  orca.board_locations b ON b.txn_id = t.orig_txn_id
  JOIN  orca.alight_locations a ON a.txn_id = t.dest_txn_id;

/*
------------------------------------------------------------
-- processing notes:

--  import datetime from - to           max txn_id      nominal dates (ignoring bad txns)
--  2021-05-19 00:06:02+00 (static)     187586382       2019-01-01 to 2020-12-31
--  2021-12-12 05:01:22+00 08:58:15+00: 219889619       2021-01-01 to 2021-10-31
--  2022-09-19 20:41:31+00 21:03:05+00: 250676556       2021-11-01 to 2022-05-15

-- data imported thru:
--   orca transactions:         2022-05-15
--   avl kcm records:           2022-06-30
--   avl ct records:            2022-06-30
--   avl pt (swiftly):          2022-06-30

-- device matching processed:   2021-12-31

------------------------------------------------------------
-- data export for KCM/CS:

-- orca transactions
\copy orca.transactions_2019 TO '~/dl/orca_transactions_2019.csv' WITH (FORMAT CSV, HEADER);
\copy orca.transactions_2020 TO '~/dl/orca_transactions_2020.csv' WITH (FORMAT CSV, HEADER);
\copy orca.transactions_2021 TO '~/dl/orca_transactions_2021.csv' WITH (FORMAT CSV, HEADER);
\copy orca.transactions_2022 TO '~/dl/orca_transactions_2022.csv' WITH (FORMAT CSV, HEADER);

-- agency and orca enumeration tables
\copy agency.agencies TO '~/dl/agency_agencies.csv' WITH (FORMAT CSV, HEADER);
\copy orca.bad_txn_types TO '~/dl/orca_bad_txn_types.csv' WITH (FORMAT CSV, HEADER);
\copy orca.break_types TO '~/dl/orca_break_types.csv' WITH (FORMAT CSV, HEADER);
\copy orca.directions TO '~/dl/orca_directions.csv' WITH (FORMAT CSV, HEADER);
\copy orca.institutions TO '~/dl/orca_institutions.csv' WITH (FORMAT CSV, HEADER);
\copy orca.location_sources TO '~/dl/orca_location_sources.csv' WITH (FORMAT CSV, HEADER);
\copy orca.modes TO '~/dl/orca_modes.csv' WITH (FORMAT CSV, HEADER);
\copy orca.passenger_types TO '~/dl/orca_passenger_types.csv' WITH (FORMAT CSV, HEADER);
\copy orca.products TO '~/dl/orca_products.csv' WITH (FORMAT CSV, HEADER);
\copy orca.transaction_types TO '~/dl/orca_transaction_types.csv' WITH (FORMAT CSV, HEADER);

-- orca boarding_groups and trip_breaks?
\copy orca.boarding_groups_100m TO '~/dl/orca_boarding_groups_100m.csv' WITH (FORMAT CSV, HEADER);
\copy orca.boarding_groups_200m TO '~/dl/orca_boarding_groups_200m.csv' WITH (FORMAT CSV, HEADER);
\copy orca.boarding_groups_300m TO '~/dl/orca_boarding_groups_300m.csv' WITH (FORMAT CSV, HEADER);

-- transfer_detail and trip_detail
\copy orca.trip_detail_100m TO '~/dl/orca_trip_detail_100m.csv' WITH (FORMAT CSV, HEADER);
\copy orca.trip_detail_200m TO '~/dl/orca_trip_detail_200m.csv' WITH (FORMAT CSV, HEADER);
\copy orca.trip_detail_300m TO '~/dl/orca_trip_detail_300m.csv' WITH (FORMAT CSV, HEADER);
\copy orca.transfer_detail_100m TO '~/dl/orca_transfer_detail_100m.csv' WITH (FORMAT CSV, HEADER);
\copy orca.transfer_detail_200m TO '~/dl/orca_transfer_detail_200m.csv' WITH (FORMAT CSV, HEADER);
\copy orca.transfer_detail_300m TO '~/dl/orca_transfer_detail_300m.csv' WITH (FORMAT CSV, HEADER);

-- unified stop locations
\copy (SELECT * FROM agency.v_uniq_stop_location_coords) TO '~/dl/agency_v_uniq_stop_location_coords.csv' WITH (FORMAT CSV, HEADER);

------------------------------------------------------------
------ future updates
-- look into optimizing boardings/alightings/upgrade - are separate tables needed?

-- rename brt_stops to offboard_readers

-- next steps for 2022 data import:
[ ] write new monthly trip/transfer summaries by institution id
[ ] drop gtfs_stop_id and created_at from boardings_avl?
[ ] ensure boardings_avl process selects from boardings, not transactions
[x] process txns
[ ] clean up/remove old AVL data in orca, orca2020 databases; remove 2019 kcm avl partition if needed
[ ] import avl data
[ ] process devices
[ ] write locations
[ ] update trip and transfer tables

overall process:
 - load orca txns
 - process boarding groups
   - TODO: develop process to remove boardings that occur simultaneously as alighting?
 - run process to match devices to vehicles
   - TODO: this currently writes to boardings_avl for buses as well - separate process when we get new orca format
 - identify boarding locations:
   - for bus, based on stop on route nearest to tap coordinates at time of tap (new process)
   - for brt & rail, based on offboard reader location; also identify route_id
   - correct mode_id for on-board brt taps and off-baord non-brt taps
 - identify alighting locations
   - for bus & brt, search for stops along current route within 1/3 mile of next boarding location and select closest stop
   - for rail, check for tap-off txn; if none, apply bus process
   - for all, compute distance from alighting to next boarding
 - process trips and transfers
   - break trip if same route used or transfer distance is greater than 1/3 mile
   - TODO: also consider excessive transfer time?

-- orca.transactions - raw txns
-- orca.v_boardings - boarding transactions (TODO: rename from boardings)
-- orca.v_alightings - alighting transactions (TODO: needs to be created)
-- orca.v_board_groups - links txn to previous txn and if within transfer window (TODO: rename from boarding_groups, delete gtfs_stop_id and created_at)
-- orca.v_trip_txns - get all txns in a trip (including alightings or just boardings? TODO: create)
-- orca.boardings_avl - boarding locations by AVL (TODO: delete this in favor of board_locations)
-- orca.board_locations - boarding locations
-- orca.alight_locations - alighting locations (TODO: add imputed flag or type field for future imputation based on card behavior, etc)
-- orca.trips - origin/destination of full trip
-- orca.trip_breaks - info to link trip break to previous trip if needed
-- orca.transfers - intermediate transfers (or add as flag in orca.boarding_txns?)
-- gtfs alternatives: (or consider adding gtfs/rt_gtfs fields to [board|alight]_locations tables)
  -- orca.board_gtfs - boarding locations based on gtfs schedule instead of avl
  -- orca.alight_gtfs - alighting locations based on gtfs schedule instead of avl
  -- orca.board_rtgtfs - boarding locations based on real-time gtfs instead of avl
  -- orca.alight_rtgtfs - alighting locations based on real-time gtfs instead of avl

 - in future, consider ferry (8), streetcar (249), and demand-responsive (254)

-- back up dmitri's schema:
-- pg_dump -U rpavery -h 10.142.198.115 -O -n dz orca_pod | 7za a -si ~/dl/20230214_orca_pod_dz_schema.7z

--************************************************************--
-- backing up old orca database:

-- get database size:
SELECT pg_size_pretty(pg_database_size('orca'));

-- schema only:
-- pg_dump -U rpavery -h 10.142.198.115 -O --schema-only orca > ~/dl/20230214_old_orca_schema.sql

-- full database (use 7zip to zip from standard input):
-- pg_dump -U rpavery -h 10.142.198.115 -O orca | 7za a -si ~/dl/20230214_old_orca.7z

*/

-- other standard functions to create:
-- function to list all txns in group by txn_id (see analaysis file)
-- function to look at txns by csn_hash and optional dates

---------- LONG TERM ISSUES ----------
-- need to improve how to handle stops moving over time
-- review complete stops from Melissa
-- also, in gtfs_stops, change effectiive_date to start_date and add end_date for easier selection

/*############################################################################*/
/*##########                    WEB ORCA SUPPORT                    ##########*/
/*############################################################################*/

-- find how many distinct users are at an institution (floor of number of passes given out)
SELECT count(DISTINCT t.csn_hash) FROM orca.transactions t WHERE txn_institution_id = '4032';

----- 'new' data imported to show in dashboard:
-- move _tmp table to orca_ng schema
ALTER TABLE _tmp.institution_weekly_usage SET SCHEMA orca_ng;

