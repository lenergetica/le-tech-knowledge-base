---
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

# Configurar postgres_fdw

**postgres_fdw** és una extensió nativa de PostgreSQL que permet consultar i modificar dades d'altres bases de dades PostgreSQL remotes. Actua com un pont. Fa que les taules remotes funcionin com si fossin taules locals mitjançant SQL estàndard.

## Com ho configurem? (exemple a HALL)

En aquest cas, volem que l'esquema `public` de HALL apunti a l'esquema `public` de la BD de Pro de GISCE.

1. Ens connectem a la BD de HALL amb superusuari (`postgres`)

    ```sql
    SELECT current_user;
    ```

    Això ens ha de mostrar que estem connectats com a `postgres`

1. Creem la base de dades `energetica`

    ```sql
    CREATE DATABASE energetica ENCODING = 'UTF8';
    ```

1. Ara ens hem de connectar a la nova base de dades `energetica` i crear l'esquema `develrw`

    ```sql
    CREATE SCHEMA develrw;
    ```

1. Creem l'usuari `energetica` i li donem permisos sobre l'esquema `develrw`

    ```sql
    CREATE ROLE energetica LOGIN PASSWORD '[pwd_usuari_energetica]';
    GRANT USAGE, CREATE ON SCHEMA develrw TO energetica;
    ```

1. Activem l'extensió que permet connectar PostgreSQL amb un altre PostgreSQL remot mitjançant foreign tables

    ```sql
    CREATE EXTENSION IF NOT EXISTS postgres_fdw;
    ```

1. Creem el servidor remot

    Si ja existia, o volem corregir alguna cosa, prèviament l'hem d'eliminar, sinó no cal:

    ```sql
    --DROP SERVER energetica_pro CASCADE;
    ```

    Definim el servidor remot. Aquí indicarem

    * la IP o host remot
    * la base de dades remota
    * el port de connexió

    ```sql
    CREATE SERVER energetica_pro
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host '192.168.24.3', dbname 'energetica', port '5432');
    ```

    !!! note
    En el cas de HALL, utilitzarem la VLAN que ens va crear GISCE i que dona visibilitat entre els nostres servidors (192.168.24.X). Per a més informació consulteu /etc/hosts a energetica@energetica-hall.

1. Donem permís al rol `energetica` per fer servir aquest servidor remot

    ```sql
    GRANT USAGE ON FOREIGN SERVER energetica_pro TO energetica;
    ```

1. Donem permís al rol energetica per crear objectes dins del schema public de la BD local

    ```sql
    GRANT CREATE ON SCHEMA public TO energetica;
    ```

1. Ens connectem a la BD de HALL amb usuari normal (`energetica`). Comprovem que és així

    ```sql
    SELECT current_user;
    ```

    Això ens ha de mostrar que estem connectats com a `energetica`

1. Associem l’usuari local `energetica` amb unes credencials del servidor remot `energetica_pro`. Això és el que PostgreSQL utilitzarà per connectar-se a PRO quan el rol local `energetica` faci consultes FDW

    ```sql
    CREATE USER MAPPING FOR energetica
    SERVER energetica_pro
    OPTIONS (user 'energetica', password '[pwd_energetica_energetica_pro]');
    ```

1. Importem les taules de l'esquema `public` de la **BD remota** dins de l'esquema `public` **local** com a _foreign tables_. A partir d’aquí, les taules de PRO es poden consultar des de HALL com si fossin locals

    ```sql
    IMPORT FOREIGN SCHEMA public
    FROM SERVER energetica_pro
    INTO public;
    ```

1. Fem alguna prova. Aquesta query que consulta una taula de `public` a **HALL**, realment va a consultar aquesta taula a `public` de la **GISCE Producció**

    ```sql
    SELECT * FROM public.giscedata_cups_ps where name = 'ES0031408648885001LS0F';
    ```

    O una prova de fer join d'una taula de `develrw` de **HALL** amb una de `public` de **GISCE Producció**:

    ```cs
    select gcp."name", gcp.direccio, ftrd.*
    from develrw.fact_total_reclamacions_dashboard ftrd
    left join public.giscedata_cups_ps gcp on ftrd.cups = gcp."name";
    ```

## Consideracions pel que fa a _hypertables_ TimescaleDB

**_postgres\_fdw_** no “veu” els índexs de Timescale com si fossin locals: el que fa és enviar al servidor remot les parts de la consulta que es poden push down; per defecte, només les WHERE amb operadors i funcions built-in o d’extensions declarades com a extensions, i només si són IMMUTABLE. Si la condició es pot enviar al remot, és el servidor remot qui l’executa; si no, l’FDW recupera files i filtra localment.
En la pràctica, això vol dir que si la taula de PRO és una hypertable de TimescaleDB i la query és una SELECT simple sobre una columna indexada, el filtre acostuma a executar-se al remot i, per tant, el servidor de PRO pot aprofitar els seus índexs i la seva partició per chunks. Timescale indica que les hypertables funcionen com taules PostgreSQL normals per a SELECT i que suporten índexs estàndard, però també té les seves pròpies limitacions: els índexs únics han d’incloure totes les columnes de partició, els UPDATE que mouen files entre particions/chunks no s’admeten, i els foreign keys de hypertable a hypertable no estan suportats.
Per tant, la resposta curta és: sí, es pot fer i normalment funciona bé per a lectura, però la clau és que la consulta sigui “shippable” al remot. Si hi poses funcions no built-in, o expressions que l’FDW no pugui enviar, llavors perd pushdown i pot anar molt més lent. Això és una inferència directa del comportament documentat de postgres\_fdw i del fet que Timescale tracta les hypertables com a taules PostgreSQL estàndard per a SELECT.
