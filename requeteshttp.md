# Requêtes HTTP de RodChessXD & diagnostic réseau Android

> Objet : inventaire exhaustif des requêtes HTTP émises par l'application, analyse de la panne réseau totale observée sur l'export Android, solutions applicables.
> Symptôme rapporté : après export et installation sur Android, **toutes** les requêtes HTTP échouent immédiatement (service Coach, intégration Chess.com, etc.) ; **aucune activité réseau n'est observée**.

---

## 1. Constats vérifiés (preuves) — cause racine

1. `export_presets.cfg` (présent **Android**, `[preset.1]`) :
   - `permissions/internet=false` (ligne 194) — **la permission Internet n'est pas cochée** ;
   - `permissions/access_network_state=false` (ligne 133) ;
   - `gradle_build/use_gradle_build=false` (ligne 82) mais l'APK livré a été produit par un build Gradle personnalisé (multi-dex + bibliothèques androidx présentes, template `android/build/` patché — manifeste debug 4.7.1.stable) ;
   - `package/unique_name="com.example.$genname"` → APK final `com.example.rodchessxd`.
2. **Manifestes du template Android** (`android/build/src/main/AndroidManifest.xml` et `src/debug/AndroidManifest.xml`) : **aucun élément `<uses-permission>`**.
3. **APK exporté vérifié** (`RodChessXD2.apk`) via `aapt dump permissions` :
   - sortie : `package: com.example.rodchessxd` uniquement → **zéro permission déclarée, y compris `android.permission.INTERNET`** ;
   - `aapt dump xmltree` : aucun attribut `usesCleartextTraffic`, aucun `networkSecurityConfig` ; application `debuggable` (export debug) ; targetSdk 36, minSdk 24.
4. **Templates officiels Godot 4.7.1** (`android_debug.apk` / `android_release.apk` dans `%APPDATA%\Godot\export_templates`) : vérifiés de la même façon → ils ne déclarent **aucune permission par défaut** non plus. La permission Internet ne peut venir que du réglage d'export `permissions/internet` (build personnalisé) — jamais ajoutée ici.

> **Conclusion n°1 (cause confirmée)** : l'APK ne demande pas `android.permission.INTERNET`. Sur Android (≥ 6.0 / API 23, ici minSdk 24), une application sans cette permission ne peut créer **aucune socket** : `HTTPRequest` échoue quasi instantanément (échec connexion/résolution), pour HTTPS **comme** pour HTTP — exactement le symptôme « toutes les requêtes échouent immédiatement, zéro trafic réseau ». Ce n'est pas un problème de certificat TLS ni de DNS.

---

## 2. Inventaire exhaustif des requêtes HTTP émises par le code applicatif

Toutes passent par un nœud `HTTPRequest` Godot. Nomenclature : **[script : ligne]**.

### 2.1 Coach IA — `src/ai/AICoach.gd` (1 `HTTPRequest` partagé, POST JSON)

Le routage dépend du `provider` du modèle actif (`active_model_id`, défaut `z-ai/glm-5.3-flash:free` → OpenRouter).

| # | Fournisseur | Méthode / URL | Lignes | En-têtes particuliers | Payload notable |
|---|---|---|---|---|---|
| 1 | OpenRouter | POST `https://openrouter.ai/api/v1/chat/completions` | [531, 548] | `Authorization: Bearer <clé>`, `HTTP-Referer: https://rodchessxd.app`, `X-Title: RodChessXD` | `model`, `messages[system,user]`, `max_tokens: 750`, `temperature: 0.5` |
| 2 | Groq | POST `https://api.groq.com/openai/v1/chat/completions` | [484, 496] | Bearer | `model`, `messages` |
| 3 | Gemini | POST `https://generativelanguage.googleapis.com/v1beta/models/{modèle}:generateContent?key={clé}` | [509, 519] | — (clé en query) | `system_instruction`, `contents` |
| 4 | DeepSeek | POST `https://api.deepseek.com/chat/completions` | [559, 571] | Bearer | `model`, `messages` |
| 5 | OpenAI | POST `https://api.openai.com/v1/chat/completions` | [582, 594] | Bearer | `model`, `messages` |
| 6 | Anthropic | POST `https://api.anthropic.com/v1/messages` | [605, 619] | `x-api-key`, `anthropic-version: 2023-06-01` | `model`, `max_tokens: 1024`, `system`, `messages` |
| 7 | Ollama (local) | POST `http://127.0.0.1:11434/api/generate` (configurable `local_slm_url`) | [464, 473] | — | `model`, `system`, `prompt`, `stream: false` |
| 8 | SLM local autonome | POST `http://127.0.0.1:{port}/v1/chat/completions` (llama-server, défaut 8085) | [446-457] | `Content-Type: application/json` | OpenAI-compatible (`model`, `messages`, `max_tokens: 512`) |

Déclencheur : onglet Coach → envoi d'une question/analyse (`CoachPanel2D.gd:385` → `AICoach.ask_coach`). Une clé absente déclenche la réponse locale de secours **sans requête** (7 fournisseurs cloud).

### 2.2 Hub de modèles — `src/ai/ModelCatalog.gd` (2 `HTTPRequest`, GET)

| # | Cible | Lignes | Usage |
|---|---|---|---|
| 9 | GET `https://openrouter.ai/api/v1/models` (`User-Agent: RodChessXD/1.0`) | [16, 371] | Bouton « actualiser le catalogue » du `ModelHubModal` → modèles + tarifs récents, fusion/cache `user://ai_models_catalog.json` |
| 10 | GET `http://127.0.0.1:11434/api/tags` (`User-Agent: RodChessXD/1.0`) | [17, 485] | Bouton « Détecter mes modèles (Ollama) » → import des modèles locaux dans le catalogue |

### 2.3 Téléchargements de modèles SLM — `src/ai/ModelDownloader.gd`

`HTTPRequest` unique, `use_threads = true` (l. 61), `download_file` = écriture streamée directe `user://models/` (aucun chargement mémoire), GET.

| # | URL (constantes `DOWNLOADABLE_SLM`) | Lignes | Poids |
|---|---|---|---|
| 11 | `https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q4_k_m.gguf` | [22, 145] | ~229 Mo |
| 12 | `https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2_5-0_5b-instruct-q4_k_m.gguf` | [33, 145] | ~398 Mo |
| 13 | `https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf` | [44, 145] | ~1,05 Go |

En-tête `User-Agent: RodChessXD-Downloader/1.0`. Déclencheur : bouton « Installer » d'un modèle local dans `ModelHubModal` (`:544` → `start_download`).

### 2.4 Serveur SLM local — `src/ai/LocalSLMManager.gd`

| # | Cible | Lignes | Usage |
|---|---|---|---|
| 14 | GET `http://127.0.0.1:8085/health` (timeout 2 s) | [12, 143-144] | Sondage de santé après lancement de `llama-server.exe` (jusqu'à 20 tentatives espacées de 1 s) → `server_ready` |

### 2.5 Import Chess.com — `src/network/ChessComService.gd`

`HTTPRequest` dédié, GET, `User-Agent: RodChessXD-ChessAnalysisApp/1.0`.

| # | URL | Lignes | Usage |
|---|---|---|---|
| 15 | `https://api.chess.com/pub/player/{pseudo}/games/archives` | [38-41] | Étape 1 : liste des archives mensuelles |
| 16 | `https://api.chess.com/pub/player/{pseudo}/games/{AAAA}/{MM}` (dernière archive renvoyée) | [67-69] | Étape 2 : partie du dernier mois (PGN + métadonnées) |

Déclencheur : bouton « Chess.com » → modale `ChessComImportModal` (`:119` → `fetch_player_games`, max 40 parties) ; enregistrement automatique en bibliothèque.

### 2.6 Téléchargements de moteurs — `src/ui/components/EngineHubModal.gd` (+ const `EngineManager`)

`HTTPRequest` créé par la modale, GET sans en-têtes, `download_file` → `user://engines/` (exécuté sur clic « Télécharger »).

| # | URL (const `EngineManager.DOWNLOADABLE_ENGINES`) | Lignes const | Lignes requête |
|---|---|---|---|
| 17 | `https://github.com/CSSLab/maia-chess/raw/master/models/maia-1100.pb.gz` | EngineManager [32] | [145] |
| 18 | `https://github.com/CSSLab/maia-chess/raw/master/models/maia-1500.pb.gz` | EngineManager [37] | [145] |
| 19 | `https://github.com/CSSLab/maia-chess/raw/master/models/maia-1900.pb.gz` | EngineManager [42] | [145] |

### 2.7 Récapitulatif

| Famille | HTTPS | HTTP clair (localhost) | Total |
|---|---|---|---|
| Coach LLM cloud | 6 | — | 6 |
| Coach / Hub local | — | 4 (#7, #8, #10, #14) | 4 |
| Catalogues (sync) | 1 (#9) | — | 1 |
| Téléchargements modèles/moteurs | 6 (#11-13, #17-19) | — | 6 |
| Chess.com | 2 | — | 2 |
| **Total endpoints distincts** | **15** | **4** | **19** |

> Les liens web affichés dans l'UI (pages de clés API, `rodchessxd.app`…) sont du texte/des références, pas des requêtes de l'application.

---

## 3. Analyse des causes possibles (Android)

### Cause n°1 — PERMISSION INTERNET ABSENTE ✅ **confirmée**
Tout blocage décrit au §1. Sur Android, les sockets sont refusées au niveau du noyau/permission `SecurityException` (« missing INTERNET permission ») → échec **immédiat**, **aucun octet émis**, tous protocoles et toutes destinations confondus. La permission `INTERNET` est « normale » : accordée silencieusement à l'installation (pas de prompt runtime).

### Cause n°2 — RESTRICTION DU TRAFIC CLAIR (Cleartext) ⚠️ secondaire (une fois n°1 corrigée)
Depuis API 28 (Android 9), quand `targetSdk ≥ 28` (ici **targetSdk 36**), tout trafic HTTP **non chiffré** (`http://…`) est refusé par défaut, **y compris vers `127.0.0.1`**. Le manifeste de l'APK ne contient ni `android:usesCleartextTraffic="true"` ni `android:networkSecurityConfig`.
- Impact si n°1 corrigée : les 4 endpoints locaux (#7, #8, #10, #14) échoueraient avec « Cleartext HTTP traffic not permitted » ; les 15 endpoints HTTPS fonctionneraient.
- Nuance produit : #7/#10 visent un serveur Ollama externe à l'appareil et #8/#14 un `llama-server.exe` — flux de **desktop** ; sur Android ces scénarios ne sont de toute façon pas opérationnels (binaire `.exe` inexécutable, serveur hors téléphone).

### Cause n°3 — Vérifier la bonne application de la correction (pièges d'export)
- Toggle d'export appliqué **avant** l'export (le dernier APK prouve qu'aucun toggle n'a été pris en compte : zéro permission).
- **Désinstaller la version précédente** avant réinstallation : Android met en cache les permissions au moment de l'installation ; une mise à jour peut ne pas ré-appliquer le manifeste sur certains chargeurs.
- L'APK actuel est un build **debug** (`debuggable=true`) ; re-tester aussi la sortie release.
- Package `com.example.rodchessxd` : non bloquant pour le réseau, mais à corriger avant publication (boutique).

### Cause n°4 — À exclure / hors de cause
- **TLS/HTTPS** : les certificats système Android sont utilisés ; aucun certificat auto-signé dans le code.
- **ACCESS_NETWORK_STATE** : non requise pour émettre des requêtes (utile seulement pour inspecter l'état du réseau) ; peut être cochée par confort de diagnostic.
- **Mode avion / données mobiles / Wi-Fi captif** : simple vérification manuelle.
- **URLs des endpoints** : toutes cohérentes avec les API officielles (hors souci Chess.com requérant un `User-Agent` conforme, déjà fourni).

---

## 4. Solutions recommandées

### 4.1 Correctif n°1 (obligatoire) — accorder la permission Internet

**Option A (recommandée) — via le présé d'export :**
1. Ouvrir Godot → `Projet → Exporter…` → présé **Android**.
2. Cocher **Internet** (et éventuellement **Accès à l'état du réseau** `ACCESS_NETWORK_STATE`) dans la section « Permissions » des options.
3. Vérifier que `Gradle Build → Use Gradle Build` est **activé** (build personnalisé) pour que Godot injecte les permissions dans le manifeste lors de l'export — l'APK livré ayant été produit ainsi, activer ce mode et ré-exporter.
4. Ré-éxporter (`export_path` : `./RodChessXD2.apk`) puis **désinstaller/réinstaller** sur l'appareil.

**Option B — via le template Android source** (si template personnalisé géré manuellement) : ajouter dans `android/build/src/main/AndroidManifest.xml` (et `src/debug/AndroidManifest.xml` pour les builds debug) :
```xml
<uses-permission android:name="android.permission.INTERNET" />
```
juste après l'ouverture de `<manifest …>`.

**Vérification après export :**
```powershell
aapt dump permissions RodChessXD2.apk
# doit afficher : uses-permission: name='android.permission.INTERNET'
adb shell dumpsys package com.example.rodchessxd | grep -i internet
adb logcat -s Godot        # contrôle des erreurs de connexion en runtime
```

### 4.2 Correctif n°2 (si un trafic HTTP local doit fonctionner) — autoriser le cleartext ciblé
Ajouter une **configuration réseau** ciblée (meilleure pratique) plutôt que le flag global :

`android/build/src/main/res/xml/network_security_config.xml` :
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```
puis déclaration dans `<application>` du manifeste :
```xml
android:networkSecurityConfig="@xml/network_security_config"
```
(équivalent moins sûr : `android:usesCleartextTraffic="true"` sur `<application>`). Ceci ne concerne que #7/#8/#10/#14 (§2) — hors périmètre fonctionnel Android pour #8/#14 (binaire `.exe`).

### 4.3 Correctifs complémentaires
- Corriger l'identifiant de package avant publication : `package/unique_name` (ex. `com.rodchessxd.app`) dans le présé Android.
- Ne pas diffuser un APK **debug** : exporter en release (`package/signed=true` déjà activé).
- Constat d'architecture lié (indépendant du réseau) : l'analyse Stockfish et le SLM local s'appuient sur des binaires `.exe` lancés en sous-processus (`EngineManager`, `LocalSLMManager`) ; sur Android il faudra embarquer des bibliothèques natives (`.so`, approche GDExtension du plan produit) pour que ces flux fonctionnent — l'OCR reste 100 % local et fonctionnel.

### 4.4 Plan de validation final
1. Après correctif n°1 + ré-export : `aapt dump permissions` montre `INTERNET` ✅
2. Sur l'appareil : import Chess.com (HTTP/2 HTTPS), question au Coach (OpenRouter), actualisation du catalogue — les trois doivent aboutir.
3. En cas de nouvel échec instantané : vérifier `adb logcat` (traces `HTTPRequest`/`SecurityException`), l'état réseau de l'appareil, et la présence du manifeste corrigé dans l'APK réellement installé (`adb shell dumpsys package`).
