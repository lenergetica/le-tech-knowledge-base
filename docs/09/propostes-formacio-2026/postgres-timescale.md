---
owner: miquelllover@lenergetica.cat
status: draft
review_date: 2026-11-09
review_period_months: 6
tags:
    - formacio
    - postgres
    - timescale
    - postgis
---

# Fitxa formativa — Taller de PostgreSQL, TimescaleDB i PostGIS

## Denominació

Taller pràctic d’administració, rendiment i operació de PostgreSQL amb TimescaleDB i PostGIS.

## Durada

12 hores, distribuïdes en 4 sessions de 3 hores.

## Modalitat

Virtual en directe, amb format de taller pràctic.

## Destinataris

Professionals de l’equip de Tecnologia que administrin, desenvolupin, integrin o operin aplicacions i processos que utilitzen PostgreSQL, TimescaleDB o PostGIS. També professionals d'altres equips que treballin amb scripts de PostgreSQL.

## Objectiu general

Millorar la capacitat de l’equip per operar, diagnosticar, mantenir i optimitzar les bases de dades PostgreSQL pròpies, amb especial atenció a les dades temporals gestionades amb TimescaleDB i als casos geoespacials amb PostGIS. Conèixer els mecanismes d'optimització d'scripts PostgreSQL.

## Objectius específics

- Entendre els elements principals que afecten el rendiment i l’operació de PostgreSQL.
- Analitzar consultes, bloquejos i incidències mitjançant eines i mètriques natives.
- Aplicar bones pràctiques d’indexació, manteniment, còpia de seguretat, recuperació i monitoratge.
- Dissenyar i operar dades temporals amb TimescaleDB: hypertables, compressió, retenció i agregacions contínues.
- Conèixer les funcionalitats essencials de PostGIS i els criteris per treballar amb dades geogràfiques eficientment.
- Treballar sobre casos, dades i configuracions representatives dels entorns de preproducció.
- Obtenir recomanacions prioritzades i aplicables als sistemes revisats.

## Metodologia

Cada sessió combinarà aproximadament:

- **1,5 hores de formació conceptual i demostracions** per part de la persona docent.
- **1,5 hores de taller guiat** sobre una còpia de l’entorn de preproducció, amb consultes, processos o incidències reals prèviament seleccionats.

La formació haurà de prioritzar la transferència pràctica de coneixement, l’explicació del perquè de les decisions tècniques i l’obtenció de resultats reutilitzables per l’equip.

## Programa

| Sessió | Contingut formatiu | Taller aplicat |
| --- | --- | --- |
| **1. PostgreSQL: arquitectura, diagnosi i rendiment** | Arquitectura de PostgreSQL; processos, connexions, memòria, WAL, transaccions, bloquejos i autovacuum. Diagnosi amb estadístiques i logs. Anàlisi de plans amb `EXPLAIN (ANALYZE)`. Principis d’indexació. Introducció pràctica a PostGIS: tipus espacials, SRID, índexs espacials i consultes habituals. | Revisió de l’arquitectura i patrons de càrrega propis. Anàlisi de consultes lentes, bloquejos, transaccions llargues o problemes d’indexació. Revisió d’algun cas geogràfic existent, si escau. |
| **2. PostgreSQL: operació, manteniment i continuïtat** | Estratègies de còpia de seguretat i restauració; recuperació davant incidències; replicació i alta disponibilitat segons necessitats. Manteniment preventiu, *bloat*, gestió de capacitat, actualitzacions, seguretat bàsica, automatització i monitoratge. | Revisió de les pràctiques actuals de còpia, restauració i monitoratge. Identificació de riscos, comprovació de processos crítics i definició de millores prioritzades. |
| **3. TimescaleDB: modelatge i cicle de vida de les dades** | Hypertables i particionament temporal; criteris de disseny; ingestió; índexs; compressió; retenció; polítiques automatitzades i gestió del volum de dades. | Revisió de taules temporals i fluxos de càrrega propis. Ajust o proposta de particionament, compressió, retenció i manteniment. |
| **4. TimescaleDB: consultes, agregacions i casos avançats** | Continuous aggregates; optimització de consultes temporals; combinació amb dades relacionals i, si és rellevant, geogràfiques; patrons de consulta; anti-patrons i criteris d’evolució. | Resolució de casos seleccionats per l’equip. Recull final de recomanacions, decisions pendents i possibles accions de millora. |

## Requisits previs dels participants

No es requereix experiència prèvia com a DBA, però és recomanable:

- Coneixement bàsic de SQL i bases de dades relacionals.
- Familiaritat amb algun dels sistemes PostgreSQL de l’organització.
- Per als participants tècnics, coneixements bàsics de Linux i línia d’ordres.

## Preparació prèvia

Abans de la formació, l’equip facilitarà a la persona docent:

- Descripció breu de l’arquitectura i dels entorns implicats.
- Versions de PostgreSQL, TimescaleDB i PostGIS.
- Volums aproximats, ritme de creixement i patrons principals de càrrega.
- Configuracions rellevants, mecanismes de còpia de seguretat i monitoratge existents.
- Entre dos i quatre casos pràctics prioritaris: consultes lentes, incidències, creixement, càrregues ETL, dades temporals o consultes geogràfiques.
- Accés acordat a l’entorn de preproducció necessari per al taller.

## Resultats esperats

En acabar la formació, s’hauria de disposar de:

- Millor autonomia de l’equip per interpretar incidències i diagnosticar problemes de rendiment.
- Exemples concrets de consultes, índexs, polítiques de TimescaleDB i tasques de manteniment adaptats als casos revisats.
- Recomanacions tècniques prioritzades per millorar rendiment, fiabilitat, operació i escalabilitat.
- Una guia breu o document de conclusions amb les accions acordades, els criteris operatius i els aspectes pendents.

## Perfil requerit de la persona docent

- Experiència demostrable com a DBA, arquitecte/a o consultor/a de PostgreSQL en entorns de producció.
- Domini pràctic de diagnosi de rendiment, `EXPLAIN (ANALYZE)`, indexació, autovacuum, WAL, còpia de seguretat/restauració, replicació i monitoratge.
- Experiència real amb TimescaleDB: hypertables, compressió, retenció, continuous aggregates, ingestió i optimització de consultes temporals.
- Coneixements sòlids de PostGIS: modelatge espacial, sistemes de referència, índexs espacials i optimització de consultes geogràfiques.
- Experiència amb Linux, automatització i eines habituals d’operació de bases de dades.
- Capacitat docent per adaptar el contingut a sistemes existents, conduir un taller tècnic i convertir les conclusions en recomanacions clares i accionables.
