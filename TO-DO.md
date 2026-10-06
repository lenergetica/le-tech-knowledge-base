- Revisar overrides/main.html i status-warning.js perquè em dona la sensació que es pot simplificar.
- Revisar MkDocs 2.0: https://squidfunk.github.io/mkdocs-material/blog/2026/02/18/mkdocs-2.0/
- Revisar etiquetas: ¿inglés o catalán? ¿cuáles? ¿qué valores puede tener status?
- Afegir a index.html com nombrar fitxers.
- L'script projectes/energetica_utils/copia_dades_pro2hall.sh hauria d'estar a GitHub o en algun altre lloc?

- Convensió nom fitxers:

Cada document del KB anirà en un fitxer. En una primera versió hem posat com a nom de fitxer el títol del document, ¿et sembla encertat o no? ¿hauríem de substituir els espais per "-" ó "_", o no cal?

1:06 PM


Sí, fer servir el títol com a base del nom és encertat, perquè facilita trobar el fitxer. Però recomanaria no copiar-lo literalment: feu servir un slug coherent i manteniu el títol llegible dins del document com a encapçalament.

Per exemple, el fitxer actual Migrar taules develrw de Pro a Hall.md podria ser:


Millor guionets (-) que guions baixos (_): són habituals als URL i més fàcils de llegir. Els espais poden funcionar, però sovint es codifiquen com %20 als enllaços i són una mica més incòmodes en ordres i scripts. També convé usar minúscules, treure accents i evitar puntuació.

El més important és establir una convenció i aplicar-la a tots els documents. Tingueu en compte que canviar noms de fitxer més endavant pot trencar enllaços; si preveieu molts canvis de títol, podeu afegir un identificador estable al nom, com ara KB-012-migrar-taules-develrw.md.


- Passar KB cap a edison

- !!! note --> !!! note "Nota", igual amb warnings i info i...

- Migrar resta docs clickup

- El breadcrumb no apareix a la doc de github i la data de última modificació tampoc. M'agrada com surt autor i data a Clickup

- Bot generi clickup task per docs caducats, etc (els que siguin en estat diferent de actiu no caducat)

- Mirar doc trytond per saber com optimitzar bdd (select a hall és 20 o 30 cops més ràpid!)

- Crear script que per a una taula donada faci tot lo de migrar taula develrw Pro->Hall

- Fer excel taules (o script???) mida i impacte, per començar amb les més petites i de menys impacte.
