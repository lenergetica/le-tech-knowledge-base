-- Diagnòstic de lectura; revisar els resultats segons el pas 8 del procediment.
\set ON_ERROR_STOP on
SELECT current_database(), current_user;

-- Resultat esperat: zero files. Les extensions conserven el seu propietari.
WITH objects AS (
    SELECT 'schema' AS kind, n.nspname AS name, n.nspowner AS owner
    FROM pg_namespace n WHERE n.nspname = 'develrw'
    UNION ALL
    SELECT 'relation', c.oid::regclass::text, c.relowner
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'develrw' AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
    UNION ALL
    SELECT 'routine', p.oid::regprocedure::text, p.proowner
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'develrw' AND NOT EXISTS (
        SELECT FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass
        AND d.objid = p.oid AND d.deptype = 'e')
    UNION ALL
    SELECT 'type', format('%I.%I', n.nspname, t.typname), t.typowner
    FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    LEFT JOIN pg_class c ON c.oid = t.typrelid
    WHERE n.nspname = 'develrw' AND t.typisdefined
      AND (t.typrelid = 0 OR c.relkind = 'c') AND NOT EXISTS (
        SELECT FROM pg_depend d WHERE d.classid = 'pg_type'::regclass
        AND d.objid = t.oid AND d.deptype IN ('i', 'e'))
    UNION ALL
    SELECT 'chunk', format('%I.%I', ch.chunk_schema, ch.chunk_name), c.relowner
    FROM timescaledb_information.chunks ch
    JOIN pg_namespace n ON n.nspname = ch.chunk_schema
    JOIN pg_class c ON c.relnamespace = n.oid AND c.relname = ch.chunk_name
    WHERE ch.hypertable_schema = 'develrw'
)
SELECT kind, name, pg_get_userbyid(owner) AS owner
FROM objects WHERE owner <> 'energetica'::regrole ORDER BY kind, name;

-- Resultat esperat: true, false (inclou privilegis heretats).
SELECT has_schema_privilege('energetica', 'public', 'USAGE') AS public_usage,
       has_schema_privilege('energetica', 'public', 'CREATE') AS public_create;
-- Resultat esperat: zero files.
SELECT c.relname, pg_get_userbyid(c.relowner) AS owner
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'f'
  AND (c.relowner = 'energetica'::regrole
       OR NOT has_table_privilege('energetica', c.oid, 'SELECT')
       OR has_table_privilege('energetica', c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'));

-- Contrastar last_value:is_called amb l'última entrada de cada seqüència al TSV.
SELECT format('SELECT %L AS sequence, last_value, is_called FROM %I.%I;',
              c.relname, n.nspname, c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'develrw' AND c.relkind = 'S' ORDER BY c.relname
\gexec

SELECT c.relname, c.relispopulated
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'develrw' AND c.relkind = 'm' ORDER BY c.relname;

-- Revisar SECURITY DEFINER: el canvi de propietari canvia el rol d'execució.
SELECT p.oid::regprocedure, p.prosecdef
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'develrw' AND p.prosecdef;
