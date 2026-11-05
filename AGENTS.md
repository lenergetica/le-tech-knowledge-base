# Instruccions per a la Knowledge Base

Quan creeu o actualitzeu un document de la KB a `docs/`, manteniu-ne també les
metadades YAML, encara que l'usuari només demani un canvi de text o format.
Apliqueu la convenció de [docs/index.md](docs/index.md), que és la font de veritat
per als camps, les plantilles i el format. Per documentar una sessió, seguiu
l'[skill document-session](.github/skills/document-session/SKILL.md).

- En crear un document, establiu `author` i `reviewed_by` amb el nom de l'usuari
  que fa el canvi: primer el nom que hagi indicat i, si no n'ha indicat cap,
  `git config user.name` del repositori. No atribuïu l'autoria a l'assistent.
  Poseu la data actual a `creation_date` i `review_date` i establiu `status: "draft"`.
- En editar un document, conserveu `author` i `creation_date`; actualitzeu
  `reviewed_by` i `review_date`. Si la identitat o l'autoria original no es poden
  determinar, no les inventeu. Useu la data local de l'usuari quan estigui disponible.
- Establiu `owner: "Equip de Tecnologia de L'Energètica"`.
- Per a `review_after_months`, el valor per defecte és `60`. Conserveu els terminis
  explícits existents tret que l'usuari demani canviar-los. Si trobeu l'antic
  `review_period_months`, migreu-ne el valor al camp nou.
- Manteniu juntes `creation_date`, `review_date` i `review_after_months`, i poseu
  entre cometes dobles els textos i les dates; deixeu els enters sense cometes.
- Reviseu els altres camps de la plantilla, com `title`, `status`, `version`,
  `tags` i `references`, segons el canvi. No inferiu una aprovació funcional ni
  incrementeu la versió només per haver editat metadades.
- Els documents nous comencen en `draft`. El hook `pre-push` pregunta si l'usuari
  vol passar els esborranys a `active`; no respongueu afirmativament en nom seu.
  Si accepta, cal revisar i fer commit dels canvis abans de repetir el push.
- Abans d'acabar, comproveu que les metadades del document editat són coherents
  amb aquests criteris i que els enllaços afegits o modificats són vàlids.

Aquestes metadades són per als articles de la KB; no afegiu la seva capçalera als
fitxers d'instruccions (`AGENTS.md`, `SKILL.md`), als scripts ni als recursos tècnics.

La KB utilitza `zensical.toml` amb tema `modern` i dependències fixades a
`requirements.txt`. Després de canvis de contingut o configuració, executeu
`zensical build --clean` i `python scripts/check_zensical_site.py` des de l'entorn
Python 3.14 del projecte. Utilitzeu la integració nativa de Mermaid.
