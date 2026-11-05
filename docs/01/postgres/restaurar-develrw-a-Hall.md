---
owner: L'Energetica Tech
status: draft
review_date: 2026-10-28
review_period_months: 6
tags:
    - postgresql
    - hall
    - restauracio
    - timescaledb
    - postgres_fdw
---

# Procediment per restaurar a HALL l'esquema `develrw` incloent-hi hypertaules (timescales associats), i taules forànies a `public` de PRO

## En què consisteix

Aquest procediment prepara una base de dades nova a HALL amb l'estructura de
`develrw` i, en un pas posterior, hi copia les dades actuals des de PRO.
Opcionalment, també configura `postgres_fdw` per consultar taules de `public`
a PRO des de HALL, si l'aplicació o les vistes materialitzades ho necessiten:

1. Es crea una BD a HALL amb TimescaleDB habilitat. La configuració de
   `postgres_fdw` i la importació de foreign tables són opcionals i independents
   de la còpia de dades.
2. Es genera un dump SQL de **només l'estructura** de `develrw` des de la BD d'origen
   i es restaura sobre la nova BD. El DDL
   inclou les definicions de les taules normals i les taules que a PRO són
   hypertables, però no les files de dades.
3. L'script versionat [`restore_develrw_data.sh`](../../scripts/postgres/restore_develrw_data.sh)
   copia les dades de les taules
   normals i de les hypertables associades des d'un snapshot consistent de PRO.
4. Es validen les estructures, les hypertables, els recomptes de files i les
   seqüències abans que la BD es consideri preparada.

El DDL no conté les dades ni configura per si sol tota la restauració. Cal
habilitar TimescaleDB i revisar els permisos abans de restaurar-lo. Si cal
consultar dades remotes, també s'han de configurar `postgres_fdw`, el servidor,
el user mapping i les foreign tables. L'script de dades crea les hypertables
de destinació i cal validar-les després.

**Estat:** el DDL de referència i l'script de restauració de dades formen part
d'aquest repositori. Feu servir l'script del mateix checkout que aquesta guia,
no una còpia independent a `/var/backups`. Proveu-lo en una BD descartable
abans d'una restauració operativa. L'script admet reprendre una còpia
interrompuda amb `--resume`; vegeu-ne les instruccions al punt 3.

## Abans de començar

Confirmeu i ajusteu els valors d'exemple abans d'executar ordres:

- Contenidor PostgreSQL: indiqueu l'ID del contenidor que fareu servir per a
  tot el procediment. Als exemples, la variable `CONTENIDOR_POSTGRES` conté
  aquest ID.
- Base de dades d'origen: `energetica`.
- Base de dades de destinació d'exemple: `energetica_develrw`.
- Rol d'origen: `energetica`.
- Fitxer DDL temporal dins del contenidor:
  `/tmp/energetica-develrw-schema-20261028.sql`.

Feu cada restauració en una BD nova i buida. No reutilitzeu una BD amb dades
sense revisar abans el seu estat. No poseu contrasenyes en aquest document,
scripts, ordres visibles, historial ni logs; feu servir els prompts
interactius o el gestor de credencials aprovat.

Abans de començar una restauració, comproveu que les versions de PostgreSQL i
TimescaleDB de destí són compatibles amb les de l'origen. En particular, el
DDL de referència es va generar amb `pg_dump` 15.4 des del contenidor i indica
que l'origen és PostgreSQL 15.4.

Si la BD de destinació ja existeix i està preparada —amb TimescaleDB habilitat
i els permisos necessaris—, podeu ometre el punt 1 i anar directament al punt
2. Només cal configurar `postgres_fdw` si es necessiten consultes a taules
remotes; no és un prerequisit per generar/restaurar el DDL ni per copiar les
dades amb l'script. El punt 2 genera i, després de verificar el fitxer,
restaura el DDL.

## 1. Crear la BD de destinació

### 1.1 Crear la BD buida

Connecteu-vos al PostgreSQL de HALL com a `postgres`, a la BD administrativa
`postgres`, i creeu una BD nova:

```sql
CREATE DATABASE energetica_develrw ENCODING = 'UTF8';
```

Si ja existeix, no repetiu l'ordre: inspeccioneu la BD i confirmeu que es pot
reutilitzar abans de continuar.

### 1.2 Preparar les extensions i els permisos

Connecteu-vos a `energetica_develrw` com a `postgres`. Activeu les extensions
necessàries:

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;
```

No creeu manualment l'esquema `develrw`: el DDL el crearà. Després de restaurar-lo, executeu el pas final de propietat i permisos del
punt 5. Com que el dump es genera amb `--no-owner`, els objectes queden
inicialment propietat del rol que executa la restauració (en l'exemple,
`postgres`). L'script de dades s'executa per defecte com a `postgres` dins del
contenidor i com a rol PostgreSQL `postgres`; el pas final traspassa la
propietat de l'esquema `develrw`, els objectes i els chunks al rol
`energetica`.

### 1.3 Configurar opcionalment `postgres_fdw`

Ometeu aquesta secció si la BD no ha de consultar taules remotes de PRO. La
còpia de dades de `develrw` es connecta directament a PRO i no depèn de FDW.
Si calen les foreign tables, connecteu-vos a `energetica_develrw` com a
`postgres`, activeu l'extensió i doneu al rol local el permís per importar-les:

```sql
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
GRANT CREATE ON SCHEMA public TO energetica;
```

#### 1.3.1 Crear el servidor remot

Com a `postgres`, creeu el servidor remot i doneu-ne ús al rol local:
```sql
CREATE SERVER energetica_pro
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (host '192.168.24.3', dbname 'energetica', port '5432');

GRANT USAGE ON FOREIGN SERVER energetica_pro TO energetica;
```

Creeu el user mapping amb el mecanisme segur de credencials aprovat. No
escriviu la contrasenya com a literal en un fitxer o consulta persistent. Si
el servidor o el mapping ja existeixen, inspeccioneu-los abans de modificar-los
i no els esborreu amb `CASCADE`.

#### 1.3.2 Crear el user mapping

En una sessió interactiva de `psql` connectada com a `postgres` a la BD de
destinació, demaneu la contrasenya sense mostrar-la i passeu-la com a variable
de `psql`:

```psql
\prompt -s 'Contrasenya del rol energetica a PRO: ' fdw_password
CREATE USER MAPPING FOR energetica
SERVER energetica_pro
OPTIONS (user 'energetica', password :'fdw_password');
\unset fdw_password
```

La substitució `:'fdw_password'` cita el valor com a literal SQL. No deseu la
contrasenya en un fitxer ni l'escriviu a la línia d'ordres. Abans d'executar-ho,
assegureu-vos que la configuració de registre del servidor no desi la sentència
amb la contrasenya expandida.

#### 1.3.3 Importar les foreign tables

Importeu les foreign tables necessàries com a rol local `energetica`:

```sql
IMPORT FOREIGN SCHEMA public
FROM SERVER energetica_pro
INTO public;
```

Després de la importació, executeu el pas 5 per transferir-ne la propietat a
`postgres`, conservar només `SELECT` per a `energetica` i retirar-li `CREATE`
a l'esquema `public`. La revocació de privilegis d'escriptura no és suficient
si `energetica` continua sent propietària de les foreign tables.

Consulteu [Configurar postgres_fdw](./configurar-postgres_fdw.md) per als
detalls de connexió, mapatge i verificació de les foreign tables.

## 2. Crear i restaurar el DDL

### 2.1 Crear un dump DDL de l'esquema develrw de PRO

Per assegurar compatibilitat amb la versió i l'entorn PostgreSQL d'origen,
executeu `pg_dump` dins del contenidor PostgreSQL indicat. El dump és en format
SQL pla; per tant, es restaurarà amb `psql`, no amb `pg_restore`. El fitxer es
crea a `/tmp` dins del contenidor i s'hi restaura després, sense copiar-lo al
host.

Des del terminal del host Docker:

```bash
CONTENIDOR_POSTGRES="ID_DEL_CONTENIDOR_POSTGRES"
docker exec -it "$CONTENIDOR_POSTGRES" sh -c '
  set -eu
  umask 077
  pg_dump \
    --password \
    --host=192.168.24.3 \
    --port=5432 \
    --username=energetica \
    --dbname=energetica \
    --schema=develrw \
    --schema-only \
    --no-owner \
    --no-acl \
    --quote-all-identifiers \
    --format=plain \
    --file=/tmp/energetica-develrw-schema-20261028.sql
  chmod 600 /tmp/energetica-develrw-schema-20261028.sql
'
```

Introduïu la contrasenya quan `pg_dump` la demani. No afegiu
`PGPASSWORD=...` a la comanda.

Comproveu, dins del contenidor, que el fitxer existeix, no és buit i no inclou
blocs `COPY` de dades:

```bash
docker exec "$CONTENIDOR_POSTGRES" sh -c '
  set -eu
  fitxer=/tmp/energetica-develrw-schema-20261028.sql
  test -s "$fitxer"
  stat -c "%a %s %n" "$fitxer"
  if grep -n "^COPY " "$fitxer"; then
    echo "ERROR: s'han trobat blocs COPY; reviseu el dump"
    exit 1
  else
    echo "No s'han trobat blocs COPY de dades"
  fi
'
```

Reviseu els avisos de `pg_dump` i les definicions resultants. `--schema=develrw`
selecciona els objectes de l'esquema, però no inclou necessàriament objectes
dels quals depengui `develrw` si aquests són en altres esquemes. Les
extensions que necessitin les definicions s'han d'instal·lar a la BD de
destinació abans de restaurar el DDL.

Hi ha una còpia de referència del dump a
`/home/energetica/var/backups/energetica-develrw-schema-20261028.sql`. S'ha
comprovat que és SQL pla, que l'ha generat `pg_dump` 15.4 i que no conté
línies `COPY`. Aquesta còpia al host és només de referència: el procediment
genera i restaura el fitxer temporal dins del contenidor. Si l'estructura de
PRO canvia, genereu i reviseu un DDL nou; no modifiqueu a mà el dump antic amb
dades.

### 2.2 Restaurar el DDL a Hall

Abans de restaurar, confirmeu que `energetica_develrw` és la BD correcta, que
l'esquema `develrw` encara no existeix i que TimescaleDB hi està habilitat. La
BD ja pot contenir les foreign tables importades a `public`. El dump conté
`CREATE SCHEMA develrw`; no creeu l'esquema prèviament. Feu servir el mateix
contenidor que heu indicat per generar el dump.

Des del terminal del host Docker, executeu:

```bash
CONTENIDOR_POSTGRES="ID_DEL_CONTENIDOR_POSTGRES"
docker exec -it "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d energetica_develrw \
  -f /tmp/energetica-develrw-schema-20261028.sql
```

La variable `CONTENIDOR_POSTGRES` ha de tenir el mateix ID emprat per crear el
dump. L'opció `-f` fa que `psql` llegeixi el fitxer dins del contenidor; no
cal redirigir l'entrada des del host. La connexió es fa des del contenidor al
seu socket local. Amb autenticació local de tipus `peer`, no demanarà
contrasenya. `ON_ERROR_STOP=1` atura `psql` al primer error. Si hi ha un error,
no continueu amb cap càrrega de dades: reviseu l'estat de la BD i resoleu si
cal recrear-la des de zero.

Després de restaurar, comproveu que:

- Existeix l'esquema `develrw` i les taules esperades.
- Les taules normals i les destinades a ser hypertables són buides.
- Columnes, tipus, ordre, índexs, restriccions, seqüències, funcions i triggers
  s'han restaurat correctament.
- Les taules pertanyen al rol que executarà la conversió a hypertables i la
  càrrega, o s'han ajustat explícitament els permisos i propietaris.

No considereu que les taules ja siguin hypertables només perquè el DDL les
hagi creat com a taules: la conversió i la validació TimescaleDB formen part
del pas de càrrega de dades pendent.

## 3. Restaurar les dades

L'script versionat [`restore_develrw_data.sh`](../../scripts/postgres/restore_develrw_data.sh)
copia totes les taules locals ordinàries de `develrw` i les hypertables. Llegeix les taules
des d'un snapshot exportat de PRO, crea les hypertables de destinació amb la
seva columna temporal i interval de chunk, elimina abans el trigger intern
`ts_insert_blocker` que apareix al DDL, actualitza les seqüències i desa els
recomptes de `COPY` en un fitxer TSV.

### Abans d'executar

- Restaureu primer el DDL al destí i comproveu que les taules de `develrw`
  existeixen i són buides. Les foreign tables de `public` poden continuar-hi.
- Confirmeu que les versions principals de PostgreSQL coincideixen i que la
  versió de TimescaleDB és exactament la mateixa als dos costats.
- Confirmeu que el rol de destinació és propietari de les taules i seqüències
  o que té els permisos necessaris. Per defecte s'utilitzen l'usuari del
  contenidor `postgres` i el rol PostgreSQL `postgres`.
- Executeu l'script des d'un host amb `bash`, `psql`, `docker`, `awk` i GNU
  `dd` (Coreutils), amb
  connectivitat a PRO i permisos Docker sobre el contenidor de destinació.
- Planifiqueu una finestra de manteniment. El snapshot evita barrejar instants
  de lectura entre taules, però manté oberta una transacció de lectura a PRO
  durant tota la còpia. En bases grans això pot retardar el vacuum i augmentar
  l'espai necessari. Atureu les escriptures a PRO durant la còpia i la
  validació final sempre que sigui possible.

### Execució

Des del directori arrel del checkout del repositori, indiqueu el contenidor
PostgreSQL i la BD de destinació. També podeu executar-lo des de qualsevol
directori amb el camí relatiu següent. L'script demana interactivament la
contrasenya del rol d'origen `energetica`; no l'escriviu a la comanda:

```bash
./docs/scripts/postgres/restore_develrw_data.sh \
  ID_DEL_CONTENIDOR_POSTGRES energetica_develrw
```

Si una execució s'interromp després d'haver completat algunes taules, inspeccioneu
la destinació i l'informe TSV generat. Si les taules marcades `complete` són
correctes i les pendents continuen buides, es pot reprendre sense tornar a
copiar les completes:

```bash
./docs/scripts/postgres/restore_develrw_data.sh \
  ID_DEL_CONTENIDOR_POSTGRES energetica_develrw \
  --resume develrw_restore_counts_YYYYMMDD_HHMMSS.tsv
```

Feu servir el mateix fitxer d'informe generat per l'execució interrompuda; no
l'editeu per marcar taules com a completes. La represa obre un snapshot nou de
PRO, de manera que les taules pendents poden contenir dades més recents que les
ja copiades. No garanteix coherència temporal estricta. El preflight rebutja
taules pendents que ja continguin dades. Si l'error es produeix després de
començar la còpia d'una taula però abans que quedi anotada com a `complete`,
inspeccioneu-la: si és parcial, no reprengueu sense resoldre el seu estat.

Si totes les taules consten com a completes però la sincronització de
seqüències ha fallat, torneu a executar el mode `--resume` amb el mateix
informe: l'script omet les taules completes i continua amb les seqüències.
Abans de reprendre, comproveu que hi ha espai suficient per a les dades
pendents.

Per canviar els valors per defecte, definiu variables d'entorn abans
d'executar-lo, per exemple `SOURCE_HOST`, `SOURCE_PORT`, `SOURCE_USER`,
`SOURCE_DB`, `DEST_USER` i `DEST_DOCKER_USER`. La destinació per defecte és
`energetica_develrw`; el host d'origen per defecte és `192.168.24.3`.
`DEST_DOCKER_USER` és l'usuari del sistema operatiu dins del contenidor;
`DEST_USER` és el rol PostgreSQL.

L'script informa de l'etapa actual, del progrés de les comprovacions i de cada
taula. Durant cada còpia, `dd status=progress` mostra periòdicament els bytes
transferits i el temps transcorregut; quan acaba una taula, s'imprimeix el
recompte de files. Abans de modificar dades demana escriure exactament
`RESTORE develrw` en una execució inicial o `RESUME develrw` en una represa.
Manteniu el terminal obert i no interrompeu el procés si continua mostrant
progrés.

L'script comprova versions, llista de taules, definicions de columnes,
hypertables i que les taules locals de destí siguin buides (o bé, en mode de
represa, que les completes tinguin dades i les pendents continuïn buides).
Rebutja claus foranes a `develrw`, dimensions addicionals i intervals de
calendari perquè aquests casos requereixen una estratègia de càrrega diferent.

Si hi ha un error després de començar la creació de hypertables o la còpia,
el destí pot quedar parcialment carregat. Inspeccioneu l'estat i seguiu les
condicions de represa d'aquest apartat abans de tornar a executar l'script.
Les xifres de `COPY` i els estats de seqüències es guarden en un TSV amb
permisos restringits al directori des d'on s'executa l'script. Els valors de
seqüència es llegeixen després de la còpia i, per tant, no formen part del
snapshot MVCC de les taules. El TSV registra també les vistes materialitzades
de PRO i si caldrà refrescar-les.

No considereu completa la restauració fins a comparar els recomptes amb PRO i
verificar les hypertables, les seqüències, la compressió, els permisos, les
vistes materialitzades i la resta de comprovacions dels punts 4–7.

## 4. Aplicar compressió i polítiques de PRO (TimescaleDB 2.11)

Després de copiar les dades, executeu les ordres següents a la BD de
destinació com a `postgres`. Això reprodueix les opcions de compressió de PRO
a les sis hypertables i les cinc polítiques programades. `apigisce_tgp1_old`
té la compressió activada a PRO però no té política, i per tant no se n'hi
afegeix cap.

| Hypertable | Segmentació | Ordenació | Comprimir després de | Freqüència |
|---|---|---|---|---|
| `apigisce_adjunts_factura` | `cups, tipus` | `timestamp DESC NULLS FIRST` | 14 dies | 3 dies 12 hores |
| `apigisce_tgcchfact` | `cups` | `timestamp DESC NULLS FIRST` | 14 dies | 3 dies 12 hores |
| `apigisce_tgcchval` | `cups` | `timestamp DESC NULLS FIRST` | 14 dies | 3 dies 12 hores |
| `apigisce_tgf1` | `cups, type` | `timestamp DESC NULLS FIRST` | 14 dies | 3 dies 12 hores |
| `apigisce_tgp1_old` | `cups` | `timestamp DESC` | — (PRO no té política) | — |
| `ree_simel_epfpfqh` | — | `timestamp DESC NULLS FIRST` | 120 dies | 3 dies 12 hores |

??? info "Consultes SQL per aplicar les polítiques de compressió"
    ```sql
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
    ```

    Les crides `add_compression_policy` són idempotents si ja existeix la política
    perquè fan servir `if_not_exists`; verifiqueu que la configuració existent sigui
    la desitjada. Les polítiques poden comprimir chunks elegibles immediatament:
    vigileu l'espai de disc i la càrrega.

## 5. Aplicar la propietat i els permisos finals

Executeu aquest pas obligatòriament després de restaurar el DDL, copiar les
dades, crear les hypertables i configurar la compressió i les seves polítiques.
El DDL i l'script de dades s'executen com a `postgres`; aquest pas deixa
`develrw`, els seus objectes i els chunks de TimescaleDB a nom d'`energetica`.
Les ordres `ALTER` es generen i s'executen individualment amb `\gexec`, en lloc
d'una transacció massiva, per evitar exhaurir els locks.

Executeu al host Docker amb el contenidor i la BD de destinació correctes:

```bash
CONTENIDOR_POSTGRES="ID_DEL_CONTENIDOR_POSTGRES"
docker exec -i "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d energetica_develrw <<'SQL'
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
SQL
```

En canviar el propietari de les taules amb seqüències `serial` o `identity`,
PostgreSQL actualitza també la propietat de les seqüències vinculades. La
segona consulta només canvia seqüències independents. Canviar el propietari
d'una hypertable també actualitza els seus chunks; no canvieu cada chunk en
una transacció massiva.

La importació de foreign tables s'ha fet com a `energetica`; per això no n'hi
ha prou amb revocar privilegis d'escriptura: un propietari sempre conserva
capacitat d'escriure. El bloc anterior les traspassa a `postgres`, conserva
només `SELECT` per a `energetica` i elimina `CREATE` a `public`. Si s'importen
més foreign tables en el futur, repetiu aquest pas.

A PRO hi ha un privilegi per defecte que concedeix `SELECT` a `energetica`
sobre taules noves creades per `erp` a `public`. Si a HALL existeix el rol
`erp` i aquest rol crearà objectes locals nous a `public`, podeu replicar-lo:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE erp IN SCHEMA public
GRANT SELECT ON TABLES TO energetica;
```

Aquest privilegi per defecte no substitueix el pas de propietat/read-only de
les foreign tables importades. Verifiqueu els permisos finals amb
`has_schema_privilege`, `has_table_privilege` i `pg_get_userbyid(relowner)`
abans d'habilitar l'aplicació.

## 6. Refrescar les vistes materialitzades

L'informe TSV indica que 15 vistes materialitzades eren poblades a PRO i 5 no
ho eren: `factures_dia_mv`, `factures_validar`, `inventari_cups_qh_mv`,
`mvqh_mensual` i `pig_factures_qh_mv`. El script següent refresca només les 15
poblades; les cinc `source_unpopulated` es deixen sense poblar per reproduir
l'estat de PRO.
Executeu-lo després del pas 5, quan `energetica` ja sigui propietària de les
vistes i tingui accés de lectura a les foreign tables necessàries.

El script consulta `pg_depend` i segueix també les vistes normals que
intervinguin entre dues vistes materialitzades. Així refresca primer les
dependències i després les dependents, sense haver de fixar manualment un ordre.
Les dependències dinàmiques dins de funcions no es poden deduir d'aquests
catàlegs; si una definició utilitza SQL dinàmic, reviseu-ne l'ordre a mà.

```bash
CONTENIDOR_POSTGRES="ID_DEL_CONTENIDOR_POSTGRES"
docker exec -i "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d energetica_develrw <<'SQL'
\set ON_ERROR_STOP on
SET ROLE energetica;

DO $check$
DECLARE
    expected_count integer := 15;
    actual_count integer;
BEGIN
    SELECT count(*) INTO actual_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'develrw'
      AND c.relkind = 'm'
      AND c.relname = ANY (ARRAY[
          'apigisce_curve_factura_mv',
          'apigisce_perfilats_distri_mv',
          'ene_preus_mv',
          'factures_mes_mv',
          'mvqh_rep_mv',
          'pig_base_mv',
          'pig_estat_factura_mv',
          'pig_estat_factures_mv',
          'pig_factures_erp_mv',
          'pig_factures_mes_mv',
          'pig_petar_mv',
          'pig_preus_c2_mv',
          'pig_preus_mv',
          'pig_reganecu_mv',
          'ree_brp_mv'
      ]::name[]);
    IF actual_count <> expected_count THEN
        RAISE EXCEPTION 'Expected % source-populated materialized views, found %',
            expected_count, actual_count;
    END IF;
END;
$check$;

WITH RECURSIVE target_mvs AS (
    SELECT c.oid, n.nspname, c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'develrw'
      AND c.relkind = 'm'
      AND c.relname = ANY (ARRAY[
          'apigisce_curve_factura_mv',
          'apigisce_perfilats_distri_mv',
          'ene_preus_mv',
          'factures_mes_mv',
          'mvqh_rep_mv',
          'pig_base_mv',
          'pig_estat_factura_mv',
          'pig_estat_factures_mv',
          'pig_factures_erp_mv',
          'pig_factures_mes_mv',
          'pig_petar_mv',
          'pig_preus_c2_mv',
          'pig_preus_mv',
          'pig_reganecu_mv',
          'ree_brp_mv'
      ]::name[])
),
view_refs(root_oid, ref_oid, path) AS (
    SELECT t.oid, d.refobjid, ARRAY[t.oid, d.refobjid]::oid[]
    FROM target_mvs t
    JOIN pg_rewrite rw
      ON rw.ev_class = t.oid AND rw.rulename = '_RETURN'
    JOIN pg_depend d
      ON d.classid = 'pg_rewrite'::regclass
     AND d.objid = rw.oid
     AND d.refclassid = 'pg_class'::regclass
    JOIN pg_class ref ON ref.oid = d.refobjid
    WHERE ref.relkind IN ('v', 'm')
      AND d.refobjid <> t.oid

    UNION ALL

    SELECT vr.root_oid, d.refobjid, vr.path || d.refobjid
    FROM view_refs vr
    JOIN pg_class current_view
      ON current_view.oid = vr.ref_oid AND current_view.relkind = 'v'
    JOIN pg_rewrite rw
      ON rw.ev_class = current_view.oid AND rw.rulename = '_RETURN'
    JOIN pg_depend d
      ON d.classid = 'pg_rewrite'::regclass
     AND d.objid = rw.oid
     AND d.refclassid = 'pg_class'::regclass
    JOIN pg_class ref ON ref.oid = d.refobjid
    WHERE ref.relkind IN ('v', 'm')
      AND NOT d.refobjid = ANY (vr.path)
),
mv_edges AS (
    SELECT DISTINCT vr.root_oid AS dependent_oid, vr.ref_oid AS dependency_oid
    FROM view_refs vr
    JOIN pg_class dependency ON dependency.oid = vr.ref_oid
    JOIN target_mvs target_dependency ON target_dependency.oid = dependency.oid
    WHERE dependency.relkind = 'm'
      AND vr.root_oid <> vr.ref_oid
),
dependency_walk(root_oid, current_oid, depth, path) AS (
    SELECT oid, oid, 0, ARRAY[oid]::oid[]
    FROM target_mvs

    UNION ALL

    SELECT w.root_oid, e.dependency_oid, w.depth + 1, w.path || e.dependency_oid
    FROM dependency_walk w
    JOIN mv_edges e ON e.dependent_oid = w.current_oid
    WHERE NOT e.dependency_oid = ANY (w.path)
),
depths AS (
    SELECT root_oid, max(depth) AS dependency_depth
    FROM dependency_walk
    GROUP BY root_oid
)
SELECT format('REFRESH MATERIALIZED VIEW %I.%I;', t.nspname, t.relname)
FROM target_mvs t
JOIN depths d ON d.root_oid = t.oid
ORDER BY d.dependency_depth, t.relname
\gexec

RESET ROLE;
SQL
```

Els `REFRESH` es fan sense `CONCURRENTLY`: així funcionen també amb vistes
acabades de crear i buides. El procés requereix espai temporal suficient i pot
carregar PRO si les vistes consulten foreign tables. Com que les foreign tables
llegeixen PRO en temps real i la còpia local prové d'un snapshot anterior, no
hi ha garantia que el resultat sigui un snapshot globalment consistent. Si es
requereix coherència estricta, atureu les escriptures a PRO durant la còpia i
els refrescos, o coordineu explícitament els punts de tall.

## 7. Verificar la restauració

Quan l'script de dades hagi acabat, compareu PRO i HALL:

- Recompte exacte de files per taula, anotant l'hora de cada lectura.
- Llista i registre de les hypertables a `timescaledb_information.hypertables`.
- Opcions de compressió i polítiques a `timescaledb_information.hypertables`,
  `timescaledb_information.compression_settings` i
  `timescaledb_information.jobs`; han de coincidir amb el pas 4.
- Columnes, tipus, ordre, índexs i restriccions.
- Estat de seqüències i valors per defecte.
- Estat de les 20 vistes materialitzades: les 15 que eren poblades a PRO han
  d'estar poblades després del pas 6; les 5 que eren buides a PRO continuen
  sense poblar.
- Rang temporal de les hypertables i una consulta representativa de l'aplicació.
- Propietari `energetica` de l'esquema `develrw`, les taules, les vistes, les
  vistes materialitzades, les seqüències i els chunks.
- A `public`, `energetica` té `USAGE` però no `CREATE`; conserva `SELECT` a les
  foreign tables, no n'és propietària i no hi té privilegis d'escriptura.
- Errors, avisos i resultats parcials als logs.

Si hi ha escriptures actives durant la validació, els recomptes de dues lectures
seqüencials poden diferir per dades noves. Per a una comparació rigorosa,
utilitzeu un snapshot comú o atureu les escriptures durant la còpia i la
validació.

No esborreu manualment dades ni marcadors per forçar una represa. Si una
execució queda interrompuda, inspeccioneu els resultats i repreneu-la només
seguint les condicions del punt 3. Si no podeu verificar quines taules han
acabat o n'hi ha de parcialment copiades, feu servir una BD descartable nova
per repetir la restauració.

## 8. Programar còpies de seguretat a Databasus (opcional)

Decidiu amb la persona responsable si la BD nova s'ha d'incloure a Databasus.
Abans de configurar-la:

- Comproveu si el rol de clúster `databasus` ja existeix; a HALL ja existeix i
  no s'ha de crear de nou.
- Doneu-li només accés de lectura necessari a la BD nova i a les seves taules.
- Si cal crear el rol en un clúster nou, establiu la contrasenya
  interactivament amb `\password databasus`; no la deseu en aquest document.
- Configureu i proveu una còpia de seguretat segons la retenció i el destí
  establerts per l'equip.

Les foreign tables són referències a dades remotes, no una còpia local de les
dades de PRO. No activeu còpia de dades estrangeres sense haver-ne validat
l'impacte i les credencials. Documenteu els user mappings al gestor de secrets,
no en aquest fitxer.
