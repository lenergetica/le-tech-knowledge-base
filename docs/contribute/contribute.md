---
title: "Contribuir a la Knowledge Base"
author: "joseantonioarias"
reviewed_by: "joseantonioarias"
owner: "Equip de Tecnologia de L'Energètica"
status: "draft"
version: "1.0"
creation_date: "2026-10-01"
review_date: "2026-11-05"
review_after_months: 60
tags:
    - "KB"
    - "Zensical"
    - "contribucio"
references:
    - "https://zensical.org/docs/get-started/"
---

# Contribuir a la Knowledge Base

## Preparar l'entorn

Utilitzeu Python 3.14. Des de l'arrel del repositori:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
./scripts/install-hooks.sh
```

Les versions de Zensical i les dependències estan fixades a `requirements.txt`.
La configuració del lloc és a `zensical.toml`, amb el tema `modern` i la llengua
catalana. Els hooks s'han d'activar una vegada a cada checkout.

## Crear o actualitzar un document

1. Situeu el Markdown al directori adequat de `docs/`.
2. Completeu les [metadades](../index.md#6-metadades-del-document-yaml-front-matter).
   Els documents nous comencen en `draft`; en editar-los, actualitzeu
   `reviewed_by` i `review_date` i conserveu l'autoria i la data de creació.
3. Si és una pàgina nova, afegiu-la a `project.nav` de `zensical.toml`.
4. Previsualitzeu-la amb `zensical serve` i obriu `http://localhost:8000`.
5. Construïu i comproveu el lloc abans de fer commit:

    ```bash
    zensical build --clean
    python scripts/check_zensical_site.py
    ```

Reviseu també els enllaços, la cerca i els diagrames al navegador. Mermaid
s'inicialitza amb la integració nativa de Zensical; no afegiu un CDN o un script
propi per inicialitzar-lo.

## Fer push

El hook comprova els documents afectats que continuen en `draft` i pregunta si
voleu passar-los a `active`, enviar-los com a esborranys o cancel·lar.
Si accepteu activar-los, s'atura el push: reviseu i feu commit dels canvis abans
de repetir-lo. El hook no fa commits automàticament.

## Construcció i publicació

GitHub Actions executa `zensical build --clean` amb Python 3.14 i les dependències
fixades, valida el lloc i envia `site/` a GitHub Pages. La primera publicació de
producció i el desplegament a Edison continuen pendents.
