---
title: "Usuaris i perfils PostgreSQL a HALL"
author: "L'Energètica"
reviewed_by: "L'Energètica"
owner: "Equip de Tecnologia de L'Energètica"
status: "draft"
version: "1.0"
creation_date: "2026-11-17"
review_date: "2026-11-17"
review_after_months: 60
tags:
  - "postgresql"
  - "hall"
  - "permisos"
  - "postgres_fdw"
references:
  - "https://www.postgresql.org/docs/15/role-membership.html"
  - "https://www.postgresql.org/docs/15/sql-alterrole.html"
  - "https://www.postgresql.org/docs/15/sql-set-role.html"
  - "https://www.postgresql.org/docs/15/sql-alterdefaultprivileges.html"
  - "https://www.postgresql.org/docs/15/sql-createusermapping.html"
  - "https://www.postgresql.org/docs/15/sql-alterusermapping.html"
  - "https://www.postgresql.org/docs/15/view-pg-user-mappings.html"
  - "https://docs.sqlalchemy.org/en/20/core/engines.html#creating-urls-programmatically"
  - "https://dbcode.io/docs/connections/security"
---

# Usuaris i perfils PostgreSQL a HALL

L'accés habitual a les dades es fa a la BD `energetica` de **HALL** amb un
compte personal o de servei. `develrw` conté les dades locals de treball;
`public` exposa les taules de PRO mitjançant FDW, amb permisos de lectura.

Aquesta pàgina descriu la configuració aplicada. Les comandes d'alta,
verificació, rotació i recuperació són a l'[annex operatiu](usuaris-perfils-hall-annex.md).

## Connexió i criteri d'identitat

| Paràmetre | Valor |
|---|---|
| Servidor | HALL, `192.168.24.2` |
| Port | `5432` |
| Base de dades | `energetica` |
| Usuari personal | Part del correu anterior a `@lenergetica.cat`, segons la llista d'assignacions |
| Contrasenya | Individual, gestionada a KeePass i facilitada per canal separat |

Les persones han d'utilitzar el seu login a les eines SQL i als scripts que
executen localment. Per configurar DBCode, es pot duplicar una connexió de
HALL ja validada i canviar-ne l'usuari i la contrasenya, conservant la ruta
de connexió o túnel corresponent.

Les regles d'autenticació autoritzen els membres dels dos perfils des de
l'origen `172.18.0.1` que veu PostgreSQL en el recorregut validat a HALL,
amb `scram-sha-256`. L'accés des d'altres orígens requereix revisar-ne la ruta
i `pg_hba.conf`. L'endpoint PostgreSQL de HALL té TLS desactivat en l'estat
observat; la connexió directa de HALL a PRO s'ha verificat amb TLS.

## Perfils de grup

![Rol de grup](../../images/dbcode/rol-grup.svg) indica un perfil `NOLOGIN`, que agrupa permisos i no inicia
connexions. ![Rol individual](../../images/dbcode/rol-individual.svg) indica un compte `LOGIN`, personal o de servei.
Les icones són les de DBCode; a PostgreSQL tots aquests elements són rols.

| Permís | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_dades` |
|---|---|---|
| SELECT, INSERT, UPDATE, DELETE a develrw | Sí | Sí |
| TRUNCATE a develrw | Sí | No |
| Crear, modificar i eliminar objectes de develrw | Sí | No |
| Consultar public de PRO via FDW | Sí | Sí |
| Escriure a public de PRO | No | No |

- `develrw_admin` hereta els rols `energetica` i `develrw_dades`.
- `develrw_dades` té els permisos sobre dades i `USAGE, SELECT` sobre les seqüències.
- Els objectes nous creats per `energetica` a `develrw` concedeixen automàticament
  SELECT, INSERT, UPDATE i DELETE a `develrw_dades`, i l'ús i lectura de seqüències.
- Les foreign tables noves importades per `postgres` a `public` concedeixen
  SELECT als dos perfils.
- Les funcions i els procediments conserven els seus permisos existents;
  no s'hi han afegit restriccions. També es mantenen les regles pròpies de
  les vistes, els triggers i les eventuals polítiques de files.

El perfil administrador pot gestionar els objectes propietat d'`energetica`,
inclòs eliminar-los i concedir-hi permisos. Hereta tots els permisos que tingui
`energetica` a HALL, no només els de `develrw`. No és superusuari de PostgreSQL
ni rep `CREATEROLE` o `CREATEDB`, atributs que `energetica` no té.

## Comptes personals

| Compte de connexió | Perfil assignat |
|---|---|
| ![Rol individual](../../images/dbcode/rol-individual.svg) `miquelllover` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `guillemmarpons` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `joansegura` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `joseantonioarias` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `juliaperona` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `lauramari` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `randanajjari` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_dades` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `martigarcia` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_dades` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `marcnunez` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_dades` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `blancaperez` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_dades` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `paulaferrate` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_dades` |

Hi ha **onze comptes personals**: sis administradors i cinc de dades.
Les credencials són individuals i no s'han de compartir entre persones.

## Comptes de servei

| Compte de connexió | Ús | Perfil |
|---|---|---|
| ![Rol individual](../../images/dbcode/rol-individual.svg) `svc_energetica_etl` | Scripts programats d'energetica_etl | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `svc_comercialitzacio` | Scripts programats de comercialitzacio | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |

Els comptes de servei identifiquen processos i són independents de les persones
responsables. Els dos perfils administradors són necessaris perquè els scripts
actuals també creen o recreen taules, gestionen hipertaules o refresquen vistes
materialitzades. La justificació per repositori és a l'annex.

`energetica_utils` és una biblioteca compartida: utilitza el compte del procés
que la importa i no necessita un compte de BD propi.

## Rol actiu, propietat compartida i identificació

El rol ![Rol individual](../../images/dbcode/rol-individual.svg) `energetica` de HALL es manté com a propietari compartit
de `develrw` i els seus objectes. Conserva `LOGIN`, però les connexions humanes
habituals es fan amb el compte personal.

Els sis administradors personals i els dos comptes de servei tenen configurat
al servidor, només per a la BD `energetica`, **`role=energetica` com a valor
per defecte de les connexions noves**. Els scripts no han d'executar un
`SET ROLE` manual per obtenir aquest comportament.

| Connexió iniciada com a | session_user | current_user | Propietari dels objectes nous |
|---|---|---|---|
| juliaperona | juliaperona | energetica | energetica |
| svc_energetica_etl | svc_energetica_etl | energetica | energetica |
| randanajjari | randanajjari | randanajjari | No té permís de creació a develrw |

Això permet gestionar els objectes entre administradors i aplicar-hi els
mateixos permisos per defecte. La propietat dels objectes antics no es
modifica automàticament si ja pertanyen a un altre compte.

La identitat autenticada es conserva a `session_user` i a `usename` de
`pg_stat_activity`, de manera que podem identificar qui ha llançat una consulta
en execució. `current_user` és el rol amb què es comproven els permisos.
Un historial complet requereix logs o auditoria configurats; aquesta
configuració de rols no activa una auditoria automàtica de totes les accions.

Si un administrador executa expressament `SET ROLE NONE`, actua amb el seu
login i els objectes que creï a partir d'aquell moment li pertanyeran.
`RESET ROLE` recupera el rol actiu configurat per a la connexió. Per canviar
una persona al perfil de dades cal retirar també el rol actiu per defecte.

## Un únic config.yml i selecció automàtica de credencials

Es manté **`/home/energetica/config.yml` com a únic fitxer de configuració**.
Les contrasenyes són al fitxer privat i a KeePass; no es documenten ni es
versionen a la KB.

| Clau | Usuari | Destinació i ús |
|---|---|---|
| postgresql_hall | energetica | HALL; compatibilitat amb execucions sense selecció |
| postgresql_hall_etl | svc_energetica_etl | HALL; processos d'ETL |
| postgresql_hall_comercialitzacio | svc_comercialitzacio | HALL; processos de Comercialització |
| postgresql_prod_ro_fw | energetica | PRO; comprovació d'estructura del public remot |

### run_cron_job.sh

El wrapper és **`/home/energetica/run_cron_job.sh`**, un enllaç simbòlic a
`/home/energetica/projectes/energetica_etl/run_cron_job.sh`.

Identifica la ruta del repositori dins de la comanda que rep i exporta
`POSTGRESQL_HALL_CONNECTION`:

| Ruta de la comanda | Valor seleccionat |
|---|---|
| /home/energetica/projectes/energetica_etl/ | postgresql_hall_etl |
| /home/energetica/projectes/comercialitzacio/ | postgresql_hall_comercialitzacio |

Les entrades de cron i els scripts individuals conserven les seves ordres.
En el crontab auditat, les 61 entrades d'ETL i les dues de Comercialització
passen pel wrapper. La tasca addicional de neteja de logs també hi passa i
no consulta la BD. Les tres entrades del crontab de l'usuari del host fan
`git pull` i no accedeixen a la BD.

### config_lenergetica.py

`/home/energetica/projectes/energetica_utils/config_lenergetica.py` carrega el
YAML de `CONFIG_FILE`. Si rep `POSTGRESQL_HALL_CONNECTION`, presenta el bloc
seleccionat com a **`config['postgresql_hall']` en memòria**. Per això els
scripts continuen demanant la mateixa clau i reben el compte del seu repositori.
Una selecció inexistent o que no sigui un bloc de configuració produeix error.

Sense variable de selecció, es conserva la connexió original. Això també
s'aplica a execucions manuals que no passin pel wrapper: no es converteixen
automàticament en execucions amb compte de servei. La selecció per ruta és una
convenció operativa, no una restricció de seguretat.

### sql_functions.py

El helper `/home/energetica/projectes/energetica_utils/sql_functions.py` crea
les URLs amb `sqlalchemy.engine.URL.create()`. Això permet usar les contrasenyes
de KeePass amb caràcters especials sense codificar-les manualment.
L'opció `search_path` incorpora el valor real de `schema`, habitualment
`develrw` o `public`. Els canvis són al helper compartit i no requereixen
editar cada script.

## Accés a PRO i contrasenya renovada

HALL consulta PRO amb el servidor FDW **`energetica_pro`**, que apunta a
`192.168.24.3:5432`, BD `energetica`. El compte remot és `energetica` i té
lectura de les taules i vistes de `public`.

Hi ha **sis mappings** que utilitzen aquesta identitat remota:

- El mapping local d'`energetica`, utilitzat pels administradors i serveis
  quan aquest és el seu rol actiu.
- Els mappings personals de `randanajjari`, `martigarcia`, `marcnunez`,
  `blancaperez` i `paulaferrate`, utilitzats pel perfil de dades.

La contrasenya d'`energetica` de PRO **ja s'ha canviat**. Els sis mappings i
`postgresql_prod_ro_fw.password` estan actualitzats. La contrasenya antiga
és rebutjada en connexions noves autenticades per contrasenya. El camp
transitori `password_nova` ja no existeix al YAML. La contrasenya d'`energetica`
de HALL és independent i no s'ha canviat en aquesta rotació.

L'excepció d'accés directe a PRO és
`energetica_etl/develrw/check_public_foreign_tables_hall.py`. Utilitza
`postgresql_prod_ro_fw` per llegir els catàlegs de PRO i `postgresql_hall`
per comparar-los amb les foreign tables de HALL. Executat pel wrapper d'ETL,
aquesta segona connexió utilitza `svc_energetica_etl`.

!!! warning "Límit acceptat: la rotació no força l'accés exclusiu via FDW"
    Els usuaris autoritzats poden consultar les credencials dels mappings que
    utilitzen; també poden llegir la secció de PRO si tenen accés al YAML
    compartit. La rotació retira la credencial antiga, però PostgreSQL no
    distingeix quin fitxer Python inicia una connexió. Qui obtingui la credencial
    nova pot reutilitzar-la des d'un origen permès per les regles d'accés.
    Limitar l'origen a HALL tampoc no distingeix FDW d'altres processos del host.

La rotació no ha finalitzat les sessions de PRO ja obertes. Tampoc no elimina
l'antic `develrw` de PRO ni resol la seva propietat: el bloqueig d'accés o la
seva retirada s'han de tractar separadament. No consta confirmat que el
`REVOKE` plantejat per a aquest esquema s'hagi aplicat.

## Validació i seguiment operatiu

- Validats els accessos personals de `juliaperona` i `randanajjari`, amb els
  rols actius i permisos d'esquema esperats.
- Validats els dos comptes de servei des del contenidor cron, el recorregut
  del wrapper i del carregador, i les connexions reals del helper SQLAlchemy.
- Validats els sis mappings amb sessions noves i lectura real via FDW.
- El comprovador d'estructura ha acabat amb **codi 0: 1.012 relacions a PRO,
  1.012 foreign tables de HALL i cap diferència d'esquema**.
- Hi ha proves de regressió del helper per a caràcters especials i `search_path`.

La recuperació de vuit execucions que van fallar per l'error de construcció
manual de la URL està en curs. L'[annex de seguiment](usuaris-perfils-hall-annex.md#recuperacio-de-les-execucions-programades)
identifica els registres de progrés i l'últim estat observat. El resultat
d'aquest lot no s'ha de donar per completat només perquè s'hagi iniciat.

Els canvis de codi són aplicats als repositoris locals de HALL; no s'han fet
commits ni publicacions durant aquesta sessió. Les proves controlades de DDL
i dels permisos d'escriptura del perfil de dades es van ometre per decisió
de l'usuari; això queda separat de la validació real de les tasques recuperades.

## Annexos i material de referència

- [Annex operatiu: comandes, verificacions, anàlisi i recuperació](usuaris-perfils-hall-annex.md).
- [Còpia íntegra del document anterior a la reorganització](../../scripts/postgres/usuaris-perfils-hall-abans-reorganitzacio-20261117.md.bak).
- [Restauració de develrw de PRO a HALL](restaurar-develrw-a-Hall.md).
- [Configuració FDW](configurar-postgres_fdw.md).
