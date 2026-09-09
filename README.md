# RodChessXD

Application mobile d'analyse d'échecs, développée avec **Godot 4.7** (renderer GL
Compatibility, viewport portrait 450×800). RodChessXD embarque un plateau interactif,
des moteurs d'analyse **Stockfish** (et **lc0 + profils Maia** sur le bureau) et un
**Coach IA explicatif** fonctionnant en « bring-your-own-key » (clés saisies par
l'utilisateur, rien n'est hébergé côté serveur).

## Essayer

| Plateforme | Description | État |
| --- | --- | --- |
| **Web / PWA installable** | Version navigateur (WASM mono-thread). Analyse **Stockfish** intégrée, sauvegardes locales (IndexedDB), hors-ligne après le 1er chargement, installation en PWA (manifest + service worker). | Déployée sur GitHub Pages — voir lien dans la description du dépôt / section Déploiement |
| **Windows** | Exécutable autonome (~258 Mo) avec Stockfish **et** lc0 + réseaux Maia 1100/1500/1900 embarqués, OCR (import d'image du plateau), coach cloud BYOK **et** LLM local. | Distribué via itch.io (voir `docs/ITCH_PAGE_COPY.md`) |
| **Android / iOS** | Presets d'export configurés (Stockfish natif Android via plugin `RodChessUci`). | En cours — builds locaux non publiés |

> Version en ligne = **fonctionnalités réduites** : pas de profils Maia/lc0, pas d'OCR,
> pas de LLM local, Engine Hub inopérant (voir matrice ci-dessous).

## Matrice des fonctionnalités

Légende : ✓ disponible · ✗ indisponible · ⚠ à confirmer après mise en ligne.

| Fonction | Web / PWA | Desktop Windows |
| --- | --- | --- |
| Analyse en direct (score, profondeur, multi-PV, barre d'évaluation) | ✓ (Stockfish WASM, mono-thread) | ✓ (Stockfish, multi-cœurs) |
| Analyse complète de partie + graphique d'avantage | ✓ (chemin asynchrone `await`) | ✓ (thread dédié) |
| Profils Maia 1100 / 1500 / 1900 (style de jeu « humain », via lc0) | ✗ | ✓ (réseaux embarqués) |
| Import/export PGN | ✓ | ✓ |
| Banque de parties locale | ✓ (IndexedDB) | ✓ |
| Coach IA explicatif (cloud, BYOK : Gemini / Groq / API personnalisée) | ✓ ⚠ CORS à valider | ✓ |
| LLM local (Ollama / llama.cpp) | ✗ (non exécutable dans le navigateur) | ✓ |
| OCR — import photo du plateau | ✗ | ✓ |
| Import Chess.com | ⚠ CORS à valider | ✓ |
| Engine Hub (téléchargements de moteurs/réseaux) | ✗ (inopérant) | ✓ |
| Hors-ligne complet | ✓ après 1er chargement | ✓ |
| Thèmes, sons, plateau retournable | ✓ | ✓ |

## Développement

Prérequis : **Godot 4.7.1 stable** (templates d'export installés pour cibler Web/Android/iOS).

```bash
# Ouvrir le projet
godot -e --path .

# Lancer un test rapide (exports de tests en scripts GDScript autonomes dans tests/)
godot --headless --path . --script res://tests/test_chess_game.gd
```

### Version Web en local

1. Exporter le preset **Web** (chemin d'export par défaut : `RodChessXD2.html` à la racine).
2. Copier les fichiers web à côté du build :
   `cp assets/web/uci_worker_bridge.js assets/web/stockfish.js .`
3. Servir le dossier : `python serve_web.py` → <http://localhost:8060/RodChessXD2.html>

> Pour un build **PWA** (manifest + service worker) complet, exporter vers `dist/index.html`
> puis copier les 2 fichiers web dans `dist/` et appliquer
> `python tools/patch_pwa_sw.py dist/index.service.worker.js` (pré-cache du moteur WASM).
> Le workflow GitHub Actions fait tout cela automatiquement.

### Icônes PWA

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/render_pwa_icons.gd
```

## Déploiement GitHub Pages (PWA)

Un workflow `.github/workflows/deploy-web.yml` exporte le build Web sur chaque
`push` vers la branche `main` et déploie sur GitHub Pages (`Actions` comme source).
Le service worker et le manifest sont générés par Godot ; le moteur Stockfish WASM et
le pont UCI sont pré-cachés pour un usage hors-ligne.

Étapes manuelles (une seule fois) : `Settings → Pages → Source: GitHub Actions`, puis
activer l'environnement `github-pages` lors de la première exécution du workflow.

## Licence

Ce dépôt est publié sous **GNU GPL v3.0** — voir `LICENSE` et `NOTICE.md` pour les
attributions et les licences des composants tiers.

## Structure

```
src/            Code applicatif (moteur UCI, coach IA, UI, vision/OCR, réseau)
assets/         Pièces SVG, sons, polices, fichiers web (Stockfish WASM, pont UCI, icônes PWA)
tools/          Scripts de génération (icônes PWA, sons, pièces) et patch du service worker
tests/          Scénarios de test GDScript
docs/           Documentation et copies de publication
export_presets.cfg  Presets Web / Android / iOS / Windows Desktop
```
