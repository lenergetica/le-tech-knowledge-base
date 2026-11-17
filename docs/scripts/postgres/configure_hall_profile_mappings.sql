-- Proposta pendent d'aplicar, després de configure_hall_user_profiles.sql.
-- Executar com a postgres a la BD energetica de HALL.
-- Copia les opcions del mapping d'energetica als cinc usuaris de dades.
-- Els administradors utilitzen el mapping existent en actuar com a energetica.
-- No imprimeix ni inclou credencials literals al fitxer.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    account text;
    server_oid oid;
    source_options text[];
    options_sql text;
BEGIN
    IF current_database() <> 'energetica'
       OR NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'Executeu com a postgres a la BD energetica de HALL';
    END IF;

    SELECT oid INTO STRICT server_oid
    FROM pg_foreign_server WHERE srvname = 'energetica_pro';
    SELECT umoptions INTO STRICT source_options
    FROM pg_user_mapping
    WHERE umserver = server_oid
      AND umuser = (SELECT oid FROM pg_roles WHERE rolname = 'energetica');

    IF source_options IS NULL THEN
        RAISE EXCEPTION 'El mapping origen no conté opcions; revisar-lo abans';
    END IF;
    SELECT string_agg(format('%I %L', option_name, option_value), ', ' ORDER BY option_name)
    INTO options_sql FROM pg_options_to_table(source_options);

    FOREACH account IN ARRAY ARRAY[
        'randanajjari', 'martigarcia', 'marcnunez',
        'blancaperez', 'paulaferrate'
    ] LOOP
        -- Si ja existeix, s'atura tota la transacció per revisar-lo.
        IF EXISTS (
            SELECT 1 FROM pg_user_mapping m
            JOIN pg_roles r ON r.oid = m.umuser
            WHERE m.umserver = server_oid AND r.rolname = account
        ) THEN
            RAISE EXCEPTION 'Ja existeix el mapping de %; revisar-lo abans', account;
        END IF;
        BEGIN
            EXECUTE format(
                'CREATE USER MAPPING FOR %I SERVER energetica_pro OPTIONS (%s)',
                account, options_sql
            );
        EXCEPTION WHEN OTHERS THEN
            -- No propagar el SQL dinàmic amb credencials al context d'error.
            RAISE EXCEPTION 'No s’ha pogut crear el mapping de %; transacció cancel·lada', account;
        END;
    END LOOP;
END;
$$;

COMMIT;
