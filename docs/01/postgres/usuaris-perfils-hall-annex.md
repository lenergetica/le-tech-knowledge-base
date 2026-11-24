---
title: "Annex operatiu dels accessos PostgreSQL a HALL"
author: "L'Energètica"
reviewed_by: "L'Energètica"
owner: "Equip de Tecnologia de L'Energètica"
status: "active"
version: "1.0"
creation_date: "2026-11-17"
review_date: "2026-11-23"
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
inclou els onze logins personals i els dos comptes de servei inicials. No inclou l’alta posterior de `develrw_lectura` i `svc_powerbi`, documentada a continuació.
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
les foreign tables. Els administradors que actuen com a propietari poden gestionar les definicions
FDW i recuperar permisos locals; cal comprovar també la lectura al compte remot
de PRO. Altres permisos preexistents s'han de revisar abans d'activar comptes
reutilitzats. La possibilitat de crear taules temporals no es modifica.

La selecció dels comptes de servei ja està aplicada al wrapper i al carregador
compartits, amb un únic `CONFIG_FILE`. Queda pendent observar o validar el
resultat funcional dels processos programats i revisar les execucions fallides
durant el canvi. La contrasenya antiga de PRO ja està invalidada en connexions
noves. El compte Linux del cron i el compte PostgreSQL són identitats
diferents; el primer ha de poder llegir la configuració necessària.


## Cas pràctic: alta de svc_powerbi per al bridge ODBC de Power BI (19/11/2026)

L'usuari ha executat l'alta a HALL, ha substituït les credencials d'`energetica`
per les de `svc_powerbi` al bridge ODBC de la màquina OMIE i ha confirmat el
funcionament de Power BI. A Power BI Desktop s'utilitzen els comptes personals,
amb els permisos que ja tenen assignats.

El cas il·lustra les peces independents que cal configurar:

| Peça | Funció en aquest cas |
|---|---|
| Perfil `develrw_lectura` (`NOLOGIN`) | Agrupa els permisos de lectura sobre els objectes |
| Compte `svc_powerbi` (`LOGIN`) | Autentica les connexions del bridge ODBC i hereta el perfil |
| Mapping de `svc_powerbi` a `energetica_pro` | Permet consultar les foreign tables amb la identitat remota `energetica` |
| Regla de `pg_hba.conf` | Admet la connexió a HALL des de l'origen autoritzat |
| Credencials al bridge ODBC d'OMIE | Fan que Power BI utilitzi el nou compte |

Les comandes següents són referència de la configuració aplicada; no repetir-les
sobre els rols o el mapping existents. Les ordres SQL s'han executat a la BD
`energetica` de HALL com a `postgres`.

### 1. Crear un perfil de lectura reutilitzable

El perfil `develrw_dades` existent permet INSERT, UPDATE i DELETE. Per a les
consultes de Power BI es va crear `develrw_lectura`, sense aquests permisos.
`NOLOGIN` indica que és un grup de permisos, no el compte que s'autenticarà.

```sql
BEGIN;
CREATE ROLE develrw_lectura NOLOGIN INHERIT;
GRANT CONNECT ON DATABASE energetica TO develrw_lectura;
GRANT USAGE ON SCHEMA develrw, public TO develrw_lectura;
GRANT SELECT ON ALL TABLES IN SCHEMA develrw, public TO develrw_lectura;
ALTER DEFAULT PRIVILEGES FOR ROLE energetica IN SCHEMA develrw
    GRANT SELECT ON TABLES TO develrw_lectura;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT SELECT ON TABLES TO develrw_lectura;
GRANT USAGE ON FOREIGN SERVER energetica_pro TO develrw_lectura;
COMMIT;
```

Els GRANT cobreixen els objectes existents. Els `ALTER DEFAULT PRIVILEGES`
cobrien els futurs objectes creats per `energetica` a `develrw` i per
`postgres` a `public` en aquesta alta. Amb el reconciliador actual, el creador
de les foreign tables és `energetica`: cal revisar també els permisos per
defecte d’aquest rol a `public`, tal com es descriu a l’apartat següent.

### 2. Crear el compte de servei i assignar-li el perfil

```sql
BEGIN;
CREATE ROLE svc_powerbi LOGIN INHERIT;
GRANT develrw_lectura TO svc_powerbi;
COMMIT;
```

La contrasenya s'ha generat a KeePass i assignat al compte. Per a futures altes,
`\password svc_powerbi` des de `psql` permet assignar-la interactivament sense
guardar-la en una sentència SQL. No s'ha configurat `SET ROLE energetica` per
a aquest compte. D'aquesta manera no adquireix les capacitats de propietari
compartit dels administradors i conserva `current_user = svc_powerbi`.

### 3. Crear el mapping per consultar PRO a través de HALL

Els permisos SELECT sobre les foreign tables i USAGE sobre el servidor FDW
no aporten per si sols les credencials remotes. Com que el rol actiu és
`svc_powerbi`, necessita un mapping propi per consultar `public` de PRO.
No necessita aquest mapping per llegir les taules locals de `develrw`.

El mapping s'ha creat copiant les opcions del mapping local d'`energetica`,
sense mostrar-les:

```sql
DO $$
DECLARE
    opcions text;
BEGIN
    SELECT string_agg(format('%I %L', o.option_name, o.option_value), ', ')
    INTO opcions
    FROM pg_user_mapping AS m
    JOIN pg_foreign_server AS s ON s.oid = m.umserver
    CROSS JOIN LATERAL pg_options_to_table(m.umoptions) AS o
    WHERE s.srvname = 'energetica_pro'
      AND m.umuser = 'energetica'::regrole;

    IF opcions IS NULL THEN
        RAISE EXCEPTION 'No existeix el mapping de referencia per a energetica';
    END IF;

    EXECUTE format(
        'CREATE USER MAPPING FOR svc_powerbi SERVER energetica_pro OPTIONS (%s)',
        opcions
    );
END;
$$;
```

Cal incloure aquest mapping en futures rotacions de la contrasenya de PRO.

### 4. Autoritzar l'origen de connexió a pg_hba.conf

Amb el compte i els permisos creats encara va caldre autoritzar la connexió
al `pg_hba.conf` de HALL. Les regles existents per a `+develrw_admin` i
`+develrw_dades` no cobreixen el nou perfil: `develrw_lectura` no n'és membre.
L'usuari va afegir aquesta regla i va confirmar que la connexió funcionava:

```text
host        energetica   +develrw_lectura               192.168.24.7/32  scram-sha-256
```

| Camp | Significat |
|---|---|
| `host` | Connexions TCP, amb SSL o sense, segons la configuració del servidor i del client |
| `energetica` | Base de dades de destinació |
| `+develrw_lectura` | Membres d'aquest perfil; el signe `+` indica membresia de rol |
| `192.168.24.7/32` | Un únic origen admès, tal com el veu PostgreSQL |
| `scram-sha-256` | Autenticació amb contrasenya SCRAM |

La regla s'ha de situar abans de qualsevol regla que rebutgi aquesta connexió:
PostgreSQL aplica la primera coincidència i no prova regles posteriors si
l'autenticació falla. Cal aplicar el canvi a la configuració persistent del
desplegament i fer que PostgreSQL el carregui; una edició efímera dins d'un
contenidor es pot perdre quan es recreï.

Aquesta autorització permet arribar a la BD, però no concedeix SELECT ni
permisos d'escriptura: això ho determinen els GRANT del perfil. Igualment,
tenir els GRANT correctes no substitueix una regla d'accés vàlida.

La IP és l'origen observat per a aquesta connexió, que pot correspondre a un
intermediari si hi ha NAT o túnels. Si canvia l'origen del bridge, cal revisar
la regla. Aquesta alta no autoritza automàticament altres equips que executin
Power BI Desktop.

### 5. Actualitzar el bridge ODBC d'OMIE

Al bridge ODBC de la màquina OMIE es van substituir les credencials compartides
d'`energetica` per les de `svc_powerbi`, mantenint com a destinació HALL
(`192.168.24.2:5432`), BD `energetica`. L'usuari va confirmar que Power BI
funcionava amb el nou compte.

Les connexions de Power BI Desktop utilitzen el compte personal de cadascú,
amb els permisos del seu perfil i les regles d'accés corresponents. No cal
compartir-hi la contrasenya del servei. El resum de la configuració actual és
a la [guia principal](usuaris-perfils-hall.md#power-bi).

### 6. Comprovar identitat i permisos efectius

Executar amb una connexió nova com a `svc_powerbi`:

```sql
SELECT session_user AS usuari_connexio,
       current_user AS rol_actiu,
       pg_has_role(current_user, 'develrw_lectura', 'USAGE') AS perfil_lectura_actiu,
       has_schema_privilege(current_user, 'develrw', 'USAGE') AS pot_accedir_develrw,
       has_schema_privilege(current_user, 'develrw', 'CREATE') AS pot_crear_objectes;
```

Esperat: `svc_powerbi` a les dues identitats; `true`, `true`, `false`.

```sql
SELECT n.nspname AS esquema,
       count(*) AS objectes,
       bool_and(has_table_privilege(c.oid, 'SELECT')) AS pot_llegir_tots,
       bool_or(
           has_table_privilege(c.oid, 'INSERT')
           OR has_table_privilege(c.oid, 'UPDATE')
           OR has_table_privilege(c.oid, 'DELETE')
           OR has_table_privilege(c.oid, 'TRUNCATE')
       ) AS pot_modificar_algun
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname IN ('develrw', 'public')
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
GROUP BY n.nspname;
```

Esperat: `pot_llegir_tots = true` i `pot_modificar_algun = false` a tots dos
esquemes. Les consultes es van facilitar a l'usuari; no s'han aportat els
resultats a la conversa. La validació confirmada és el funcionament de Power BI.
Els permisos existents de funcions i procediments es mantenen, com als altres
perfils; no s'han afegit restriccions específiques per a aquest compte.


## Propietat i reconciliació de les foreign tables

Revisió estàtica del codi local d’`energetica_etl` del **23/11/2026**. El
comprovador `develrw/check_public_foreign_tables_hall.py` ara corregeix
l’esquema FDW. Els passos següents són referència per revisar o completar la
configuració; no s’han executat sobre les bases de dades en aquesta revisió.

### Connexions i requisits

| Element | Requisit del codi |
|---|---|
| Catàleg de PRO | Clau explícita `postgresql_prod_public_ro`, amb accés de lectura a `public` |
| Connexió a HALL | Clau explícita `postgresql_hall_etl`, BD `energetica` |
| Identitat a HALL | Login previst `svc_energetica_etl`; el codi valida `current_user = energetica`, però no comprova `session_user` |
| Esquema local `public` | `USAGE` i `CREATE` per a `energetica` |
| Servidor `energetica_pro` | `USAGE` i mapping propi per a `energetica` |
| Foreign tables gestionades | Totes les de `public` associades a `energetica_pro`, propietat d’`energetica` |

El procés rebutja la connexió si la BD o el rol actiu són incorrectes, o si
falta algun dels permisos, el mapping o la propietat. No transfereix la
propietat automàticament. El propietari del servidor FDW i el de l’esquema
`public` poden continuar sent diferents del propietari de les foreign tables.

Per inventariar la propietat sense exposar opcions dels mappings:

```sql
SELECT n.nspname AS esquema, c.relname AS foreign_table,
       pg_get_userbyid(c.relowner) AS propietari, s.srvname AS servidor
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_foreign_table AS ft ON ft.ftrelid = c.oid
JOIN pg_foreign_server AS s ON s.oid = ft.ftserver
WHERE n.nspname = 'public' AND s.srvname = 'energetica_pro'
ORDER BY c.relname;
```

Si cal migrar la propietat, revisar primer aquest inventari i executar com a
administrador a HALL, BD `energetica`, únicament per a les foreign tables del
servidor gestionat:

```sql
BEGIN;
GRANT USAGE, CREATE ON SCHEMA public TO energetica;
GRANT USAGE ON FOREIGN SERVER energetica_pro TO energetica;
DO $$
DECLARE
    taula record;
BEGIN
    FOR taula IN
        SELECT n.nspname, c.relname
        FROM pg_class AS c
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        JOIN pg_foreign_table AS ft ON ft.ftrelid = c.oid
        JOIN pg_foreign_server AS s ON s.oid = ft.ftserver
        WHERE n.nspname = 'public'
          AND s.srvname = 'energetica_pro'
          AND c.relowner <> 'energetica'::regrole
    LOOP
        EXECUTE format('ALTER FOREIGN TABLE %I.%I OWNER TO energetica',
                       taula.nspname, taula.relname);
    END LOOP;
END;
$$;
GRANT SELECT ON ALL TABLES IN SCHEMA public
    TO develrw_admin, develrw_dades, develrw_lectura;
ALTER DEFAULT PRIVILEGES FOR ROLE energetica IN SCHEMA public
    GRANT SELECT ON TABLES TO develrw_admin, develrw_dades, develrw_lectura;
COMMIT;
```

La transferència de propietat no substitueix els permisos sobre objectes
existents ni els permisos per defecte del nou creador. Els antics
`ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public` poden conservar-se
per a importacions com a `postgres`, però no cobreixen les d’`energetica`.
El reconciliador només afegeix SELECT explícit per a `energetica` després
d’importar; no configura els GRANT dels tres perfils. Per això cal revisar-los
abans que una reimportació substitueixi una foreign table amb permisos particulars.

### Canvis automàtics i resultats

El procés llegeix les taules, taules particionades, vistes i vistes
materialitzades de `public` de PRO. A HALL només gestiona les foreign tables
de `public` del servidor `energetica_pro`:

- Importa les relacions noves i elimina les que ja no consten a PRO.
- Ajusta les opcions `schema_name` i `table_name` i afegeix, elimina o modifica
  columnes, tipus i nul·labilitat amb `ALTER FOREIGN TABLE` quan és possible.
- Elimina i reimporta la foreign table quan els canvis anteriors no permeten
  reproduir l’ordre de columnes de PRO.
- Avorta si un nom necessari ja correspon a un objecte local o a una foreign
  table d’un altre servidor. No substitueix aquests objectes.

Utilitza un bloqueig assessor transaccional amb el nom
`check_public_foreign_tables_hall`. Els canvis a HALL i la comprovació posterior
es fan en una sola transacció; si hi ha errors o diferències residuals es fa
rollback. Les eliminacions són `RESTRICT`, sense `CASCADE`: les dependències
poden impedir una eliminació o reimportació. El procés compara amb la lectura
inicial de PRO; no constitueix una transacció compartida entre les dues BD.

| Resultat | Codi de l’script | Log del wrapper | Codi del wrapper |
|---|---|---|---|
| Cap diferència | `0` | `OK_...` | `0` |
| Diferències corregides, verificades i confirmades | `0` | `OK_...` | `0` |
| Error, conflicte o canvi impedit per dependències | No zero | `FAIL_...` | Conserva el codi |

Les línies `AVÍS` anuncien diferències o canvis previstos. Després del commit,
el reconciliador escriu el detall amb `INFO: diferència corregida i verificada:`
i el resum `INFO: FDW sincronitzat;`. `INFO` és el nivell del missatge; el log
és `OK_...` i tant l’script com el wrapper retornen `0`. Si no hi ha diferències,
no s’emet el resum de sincronització. Qualsevol codi no zero és `FAIL`.

El wrapper continua arxivant els antics logs `INFO_...` a `z_historic`, però
ja no en crea de nous. Permet canviar el directori de logs amb `ETL_LOG_DIR`.
L’usuari ha confirmat el **23/11/2026** que el funcionament del monitor del
correu a Edison està verificat. El manteniment manual es descriu a
l’[apartat següent](#actualitzacio-manual-del-monitor-de-correu-a-edison).
No s’ha executat el reconciliador en aquesta revisió: pot modificar les
definicions FDW de HALL.

## Actualització manual del monitor de correu a Edison

El monitor operatiu és `/opt/scripts/log_monitor_hall.sh` a Edison.
L’usuari ha confirmat el **23/11/2026** que hi ha traslladat l’script i que
el funcionament està verificat. També ha confirmat que ha eliminat expressament
la còpia local `monitoring/log_monitor_hall.sh` del repositori d’`energetica_etl`.
El monitor es manté a Edison; recuperar o versionar aquesta còpia local no és
cap tasca pendent.

Abans d’editar l’script a Edison, fer-ne una còpia de seguretat amb `cp -p` i
conservar els permisos. Si es rep la nova versió en un fitxer temporal,
validar-la amb `bash -n` abans de substituir l’actual. El cron que apunta
al mateix fitxer utilitzarà el contingut nou en la següent execució.
Amb el disseny acordat, la plantilla `/opt/scripts/templates/log_report_hall.html` no necessita canvis:
els blocs FDW s’afegeixen abans de la secció general d’errors.

Comportament acordat:

- Si no s’han corregit diferències ni hi ha errors FDW, ometre tot el bloc FDW.
- Si un log `OK_*_check_public_foreign_tables_hall_*` conté
  `INFO: FDW sincronitzat;`, mostrar **FDW sincronitzat** amb el nom del fitxer.
  Aquesta execució compta només com a `OK`.
- Si hi ha un log `FAIL_*_check_public_foreign_tables_hall_*`, mostrar
  **FDW no s’ha pogut sincronitzar** amb el nom del fitxer.
- Si diferents execucions del període tenen resultats diferents, mostrar
  els dos blocs amb els seus fitxers. Els errors d’altres ETL no generen
  un bloc FDW: apareixen a la secció general d’errors.

Es conserven els recomptes `RUN`, `OK` i `FAIL`, l’assumpte original, Barman,
els destinataris i el relay SMTP. Una correcció amb èxit conserva l’assumpte
`[OK]` si no hi ha errors ETL ni de Barman; els errors mantenen `[ALERTA]`.
No hi ha comptador `INFO` addicional. El nom de tasca ha de conservar
`check_public_foreign_tables_hall` perquè el monitor reconegui els seus logs.
Es manté `find -maxdepth 1 -mmin -1440`, que exclou `z_historic`:
és una vista dels logs presents modificats les últimes 24 hores, no un
recompte exhaustiu de totes les execucions del dia.

Validació manual a Edison després de substituir el fitxer:

```bash
bash -n /opt/scripts/log_monitor_hall.sh
/opt/scripts/log_monitor_hall.sh --dry-run > /tmp/log_report_hall_preview.eml
less /tmp/log_report_hall_preview.eml
```

`--dry-run` evita SMTP, però continua consultant HALL per SSH i Barman per
Docker. El fitxer local `develrw/tests/test_log_monitor_hall.py` conserva set
casos amb dobles d’aquestes eines, utilitzats per comprovar la generació del
correu sense enviaments ni canvis a les bases de dades. Depèn de la còpia
local eliminada expressament i queda fora de la validació local actual;
no és una tasca pendent recuperar-la per executar-lo. La descoberta completa
de tests encara inclouria aquest fitxer i fallaria per la seva dependència:
per validar la part ETL, executar només els tests de reconciliació i del
wrapper, com indica el README. El monitor es valida i es manté a Edison.

### Mostres manuals i criteris d’acceptació

| Escenari | Log | Resultat al correu |
|---|---|---|
| PRO i HALL ja coincideixen | `OK_...`, sense resum de correcció | Cap bloc FDW |
| S’han corregit i confirmat diferències | `OK_...`, amb `INFO: FDW sincronitzat;` | **FDW sincronitzat** |
| Falla la tasca de reconciliació | `FAIL_...check_public_foreign_tables_hall_...` | **FDW no s’ha pogut sincronitzar** i error al recompte general |
| Falla una altra ETL | `FAIL_...` d’una altra tasca | Només la secció general d’errors |

Un fitxer de prova dins del directori real `cron_log` participa en el correu
igual que un log real mentre compleixi el filtre temporal. Les mostres han
d’indicar explícitament que no s’ha executat SQL i que els objectes són ficticis.
En acabar, retirar-les del directori principal perquè no alterin els recomptes
ni provoquin alertes posteriors. Les dues mostres `*_prova_simulada*` creades
durant la conversa ja no són presents en la revisió del 23/11/2026.

El funcionament a Edison queda registrat com a verificat per confirmació
de l’usuari del **23/11/2026**. No s’han repetit les proves remotes des d’aquest
entorn. Per a futures validacions, un `--dry-run` correcte comprova la generació;
no acredita per si sol el lliurament SMTP. La retirada intencionada de la
còpia local no deixa cap desplegament ni validació pendent a Edison.

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
sempre aquests tres components: compte remot, tots els mappings que el facin servir i configuració. Actualment són set mappings, inclòs el de `svc_powerbi`; en la rotació inicial eren sis.

1. Preparar la nova credencial a KeePass i inventariar els mappings que
   utilitzin el compte remot. No imprimir-ne les opcions amb contrasenyes.
2. El mateix `energetica` de PRO pot canviar-se la contrasenya pròpia; no cal
   superusuari per a aquesta operació. Amb `psql`, `\password energetica`
   evita escriure la contrasenya literal a la sentència de l'historial.
3. Actualitzar els mappings amb `ALTER USER MAPPING` i els blocs del YAML que
   utilitzin el mateix compte remot. El reconciliador actual demana
   `postgresql_prod_public_ro`; `postgresql_prod_ro_fw` és el nom històric de
   la rotació inicial. Comprovar l’usuari de cada bloc abans de decidir quina
   credencial cal renovar. No tornar a crear els mappings.
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
