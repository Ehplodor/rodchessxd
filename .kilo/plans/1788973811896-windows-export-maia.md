# Plan — Export Windows autonome (Stockfish + lc0 + Maia) pour itch.io

## Objectif
Produire un preset d'export **Godot 4.7 « Windows Desktop » (x86_64, Release)** pour `RodChessXD`
qui embarque tout le nécessaire hors-ligne dans un seul `.exe` :
- `stockfish.exe` (profil Stockfish)
- `lc0.exe` + `dnnl.dll` + `mimalloc-*.dll` (moteur requis par le profil Maia)
- les 3 réseaux Maia `maia-1100/1500/1900.pb.gz`

publiable tel quel sur itch.io (upload Windows, ~100–250 Mo, limite itch 1 Go).

## Contexte vérifié (source de vérité)
- `export_presets.cfg` ne contient que Web, Android, Android Emulator, iOS → **aucun preset Windows**.
- Godot n'exporte par défaut que les *ressources* : les fichiers plats (`.exe`, `.dll`, `.pb.gz`, `.js`, `.wasm`…) ne sortent **que via `include_filter`**. Preuve locale : le `.pck` Web ne pèse que 2,7 Mo alors que `bin/` (moteurs) et les artefacts Web existent déjà à la racine.
- Recherche de moteur (`EngineManager._find_binary_path`) : chemin custom → `user://engines/` → `res://bin/` (extrait dans `user://engines`) → chemin dev `c:/Dev/RodChessXD/bin` (ne doit PAS être utilisé par l'export).
- lc0 (build dnnl) charge ses DLL depuis le dossier de l'exe. Le code n'extrait jamais les DLL (seul le zip téléchargé dépose `dnnl.dll`/`mimalloc-*`). Sans correctif, lc0 **planterait** sur le PC d'un ami.
- Réseaux Maia : l'app teste/sert uniquement `user://engines/maia-{1100,1500,1900}.pb.gz` (`is_maia_net_installed`, `get_active_maia_net_path`). `bin/` ne contient que `791556.pb.gz` (jamais lu par le code). Stockfish n'a **pas** de téléchargement auto sur Windows → doit être embarqué.
- Les 3 réseaux existent dans le dépôt amont déjà utilisé par l'app : `github.com/CSSLab/maia-chess/raw/master/maia_weights/maia-{1100,1500,1900}.pb.gz`.

## Décisions
1. `.exe` unique avec PCK embarqué (`binary_format/embed_pck=true`) → 1 fichier à uploader.
2. Moteurs embarqués via `include_filter="bin/*"` (inclus licences/dll présentes dans `bin/`).
3. Provisioning au premier lancement (code GDScript) : copie `res://bin/*` → `user://engines/` si absent, uniquement Windows hors-éditeur.
4. Les 3 réseaux Maia sont téléchargés dans `bin/` sous leur nom attendu par l'app.

## Tâches

### 1. `export_presets.cfg` — ajouter le preset Windows
- Ajouter dans `[runnable_presets]` : `Windows="Windows Desktop"`.
- **Append** d'un bloc `[preset.4]` (ne pas réordonner/renuméroter les presets 0-3 existants) :
```ini
[preset.4]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="bin/*"
exclude_filter=""
export_path="./RodChessXD2_Windows.exe"
patches=PackedStringArray()
patch_delta_encoding=false
patch_delta_compression_level_zstd=19
patch_delta_min_reduction=0.1
patch_delta_include_filters="*"
patch_delta_exclude_filters=""
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.4.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
application/modify_resources=true
application/icon=""
application/icon_interpolation=4
application/console_wrapper_icon=""
application/console_wrapper_icon_interpolation=4
application/file_version=""
application/product_version=""
application/company_name="RodChess"
application/product_name="RodChessXD"
application/file_description="Application mobile multi-plateforme d'analyse echiqueenne avec Stockfish et Coach IA LLM/SLM"
application/copyright=""
application/trademarks=""
```
Note : Godot complète automatiquement les options absentes avec leurs valeurs par défaut (UI et CLI). La sortie `RodChessXD2_Windows.exe` à la racine est un fichier non-ressource : il ne sera pas réinclus dans les autres exports.

### 2. `bin/` — réseaux Maia
- Télécharger dans `bin/` :
  `https://github.com/CSSLab/maia-chess/raw/master/maia_weights/maia-1100.pb.gz`
  `.../maia-1500.pb.gz` et `.../maia-1900.pb.gz`.
- Comparer `Get-FileHash` de `maia-1900.pb.gz` avec `bin/791556.pb.gz` :
  - si identiques → supprimer `791556.pb.gz` (après `grep -r "791556"` sur `src/` et `tests/` : si référencé, NE PAS supprimer) ;
  - sinon le conserver (et le documenter).
- Conserver tous les autres fichiers de `bin/` (DLL, licences, lc0, stockfish).

### 3. `src/engine/EngineManager.gd` — provisioning embarqué
- Dans `_ready()`, juste après `_ensure_engine_directories()`, appeler une nouvelle méthode privée `_provision_bundled_engine_files()`.
- Implémentation :
  - Guard : `if OS.get_name() != "Windows" or OS.has_feature("editor"): return`.
  - `const` local (PackedStringArray) : `["lc0.exe", "dnnl.dll", "mimalloc-override.dll", "mimalloc-redirect.dll", "maia-1100.pb.gz", "maia-1500.pb.gz", "maia-1900.pb.gz"]`.
  - Pour chaque fichier `f` : si `FileAccess.file_exists("res://bin/" + f)` ET non présent dans `OS.get_user_data_dir() + "/engines/" + f` → `_copy_file_bytes("res://bin/" + f, <user engines>/f)` + `print` de log.
  - Réutiliser la méthode `_copy_file_bytes()` existante ; rester synchrone (copie ponctuelle au 1er lancement uniquement).
- Ne PAS copier `stockfish.exe` ici : l'extraction existante de `_find_binary_path()` (étape res://bin) s'en charge déjà au lancement du profil Stockfish.

### 4. Validation
- Prérequis : installer le template « Windows Desktop » dans Godot (Éditeur → Gérer les templates d'export) si absent.
- Lancer l'export : `godot --path . --headless --export-release "Windows Desktop"` (ou via l'UI Export → « Windows Desktop »). Vérifier qu'il n'y a pas d'erreur et que la taille de l'exe ≈ somme(bin/) + ressources (log « storing bin/… »).
- Tester sur une machine Windows **vierge de tout moteur** (pas `C:\Dev\RodChessXD`) :
  - 1er lancement → `%APPDATA%\Godot\app_userdata\RodChessXD\engines\` doit contenir `stockfish.exe`, `lc0.exe`, `dnnl.dll`, `mimalloc-override.dll`, `mimalloc-redirect.dll`, `maia-1100/1500/1900.pb.gz`.
  - Profil Stockfish : l'analyse tourne (score/depth).
  - Engine Hub : sélectionner « Maia 1100 », « Maia 1500 », « Maia 1900 » → lc0 démarre **sans erreur DLL**, `go` produit des coups/évals.
  - Redémarrer l'app → démarrage rapide (pas de re-copie).
  - Tester **hors-ligne** (réseau coupé) pour prouver l'autosuffisance.
- SmartScreen signalera un exe non signé : documenter « Plus d'infos → Exécuter quand même » pour les testeurs.

### 5. Empaquetage itch.io
- Zipper l'exe seul ou un dossier `dist/` contenant `RodChessXD2_Windows.exe` + un court `LISEZMOI.txt` (SmartScreen + touches).
- itch.io → créer/éditer le projet → upload « Windows » (fichier zip ou exe direct). La limite de fichier itch (~1 Go) est très supérieure à la taille attendue.
- Optionnel : ajouter bandeau/capture à la page.

## Risques & points d'attention
- Renderer `gl_compatibility` : exige OpenGL 3.3 sur le PC des amis. Si un testeur a un pilote défaillant, l'option « Export ANGLE libraries » (UI d'export Windows) pourra être activée ultérieurement.
- Faux positifs antivirus possibles (Godot + lc0/stockfish non signés) — normal, prévenir les testeurs.
- Ne pas exécuter de `git commit` sans demande explicite de l'utilisateur.
- Reste hors périmètre : cache/service worker Web (question précédente), allègement des presets Android/Web existants (à refaire plus tard si souhaité), signature de code.

## Exécution
Ce plan nécessite des modifications de sources (`export_presets.cfg`, `EngineManager.gd`) et le téléchargement de fichiers binaires : à exécuter par un agent capable d'éditer du code, puis à valider par l'utilisateur dans l'éditeur Godot (export + tests manuels).
