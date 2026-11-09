# Tasques pendents de la KB

Darrera actualització: 2026-11-05.

## Publicació i contingut

- [ ] Migrar la documentació restant de ClickUp a `docs/`, amb les metadades
    i la navegació de la KB.
- [ ] Confirmar la correspondència entre producció i preproducció a la
    [guia de l'API GISCE](docs/02/gisce/api-rest-gisce.md): els encapçalaments
    actuals barregen «producció (PRE)» i «preproducció (PRO)».

## Convencions i presentació

- [ ] Acordar i documentar a la [guia de la KB](docs/index.md) una convenció
    de noms de fitxer: minúscules, accents, separadors i estabilitat dels noms.
    Aplicar-la revisant també els enllaços i `zensical.toml`.
- [ ] Definir l'idioma i el vocabulari de les etiquetes `tags`, i unificar les
    existents. Els camps de metadades i els valors de `status` ja estan documentats.
- [ ] Mostrar a cada article l'autoria original, qui ha fet l'última
    actualització i la data corresponent, aprofitant `author`, `reviewed_by`
    i `review_date`.
- [ ] Revisar si es poden simplificar la
    [plantilla de metadades](overrides/main.html) i els
    [avisos de revisió](docs/assets/javascripts/status-warning.js), conservant
    el comportament validat amb el tema `modern`.

## Automatització

- [ ] Definir quins estats i dates han de generar una tasca de revisió a
    ClickUp i implementar l'automatització evitant tasques duplicades.

## PostgreSQL i migracions

- [ ] Determinar la ubicació canònica i versionar
    `projectes/energetica_utils/copia_dades_pro2hall.sh`, encara referenciat al
    [procediment de migració](docs/01/postgres/migrar-scripts-etl-de-pro-a-hall.md).
- [ ] Investigar les diferències de rendiment entre PRO i HALL, comparant
    consultes, plans d'execució i configuració.
