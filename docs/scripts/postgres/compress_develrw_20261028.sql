-- Configuració de referència de PRO del 2026-10-28, TimescaleDB 2.11.
-- Compareu-la amb PRO abans d'executar-la; if_not_exists no actualitza polítiques.
\set ON_ERROR_STOP on
DO $check$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_extension WHERE extname = 'timescaledb'
                   AND extversion ~ '^2[.]11([.]|$)') THEN
        RAISE EXCEPTION 'This reference configuration requires TimescaleDB 2.11';
    END IF;
END;
$check$;

ALTER TABLE develrw.apigisce_adjunts_factura SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'cups, tipus',
  timescaledb.compress_orderby = 'timestamp DESC NULLS FIRST'
);
ALTER TABLE develrw.apigisce_tgcchfact SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'cups',
  timescaledb.compress_orderby = 'timestamp DESC NULLS FIRST'
);
ALTER TABLE develrw.apigisce_tgcchval SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'cups',
  timescaledb.compress_orderby = 'timestamp DESC NULLS FIRST'
);
ALTER TABLE develrw.apigisce_tgf1 SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'cups, type',
  timescaledb.compress_orderby = 'timestamp DESC NULLS FIRST'
);
ALTER TABLE develrw.apigisce_tgp1_old SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'cups',
  timescaledb.compress_orderby = 'timestamp DESC NULLS FIRST'
);
ALTER TABLE develrw.ree_simel_epfpfqh SET (
  timescaledb.compress,
  timescaledb.compress_orderby = 'timestamp DESC NULLS FIRST'
);

SELECT add_compression_policy(
  'develrw.apigisce_adjunts_factura'::regclass,
  INTERVAL '14 days',
  if_not_exists => TRUE,
  schedule_interval => INTERVAL '3 days 12 hours'
);
SELECT add_compression_policy(
  'develrw.apigisce_tgcchfact'::regclass,
  INTERVAL '14 days',
  if_not_exists => TRUE,
  schedule_interval => INTERVAL '3 days 12 hours'
);
SELECT add_compression_policy(
  'develrw.apigisce_tgcchval'::regclass,
  INTERVAL '14 days',
  if_not_exists => TRUE,
  schedule_interval => INTERVAL '3 days 12 hours'
);
SELECT add_compression_policy(
  'develrw.apigisce_tgf1'::regclass,
  INTERVAL '14 days',
  if_not_exists => TRUE,
  schedule_interval => INTERVAL '3 days 12 hours'
);
SELECT add_compression_policy(
  'develrw.ree_simel_epfpfqh'::regclass,
  INTERVAL '120 days',
  if_not_exists => TRUE,
  schedule_interval => INTERVAL '3 days 12 hours'
);
