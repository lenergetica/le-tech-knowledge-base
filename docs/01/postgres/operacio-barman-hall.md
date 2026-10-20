---
owner: L'Energetica Tech
status: draft
review_date: 2026-10-20
review_period_months: 1
tags:
    - postgresql
    - hall
    - edison
    - base de dades
    - databasus
    - develrw
---

# Operació de les còpies PostgreSQL de Hall amb Barman

Aquest document descriu com aturar i reprendre les còpies del clúster PostgreSQL de Hall.

!!! warning "Còpies físiques"
    Barman fa còpies **físiques de tot el clúster PostgreSQL**. Per tant, la còpia inclou totes les bases de dades de la instància, no només `energetica`.

## Dades de l'entorn

- Servei Barman a Dokploy: el desplegat des de `infra/barman/compose.edison-dokploy.yml`.
- Servidor configurat a Barman: `energetica`.
- PostgreSQL origen: `gw.lenergetica.gisce.cloud:5444`.
- Replication slot: `barman_energetica`.
- Espai de còpies actual: `/mnt/barman` al servidor de Dokploy.
- Còpia programada: a les `02:00` UTC (configurable amb `BARMAN_BACKUP_TIME_UTC`).

Per trobar el contenidor en execució sense dependre del seu identificador temporal:

``` bash
docker ps --filter 'name=_barman.' --format 'table {{.Names}}\t{{.Status}}'
```

Als exemples següents, substituïu `<contenidor-barman>` pel nom retornat per aquesta ordre.

## Què cal saber abans d'aturar-lo

Barman rep contínuament els WAL de PostgreSQL mitjançant el replication slot. Els WAL són els
canvis necessaris per deixar una còpia física en un estat recuperable.

Si Barman s'atura però el slot continua existint, PostgreSQL **no pot eliminar els WAL pendents**
per a Barman. En una pausa llarga això pot omplir el disc de PostgreSQL. Per això, abans d'una
actualització o d'una aturada de durada desconeguda, cal aturar Barman i eliminar el slot.

## Aturada segura per a manteniment llarg

### 1. Aturar Barman a Dokploy

Des de Dokploy, atureu el servei o l'stack de Barman. No cal eliminar el desplegament ni els seus
volums.

Comproveu que ja no hi ha cap procés de Barman actiu. Aquesta ordre només funcionarà mentre el
contenidor encara estigui en marxa; és útil abans d'aturar-lo:

``` bash
docker exec --user barman <contenidor-barman> \
  env PGPASSFILE=/var/lib/barman-locks/.pgpass \
  barman list-processes energetica
```

No hi ha d'haver cap procés `backup`. Que hi aparegui `receive-wal` abans d'aturar el servei és
normal.

### 2. Confirmar que el slot ja no és actiu

Connecteu-vos a PostgreSQL amb un usuari administrador i executeu:

``` sql
SELECT slot_name, active
FROM pg_replication_slots
WHERE slot_name = 'barman_energetica';
```

El resultat ha de mostrar `active = false` (a `psql`, `[ ]`). Si encara és actiu, espereu uns
segons i repetiu la consulta. No elimineu un slot actiu.

### 3. Eliminar el replication slot

Quan el resultat sigui inactiu:

``` sql
SELECT pg_drop_replication_slot('barman_energetica');
```

Amb això PostgreSQL deixa de retenir WAL per a Barman. Les còpies que ja hi havia a Barman no es
modifiquen, però durant la pausa no hi haurà còpia contínua ni recuperació a un punt en el temps.

### 4. Verificació opcional

``` sql
SELECT slot_name
FROM pg_replication_slots
WHERE slot_name = 'barman_energetica';
```

No ha de retornar cap fila.

## Pausa curta

Per una intervenció molt curta es pot aturar només Barman a Dokploy i tornar-lo a iniciar després.
No s'ha d'eliminar el slot en aquest cas.

No és una opció adequada per a processos llargs o de durada incerta: PostgreSQL conservarà els
WAL pendents mentre Barman estigui aturat i podria quedar-se sense espai.

## Reprendre les còpies després del manteniment

Després d'una pausa segura, cal tornar a crear el flux de WAL i fer una còpia física nova.

### 1. Iniciar Barman a Dokploy

Inicieu el servei/stack de Barman des de Dokploy i espereu que aparegui com a saludable:

``` bash
docker ps --filter 'name=_barman.' --format 'table {{.Names}}\t{{.Status}}'
```

### 2. Iniciar la recepció de WAL

El fitxer de configuració conté `create_slot = auto`; Barman recrearà automàticament el slot quan
s'inicialitzi la recepció. Per fer-ho immediatament, sense esperar el cicle intern d'un minut:

``` bash
docker exec --user barman <contenidor-barman> \
  env PGPASSFILE=/var/lib/barman-locks/.pgpass \
  barman cron
```

### 3. Comprovar la connexió

``` bash
docker exec --user barman <contenidor-barman> \
  env PGPASSFILE=/var/lib/barman-locks/.pgpass \
  barman check energetica
```

Han de sortir com a `OK`, com a mínim, `PostgreSQL streaming`, `replication slot` i
`receive-wal running`.

### 4. Crear una còpia física nova

No s'ha de confiar en els WAL anteriors a la pausa. Feu una còpia base nova manualment o espereu
l'hora programada:

``` bash
docker exec --user barman <contenidor-barman> \
  env PGPASSFILE=/var/lib/barman-locks/.pgpass \
  barman backup energetica
```

En acabar, forceu l'arxivament del WAL de tancament i verifiqueu la còpia:

``` bash
docker exec --user barman <contenidor-barman> \
  env PGPASSFILE=/var/lib/barman-locks/.pgpass \
  barman switch-wal --archive energetica

docker exec --user barman <contenidor-barman> \
  env PGPASSFILE=/var/lib/barman-locks/.pgpass \
  barman check-backup energetica latest

docker exec --user barman <contenidor-barman> \
  env PGPASSFILE=/var/lib/barman-locks/.pgpass \
  barman verify-backup energetica latest
```

`check-backup` i `verify-backup` no mostren sortida quan tenen èxit; l'indicador fiable és el codi
de sortida `0` de l'ordre.

## Esborrar les còpies i començar de zero

Només si no cal conservar cap còpia existent, amb Barman aturat i el slot eliminat, es pot esborrar
el directori del servidor a l'espai de còpies:

``` bash
sudo du -sh /mnt/barman/energetica
sudo rm -rf /mnt/barman/energetica
```

La segona ordre és destructiva: elimina les còpies físiques, els WAL i el catàleg de Barman de
`energetica`. No modifica les dades del PostgreSQL origen.

## Incidència coneguda: CIFS directe

La còpia gran de Hall va fallar escrivint directament al CIFS amb un error `fsync` (`Bad file
descriptor`), acompanyat al servidor de missatges `CIFS: VFS: No writable handle in writepages`.

Abans de reprendre còpies grans, cal adoptar emmagatzematge local fiable per a Barman (per exemple,
un disc local ext4/XFS) i replicar després les còpies completes cap al CIFS. La compressió pot
reduir trànsit i espai, però no resol aquest error de durabilitat del muntatge CIFS.
