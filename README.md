# le-tech-knowledge-base

Knowledge Base de l'Equip de Tecnologia de L'Energètica, amb Zensical i tema
`modern`. La configuració és a `zensical.toml`; les dependències estan fixades a
`requirements.txt`.

## Desenvolupament local

Amb Python 3.14, des de l'arrel del repositori:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
zensical serve
```

Obriu `http://localhost:8000`. Per construir el lloc i comprovar-lo:

```bash
zensical build --clean
python scripts/check_zensical_site.py
```

El resultat es genera a `site/`. GitHub Actions utilitza les mateixes versions i
ordres per preparar la publicació a GitHub Pages. La primera versió de producció
i el desplegament a Edison continuen pendents.

## Hooks locals

Per activar l'avís interactiu de documents `draft` abans de `git push`, executeu
una vegada per checkout:

```bash
./scripts/install-hooks.sh
```

El hook pregunta si voleu passar els esborranys a `active`, enviar-los com a
`draft` o cancel·lar. Si accepteu activar-los, atura el push perquè pugueu revisar
els canvis i fer-ne commit. Vegeu la [guia de contribució](docs/contribute/contribute.md)
i les [convencions de metadades](docs/index.md#6-metadades-del-document-yaml-front-matter).
