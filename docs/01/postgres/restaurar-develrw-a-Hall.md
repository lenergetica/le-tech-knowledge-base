---
title: "Restaurar develrw de PRO a HALL amb TimescaleDB i accés FDW a public"
author: "joseantonioarias"
reviewed_by: "joseantonioarias"
owner: "Equip de Tecnologia de L'Energètica"
status: "draft"
version: "1.0"
creation_date: "2026-11-03"
review_date: "2026-11-05"
review_after_months: 60
tags:
    - "postgresql"
    - "hall"
    - "restauracio"
    - "timescaledb"
    - "postgres_fdw"
    - "runbook"
references:
    - "./configurar-postgres_fdw.md"
    - "../../scripts/postgres/restore_develrw_data.sh"
    - "../../scripts/postgres/compress_develrw_20261028.sql"
---

# Restaurar `develrw` de PRO a HALL amb TimescaleDB i accés FDW a `public`

Aquest procediment copia l'estructura i les dades de `develrw` de PRO a una
BD nova de HALL. Les taules foranes de `public` permeten consultar PRO en directe;
les seves dades no es copien a HALL.

1. Crear la BD i habilitar TimescaleDB.
2. Configurar FDW, importar `public` i limitar-ne els permisos locals a lectura.
3. Generar i restaurar el DDL de `develrw`.
4. Copiar les dades i crear les hypertables amb un snapshot de PRO.
5. Aplicar la configuració de compressió contrastada amb PRO.
6. Traspassar la propietat de `develrw` a `energetica`.
7. Refrescar les vistes materialitzades segons l'informe de càrrega i executar `ANALYZE`.
8. Verificar la restauració.
9. Programar còpies de seguretat.

## Abans de començar

Les ordres de terminal s'executen **al host Docker, des de l'arrel d'aquest
repositori**. Els blocs SQL indiquen la BD i el rol amb què s'han d'executar.
Ajusteu aquests valors i manteniu el mateix terminal durant el procediment:

```bash
CONTENIDOR_POSTGRES="ID_DEL_CONTENIDOR_POSTGRES"  # PostgreSQL de HALL
BD_DESTI="energetica_develrw"
FITXER_DDL="/tmp/energetica-develrw-schema-$(date +%Y%m%d_%H%M%S).sql"
```

- Origen: `energetica@192.168.24.3:5432/energetica` (PRO).
- Destinació: el socket local del contenidor de HALL, amb rol PostgreSQL
  `postgres` i usuari del sistema operatiu `postgres` (`docker exec --user postgres`).
- El rol local `energetica` ha d'existir i no ha de ser superusuari ni heretar
  privilegis que permetin escriure a les taules foranes. Si falta, creeu-lo com a
  `postgres` amb `CREATE ROLE energetica LOGIN` i establiu-ne la contrasenya amb
  `\password energetica` en una sessió interactiva.
- Host: Bash 4 o superior, `psql`, `docker`, `awk` i GNU `dd`, amb permisos Docker.
  El host i el contenidor han de poder connectar-se a PRO; FDW es connecta des
  del servidor PostgreSQL de HALL.
- PostgreSQL ha de tenir la mateixa versió principal als dos costats i
  TimescaleDB la mateixa versió exacta. Les consultes i la plantilla de
  compressió d'aquest document estan preparades per a TimescaleDB 2.11.
  Comproveu també que el `pg_dump` del contenidor pot llegir la versió de PRO.
- Reserveu espai per a dades, índexs, operacions de compressió i refrescos.
  Reviseu les dependències de `develrw` en altres esquemes i les extensions
  necessàries abans de restaurar el DDL.
- No feu canvis de DDL a PRO des de la generació del dump fins al final de la
  càrrega. El preflight comprova inventaris i columnes, però no totes les
  definicions de funcions, índexs, triggers i vistes.
- El snapshot manté una transacció oberta durant la còpia i pot retardar el
  vacuum a PRO. Si cal coherència entre dades locals i consultes FDW, atureu les
  escriptures abans de la còpia i manteniu l'aturada fins al final dels refrescos
  i la validació. Una represa obre un snapshot nou.

!!! warning "Seguretat i contrasenyes"
    Feu la restauració en una BD nova, sense dades ni esquema `develrw`.
    Una BD només preparada amb extensions i FDW pot continuar al pas 3 després
    de verificar-ne la configuració. No poseu contrasenyes en fitxers,
    arguments de comandes, historial ni logs. Feu servir l'entrada oculta dels
    scripts o el gestor de credencials aprovat.

Per comprovar versions, executeu a cada BD:

```sql
SELECT current_database(), current_user, version();
SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';
```

## 1. Crear la BD de destinació

Com a `postgres`, connectat a la BD administrativa `postgres` de HALL:

```sql
CREATE DATABASE energetica_develrw ENCODING = 'UTF8';
```

El nom ha de coincidir amb `BD_DESTI`. Si la BD ja existeix, inspeccioneu-la
abans de continuar. Connecteu-vos a la BD nova com a `postgres`:

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;
```

No creeu `develrw`: el DDL el crearà. Els objectes es restauraran inicialment
com a `postgres` perquè el dump s'obté amb `--no-owner`.

## 2. Configurar FDW i importar les taules foranes

### 2.1 Crear l'extensió i el servidor

A la BD de destinació, com a `postgres`:

```sql
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SERVER energetica_pro
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (host '192.168.24.3', dbname 'energetica', port '5432');
GRANT USAGE ON FOREIGN SERVER energetica_pro TO energetica;
GRANT USAGE, CREATE ON SCHEMA public TO energetica;
```

Si el servidor o el mapping ja existeixen, inspeccioneu-los abans de
modificar-los. No els esborreu amb `CASCADE`.

### 2.2 Crear el mapping amb entrada oculta

Abans d'executar aquest pas, confirmeu que el registre SQL del servidor i les
eines d'auditoria no desaran la sentència amb la contrasenya. El
[script de mapping](../../scripts/postgres/configure_develrw_fdw_mapping.sh)
la demana amb `read -s` i envia el SQL per l'entrada estàndard, sense arguments
amb secrets ni fitxers temporals. No l'executeu amb traça del shell o del terminal.
La credencial quedarà emmagatzemada al catàleg del mapping de PostgreSQL.

```bash
./docs/scripts/postgres/configure_develrw_fdw_mapping.sh \
  "$CONTENIDOR_POSTGRES" "$BD_DESTI"
```

`psql` 15 no té una opció `\prompt -s` per ocultar l'entrada.

### 2.3 Importar i limitar els permisos

A la BD de destinació, en una sessió de `psql` com a `postgres`:

```sql
SET ROLE energetica;
IMPORT FOREIGN SCHEMA public FROM SERVER energetica_pro INTO public;
RESET ROLE;
```

Tot seguit, executeu el
[SQL de permisos FDW](../../scripts/postgres/configure_develrw_fdw_permissions.sql):

```bash
docker exec -i --user postgres "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d "$BD_DESTI" \
  < docs/scripts/postgres/configure_develrw_fdw_permissions.sql
```

Aquest pas traspassa a `postgres` les taules foranes de `public`, concedeix
`SELECT` a `energetica`, revoca els privilegis directes d'escriptura i li retira
`CREATE` a `public`. Cal repetir-lo després de noves importacions. Verifiqueu
els privilegis efectius al pas 8: els permisos heretats també compten.

La [guia general de FDW](./configurar-postgres_fdw.md) explica la connexió i
les consultes. Per a aquesta restauració, seguiu l'ordre i els permisos d'aquest
document; no creeu `develrw` manualment.

## 3. Generar i restaurar el DDL

### 3.1 Generar el dump a partir de PRO

El fitxer SQL pla es crea dins del contenidor de HALL i es restaura amb `psql`.
`pg_dump` demana la contrasenya de PRO interactivament:

```bash
docker exec -it --user postgres "$CONTENIDOR_POSTGRES" sh -c '
  set -eu
  umask 077
  pg_dump --password --host=192.168.24.3 --port=5432 \
    --username=energetica --dbname=energetica \
    --schema=develrw --schema-only --no-owner --no-acl \
    --quote-all-identifiers --format=plain --file="$1"
  chmod 600 "$1"
' sh "$FITXER_DDL"
```

Comproveu el fitxer sense copiar-lo al host:

```bash
docker exec --user postgres "$CONTENIDOR_POSTGRES" sh -c '
  set -eu
  test -s "$1"
  stat -c "%a %s %n" "$1"
  if grep -n "^COPY " "$1"; then
    echo "ERROR: el dump conté blocs COPY" >&2
    exit 1
  fi
  echo "Comprovació correcta: fitxer no buit i sense blocs COPY"
' sh "$FITXER_DDL"
```

Reviseu els avisos de `pg_dump` i les definicions. L'absència de `COPY` és una
comprovació auxiliar: `--schema-only` és l'opció que exclou les dades.
`--schema=develrw` no inclou necessàriament les dependències d'altres esquemes.

La còpia `/home/energetica/var/backups/energetica-develrw-schema-20261028.sql`
és una referència històrica generada amb `pg_dump` 15.4 sobre PostgreSQL 15.4.
No substitueix el dump nou ni acredita les versions actuals.

### 3.2 Restaurar a HALL

Confirmeu que la BD és la correcta, que TimescaleDB està habilitat i que
`develrw` encara no existeix; les taules foranes de `public` sí que poden existir.

```bash
docker exec -it --user postgres "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d "$BD_DESTI" -f "$FITXER_DDL"
```

La connexió usa el socket local. Amb `peer`, l'usuari del sistema `postgres`
coincideix amb el rol sol·licitat, llevat que hi hagi un mapatge específic.
`ON_ERROR_STOP` atura el procés al primer error, però no desfà ordres anteriors.
Si falla, inspeccioneu la BD abans de decidir si cal recrear-la.

Verifiqueu que existeixen els objectes esperats, amb les taules buides i les
definicions de columnes, índexs, restriccions, seqüències, funcions i triggers
correctes. Les taules destinades a ser hypertables encara són taules ordinàries;
la conversió es fa al pas 4.

## 4. Copiar les dades

L'[script de càrrega](../../scripts/postgres/restore_develrw_data.sh) llegeix
les taules locals de `develrw` des d'un snapshot exportat de PRO. Elimina el
trigger intern `ts_insert_blocker` abans de crear les hypertables, conserva la
columna temporal i l'interval de chunk, copia les dades i sincronitza les
seqüències. Rebutja claus foranes, dimensions addicionals i intervals de calendari.

```bash
./docs/scripts/postgres/restore_develrw_data.sh \
  "$CONTENIDOR_POSTGRES" "$BD_DESTI"
```

L'script demana la contrasenya de PRO i la confirmació `RESTORE develrw`.
Mostra progrés amb `dd` i desa un TSV amb permisos restringits al directori
actual. **Conserveu el camí de l'informe** i assigneu-lo per als passos següents:

```bash
INFORME="develrw_restore_counts_YYYYMMDD_HHMMSS.tsv"  # Nom real generat
```

El TSV registra recomptes de `COPY`, estats de seqüències i quines vistes
materialitzades estaven poblades a PRO. Les seqüències es llegeixen després de
la còpia i no formen part del snapshot de dades.

Els valors per defecte es poden ajustar amb `SOURCE_HOST`, `SOURCE_PORT`,
`SOURCE_USER`, `SOURCE_DB`, `DEST_USER` i `DEST_DOCKER_USER`. Per defecte són els
valors d'aquest document; la BD per defecte és `energetica_develrw`, però aquí
s'indica sempre explícitament. `DEST_DOCKER_USER` és l'usuari del sistema i
`DEST_USER` el rol PostgreSQL. Si canvieu els rols, reviseu també els SQL dels
passos posteriors, que utilitzen `postgres` i `energetica`.

### Si la càrrega s'interromp

Només reprengueu si podeu verificar que:

- El TSV correspon a aquesta BD i conté almenys una taula `complete`.
- Les taules completes tenen exactament el recompte registrat; el preflight
  només comprova si són buides o contenen dades, no el recompte exacte.
- Les taules pendents són buides i totes les hypertables ja estan creades.
- Les vistes materialitzades encara estan sense poblar i l'estructura de PRO
  no ha canviat. Si n'ha canviat l'estat de població, reviseu el TSV abans de
  continuar; la represa no n'actualitza les entrades.

```bash
./docs/scripts/postgres/restore_develrw_data.sh \
  "$CONTENIDOR_POSTGRES" "$BD_DESTI" --resume "$INFORME"
```

La confirmació és `RESUME develrw`. La represa usa un snapshot nou: pot barrejar
moments diferents entre taules si PRO ha canviat. També permet repetir la
sincronització de seqüències quan totes les taules ja estan completes.

Si la interrupció ha deixat hypertables sense crear, taules pendents amb dades
o un estat que no podeu verificar, repetiu la restauració en una BD nova. No
esborreu dades ni editeu marcadors `complete` per forçar una represa.

## 5. Aplicar la compressió contrastada amb PRO

La càrrega no trasllada la configuració de compressió ni els jobs. Obteniu
l'inventari actual amb el
[SQL d'inspecció TimescaleDB](../../scripts/postgres/inspect_develrw_timescale.sql),
executat tant a PRO com a HALL. Exemple de lectura a PRO:

```bash
psql -X -W -v ON_ERROR_STOP=1 -h 192.168.24.3 -p 5432 \
  -U energetica -d energetica \
  -f docs/scripts/postgres/inspect_develrw_timescale.sql
```

La plantilla [compress_develrw_20261028.sql](../../scripts/postgres/compress_develrw_20261028.sql)
reprodueix la **referència del 2026-10-28 per a TimescaleDB 2.11**:

| Hypertable | Segmentació | Ordenació | Comprimir després de | Freqüència |
|---|---|---|---|---|
| `apigisce_adjunts_factura` | `cups, tipus` | `timestamp DESC NULLS FIRST` | 14 dies | 3 dies 12 hores |
| `apigisce_tgcchfact` | `cups` | `timestamp DESC NULLS FIRST` | 14 dies | 3 dies 12 hores |
| `apigisce_tgcchval` | `cups` | `timestamp DESC NULLS FIRST` | 14 dies | 3 dies 12 hores |
| `apigisce_tgf1` | `cups, type` | `timestamp DESC NULLS FIRST` | 14 dies | 3 dies 12 hores |
| `apigisce_tgp1_old` | `cups` | `timestamp DESC NULLS FIRST` | Sense política | — |
| `ree_simel_epfpfqh` | — | `timestamp DESC NULLS FIRST` | 120 dies | 3 dies 12 hores |

Executeu-la **només si l'inventari actual de PRO coincideix**. Si difereix,
prepareu i reviseu una configuració actualitzada abans de continuar:

```bash
docker exec -i --user postgres "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d "$BD_DESTI" \
  < docs/scripts/postgres/compress_develrw_20261028.sql
```

`if_not_exists` evita duplicar polítiques, però no corregeix una configuració
existent diferent. Reviseu també propietaris i altres jobs que apareguin a PRO;
la plantilla només aplica aquestes cinc polítiques de compressió. Poden començar
a comprimir immediatament: vigileu l'espai i la càrrega. Activar la compressió
no reprodueix instantàniament l'estat físic dels chunks de PRO.

## 6. Aplicar la propietat final de `develrw`

Després de la càrrega i la compressió, executeu el
[SQL de propietat](../../scripts/postgres/finalize_develrw_ownership.sql):

```bash
docker exec -i --user postgres "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d "$BD_DESTI" \
  < docs/scripts/postgres/finalize_develrw_ownership.sql
```

Traspassa a `energetica` l'esquema, les taules, les vistes, les vistes
materialitzades, les seqüències, les rutines i els tipus propis independents.
Exclou els objectes de rutines i tipus que pertanyen a extensions. PostgreSQL
propaga la propietat a les seqüències vinculades i TimescaleDB als chunks.
Els `ALTER` s'executen individualment amb `\gexec` per limitar els locks; no
embolcalleu tot el fitxer en una transacció.

Reviseu les funcions `SECURITY DEFINER`: canviar-ne el propietari també canvia
el rol amb què s'executen. Els permisos de `public` ja s'han aplicat al pas 2.3.

## 7. Refrescar les vistes materialitzades i actualitzar estadístiques

L'[script de refresc](../../scripts/postgres/restore_develrw_matviews.sh)
llegeix l'inventari i l'estat de població del TSV, sense llistes fixes:

```bash
./docs/scripts/postgres/restore_develrw_matviews.sh \
  "$CONTENIDOR_POSTGRES" "$BD_DESTI" "$INFORME"
```

Abans de refrescar, comprova l'inventari complet de taules i vistes
materialitzades i els recomptes exactes de les taules respecte del TSV. Executa
`ANALYZE` sobre les taules locals, refresca com a `energetica` només les vistes
que estaven poblades a PRO i n'actualitza les estadístiques. Les que estaven
sense poblar es mantenen així. «Sense poblar» no equival a «poblada amb zero files».

El [SQL de refresc](../../scripts/postgres/refresh_develrw_matviews.sql) ordena
les dependències declarades a `pg_depend`, incloses les vistes normals
intermèdies. Reviseu manualment les dependències dins de funcions, SQL dinàmic
o altres esquemes, que poden requerir preparació addicional.

Els refrescos es fan sense `CONCURRENTLY`, també vàlids per a vistes encara
sense poblar. Poden requerir molt espai temporal i generar càrrega a PRO per
FDW. Les dades FDW són actuals i no comparteixen el snapshot de la còpia local.
La referència històrica tenia 15 vistes poblades i 5 sense poblar; el criteri
operatiu és sempre el TSV d'aquesta execució.

## 8. Verificar la restauració

Manteniu HALL sense escriptures d'aplicació fins a completar les comprovacions.
Valideu de nou inventaris, recomptes i estat de població, sense refrescar:

```bash
./docs/scripts/postgres/restore_develrw_matviews.sh \
  "$CONTENIDOR_POSTGRES" "$BD_DESTI" "$INFORME" --check-only

docker exec -i --user postgres "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d "$BD_DESTI" \
  < docs/scripts/postgres/verify_develrw_restore.sql

docker exec -i --user postgres "$CONTENIDOR_POSTGRES" \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d "$BD_DESTI" \
  < docs/scripts/postgres/inspect_develrw_timescale.sql
```

El [SQL de verificació](../../scripts/postgres/verify_develrw_restore.sql) és de
diagnòstic: cal revisar-ne la sortida, encara que `psql` acabi correctament.

| Comprovació | Resultat esperat |
|---|---|
| Propietaris de `develrw`, relacions, seqüències, rutines, tipus propis i chunks | Zero discrepàncies respecte d'`energetica` |
| Permisos efectius de `public` | `USAGE = true`, `CREATE = false`; zero taules foranes amb propietat o privilegis incorrectes |
| Seqüències | `last_value:is_called` coincideix amb l'última entrada de cada seqüència al TSV |
| Vistes materialitzades | Inventari i `relispopulated` coincideixen amb el TSV |
| Hypertables i dimensions | Inventari, columna temporal i interval coincideixen amb PRO |
| Compressió i jobs | Coincideixen amb la configuració contrastada del pas 5; propietaris i execució revisats |

Completeu la revisió amb les definicions de columnes, valors per defecte,
índexs, restriccions, funcions i triggers; els rangs temporals de les hypertables;
una consulta representativa de l'aplicació com a `energetica`; i els errors o
avisos de cada etapa. Si detecteu permisos heretats inesperats, resoleu-los abans
d'habilitar l'aplicació.

Els recomptes del TSV corresponen a les dades copiades. Una consulta al PRO
actual pot donar un altre recompte si hi ha escriptures. Per comparar directament
PRO i HALL, manteniu l'aturada d'escriptures des d'abans de la còpia fins a la
validació; anotar l'hora no substitueix aquesta garantia. El snapshot de l'script
es tanca en acabar i no es pot reutilitzar a posteriori ni aplicar a HALL.

Conserveu el TSV, l'inventari de PRO i els resultats de verificació com a evidència
de la restauració, sense credencials.

## 9. Programar còpies de seguretat

Veure [Operació Barman Hall](./operacio-barman-hall.md).
