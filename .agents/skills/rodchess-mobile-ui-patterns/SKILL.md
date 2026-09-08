---
name: rodchess-mobile-ui-patterns
description: >-
  Directives et patrons de conception pour l'ergonomie mobile, le dimensionnement des modales et l'alignement des composants UI dans RodChessXD.
  À utiliser systématiquement lors de l'ajout ou de la retouche d'éléments d'interface, boutons, barres d'outils, modales et panneaux de contrôle.
---

# RodChessXD - Patrons d'Ergonomie et de Mise en Page Mobile

Ce document rassemble les règles d'or et les standards établis pour garantir un affichage fluide, lisible et 100% responsive sur smartphone pour **RodChessXD** (Godot 4).

---

## 1. Règle d'or du dimensionnement des fenêtres modales

Toutes les fenêtres modales (`Window`) doivent impérativement s'adapter dynamiquement à la largeur de l'écran pour éviter tout débordement sur petit écran (écrans de 360 à 420 px de large) :

### ✅ À faire systématiquement :
Utiliser la méthode statique de référence `DesignTokens.adapt_modal_size()` dans `_ready()` ou `_configure_window()` :

```gdscript
func _ready() -> void:
    title = "Mon Titre"
    DesignTokens.adapt_modal_size(self, 410, 650) # (win, base_w = 410, base_h = 650)
    exclusive = true
    close_requested.connect(queue_free)
```

### ❌ À proscrire :
- Définir `size = Vector2i(400, 500)` en dur.
- Calculer des `clampf(screen_w * 0.94, 340.0, 450.0)` manuellement avec une largeur maximale supérieure à 410-420 px.

---

## 2. Organisation des barres d'outils et en-têtes (Coach, Navigation, etc.)

Sur mobile en mode portrait, l'espace horizontal est très restreint (<= 420 px).

### Principes :
1. **Éviter de surcharger un `HBoxContainer` unique** :
   - Ne jamais placer à la fois un badge extensible, un sélecteur de modèle/mode, un statut textuel et des boutons d'action sur la même ligne.
   - Si les éléments sont nombreux, scinder en **deux lignes distinctes** :
     - **Ligne 1** : Informations de contexte (ex. numéro de coup, position) + statut court + bouton d'action secondaire (ex. historique 📜).
     - **Ligne 2** : Sélecteur principal étendu (ex. sélecteur de modèle IA, sélecteur de moteur) prenant toute la largeur (`size_flags_horizontal = Control.SIZE_EXPAND_FILL`).

2. **Propriétés de troncation obligatoires** :
   - Tout `Label` susceptible de recevoir du texte variable doit avoir :
     ```gdscript
     label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
     ```
   - Tout `Button` affichant du texte dynamique (ex. nom d'un modèle IA) doit comporter :
     ```gdscript
     btn.clip_text = true
     btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
     ```

3. **Cibles tactiles adaptées (Touch Targets)** :
   - Hauteur minimale pour les boutons denses : `DesignTokens.TOUCH_DENSE` (40 px).
   - Hauteur minimale standard : `DesignTokens.TOUCH_MIN` (48 px).
   - Largeur minimale pour les boutons d'action carrés/icônes : >= 40 px (idéalement 44-48 px).

---

## 3. Formulaires et Réglages (SettingsModal, Hubs)

Dans les formulaires et options :
1. **Largeur minimale des libellés (`Label`)** :
   - Ne jamais fixer de `custom_minimum_size.x` trop grand (garder <= 50 px).
2. **Largeur des contrôles interactifs (`SpinBox`, `OptionButton`, `LineEdit`)** :
   - Garder les `SpinBox` à 80 px de large maximum sur mobile.
   - Les `OptionButton` doivent utiliser `size_flags_horizontal = Control.SIZE_EXPAND_FILL` pour occuper l'espace restant sans pousser la colonne hors écran.
3. **Boutons avec icônes de visibilité / bascule** :
   - Les boutons d'action compacts associés à un champ de saisie doivent avoir une largeur fixe de 40 à 44 px avec `expand_icon = true`.

---

## 4. Défilement tactile fluide (ScrollTouch)

- Tout composant de type `ScrollContainer` doit appeler :
  ```gdscript
  DesignTokens.touch_scroll(self)
  ```
- Désactiver le scroll horizontal si non requis :
  ```gdscript
  horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  ```

---

## 5. Procédure de validation

Après toute retouche sur l'interface :
1. Lancer le test de conformité des modales :
   ```powershell
   & "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --script tests/test_ui_modals.gd
   ```
2. Lancer le test de synchronisation et mise en page :
   ```powershell
   & "C:\Dev\tools\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --script tests/test_eval_sync_and_settings_layout.gd
   ```
