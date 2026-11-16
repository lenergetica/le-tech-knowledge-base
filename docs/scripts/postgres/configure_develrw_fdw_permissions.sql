GRANT USAGE ON SCHEMA public TO energetica;

DO $$
DECLARE
    foreign_table record;
BEGIN
    FOR foreign_table IN
        SELECT n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'f'
        ORDER BY c.relname
    LOOP
        EXECUTE format(
            'ALTER FOREIGN TABLE %I.%I OWNER TO postgres',
            foreign_table.nspname,
            foreign_table.relname
        );
        EXECUTE format(
            'GRANT SELECT ON TABLE %I.%I TO energetica',
            foreign_table.nspname,
            foreign_table.relname
        );
        EXECUTE format(
            'REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE %I.%I FROM energetica, PUBLIC',
            foreign_table.nspname,
            foreign_table.relname
        );
    END LOOP;
END;
$$;

REVOKE CREATE ON SCHEMA public FROM energetica;
