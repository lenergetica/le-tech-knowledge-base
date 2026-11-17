-- Proposta pendent d'aplicar. Executar amb psql, com a postgres, a HALL.
-- Crea els dos perfils; no està pensat per repetir-lo si ja existeixen.
-- No estableix contrasenyes, no crea mappings i no modifica PRO.
\set ON_ERROR_STOP on
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'energetica'
       OR NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'energetica_pro')
       OR NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'develrw') THEN
        RAISE EXCEPTION 'Comproveu la connexió: cal la BD energetica de HALL, amb develrw i energetica_pro';
    END IF;
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'Executeu aquest script amb un superusuari';
    END IF;
END;
$$;

CREATE ROLE develrw_admin NOLOGIN INHERIT;
CREATE ROLE develrw_dades NOLOGIN INHERIT;

-- El rol existent energetica conserva la propietat dels objectes.
-- Els administradors hereten tots els seus permisos a HALL.
GRANT energetica TO develrw_admin;
GRANT develrw_dades TO develrw_admin;

GRANT CONNECT ON DATABASE energetica TO develrw_admin, develrw_dades;
GRANT USAGE ON SCHEMA develrw TO develrw_dades;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA develrw TO develrw_dades;
GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA develrw TO develrw_dades;

GRANT USAGE ON SCHEMA public TO develrw_admin, develrw_dades;
GRANT SELECT ON ALL TABLES IN SCHEMA public
    TO develrw_admin, develrw_dades;
GRANT USAGE ON FOREIGN SERVER energetica_pro
    TO develrw_admin, develrw_dades;

-- Només s'apliquen als objectes nous creats pel rol indicat.
ALTER DEFAULT PRIVILEGES FOR ROLE energetica IN SCHEMA develrw
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO develrw_dades;
ALTER DEFAULT PRIVILEGES FOR ROLE energetica IN SCHEMA develrw
    GRANT USAGE, SELECT ON SEQUENCES TO develrw_dades;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT SELECT ON TABLES TO develrw_admin, develrw_dades;

-- Reutilitza els logins que ja existeixin sense canviar-ne la contrasenya.
-- Els nous es creen sense contrasenya: establir-la després amb \password.
DO $$
DECLARE
    account text;
BEGIN
    FOREACH account IN ARRAY ARRAY[
        'miquelllover', 'guillemmarpons', 'joansegura',
        'joseantonioarias', 'juliaperona', 'lauramari',
        'randanajjari', 'martigarcia', 'marcnunez',
        'blancaperez', 'paulaferrate',
        'svc_energetica_etl', 'svc_comercialitzacio'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = account) THEN
            EXECUTE format(
                'CREATE ROLE %I LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
                account
            );
        END IF;
        IF EXISTS (
            SELECT 1 FROM pg_roles WHERE rolname = account
            AND (NOT rolcanlogin OR NOT rolinherit OR rolsuper OR rolcreatedb
                 OR rolcreaterole OR rolreplication OR rolbypassrls)
        ) THEN
            RAISE EXCEPTION 'El rol % ja existeix amb atributs incompatibles; revisar-lo abans', account;
        END IF;
    END LOOP;
END;
$$;

GRANT develrw_admin TO
    miquelllover, guillemmarpons, joansegura,
    joseantonioarias, juliaperona, lauramari,
    svc_energetica_etl, svc_comercialitzacio;

GRANT develrw_dades TO
    randanajjari, martigarcia, marcnunez, blancaperez, paulaferrate;

-- Cada connexió nova dels administradors actuarà com a energetica.
-- session_user conserva el login original. La configuració no s'hereta:
-- s'ha de definir per a cadascun dels logins i només en aquesta BD.
DO $$
DECLARE
    account text;
BEGIN
    FOREACH account IN ARRAY ARRAY[
        'miquelllover', 'guillemmarpons', 'joansegura',
        'joseantonioarias', 'juliaperona', 'lauramari',
        'svc_energetica_etl', 'svc_comercialitzacio'
    ] LOOP
        EXECUTE format(
            'ALTER ROLE %I IN DATABASE energetica SET role = %L',
            account, 'energetica'
        );
    END LOOP;
END;
$$;

-- Retira assignacions directes incompatibles amb el perfil de dades.
-- Altres assignacions o propietats no es modifiquen: es comproven a sota.
REVOKE energetica, develrw_admin FROM
    randanajjari, martigarcia, marcnunez, blancaperez, paulaferrate;

DO $$
DECLARE
    account text;
BEGIN
    FOREACH account IN ARRAY ARRAY[
        'randanajjari', 'martigarcia', 'marcnunez', 'blancaperez', 'paulaferrate'
    ] LOOP
        IF pg_has_role(account, 'energetica', 'MEMBER')
           OR has_schema_privilege(account, 'develrw', 'CREATE')
           OR EXISTS (
               SELECT 1 FROM pg_class c
               JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'develrw'
                 AND (pg_has_role(account, c.relowner, 'MEMBER')
                      OR (c.relkind IN ('r', 'p', 'v', 'm', 'f')
                          AND has_table_privilege(account, c.oid, 'TRUNCATE')))
           ) THEN
            RAISE EXCEPTION 'El rol % conserva permisos de gestió, propietat o TRUNCATE a develrw; revisar-los abans', account;
        END IF;
    END LOOP;
END;
$$;

-- No es canvien els permisos de funcions ni procediments.
COMMIT;
