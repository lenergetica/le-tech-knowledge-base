---
title: "Usuaris i perfils PostgreSQL a HALL"
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

# Usuaris i perfils de BD a HALL

L'accés a la BD `energetica` de GISCE s'ha de fer a través de **HALL** amb un
compte personal o de servei. L'esquema `develrw` conté les dades locals de treball;
`public` exposa les taules de PRO mitjançant FDW, amb permisos de lectura.

Aquesta pàgina descriu la configuració aplicada. Les comandes d'alta,
verificació, rotació i recuperació són a l'[annex operatiu](usuaris-perfils-hall-annex.md).

## Connexió

Per connectar-se a la BD de HALL els usuaris han d'utilitzar el seu propi login a les eines SQL i als scripts que executen localment.

???info "Configuració DBCode"
    Per configurar DBCode, es pot duplicar una connexió de
    HALL ja validada i canviar-ne l'usuari i la contrasenya, conservant la ruta
    de connexió o túnel corresponent.

| Paràmetre | Des de fora | Des de dintre |
|---|---|---|
| Servidor | gw.lenergetica.gisce.cloud | `192.168.24.2`, localhost |
| Port | `5444` | `5432` |
| Base de dades | `energetica` |
| Usuari personal | Cadascú el seu |
| Contrasenya | Individual, gestionada a KeePass i facilitada per canal separat |

!!!warning "Orígens permesos per accés"
    Al `pg_hba.conf` s'han definit unes regles d'autenticació que autoritzen els membres dels perfils `develrw_admin` i `develrw_dades` (veure següent apartat), des dels orígens següents: `172.18.0.1` (passarel·la `docker_gwbridge` de HALL) i `10.46.0.6`.
    L'accés des d'altres orígens requereix revisar-ne `pg_hba.conf`.

## Perfils de grup

A la BD de HALL hem creat els perfils `NOLOGIN` `develrw_admin` i `develrw_dades` amb els següents permisos:

???info "Rols `LOGIN` ![Rol individual](../../images/dbcode/rol-individual.svg) i `NOLOGIN` ![Rol de grup](../../images/dbcode/rol-grup.svg)"
    ![Rol de grup](../../images/dbcode/rol-grup.svg) indica un perfil `NOLOGIN`, que agrupa permisos i no inicia connexions. ![Rol individual](../../images/dbcode/rol-individual.svg) indica un compte `LOGIN`, personal o de servei; a PostgreSQL tots aquests elements són rols.

| Permís | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_dades` |
|---|---|---|
| SELECT, INSERT, UPDATE, DELETE a develrw | Sí | Sí |
| TRUNCATE a develrw | Sí | No |
| Crear, modificar i eliminar objectes de develrw | Sí | No |
| Consultar public de PRO via FDW | Sí | Sí |
| Escriure a public de PRO | No | No |

Sobre aquests perfils:

- `develrw_admin` hereta els rols `energetica` i `develrw_dades`. Pot gestionar els objectes propietat d'`energetica`, inclòs eliminar-los i concedir-hi permisos. No és superusuari de PostgreSQL ni rep `CREATEROLE` o `CREATEDB` (atributs que `energetica` no té).
- `develrw_dades` té els permisos sobre dades i `USAGE, SELECT` sobre les seqüències.
- Els objectes nous creats per `energetica` a `develrw` concedeixen automàticament SELECT, INSERT, UPDATE i DELETE a `develrw_dades`, i l'ús i lectura de seqüències.
- Les foreign tables noves importades per `postgres` a `public` concedeixen SELECT als dos perfils.
- Les funcions i els procediments conserven els seus permisos existents; no s'hi han afegit restriccions. També es mantenen les regles pròpies de les vistes, els triggers i les eventuals polítiques de files.

## Comptes personals

Hi ha **11 comptes personals**: 6 de tipus `develrw_admin` i 5 de tipus `develrw_dades`.

!!!warning "Atenció"
    Les credencials són individuals i no s'han de compartir entre persones.

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


## Comptes de servei

Els comptes de servei s'utilitzen per executar processos automàtics (scripts ETL) i són independents de les persones responsables.

!!!info "Comptes amb perfil `develrw_admin`"
    Els scripts
    actuals creen o recreen taules, gestionen hipertaules o refresquen vistes
    materialitzades. La justificació per repositori és a l'annex.

| Compte de connexió | Ús | Perfil |
|---|---|---|
| ![Rol individual](../../images/dbcode/rol-individual.svg) `svc_energetica_etl` | Scripts programats d'energetica_etl | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |
| ![Rol individual](../../images/dbcode/rol-individual.svg) `svc_comercialitzacio` | Scripts programats de comercialitzacio | ![Rol de grup](../../images/dbcode/rol-grup.svg) `develrw_admin` |


## Rol actiu, propietat compartida i identificació

El rol ![Rol individual](../../images/dbcode/rol-individual.svg) `energetica` de HALL es manté com a propietari compartit
de `develrw` i els seus objectes. Conserva `LOGIN`, però les connexions humanes
habituals s'han de fer amb el compte personal (de fet no donem la contrasenya d'aquest rol).

Cada persona o servei es connecta amb el seu usuari i contrasenya, però PostgreSQL activa automàticament el rol energetica quan entra a la BD energetica de HALL.

Ho vam configurar per a cada compte administrador i de servei amb una ordre com aquesta:

```SQL
ALTER ROLE juliaperona IN DATABASE energetica
SET ROLE = 'energetica';
```

Això equival a executar SET ROLE energetica a l’inici de cada connexió, sense haver d’afegir-ho als scripts.

| Connexió iniciada com a | session_user | current_user | Propietari dels objectes nous |
|---|---|---|---|
| juliaperona | juliaperona | energetica | energetica |
| svc_energetica_etl | svc_energetica_etl | energetica | energetica |
| randanajjari | randanajjari | randanajjari | No té permís de creació a develrw |

Això permet gestionar els objectes entre administradors i aplicar-hi els
mateixos permisos per defecte. La propietat dels objectes antics no es
modifica automàticament si ja pertanyen a un altre compte.

La identitat autenticada es conserva a `session_user` i a `username` de
`pg_stat_activity`, de manera que podem identificar qui ha llançat una consulta
en execució. `current_user` és el rol amb què es comproven els permisos.
Un historial complet requereix logs o auditoria configurats; aquesta
configuració de rols no activa una auditoria automàtica de totes les accions.

!!!info "`SET ROLE NONE`"
    Si un administrador executa expressament `SET ROLE NONE`, actua amb el seu
    login i els objectes que creï a partir d'aquell moment li pertanyeran.
    `RESET ROLE` recupera el rol actiu configurat per a la connexió. Per canviar
    una persona al perfil de dades cal retirar també el rol actiu per defecte.
    Els usuaris del perfil develrw_dades no tenen aquesta activació automàtica: treballen amb el seu usuari i els permisos heretats del grup.

## Selecció automàtica de credencials als scripts programats a crontab

### config.yml

Es manté `/home/energetica/config.yml` com a **únic fitxer de configuració**.

!!!info "KeePass"
    Les contrasenyes són al fitxer privat i a KeePass.

| Clau | Usuari | Destinació i ús |
|---|---|---|
| postgresql_hall | energetica | HALL; compatibilitat amb execucions sense selecció |
| postgresql_hall_etl | svc_energetica_etl | HALL; processos d'ETL |
| postgresql_hall_comercialitzacio | svc_comercialitzacio | HALL; processos de Comercialització |
| postgresql_prod_ro_fw | energetica | PRO; execució check_foreign_tables_public_hall.py |

### run_cron_job.sh

El wrapper és **`/home/energetica/run_cron_job.sh`**, un enllaç simbòlic a
`/home/energetica/projectes/energetica_etl/run_cron_job.sh`.

Identifica la ruta del repositori dins de la comanda que rep i exporta
`POSTGRESQL_HALL_CONNECTION`:

| Ruta de la comanda | Valor seleccionat |
|---|---|
| /home/energetica/projectes/energetica_etl/ | postgresql_hall_etl |
| /home/energetica/projectes/comercialitzacio/ | postgresql_hall_comercialitzacio |

### config_lenergetica.py

`/home/energetica/projectes/energetica_utils/config_lenergetica.py` carrega el
YAML de `CONFIG_FILE`. Si rep `POSTGRESQL_HALL_CONNECTION`, presenta el bloc
seleccionat com a `config['postgresql_hall']` en memòria. Per això els
scripts continuen demanant la mateixa clau i reben el compte del seu repositori.
Una selecció inexistent o que no sigui un bloc de configuració produeix error.

!!!info
    Sense variable de selecció, es conserva la connexió original. Això també
    s'aplica a execucions manuals que no passin pel wrapper: no es converteixen
    automàticament en execucions amb compte de servei. La selecció per ruta és una
    convenció operativa, no una restricció de seguretat.

!!!note "sql_functions.py"
    El helper `/home/energetica/projectes/energetica_utils/sql_functions.py` crea
    les URLs amb `sqlalchemy.engine.URL.create()`. Això permet usar les contrasenyes
    de KeePass amb caràcters especials sense codificar-les manualment.
    L'opció `search_path` incorpora el valor real de `schema`, habitualment
    `develrw` o `public`. Els canvis són al helper compartit i no requereixen
    editar cada script.

## Accés a PRO i contrasenya renovada

HALL consulta PRO a través del servidor FDW **`energetica_pro`**, que apunta a
`192.168.24.3:5432`, BD `energetica`. El compte remot és `energetica` i té
lectura de les taules i vistes de `public`.

Hi ha **6 mappings** que utilitzen aquesta identitat remota:

- El mapping local d'`energetica`, utilitzat pels administradors i serveis
  quan aquest és el seu rol actiu.
- Els mappings personals de `randanajjari`, `martigarcia`, `marcnunez`,
  `blancaperez` i `paulaferrate`, utilitzats pel perfil de `develrw_dades`.

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

## Annexos i material de referència

- [Annex operatiu: comandes, verificacions, anàlisi i recuperació](usuaris-perfils-hall-annex.md).
- [Restauració de develrw de PRO a HALL](restaurar-develrw-a-Hall.md).
- [Configuració FDW](configurar-postgres_fdw.md).
