-- Executar com a postgres després de la càrrega i la compressió.
-- Sense transacció global: cada hypertable pot requerir molts locks als chunks.
\set ON_ERROR_STOP on
GRANT USAGE, CREATE ON SCHEMA develrw TO energetica;
ALTER SCHEMA develrw OWNER TO energetica;

SELECT format(
    'ALTER %s %I.%I OWNER TO energetica',
    CASE c.relkind
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        ELSE 'TABLE'
    END,
    n.nspname,
    c.relname
)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'develrw'
  AND c.relkind IN ('r', 'p', 'v', 'm')
ORDER BY c.relkind, c.relname
\gexec

SELECT format('ALTER SEQUENCE %I.%I OWNER TO energetica', n.nspname, c.relname)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'develrw'
  AND c.relkind = 'S'
  AND NOT EXISTS (
      SELECT 1
      FROM pg_depend d
      WHERE d.classid = 'pg_class'::regclass
        AND d.objid = c.oid
        AND d.refclassid = 'pg_class'::regclass
        AND d.deptype IN ('a', 'i')
  )
ORDER BY c.relname
\gexec

-- Les funcions i els tipus no canvien de propietari en canviar el de l'esquema.
SELECT format('ALTER %s %I.%I(%s) OWNER TO energetica',
              CASE p.prokind WHEN 'p' THEN 'PROCEDURE'
                             WHEN 'a' THEN 'AGGREGATE' ELSE 'FUNCTION' END,
              n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'develrw'
  AND NOT EXISTS (SELECT 1 FROM pg_depend d
                  WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
                    AND d.deptype = 'e')
ORDER BY p.oid
\gexec

-- Excloure tipus de fila de taules, arrays i tipus interns o d'extensions.
SELECT format('ALTER %s %I.%I OWNER TO energetica',
              CASE t.typtype WHEN 'd' THEN 'DOMAIN' ELSE 'TYPE' END,
              n.nspname, t.typname)
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
LEFT JOIN pg_class c ON c.oid = t.typrelid
WHERE n.nspname = 'develrw' AND t.typisdefined
  AND (t.typrelid = 0 OR c.relkind = 'c')
  AND NOT EXISTS (SELECT 1 FROM pg_depend d
                  WHERE d.classid = 'pg_type'::regclass AND d.objid = t.oid
                    AND d.deptype IN ('i', 'e'))
ORDER BY t.oid
\gexec
