# le-tech-knowledge-base
Knowledge Base de l'equip Tech de L'Energètica


Per activar l'avís interactiu de documents `draft` abans de `git push`, executeu
una vegada per checkout (requereix Git i Python 3.9 o superior):

```bash
./scripts/install-hooks.sh
```

El hook pregunta si voleu passar els esborranys a `active`, enviar-los com a
`draft` o cancel·lar. Si accepteu activar-los, atura el push perquè pugueu revisar
els canvis i fer-ne commit. Vegeu els detalls a [la guia de la KB](docs/index.md#avis-de-documents-draft-abans-del-push).
