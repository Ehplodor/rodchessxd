# Copie itch.io (page Windows + lien PWA)

Ce document fournit le contenu à coller sur la page **itch.io** du projet (compte
`Ehplodor`). La page présente la **version Windows** en téléchargement principal et
renvoie vers la **version Web/PWA** (GitHub Pages).

> Page encore en édition : avant de passer « Public », coller ce contenu, puis mettre
> à jour le bloc « Essayer en ligne » quand la PWA est déployée et testée.

## Formulaire de création

| Champ | Valeur |
| --- | --- |
| Title | `RodChessXD – Analyse d'échecs par IA (Stockfish & Maia)` |
| Project URL | `rodchessxd` |
| Short description / tagline | `Analysez vos parties avec Stockfish, comparez vos coups aux profils « humains » Maia et laissez un coach IA commenter — sur Windows.` |
| Classification | Games |
| Kind of project | Downloadable |
| Release status | Released |
| Pricing | No payments (gratuit) — ou « $0 or donate », donation suggérée `$2.00` |
| Uploads | `RodChessXD2_Windows_v1.1.0.zip` (exe autonome ~258 Mo ; SmartScreen : « Plus d'informations → Exécuter quand même ») |
| Platforms | Windows |
| Genre | Strategy |
| Tags (max 10) | `chess` · `analysis` · `engine` · `stockfish` · `lc0` · `maia` · `ai` · `offline` · `training` |
| AI generation disclosure | **Yes** — « Cover art generated with an image AI. The app embeds an optional AI chess coach powered by external or local LLMs (user-provided keys). Chess engines and neural nets (Stockfish, lc0, Maia) are trained models, not generative output. » |
| Custom noun | `application` |
| Community | Comments activé |
| Visibility | Draft jusqu'à validation, puis Public |

## Description (bloc « Details »)

```markdown
**RodChessXD** transforme votre PC Windows en station d'analyse d'échecs complète,
**100 % hors-ligne** : aucun moteur à installer, tout est embarqué dans l'application.

### ⚙️ Moteurs embarqués
- **Stockfish** : analyse classique (profondeur, score, meilleurs coups, multi-PV).
- **lc0 + réseaux Maia** (3 niveaux « humains ») : **Maia 1100, 1500 et 1900** —
  comparez vos coups à ce qu'aurait joué un joueur de club de tel niveau.
- Aucune connexion requise pour l'analyse par moteur.

### 🎓 Coach IA
- Analyse commentée de vos parties et explications de vos erreurs.
- Fournisseurs au choix : services cloud gratuits (Gemini / Groq), clé API
  personnalisée, ou **LLM local** (Ollama / llama.cpp) pour rester 100 % privé.
- Clés BYOK : rien n'est stocké sur un serveur RodChessXD.

### 📐 Outils d'analyse
- Analyse en direct (profondeur, score, barre d'évaluation, graphique d'avantage).
- Analyse complète d'une partie avec statistiques.
- Liste de coups filtrable, import/export **PGN**, récupération **Chess.com**,
  saisie de position par **photo du plateau (OCR)**.
- Banque de parties locale, thèmes, sons, plateau retournable.

### 🖥️ Version en ligne (PWA) — fonctionnalités réduites
Le même projet existe en **version navigateur installable (PWA)** — voir le bloc
« Essayer en ligne » ci-dessus : analyse **Stockfish (WebAssembly)**, parties et
réglages sauvegardés localement, fonctionne hors-ligne après le premier chargement.
Cette version **n'inclut pas** les profils Maia/lc0, l'OCR, le LLM local ni l'Engine Hub.

### 📦 Notes
- **Windows 64 bits uniquement**, fichier unique, aucun installateur.
- Au premier lancement, Windows SmartScreen peut afficher un avertissement
  (application non signée) : « Plus d'informations » → « Exécuter quand même ».
- Moteurs, licences (GPL, Apache-2.0, MIT) et réseaux Maia embarqués — voir `NOTICE.md`
  du dépôt source (licence GPL-3.0) : https://github.com/Ehplodor/rodchessxd
```

## Bloc « Essayer en ligne » (à ajouter dans la description, en haut)

```markdown
**[🌐 Essayer en ligne (PWA)** — version navigateur, fonctionnalités réduites, sans
installation : **https://ehplodor.github.io/rodchessxd/** ](https://ehplodor.github.io/rodchessxd/)
```

## Rappels de cohérence
- Ne pas promettre sur la PWA/Web ce qui n'existe que sur Windows (Maia, lc0, OCR,
  LLM local, Engine Hub, téléchargements de moteurs).
- Cover image : générée par IA (respecter la mention « AI generation disclosure »),
  format recommandé 630×500.
- Une fois la PWA déployée et validée, remplacer l'URL ci-dessus et passer la page en Public.
