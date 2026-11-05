-- Inventari de lectura: executar tant a PRO com a HALL (TimescaleDB 2.11).
\set ON_ERROR_STOP on
SELECT hypertable_name, owner, num_dimensions, compression_enabled
FROM timescaledb_information.hypertables
WHERE hypertable_schema = 'develrw' ORDER BY hypertable_name;
SELECT * FROM timescaledb_information.dimensions
WHERE hypertable_schema = 'develrw' ORDER BY hypertable_name, dimension_number;
SELECT * FROM timescaledb_information.compression_settings
WHERE hypertable_schema = 'develrw' ORDER BY hypertable_name, attname;
SELECT hypertable_name, proc_name, owner, schedule_interval, config, scheduled
FROM timescaledb_information.jobs
WHERE hypertable_schema = 'develrw' ORDER BY hypertable_name, proc_name;
