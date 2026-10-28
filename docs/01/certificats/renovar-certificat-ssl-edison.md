---
owner: miquelllover@lenergetica.cat
status: actiu
review_date: 2026-10-28
review_period_months: 6
tags:
    - certificat
    - ssl
    - edison
    - https
    - tera
    - seguretat
---

# Certificats


# Certificats SSL/TLS

# Propòsit
Inventari dels certificats SSL/TLS de l'organització, amb informació de caducitat, ubicació i mecanismes de renovació.

# Inventari de certificats

| Subject Common Name | Subject Organization | Subject Alternative Name | Issuer Common Name | Issuer Organization | Not Before | Not After | Vigència | Proveïdor |
| ---| ---| ---| ---| ---| ---| ---| ---| --- |
| [lenergetica.cat](http://lenergetica.cat) | \- | [lenergetica.cat](http://lenergetica.cat) | E8 | Let's Encrypt | 25/02/2026 | 26/05/2026 | 90 | Utrans |
| [area-usuari.lenergetica.cat](http://area-usuari.lenergetica.cat) | Generalitat de Catalunya | [area-usuari.lenergetica.cat](http://area-usuari.lenergetica.cat)<br>[www.area-usuari.lenergetica.cat](http://www.area-usuari.lenergetica.cat) | Sectigo Public Server Authentication CA OV R36 | Sectigo Limited | 17/03/2026 | 02/10/2026 | 199 | GISCE |
| [talent.lenergetica.cat](http://talent.lenergetica.cat) | \- | [talent.lenergetica.cat](http://talent.lenergetica.cat) | E8 | Let's Encrypt | 13/03/2026 | 11/06/2026 | 90 | Utrans |
| [econnecta.cat](http://econnecta.cat) |  |  |  |  |  |  |  | Pendent |

# Ubicació dels certificats
Els certificats es guarden al Keepass a "Certificats SSL/TLS"
# Sistema d'alertes
Al calendari de [tecnologia@lenergetica.cat](mailto:tecnologia@lenergetica.cat) hi ha els recordatoris de caducitat (avís una setmana abans) perquè n'estiguem al cas. Amb cada renovació, cal afegir els nous recordatoris al calendari.
# Procés de renovació
Els certificats es generen d'ofici per part de:

Operació dels Sistemes d’Identificació Digital
Àrea d'Operacions de la Seguretat
Telf. 677 034 158 | 699 44 98 57
[identitat.digital@ciberseguretat.cat](mailto:identitat.digital@ciberseguretat.cat)

Són enviats a en Marc Llucià del CTTI, que els fa arribar per correu a la Randa (arxius i clau per separat).
## Proveïdor GISCE
Es deixen els arxius del certificat al servidor energetica-erp a la carpeta `/home/energetica` i se'ls avisa.

# Certificats SSL/TLS propis


# Propòsit
Com generem i renovem els certificats propis (CA Root LEnergetica).
# Com es genera el certificat arrel de L'Energètica
Navegar al directori CA (Edison):

```bash
$ cd /srv/infra/nginx/ca
```

Generar la nova Root CA (10 anys):

```bash
$ openssl req -x509 -nodes -new -sha256 -days 3650 -newkey rsa:4096 \
  -keyout lenergetica-ca.key -out lenergetica-ca.crt \
  -config ca.cnf
```

Això us demanarà dades (Country, Organization, etc.). Podeu utilitzar els mateixos valors que tenia la CA anterior o deixar els que vinguin per defecte al `ca.cnf`:

```bash
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_ca

[dn]
C = ES
ST = Catalonia
L = Barcelona
O = LEnergetica
CN = LEnergetica Root CA

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
```

Verificar que s'ha creat:

```bash
$ ls -lh lenergetica-ca.*
```

Comprovar la data de caducitat del certificat:

```bash
$ openssl x509 -enddate -noout -in lenergetica-ca.crt


notAfter=Apr 17 08:47:53 2036 GMT
```

Ara caldria:
*   ~~Moure la clau privada "lenergetica-ca.key" a un lloc segur~~ _~~offline~~_~~.~~ JA S'HA GUARDAT AL KEEPASS.
*   ~~Eliminar-la del servidor.~~
*   Desplegar la clau pública "lenergetica-ca.crt" als ordinadors Windows pertinents.
# Com es genera un certificat de servidor
Quan s'ha de generar (per primer cop o perquè ha caducat) un certificat de servidor, cal que recupereu la clau privada CA Root de LEnergetica des del lloc segur _offline, c_ap al servidor, a `/srv/infra/nginx/ca`

Cal disposar d'un arxiu amb la informació del certificat que volem generar `edison-server.cnf`:

```java
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = ES
ST = Catalonia
L = Barcelona
O = LEnergetica
CN = edison.gcc.intranet.gencat.cat

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = edison.gcc.intranet.gencat.cat
DNS.2 = localhost
IP.1 = 10.176.241.223
IP.2 = 127.0.0.1
```

O `hall-server.cnf`:

```java
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = ES
ST = Catalonia
L = Barcelona
O = LEnergetica
CN = gw.lenergetica.gisce.cloud

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = gw.lenergetica.gisce.cloud
DNS.2 = localhost
IP.1 = 192.168.24.2
IP.2 = 127.0.0.1
```

Genereu la nova clau de servidor per 90 dies:

```bash
$ cd /srv/infra/nginx/ca

# Generar clau i CSR
$ openssl req -new -nodes -newkey rsa:2048 \
    -keyout edison-server.key -out edison-server.csr \
    -config edison-server.cnf

# Signar amb la Root CA (90 dies)
$ sudo openssl x509 -req -sha256 -days 90 \
    -in edison-server.csr -CA lenergetica-ca.crt -CAkey lenergetica-ca.key \
    -CAcreateserial -out edison-server.crt \
    -extensions v3_req -extfile edison-server.cnf
```

Verifiqueu les dates:

```bash
$ openssl x509 -enddate -noout -in edison-server.crt
```

Actualitzar els certificats a nginx:

```bash
$ sudo rm /srv/infra/nginx/ssl/cert.crt /srv/infra/nginx/ssl/cert.key
$ sudo cp /srv/infra/nginx/ca/edison-server.crt /srv/infra/nginx/ssl/cert.crt
$ sudo cp /srv/infra/nginx/ca/edison-server.key /srv/infra/nginx/ssl/cert.key
```

Reinicieu nginx perquè agafi el nou certificat:

```bash
$ cd /srv/infra/nginx
$ docker compose restart nginx
```

Ara caldria:
*   Esborrar `lenergetica-ca.key` del servidor (ja està desada offline).
*   Actualitzar `lenergetica-ca.srl` al repositori offline, per no perdre la sèrie de generacions

# Com s'instal·la manualment el certificat CA Root LEnergetica a Windows

A la carpeta:

**Generalitat de Catalunya\\L'Energètica - 00\_Recursos\\03\_TIC\\Certificat CA L'Energètica**

Existeix un script (`instalar-certificat.cmd`) amb una instrucció que és capaç de desar el certificat arrel allà on toca :

```bash
> certutil -user -addstore Root "%~dp0lenergetica-ca.crt"
```

Si no funciona (permisos per instal·lar) es pot fer doble clic a l'arxiu lenergetica-ca.crt, s'obrirà una finestra. Cal fer clic a **Instalar certificado**:

![](https://t9012596076.p.clickup-attachments.com/t9012596076/9a893d96-1988-46fc-ad05-bb0af2239f8a/image.png)

**Usuario actual**, **Siguiente**:

![](https://t9012596076.p.clickup-attachments.com/t9012596076/64eba84a-17f8-4334-9208-4f6f6e0c813e/image.png)

**Colocar todos los certificados en el siguiente almacén**, **Examinar**:

![](https://t9012596076.p.clickup-attachments.com/t9012596076/6741509f-ef36-4433-bbd8-46882776630a/image.png)

**Entidades de certificación raíz de confianza**, **Aceptar**:

![](https://t9012596076.p.clickup-attachments.com/t9012596076/f658a6f1-0cfe-47c0-9816-b61b21444d3a/image.png)

**Siguiente**:

![](https://t9012596076.p.clickup-attachments.com/t9012596076/7d55d9ee-0a36-420a-a466-a3b64b7f682f/image.png)

**Finalizar**:

![](https://t9012596076.p.clickup-attachments.com/t9012596076/9c016a28-9a3b-4e8d-97b1-ccddd76e6be5/image.png)

Si tot ha anat bé, apareix:

![](https://t9012596076.p.clickup-attachments.com/t9012596076/ce052d34-f3e2-4d01-99a6-b2296b34c99f/image.png)
# Comprovar si hi ha instal·lat el certificat CA Root LEnergetica a Windows

Obrir l'administrador de certificats d'usuari (tecla Windows i escriure "cert"):

![](https://t9012596076.p.clickup-attachments.com/t9012596076/5431a266-288a-4813-a2c9-a3da479fbcd3/image.png)

A **Certificados - Usuario actual**, **Entidades de certificación raíz de confianza**, **Certificados**:

![](https://t9012596076.p.clickup-attachments.com/t9012596076/9551f066-ad4c-4bae-8681-07e066bc1420/image.png)

Hauríem de veure el certificat "LEnergetica Root CA" amb vigència fins el 17/04/2036.

Si voleu eliminar el certificat, des d'aquí mateix, botó dret i **Eliminar.**
