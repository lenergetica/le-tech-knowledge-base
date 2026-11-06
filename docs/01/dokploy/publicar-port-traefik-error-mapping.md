---
owner: miquelllover@lenergetica.cat
status: actiu
review_date: 2026-11-06
review_period_months: 6
tags:
    - dokploy
    - traefik
    - port
    - map
    - mapping
    - 8181
---


# Publicar un port a Traefik quan falla «Additional Port Mappings»

> Àmbit: servidor **Hall**, Dokploy v0.30.10 i Traefik com a contenidor `dokploy-traefik`.
> 
> Cas d'ús: publicar `https://apienergetica.gisce.cloud:8181`.

## Símptoma

En afegir el mapping `8181 → 8181 / TCP` a **Web Server → Traefik → Additional Port Mappings**, en desar apareix un error semblant a:

```text
Port 8443 is already in use by a host-level service
```

El `8443` ja és un port publicat pel mateix contenidor Traefik per a la consola de Dokploy. L'error és una validació incorrecta de Dokploy: interpreta un mapping existent de Traefik com si fos un conflicte extern.

## Què no resol l'edició de `traefik.yml`

Afegir aquest `entryPoint` a `/etc/dokploy/traefik/traefik.yml` és necessari:

```yaml
  api-secure:
    address: :8181
    http:
      tls: {}
```

Però això només fa que Traefik escolti el port **dins del contenidor**. També cal publicar al host el mapping Docker `8181:8181/tcp`.

## Workaround: recrear Traefik amb el port addicional

Aquest procediment conserva els ports existents `80`, `443` (TCP i UDP) i `8443`, i hi afegeix `8181`.

Hi haurà uns segons d'indisponibilitat de les rutes de Traefik, inclosa la consola de Dokploy. No s'ha d'eliminar el contenidor anterior fins que les comprovacions siguin correctes.

### 1. Còpia i comprovació prèvia

```bash
taskstamp="$(date +%Y%m%d-%H%M%S)"
TRAEFIK_IMAGE="$(docker inspect -f '{{.Config.Image}}' dokploy-traefik)"

sudo mkdir -p /root/dokploy-traefik-backups
sudo tar -C /etc/dokploy -czf "/root/dokploy-traefik-backups/traefik-${taskstamp}.tgz" traefik
docker inspect dokploy-traefik \
  | sudo tee "/root/dokploy-traefik-backups/dokploy-traefik-${taskstamp}.json" >/dev/null

echo "$TRAEFIK_IMAGE"
sudo grep -A4 '^  api-secure:' /etc/dokploy/traefik/traefik.yml
```

L'última ordre ha de mostrar l'`entryPoint` `api-secure` al `:8181`.

### 2. Recreació manual

```bash
sudo docker stop dokploy-traefik
sudo docker rename dokploy-traefik "dokploy-traefik-backup-${taskstamp}"

sudo docker run -d \
  --name dokploy-traefik \
  --restart always \
  -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
  -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -p 80:80/tcp \
  -p 443:443/tcp \
  -p 443:443/udp \
  -p 8443:8443/tcp \
  -p 8181:8181/tcp \
  "$TRAEFIK_IMAGE"

sudo docker network connect dokploy-network dokploy-traefik
```

El contenidor anterior queda aturat amb el nom `dokploy-traefik-backup-<data>`, de manera que es pot restaurar ràpidament.

### 3. Validació

```bash
docker port dokploy-traefik
sudo ss -ltnp '( sport = :8181 )'
docker logs --tail 50 dokploy-traefik
```

S'ha de veure `8181/tcp -> 0.0.0.0:8181` (i la versió IPv6 si està activada).

Comprovar també que la consola continua accessible:

```bash
curl -kI --connect-timeout 5 \
  --resolve gw.lenergetica.gisce.cloud:8443:127.0.0.1 \
  https://gw.lenergetica.gisce.cloud:8443/
```

I provar l'endpoint de l'API amb el camí que estigui configurat, per exemple:

```bash
curl -k --connect-timeout 5 \
  --resolve apienergetica.gisce.cloud:8181:127.0.0.1 \
  https://apienergetica.gisce.cloud:8181/<camí-del-ping>
```

Quan tot funcioni, es pot eliminar el contenidor de reserva en una finestra posterior:

```bash
sudo docker rm "dokploy-traefik-backup-${taskstamp}"
```

## Rollback

Si el nou Traefik no arrenca o deixa de publicar les rutes:

```bash
sudo docker rm -f dokploy-traefik
sudo docker rename "dokploy-traefik-backup-${taskstamp}" dokploy-traefik
sudo docker start dokploy-traefik
```

## Manteniment posterior

- No editar mai els fitxers interns de Docker sota `/var/lib/docker`.
- Després d'una actualització o recreació de Traefik, verificar sempre:

  ```bash
  docker port dokploy-traefik
  ```

- Si el mapping `8181:8181` ha desaparegut, repetir la recreació anterior, emprant la imatge que estigui executant Traefik en aquell moment.
- El fitxer `/etc/dokploy/traefik/traefik.yml` conserva l'`entryPoint`, però no conserva per si sol el mapping Docker del host.
