# Migració de BD PostgreSQL/TimescaleDB a un volum dedicat

## Resum

S'ha mogut el directori de dades del contenidor `etl-postgres` des del volum Docker local al disc dedicat muntat a `/mnt/HC_Volume_103924452`. La migració s'ha completat i s'ha confirmat que funciona.

El contenidor utilitza la imatge `timescale/timescaledb:2.11.2-pg15`. PostgreSQL continua veient les dades a `/var/lib/postgresql/data`; només ha canviat la ruta d'origen al servidor.

## Configuració abans de la migració

- Volum Docker d'origen: `etl-postgres-pgdata`
- Ruta de l'amfitrió observada: `/var/lib/docker/volumes/etl-postgres-l4ljbf_etl-postgres-pgdata/_data`
- Ruta de dades dins del contenidor: `/var/lib/postgresql/data`
- Disc nou: `/dev/sdb`, muntat a `/mnt/HC_Volume_103924452` (ext4)

## Configuració final al Compose

Al servei `etl-postgres`, el muntatge de dades és un *bind mount*:

```yaml
services:
  etl-postgres:
    volumes:
      - /mnt/HC_Volume_103924452/postgres/data:/var/lib/postgresql/data
```

La forma és `ruta_de_l'amfitrió:ruta_dins_del_contenidor`. La ruta dins del contenidor continua sent `/var/lib/postgresql/data`, que és també el valor de `PGDATA` per defecte de la imatge.

El Compose també tenia un muntatge de fitxer per a `pg_hba.conf`. Aquest és independent del directori de dades i es va deixar intacte.

La declaració superior següent del volum antic es va conservar durant la migració:

```yaml
volumes:
  etl-postgres-pgdata: null
```

Conservar-la permet mantenir la referència disponible per a una possible tornada enrere; el servei ja no utilitza aquest volum mentre tingui configurat el *bind mount* anterior.

## Procediment de migració

1. Comprovar amb `docker inspect` que el contenidor munta el volum Docker `etl-postgres-pgdata` a `/var/lib/postgresql/data`.
  ```bash
  docker ps | grep etl-postgres
  docker inspect --format '{{range .Mounts}}{{printf "%s %s -> %s\n" .Type .Source .Destination}}{{end}}' <ID_o_nom_actual_del_contenidor>
  ```
2. Confirmar amb PostgreSQL que `data_directory` és `/var/lib/postgresql/data`.
3. Comprovar que el disc dedicat està muntat a `/mnt/HC_Volume_103924452` i que aquest muntatge es restableix després d'un reinici.
4. Aturar des de Dokploy els serveis que escriuen a la base de dades i després PostgreSQL. Copiar les dades al disc dedicat preservant permisos, propietaris i atributs:
  ```bash
  sudo mkdir -p /mnt/HC_Volume_103924452/postgres/data
  sudo rsync -aHAX --numeric-ids --info=progress2 \
    /var/lib/docker/volumes/etl-postgres-l4ljbf_etl-postgres-pgdata/_data/ \
    /mnt/HC_Volume_103924452/postgres/data/
  ```
5. Comprovar que la còpia conté `PG_VERSION` i ocupa una mida coherent amb el directori original.
6. Canviar al Compose el muntatge de dades del servei pel *bind mount* nou i fer *redeploy* des de Dokploy.
7. Verificar el muntatge efectiu i que PostgreSQL arrenca i dona accés a les dades esperades abans de reprendre les escriptures.

## Comprovacions útils

Confirmar el muntatge del contenidor:

```bash
docker inspect --format '{{range .Mounts}}{{printf "%s %s -> %s\n" .Type .Source .Destination}}{{end}}' <ID_o_nom_actual_del_contenidor>
```

Per a les dades, s'espera una línia semblant a:

```text
bind /mnt/HC_Volume_103924452/postgres/data -> /var/lib/postgresql/data
```

Confirmar la versió principal de PostgreSQL copiada:

```bash
sudo cat /mnt/HC_Volume_103924452/postgres/data/PG_VERSION
```

El resultat esperat per a aquesta instal·lació és `15`.

## Important en recrear el contenidor en un altre servidor

El Compose conté una **ruta absoluta de l'amfitrió**. Si es recrea o desplega aquest contenidor en un altre servidor, no s'ha de donar per fet que `/mnt/HC_Volume_103924452/postgres/data` existeixi ni que contingui les dades.

Abans del desplegament al nou servidor:

- Muntar-hi i verificar el disc o directori que allotjarà les dades.
- Assegurar que el muntatge del disc es restableix després d'un reinici.
- Copiar-hi o restaurar-hi les dades de PostgreSQL, preservant propietaris i permisos; o inicialitzar una base nova si aquest és el propòsit.
- Actualitzar al Compose la ruta de l'amfitrió perquè coincideixi amb la ruta real del nou servidor.
- Mantenir la ruta del contenidor `/var/lib/postgresql/data` i no canviar la imatge/versió de PostgreSQL en la mateixa operació de migració.
- Verificar que PostgreSQL no s'inicia sobre un directori buit del disc del sistema si el disc de dades no està muntat.

Un *bind mount* no copia les dades ni les transporta entre servidors: només connecta una ruta existent de l'amfitrió amb una ruta del contenidor.

## Tornada enrere

Conservar el volum Docker antic fins que la instal·lació nova hagi estat validada. Per tornar-hi:

1. Aturar el contenidor nou.
2. Canviar al Compose el muntatge de dades a:
  ```
  - etl-postgres-pgdata:/var/lib/postgresql/data
  ```
3. Fer *redeploy*.

!!! note "NOTA: No executar les dues ubicacions alhora sobre la mateixa instància. Si s'han escrit dades noves al disc dedicat després de la migració, la còpia antiga no inclourà aquests canvis; caldrà tenir-ho en compte abans de tornar enrere."