---
title: "Annex operatiu dels accessos PostgreSQL a HALL"
author: "L'Energètica"
reviewed_by: "L'Energètica"
owner: "Equip de Tecnologia de L'Energètica"
status: "active"
version: "1.0"
creation_date: "2026-11-17"
review_date: "2026-11-18"
review_after_months: 60
tags:
  - "postgresql"
  - "hall"
  - "permisos"
references:
  - "https://www.postgresql.org/docs/15/sql-alterrole.html"
  - "https://www.postgresql.org/docs/15/sql-alterusermapping.html"
---

# Annex operatiu dels accessos PostgreSQL a HALL

Material de manteniment de la [guia d'estat actual](usuaris-perfils-hall.md).
Les instruccions d'aquesta pàgina són referència per a futures operacions;
no descriuen canvis pendents d'executar automàticament.

!!! warning "La configuració inicial ja està aplicada"
    No tornar a executar els scripts de creació sobre els comptes, perfils
    o mappings existents. Revisar-ne l'abast, dependències i transaccions abans
    d'adaptar-los a una alta o canvi concret. No incloure contrasenyes reals
    a la KB ni als repositoris.

## Comandes d’alta i verificació de referència

### 1. Perfils i comptes

Revisar l'[SQL de perfils i usuaris](../../scripts/postgres/configure_hall_user_profiles.sql)
i executar-lo amb `psql`, com a `postgres`, a HALL, BD `energetica`. El fitxer
inclou els onze logins personals i els dos comptes de servei proposats.
També estableix el rol actiu per defecte dels vuit comptes administradors.

```text
\i /home/energetica/le-tech-knowledge-base/docs/scripts/postgres/configure_hall_user_profiles.sql
```

La ruta és des del client `psql`; si s'executa dins d'un contenidor, cal aportar
el fitxer per entrada estàndard o copiar-lo prèviament al contenidor. Els rols
de perfil han de ser nous: l'script no és idempotent. Si hi ha un error abans
del COMMIT, la transacció no s'aplica.

Els comptes nous es creen sense contrasenya. Els existents es reutilitzen
només si tenen atributs compatibles, sense canviar-ne la contrasenya. L'script
retira als cinc usuaris de dades les assignacions directes d'`energetica` i
`develrw_admin`, i comprova que no conservin permisos de creació, propietat de
relacions o TRUNCATE a `develrw`. Si falla, cal revisar les assignacions
heretades o propietats; no es reassignen automàticament.

Establir interactivament la contrasenya de cada compte nou; per exemple:

```text
\password juliaperona
\password svc_energetica_etl
```

Repetir-ho per a la resta de comptes nous. No desar contrasenyes a la KB ni
compartir les credencials personals amb processos de cron.

### 2. Mappings FDW

Revisar l'[SQL dels mappings](../../scripts/postgres/configure_hall_profile_mappings.sql).
Copia les opcions del mapping existent d'`energetica` als cinc usuaris del
perfil `develrw_dades`, dins del servidor, sense posar contrasenyes literals
al fitxer. Els administradors i els comptes de servei utilitzen directament
el mapping existent d'`energetica`, perquè aquest és el seu rol actiu.

```text
\i /home/energetica/le-tech-knowledge-base/docs/scripts/postgres/configure_hall_profile_mappings.sql
```

S'atura si algun mapping de destinació ja existeix, per revisar-lo abans de
substituir-lo. Cal valorar els logs i l'auditoria SQL del servidor abans de
gestionar credencials; les opcions dels mappings contenen secrets.
Tots els comptes utilitzaran la identitat remota `energetica` a PRO.
Quan es renovi la contrasenya remota, s'hauran d'actualitzar tots els mappings.
Si un administrador torna expressament al rol personal amb `SET ROLE NONE`,
no tindrà mapping propi; per consultar les foreign tables haurà de recuperar
el rol compartit amb `RESET ROLE`.

### 3. Verificació abans de posar-ho en servei

```sql
SELECT r.rolname,
       pg_has_role(r.rolname, 'develrw_admin', 'MEMBER') AS perfil_admin,
       pg_has_role(r.rolname, 'develrw_dades', 'MEMBER') AS perfil_dades,
       has_schema_privilege(r.rolname, 'develrw', 'CREATE') AS pot_crear
FROM pg_roles r
WHERE r.rolname IN (
    'miquelllover', 'guillemmarpons', 'joansegura', 'joseantonioarias',
    'juliaperona', 'lauramari', 'randanajjari', 'martigarcia', 'marcnunez',
    'blancaperez', 'paulaferrate', 'svc_energetica_etl', 'svc_comercialitzacio'
)
ORDER BY r.rolname;
```

Els sis administradors i els dos comptes de servei han de tenir els tres
valors a `true`; el perfil administrador també hereta el de dades. Els cinc
usuaris de dades han de tenir `false`, `true`, `false`.

En una connexió nova iniciada com a `juliaperona`, comprovar:

```sql
SELECT session_user, current_user;
-- Esperat: juliaperona | energetica
```

Amb un usuari de dades, tots dos valors han de ser el seu login personal.

Provar amb sessions noves de cada perfil l'accés a una foreign table i les
operacions autoritzades sobre taules de prova. Comprovar que els usuaris de
dades no poden fer DDL ni TRUNCATE i que cap dels dos perfils pot escriure a
les foreign tables. Aquesta configuració no afegeix permisos d'escriptura a
`public`; altres permisos preexistents s'han de revisar abans d'activar comptes
reutilitzats. La possibilitat de crear taules temporals no es modifica.

La selecció dels comptes de servei ja està aplicada al wrapper i al carregador
compartits, amb un únic `CONFIG_FILE`. Queda pendent observar o validar el
resultat funcional dels processos programats i revisar les execucions fallides
durant el canvi. La contrasenya antiga de PRO ja està invalidada en connexions
noves. El compte Linux del cron i el compte PostgreSQL són identitats
diferents; el primer ha de poder llegir la configuració necessària.


## Consulta d'identitat i de consultes actives

A la connexió que es vol comprovar:

```sql
SELECT session_user AS usuari_connexio, current_user AS rol_actiu;
```

Com a administrador, per identificar consultes actives a HALL:

```sql
SELECT pid, usename AS usuari_connexio, application_name, client_addr,
       clock_timestamp() - query_start AS durada,
       wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE datname = 'energetica'
  AND state = 'active'
  AND pid <> pg_backend_pid()
ORDER BY query_start;
```

Un compte sense permisos de monitoratge pot no veure el text de consultes
alienes. Aquesta vista és de seguiment en viu i no substitueix un historial
d'auditoria.

## Canvi d'un perfil administrador al perfil de dades

Retirar primer la configuració de rol actiu per defecte del login afectat:

```sql
-- Exemple: adaptar el compte abans d'executar-lo.
ALTER ROLE juliaperona IN DATABASE energetica RESET role;
```

Després revisar i retirar la membresia administradora i qualsevol altra via
que li concedeixi propietat, permisos DDL o TRUNCATE. Assignar el perfil de
dades, comprovar els permisos efectius i reconnectar. Revocar només el perfil
sense retirar un rol actiu per defecte incompatible pot causar errors de login.

## Referència per a futures rotacions de PRO

La rotació del 17/11/2026 està completada. Per a una altra rotació, coordinar
sempre aquests tres components: compte remot, sis mappings i configuració.

1. Preparar la nova credencial a KeePass i inventariar els mappings que
   utilitzin el compte remot. No imprimir-ne les opcions amb contrasenyes.
2. El mateix `energetica` de PRO pot canviar-se la contrasenya pròpia; no cal
   superusuari per a aquesta operació. Amb `psql`, `\password energetica`
   evita escriure la contrasenya literal a la sentència de l'historial.
3. Actualitzar els mappings amb `ALTER USER MAPPING`, i `password` dins de
   `postgresql_prod_ro_fw` al YAML compartit. No tornar a crear els mappings.
4. Provar connexions noves amb la credencial nova, rebuig de l'antiga, lectura
   amb cada mapping i execució del comprovador a través del wrapper.
5. Si es volen tancar sessions anteriors, revisar-les expressament: la rotació
   no les finalitza. No fer una terminació general com a efecte implícit.

No hi ha una transacció única entre PRO, HALL i el YAML. Preveure un interval
breu amb possibles errors d'autenticació i un mecanisme de recuperació que
restableixi una credencial coherent als tres llocs si la validació falla.

En la rotació aplicada, la credencial es va preparar temporalment al camp
`password_nova` del mateix YAML, es va enviar a PRO com a verificador SCRAM
calculat pel client i es van actualitzar mappings i fitxer de manera coordinada.
Es van validar sis backends nous de HALL, un per mapping, i el comprovador va
retornar codi 0 amb 1.012 relacions a cada extrem i cap diferència. El camp
transitori es va retirar; no és una clau de configuració permanent.

Log de la comprovació posterior a la rotació:

```text
/home/energetica/cron_log/OK_20_38_check_public_foreign_tables_hall_rotacio_e5ee867c96_20261117_203829.txt
```

## Retirada pendent d'accés a develrw de PRO

L'usuari executarà aquest canvi manualment a PRO quan correspongui:

```sql
BEGIN;
REVOKE ALL PRIVILEGES ON SCHEMA develrw FROM energetica;
SELECT has_schema_privilege('energetica', 'develrw', 'USAGE') AS pot_accedir,
       has_schema_privilege('energetica', 'develrw', 'CREATE') AS pot_crear;
COMMIT;
```

S'espera `false` a les dues columnes segons les ACL observades. És un bloqueig
operatiu per detectar scripts antics, no una conversió completa del compte a
només lectura: `energetica` conserva la propietat i pot recuperar permisos.
Sessions existents i accessos indirectes poden conservar capacitats; provar
amb sessions noves. No s'elimina l'esquema ni els objectes de TimescaleDB.
La futura eliminació de `develrw` de PRO requereix una revisió separada.

Per revertir aquest bloqueig operatiu, el propietari o un administrador pot
restablir `GRANT USAGE, CREATE ON SCHEMA develrw TO energetica;` a PRO, d'acord
amb els permisos previs. A HALL, abans del COMMIT es pot fer ROLLBACK. Després,
retirar membresies o mappings nous requereix revisar dependències i permisos;
no fer `DROP OWNED`, `DROP ROLE` o `DROP ... CASCADE` com a reversió automàtica.


## Anàlisi inicial dels repositoris

Aquesta revisió estàtica va justificar els perfils dels comptes de servei.
Els recomptes són els observats a l'inici de la sessió; no són un inventari
que s'actualitzi automàticament amb cada canvi de codi.

### energetica_etl: revisió inicial

Es van revisar 198 fitxers Python i el SQL carregat pels scripts. Dels 58
fitxers que referencien la connexió de HALL, 52 inclouen `create_all`, 26
invoquen `create_hypertable`, dos refresquen vistes materialitzades i un elimina
i recrea una taula. Els grups se superposen.

Exemples: `develrw/ree_simel_muc_hall.py` crea taula i hipertaula;
`develrw/validacions_simel_inventari_hall.py` elimina i recrea la taula;
`develrw/refresh_mv_hall.py` refresca vistes materialitzades. A PostgreSQL 15,
el refresc requereix permisos de propietari. `create_all(checkfirst=True)` pot
no crear res si les taules existeixen, però necessita permisos de creació quan
en falta alguna.

`develrw/mvqh_mv_hall.py` carrega un SQL actiu d'inserció de dades; diversos
scripts de previsió i exportació només llegeixen PostgreSQL. Es podrien separar
en comptes amb menys permisos si es necessita més endavant.

### comercialitzacio: revisió inicial

Es van revisar 48 scripts: 30 sense connexions actives a PostgreSQL al codi,
11 de lectura i set que eliminen, recreen i carreguen taules. Aquests set
fitxers corresponen a cinc processos, amb versions PRO i HALL de dos dashboards.

| Procés | Taules de develrw | Connexió configurada |
|---|---|---|
| resum_energetica_dashboard | polisses_resum_dashboard | Versions PRO i HALL |
| facturacio_reclamacions_dashboard | fact_total_reclamacions_dashboard | Versions PRO i HALL |
| leads/update_info_cups_bbdd.py | info_cups_registre | PRE |
| leads/update_registre_agenda.py | registre_agenda | PRE |
| validacio_facturacio_dashboard.py | validacio_facturacio, validacio_facturacio_consum_ko | Escriu a PRE; consulta PRO |

Només dos fitxers referencien `postgresql_hall`. Cal revisar els processos
encara connectats a PRO/PRE abans de retirar-ne accessos.
`operacions/validacio_facturacio/validacio_facturacio_preus.py` encara consulta
`develrw.pig_cups_factura_mv` mitjançant la connexió de PRO.

### energetica_utils: revisió inicial

Es van revisar deu fitxers Python i sis scripts de shell. `sql_functions.py`
ofereix connexió, `upsert` i `insert`; els helpers SQL no creen ni eliminen
objectes. `upsert` necessita SELECT/INSERT/UPDATE i `insert` necessita INSERT
i, si rep `truncate=True`, DELETE: malgrat el nom, executa `DELETE FROM`, no
`TRUNCATE`. Encaixen amb `develrw_dades`.

`config_lenergetica.py` carrega el YAML indicat per `CONFIG_FILE`, que permet
definir connexions separades per compte de servei dins d'un únic fitxer.
`conexio_sql()` no fa `SET ROLE`: el rol actiu es configura al servidor.
Els mòduls MinIO/S3, ESIOS i GISCE/Odoo tenen permisos propis independents de
PostgreSQL; `erp_functions.py` pot crear assistents i executar accions a l'ERP.


## Recuperació de les execucions programades

La construcció manual de la URL del helper no tractava correctament els
caràcters especials d'una contrasenya de servei. Es va corregir amb
`URL.create()` i amb la interpolació correcta de `schema` a `search_path`.
Les proves de regressió són a
`/home/energetica/projectes/energetica_utils/tests/test_sql_functions_connection.py`.

Vuit tasques van fallar abans de la correcció. L'usuari va autoritzar-ne la
recuperació, iniciada el 17/11/2026 a les 20:49:50, Europe/Madrid, amb les
ordres originals del cron, el wrapper i el compte de servei d'ETL. S'han executat
una a una. El lot ha finalitzat el **18/11/2026 a les 01:59:10, Europe/Madrid**,
amb les vuit tasques correctes. El supervisor ha registrat `lot_completat`
a les 01:59:29. No s'han detectat traces d'excepció ni errors SQL o
d'autenticació als logs de les recuperacions.

Resultat final comprovat el **18/11/2026**:

| Tasca | Estat | Codi de sortida |
|---|---|---|
| `apigisce_tgcchfact_hall` | Correcta | 0 |
| `pig_estabilitzacio_hall` | Correcta | 0 |
| `ree_simel_mcilqh_hall` | Correcta | 0 |
| `ree_simel_cilcauos_hall` | Correcta | 0 |
| `apigisce_tgf1_hall` | Correcta | 0 |
| `apigisce_tgp1_hall` | Correcta | 0 |
| `ree_liqene_reganecu_hall` | Correcta | 0 |
| `pig_brp_hall` | Correcta | 0 |

Els registres conserven els codis de sortida, les hores, les durades i les
rutes dels logs de les vuit execucions:

```text
/home/energetica/cron_log/recovery_20261117_e36fd2118e.json
/home/energetica/cron_log/recovery_20261117_e36fd2118e.supervisor.json
/home/energetica/cron_log/recovery_20261117_e36fd2118e.supervisor.log
```

Cada tasca també conserva el log habitual `RUN_...`, `OK_...` o `FAIL_...`.
Els errors anteriors queden com a historial, amb els fragments sensibles del
host mal interpretat ocultats i les dates originals conservades.

El supervisor desconnectat és a:

```text
/home/energetica/backups/hall-service-routing-20261117-sc_y_kzh/recovery_supervisor_20261117.py
```

La supervisió s'ha executat independentment del xat: observava el coordinador
original i estava preparada per esperar tasques ja iniciades i continuar les
pendents sense duplicats. El lot ja està completat; no cal rellançar-lo.
El supervisor no és un servei que es reiniciï automàticament després de
recrear el contenidor. Per a qualsevol recuperació futura, revisar processos
i manifest abans de reprendre-la i verificar sempre els resultats finals.

## Còpies de seguretat i versió anterior de la guia

Les còpies de codi permeten recuperar els fitxers previs després de revisar
si hi ha edicions posteriors que s'hagin de conservar. Restaurar el helper SQL
antic reintroduiria l'error de caràcters especials. Una reversió de codi no
reverteix comptes, permisos, mappings ni contrasenyes de PostgreSQL.
