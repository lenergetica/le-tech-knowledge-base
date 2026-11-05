---
owner: L'Energetica Tech
status: draft
review_date: 2026-11-05
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

!!! note "Restauració de develrw"
    Per restaurar `develrw` de PRO a HALL, seguiu el
    [procediment de restauració](./restaurar-develrw-a-Hall.md), que fixa l'ordre
    dels passos i els permisos finals. La guia següent és per a una configuració
    FDW independent; no cal crear `develrw` per utilitzar FDW.

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

1. Ens connectem a la nova BD `energetica`. Comprovem si el rol local
   `energetica` ja existeix; només si falta, el creem com a `postgres`:

    ```sql
    CREATE ROLE energetica LOGIN;
    ```

    Establim la contrasenya interactivament amb `\password energetica`.
    L'esquema `develrw` només és necessari per a les consultes locals de l'exemple
    final; si el restaurem amb un dump, serà el dump qui el crearà.

1. Activem l'extensió que permet connectar PostgreSQL amb un altre PostgreSQL remot mitjançant foreign tables

    ```sql
    CREATE EXTENSION IF NOT EXISTS postgres_fdw;
    ```

1. Creem el servidor remot

    Si ja existeix, inspeccionem el servidor i els mappings abans de modificar-los.
    No fem servir `DROP SERVER ... CASCADE`: eliminaria els objectes dependents.

    Definim el servidor remot. Aquí indicarem

    * la IP o host remot
    * la base de dades remota
    * el port de connexió

    ```sql
    CREATE SERVER energetica_pro
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host '192.168.24.3', dbname 'energetica', port '5432');
    ```

    !!! note "Nota"
        En el cas de HALL, utilitzarem la VLAN que ens va crear GISCE i que dona visibilitat entre els nostres servidors (192.168.24.X). Per a més informació consulteu /etc/hosts a energetica@energetica-hall.

1. Donem permís al rol `energetica` per fer servir aquest servidor remot

    ```sql
    GRANT USAGE ON FOREIGN SERVER energetica_pro TO energetica;
    ```

1. Donem permís al rol energetica per crear objectes dins del schema public de la BD local

    ```sql
    GRANT USAGE, CREATE ON SCHEMA public TO energetica;
    ```

1. Ens connectem a la BD de HALL amb usuari normal (`energetica`). Comprovem que és així

    ```sql
    SELECT current_user;
    ```

    Això ens ha de mostrar que estem connectats com a `energetica`

1. Associem el rol local `energetica` amb les credencials de PRO. Des del host
   Docker i l'arrel del repositori, executem l'[script de mapping](../../scripts/postgres/configure_develrw_fdw_mapping.sh),
   que demana la contrasenya amb entrada oculta:

    ```bash
    ./docs/scripts/postgres/configure_develrw_fdw_mapping.sh \
      ID_DEL_CONTENIDOR_POSTGRES energetica
    ```

    Abans, comprovem que els logs SQL i l'auditoria del servidor no desaran la
    sentència amb la contrasenya. No executem l'script amb traça del shell o del
    terminal. El mapping s'emmagatzema al catàleg de PostgreSQL.

1. Importem les taules de l'esquema `public` de la **BD remota** dins de l'esquema `public` **local** com a _foreign tables_. A partir d’aquí, les taules de PRO es poden consultar des de HALL com si fossin locals

    ```sql
    IMPORT FOREIGN SCHEMA public
    FROM SERVER energetica_pro
    INTO public;
    ```

1. Per deixar l'accés local a les taules foranes només de lectura, executem
   com a `postgres` el [SQL de permisos FDW](../../scripts/postgres/configure_develrw_fdw_permissions.sql):

    ```bash
    docker exec -i --user postgres ID_DEL_CONTENIDOR_POSTGRES \
      psql -X -v ON_ERROR_STOP=1 -U postgres -d energetica \
      < docs/scripts/postgres/configure_develrw_fdw_permissions.sql
    ```

    Traspassa a `postgres` les taules foranes de `public`, concedeix `SELECT` a
    `energetica`, en revoca els privilegis directes d'escriptura i retira `CREATE`
    a `public`. Repetim aquest pas després de noves importacions i comprovem els
    permisos efectius, inclosos els heretats. El rol no ha de ser superusuari.

1. Com a `energetica`, fem alguna prova. Aquesta query que consulta una taula de `public` a **HALL**, realment va a consultar aquesta taula a `public` de la **GISCE Producció**

    ```sql
    SELECT *
    FROM public.giscedata_cups_ps
    WHERE name = 'ES0031408648885001LS0F';
    ```

    O una prova de fer join d'una taula de `develrw` de **HALL** amb una de `public` de **GISCE Producció**:

    ```sql
    SELECT gcp."name", gcp.direccio, ftrd.*
    FROM develrw.fact_total_reclamacions_dashboard ftrd
    LEFT JOIN public.giscedata_cups_ps gcp ON ftrd.cups = gcp."name";
    ```

??? note "Consideracions pel que fa a _hypertables_ TimescaleDB"
    **_postgres\_fdw_** no “veu” els índexs de Timescale com si fossin locals: el que fa és enviar al servidor remot les parts de la consulta que es poden push down; per defecte, només les WHERE amb operadors i funcions built-in o d’extensions declarades com a extensions, i només si són IMMUTABLE. Si la condició es pot enviar al remot, és el servidor remot qui l’executa; si no, l’FDW recupera files i filtra localment.
    En la pràctica, això vol dir que si la taula de PRO és una hypertable de TimescaleDB i la query és una SELECT simple sobre una columna indexada, el filtre acostuma a executar-se al remot i, per tant, el servidor de PRO pot aprofitar els seus índexs i la seva partició per chunks. Timescale indica que les hypertables funcionen com taules PostgreSQL normals per a SELECT i que suporten índexs estàndard, però també té les seves pròpies limitacions: els índexs únics han d’incloure totes les columnes de partició, els UPDATE que mouen files entre particions/chunks no s’admeten, i els foreign keys de hypertable a hypertable no estan suportats.
    Per tant, la resposta curta és: sí, es pot fer i normalment funciona bé per a lectura, però la clau és que la consulta sigui “shippable” al remot. Si hi poses funcions no built-in, o expressions que l’FDW no pugui enviar, llavors perd pushdown i pot anar molt més lent. Això és una inferència directa del comportament documentat de postgres\_fdw i del fet que Timescale tracta les hypertables com a taules PostgreSQL estàndard per a SELECT.
