-- Executar com a postgres a la BD de destinació, després d'importar les taules.
\set ON_ERROR_STOP on
GRANT USAGE ON SCHEMA public TO energetica;
SELECT format(
    'ALTER FOREIGN TABLE %I.%I OWNER TO postgres',
    n.nspname,
    c.relname
)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'f'
ORDER BY c.relname
\gexec
SELECT format('GRANT SELECT ON TABLE %I.%I TO energetica', n.nspname, c.relname)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'f'
ORDER BY c.relname
\gexec
SELECT format(
    'REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE %I.%I FROM energetica, PUBLIC',
    n.nspname,
    c.relname
)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'f'
ORDER BY c.relname
\gexec
REVOKE CREATE ON SCHEMA public FROM energetica;
