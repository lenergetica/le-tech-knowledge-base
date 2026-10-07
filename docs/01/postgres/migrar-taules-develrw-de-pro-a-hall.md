---
darrera_revisio: 2026-08-15
caducitat_dies: 180
estat: actiu
owner: L'Energetica Tech
status: draft
review_date: 2026-2-05
review_period_months: 1
tags:
    - postgresql
    - hall
    - edison
    - base de dades
    - postgres_fdw
    - GISCE
---

# Configuració inicial FDW i còpia pilot d'una taula develrw

Referència de la configuració inicial `postgres_fdw` i de la còpia pilot de la taula `develrw.apigisce_tgf1` de Pro a Hall.

!!! note "Situació inicial ja configurada"
    La configuració general de `postgres_fdw` ja s'ha fet: a Hall hi ha *foreign tables* per consultar les taules de `public` i `develrw` de Pro. Aquesta guia registra la configuració inicial i la còpia pilot ja realitzada; no és el procediment per migrar cada ETL. Per al runbook que cal repetir, un cop per cada script, consulteu [Migrar scripts ETL de Pro a Hall](migrar-scripts-etl-de-pro-a-hall.md).

## Exemple tècnic de la còpia pilot (ja realitzada)

Els passos següents documenten la còpia de `develrw.apigisce_tgf1` i serveixen de referència tècnica per a estructura, TimescaleDB, dades i índexs. La migració operativa de les taules dependents d'un ETL s'ha de fer seguint el runbook d'ETL enllaçat més amunt.

1. Mirem primer les dimensions de la taula a copiar, per fer-nos-en una idea

    ```sql
    SELECT count(*),
        min(timestamp),
        max(timestamp)
    FROM develrw.apigisce_tgf1;
    ```

    ```result
    count   |min                    |max                    |
    --------+-----------------------+-----------------------+
    19422440|2023-04-30 23:00:00.000|2026-09-30 22:00:00.000|
    ```

    Veiem que són 17 milions de registres... no serà ràpid 😮

1. Obtenim *DDL* de l'origen des de *DBeaver* (botó dret sobre la taula > *Generate SQL* > *DDL*)

    ```sql
    -- develrw.apigisce_tgf1 definition

    -- Drop table

    -- DROP TABLE develrw.apigisce_tgf1;

    CREATE TABLE develrw.apigisce_tgf1 (
        "timestamp" timestamp NOT NULL,
        local_timestamp timestamp NULL,
        season bool NULL,
        "type" varchar NOT NULL,
        cups varchar NOT NULL,
        "date" date NULL,
        ai_kwh numeric(18, 5) NULL,
        ao_kwh numeric(18, 5) NULL,
        r1 numeric(18, 5) NULL,
        r2 numeric(18, 5) NULL,
        r3 numeric(18, 5) NULL,
        r4 numeric(18, 5) NULL,
        measure_type int4 NULL,
        reserve1 numeric(18, 5) NULL,
        reserve2 numeric(18, 5) NULL,
        "source" int4 NULL,
        validated bool NULL,
        id int4 NULL,
        create_at timestamp NULL,
        update_at timestamp NULL,
        created_at timestamp NULL,
        updated_at timestamp NULL,
        CONSTRAINT apigisce_tgf1_pk PRIMARY KEY ("timestamp", cups, type)
    );
    CREATE INDEX apigisce_tgf1_p_ts_cups_idx ON develrw.apigisce_tgf1 USING btree ("timestamp", cups) INCLUDE (date, ai_kwh, ao_kwh) WHERE ((type)::text = 'p'::text);
    CREATE INDEX apigisce_tgf1_timestamp_idx ON develrw.apigisce_tgf1 USING btree ("timestamp" DESC);

    -- Table Triggers

    create trigger ts_insert_blocker before
    insert
        on
        develrw.apigisce_tgf1 for each row execute function _timescaledb_internal.insert_blocker();
    ```

    El trigger és de *Timescale*, no caldrà crear-lo manualment a *Hall*.

1. A *Hall*, alliberem el nom de la taula local reanomenant la *foreign table* importada des de Pro. El prefix `_fdw_` la identifica com a referència remota:

    ```sql
    ALTER FOREIGN TABLE develrw.apigisce_tgf1
        RENAME TO _fdw_apigisce_tgf1;
    ```

1. Creem la taula local a *Hall* amb el nom original i la clau primària. **Els índexs addicionals els crearem més endavant. El trigger intern de Timescale no cal recrear-lo manualment.**

    ```sql
    CREATE TABLE develrw.apigisce_tgf1 (
        "timestamp" timestamp NOT NULL,
        local_timestamp timestamp NULL,
        season bool NULL,
        "type" varchar NOT NULL,
        cups varchar NOT NULL,
        "date" date NULL,
        ai_kwh numeric(18, 5) NULL,
        ao_kwh numeric(18, 5) NULL,
        r1 numeric(18, 5) NULL,
        r2 numeric(18, 5) NULL,
        r3 numeric(18, 5) NULL,
        r4 numeric(18, 5) NULL,
        measure_type int4 NULL,
        reserve1 numeric(18, 5) NULL,
        reserve2 numeric(18, 5) NULL,
        "source" int4 NULL,
        validated bool NULL,
        id int4 NULL,
        create_at timestamp NULL,
        update_at timestamp NULL,
        created_at timestamp NULL,
        updated_at timestamp NULL,
        CONSTRAINT apigisce_tgf1_pk PRIMARY KEY ("timestamp", cups, type)
    );
    ```

1. Mirem a la taula original a *Pro*, quins són els paràmetres *Timescale*

    ```sql
    SELECT *
    FROM timescaledb_information.hypertables
    WHERE hypertable_name = 'apigisce_tgf1';
    ```

    ```result
    hypertable_schema|hypertable_name|owner     |num_dimensions|num_chunks|compression_enabled|is_distributed|replication_factor|data_nodes|tablespaces|
    -----------------+---------------+----------+--------------+----------+-------------------+--------------+------------------+----------+-----------+
    develrw          |apigisce_tgf1  |energetica|             1|       179|false              |false         |                  |NULL      |NULL       |
    ```

    ```sql
    SELECT *
    FROM timescaledb_information.dimensions
    WHERE hypertable_name = 'apigisce_tgf1'
    ORDER BY dimension_number;
    ```

    ```result
    hypertable_schema|hypertable_name|dimension_number|column_name|column_type                |dimension_type|time_interval|integer_interval|integer_now_func|num_partitions|
    -----------------+---------------+----------------+-----------+---------------------------+--------------+-------------+----------------+----------------+--------------+
    develrw          |apigisce_tgf1  |               1|timestamp  |timestamp without time zone|Time          |       7 days|                |                |              |
    ```

1. Ara, abans de carregar les dades a *Hall*, la convertirem en *hypertable* (ChatGPT pot ajudar a generar aquesta instrucció a partir dels paràmetres consultats abans).

    ```sql
    SELECT create_hypertable(
        'develrw.apigisce_tgf1',
        'timestamp',
        chunk_time_interval => INTERVAL '7 days'
    );
    ```

1. Comprovem que s'ha creat l'hypertable correctament a HALL

    ```sql
    SELECT
        hypertable_schema,
        hypertable_name,
        dimension_number,
        column_name,
        column_type,
        dimension_type,
        time_interval
    FROM timescaledb_information.dimensions
    WHERE hypertable_schema = 'develrw'
    AND hypertable_name = 'apigisce_tgf1';
    ```

    ```result
    hypertable_schema|hypertable_name|dimension_number|column_name|column_type                |dimension_type|time_interval|
    -----------------+---------------+----------------+-----------+---------------------------+--------------+-------------+
    develrw          |apigisce_tgf1  |               1|timestamp  |timestamp without time zone|Time          |       7 days|
    ```

1. Copiem les dades d'una taula a l'altra (la PK ja ens dona integritat respecte a duplicats; crearem els índexs a la taula de *Hall* després de la còpia, per no penalitzar-la més).
L'script `projectes/energetica_utils/copia_dades_pro2hall.sh` (a Hall) permet copiar les dades d'una taula a l'altra, mes a mes i amb comprovacions. A la capçalera de l'script s'explica com funciona.

1. Un cop copiades les dades, cal crear els índexs que hem vist al DDL (el de PK no cal, i el de *timestamp* tampoc, perquè ja el crea *Timescale*):

    ```sql
    CREATE INDEX apigisce_tgf1_p_ts_cups_idx
    ON develrw.apigisce_tgf1
    USING btree ("timestamp", cups)
    INCLUDE ("date", ai_kwh, ao_kwh)
    WHERE ("type")::text = 'p'::text;
    ```

1. Comprovem els índexs que té la taula a HALL i han de correspondre amb els que té la mateixa taula de PRO:

    ```sql
    SELECT indexname, indexdef
    FROM pg_indexes
    WHERE schemaname = 'develrw'
    AND tablename = 'apigisce_tgf1'
    ORDER BY indexname;
    ```

    ```result
    indexname                  |indexdef                                                                                                                                                         |
    ---------------------------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------+
    apigisce_tgf1_p_ts_cups_idx|CREATE INDEX apigisce_tgf1_p_ts_cups_idx ON develrw.apigisce_tgf1 USING btree ("timestamp", cups) INCLUDE (date, ai_kwh, ao_kwh) WHERE ((type)::text = 'p'::text)|
    apigisce_tgf1_pk           |CREATE UNIQUE INDEX apigisce_tgf1_pk ON develrw.apigisce_tgf1 USING btree ("timestamp", cups, type)                                                              |
    apigisce_tgf1_timestamp_idx|CREATE INDEX apigisce_tgf1_timestamp_idx ON develrw.apigisce_tgf1 USING btree ("timestamp" DESC)                                                                 |
    ```

Per al procediment operatiu d'actualització de *foreign tables* i de migració dels ETL dependents, consulteu [Migrar scripts ETL de Pro a Hall](migrar-scripts-etl-de-pro-a-hall.md). Aquesta guia de taules serveix de referència per a l'estructura, TimescaleDB, còpia de dades i índexs de la taula local a Hall.
