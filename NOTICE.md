# NOTICE — Composants tiers et attributions

RodChessXD est distribué sous **GNU General Public License v3.0** (voir `LICENSE`).
Le code original de RodChessXD (GDScript, HTML/JS du pont UCI, outils de génération,
pièces et sons générés) appartient au projet RodChessXD et est couvert par cette licence.

## Composants inclus dans ce dépôt

| Composant | Origine | Licence |
| --- | --- | --- |
| `assets/web/stockfish.js` | Stockfish (T. Romstad, M. Costalba, J. Kiiski, G. Linscott et contributeurs), compilé en JavaScript par Niklas Fiekas — <https://github.com/niklasf/stockfish.js> | GPL-3.0 |
| `assets/web/uci_worker_bridge.js` | RodChessXD (pont Web Worker UCI entre Godot et Stockfish.js) | GPL-3.0 |
| `assets/NotoSans-Regular.ttf`, `assets/NotoEmoji.ttf`, `assets/NotoSansSymbols2-Regular.ttf` | Google Noto Fonts | SIL Open Font License 1.1 |
| `assets/pieces/*.svg`, `assets/sounds/*` | Générés par les outils du projet (`tools/`) | GPL-3.0 (projet) |

## Composants embarqués dans les livrables de bureau (non versionnés ici)

Les binaires et réseaux suivants sont copiés dans le livrable **Windows** au moment de
l'export (`bin/`, `include_filter="bin/*"`), ou présents localement pour les builds
**Android** (`android/`, keystore et bibliothèques natives exclus du dépôt public).
Ils ne sont pas stockés dans ce dépôt ; leurs licences et textes complets sont fournis
dans `bin/` aux côtés du livrable.

| Composant | Licence | Amont |
| --- | --- | --- |
| Stockfish (binaire) | GPL-3.0 | <https://github.com/official-stockfish/Stockfish> |
| lc0 (binaire) | GPL-3.0 | <https://github.com/LeelaChessZero/lc0> |
| oneDNN (`dnnl.dll`) | Apache-2.0 | <https://github.com/oneapi-src/oneDNN> |
| mimalloc (DLL) | MIT | <https://github.com/microsoft/mimalloc> |
| Réseaux de poids lc0 / Maia (`*.pb.gz`) | Voir `bin/` du livrable (attribution et licence accompagnant chaque réseau) | <https://lczero.org> / projet Maia |

## Notes de conformité
- La GPL-3.0 couvrant le dépôt n'exclut pas la coexistence des licences propres aux
  composants tiers listés ci-dessus.
- Les moteurs d'échecs communiquent avec l'application via le protocole UCI standard
  (processus séparés sur bureau, Web Worker sur navigateur).
