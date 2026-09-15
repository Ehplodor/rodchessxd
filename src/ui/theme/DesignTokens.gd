class_name DesignTokens
## DesignTokens — tokens UI uniques de RodChessXD (jalon M1 « Ergonomie & accessibilité »).
## Référentiel : téléphone 360 dp, viewport 450 × 800 px ≈ 1,25 px/dp (décision D1 du roadmap).
## Toutes les tailles de l'interface s'expriment en px viewport via ces constantes :
## remplacer les valeurs en dur par ces tokens dans le code de l'interface.
## Contraste : les couleurs de texte respectent WCAG AA ≥ 4,5:1 sur les surfaces
## sombres de l'application (vérifié par calcul de ratio, cf. plan M1).

const _ScrollTouch = preload("res://src/ui/components/ScrollTouch.gd")

# --- Polices (px viewport) ---
const FONT_BUTTON := 20   ## Libellés de boutons (≥ 16 sp)
const FONT_BODY := 17     ## Texte courant (≥ 14 sp)
const FONT_CAPTION := 15  ## Texte secondaire / légendes (minimum lisible AA)

# --- Cibles tactiles (px) ---
const TOUCH_MIN := 60      ## 48 dp — cible standard
const TOUCH_DENSE := 56    ## Contrôles secondaires en rangées denses (chips, segments)

# --- Espacements (px ; 8/12/16 dp → 10/15/20) ---
const SPACE_XS := 6
const SPACE_S := 10
const WINDOW_INSET := 12   ## Marge intérieure des fenêtres/modales
const CARD_PAD_H := 10
const CARD_PAD_V := 8

# --- Rayons de StyleBox ---
const RADIUS_SMALL := 6
const RADIUS_MEDIUM := 8

# --- Définitions de thèmes d'interface (Mode Obscur / Mode Clair) ---
const THEME_DARK := {
	"BG_DEEP": Color("#090d16"),
	"BG_BASE": Color("#0b0f17"),
	"SURFACE": Color("#0f172a"),
	"SURFACE_ELEVATED": Color("#1e293b"),
	"BORDER": Color("#334155"),
	"BTN_BG": Color("#1f2937"),
	"BTN_BG_HOVER": Color("#293852"),
	"BTN_BG_PRESSED": Color("#141f2e"),
	"BTN_BORDER": Color("#334155"),
	"BTN_BORDER_ACTIVE": Color("#38bdf8"),
	"PRIMARY_BG": Color("#047857"),
	"PRIMARY_BG_PRESSED": Color("#065f46"),
	"PRIMARY_BORDER": Color("#34d399"),
	"ON_PRIMARY": Color("#ffffff"),
	"TEXT_PRIMARY": Color("#f1f5f9"),
	"TEXT_SECONDARY": Color("#cbd5e1"),
	"TEXT_MUTED": Color("#94a3b8"),
	"ACCENT": Color("#38bdf8"),
	"SUCCESS": Color("#22c55e"),
	"WARNING": Color("#fbbf24"),
	"DANGER": Color("#f87171"),
	"ERROR_BG": Color("#801c21"),
	"ERROR_TEXT": Color("#ffe3e3")
}

const THEME_LIGHT := {
	"BG_DEEP": Color("#e2e8f0"),
	"BG_BASE": Color("#f1f5f9"),
	"SURFACE": Color("#ffffff"),
	"SURFACE_ELEVATED": Color("#e2e8f0"),
	"BORDER": Color("#cbd5e1"),
	"BTN_BG": Color("#ffffff"),
	"BTN_BG_HOVER": Color("#f1f5f9"),
	"BTN_BG_PRESSED": Color("#e2e8f0"),
	"BTN_BORDER": Color("#cbd5e1"),
	"BTN_BORDER_ACTIVE": Color("#0284c7"),
	"PRIMARY_BG": Color("#059669"),
	"PRIMARY_BG_PRESSED": Color("#047857"),
	"PRIMARY_BORDER": Color("#10b981"),
	"ON_PRIMARY": Color("#ffffff"),
	"TEXT_PRIMARY": Color("#0f172a"),
	"TEXT_SECONDARY": Color("#334155"),
	"TEXT_MUTED": Color("#64748b"),
	"ACCENT": Color("#0284c7"),
	"SUCCESS": Color("#16a34a"),
	"WARNING": Color("#d97706"),
	"DANGER": Color("#dc2626"),
	"ERROR_BG": Color("#fee2e2"),
	"ERROR_TEXT": Color("#991b1b")
}

# --- Surfaces et Couleurs dynamiques (initialisées en Dark par défaut) ---
static var current_theme_mode: String = "dark"

static var BG_DEEP: Color = THEME_DARK["BG_DEEP"]
static var BG_BASE: Color = THEME_DARK["BG_BASE"]
static var SURFACE: Color = THEME_DARK["SURFACE"]
static var SURFACE_ELEVATED: Color = THEME_DARK["SURFACE_ELEVATED"]
static var BORDER: Color = THEME_DARK["BORDER"]

# --- Boutons chrome ---
static var BTN_BG: Color = THEME_DARK["BTN_BG"]
static var BTN_BG_HOVER: Color = THEME_DARK["BTN_BG_HOVER"]
static var BTN_BG_PRESSED: Color = THEME_DARK["BTN_BG_PRESSED"]
static var BTN_BORDER: Color = THEME_DARK["BTN_BORDER"]
static var BTN_BORDER_ACTIVE: Color = THEME_DARK["BTN_BORDER_ACTIVE"]

# --- Action primaire ---
static var PRIMARY_BG: Color = THEME_DARK["PRIMARY_BG"]
static var PRIMARY_BG_PRESSED: Color = THEME_DARK["PRIMARY_BG_PRESSED"]
static var PRIMARY_BORDER: Color = THEME_DARK["PRIMARY_BORDER"]
static var ON_PRIMARY: Color = THEME_DARK["ON_PRIMARY"]

# --- Textes ---
static var TEXT_PRIMARY: Color = THEME_DARK["TEXT_PRIMARY"]
static var TEXT_SECONDARY: Color = THEME_DARK["TEXT_SECONDARY"]
static var TEXT_MUTED: Color = THEME_DARK["TEXT_MUTED"]

# --- Couleurs sémantiques ---
static var ACCENT: Color = THEME_DARK["ACCENT"]
static var SUCCESS: Color = THEME_DARK["SUCCESS"]
static var WARNING: Color = THEME_DARK["WARNING"]
static var DANGER: Color = THEME_DARK["DANGER"]
static var ERROR_BG: Color = THEME_DARK["ERROR_BG"]
static var ERROR_TEXT: Color = THEME_DARK["ERROR_TEXT"]

## Applique la palette de couleurs sélectionnée ("dark" ou "light").
static func apply_theme_mode(mode: String) -> void:
	current_theme_mode = "light" if mode == "light" else "dark"
	var p: Dictionary = THEME_LIGHT if current_theme_mode == "light" else THEME_DARK
	BG_DEEP = p["BG_DEEP"]
	BG_BASE = p["BG_BASE"]
	SURFACE = p["SURFACE"]
	SURFACE_ELEVATED = p["SURFACE_ELEVATED"]
	BORDER = p["BORDER"]
	BTN_BG = p["BTN_BG"]
	BTN_BG_HOVER = p["BTN_BG_HOVER"]
	BTN_BG_PRESSED = p["BTN_BG_PRESSED"]
	BTN_BORDER = p["BTN_BORDER"]
	BTN_BORDER_ACTIVE = p["BTN_BORDER_ACTIVE"]
	PRIMARY_BG = p["PRIMARY_BG"]
	PRIMARY_BG_PRESSED = p["PRIMARY_BG_PRESSED"]
	PRIMARY_BORDER = p["PRIMARY_BORDER"]
	ON_PRIMARY = p["ON_PRIMARY"]
	TEXT_PRIMARY = p["TEXT_PRIMARY"]
	TEXT_SECONDARY = p["TEXT_SECONDARY"]
	TEXT_MUTED = p["TEXT_MUTED"]
	ACCENT = p["ACCENT"]
	SUCCESS = p["SUCCESS"]
	WARNING = p["WARNING"]
	DANGER = p["DANGER"]
	ERROR_BG = p["ERROR_BG"]
	ERROR_TEXT = p["ERROR_TEXT"]

## StyleBox plat unique, depuis les tokens (bordures/rayons/marges explicites).
static func flat(bg: Color, radius: int = RADIUS_SMALL, border: Color = Color.TRANSPARENT,
		border_w: int = 0, margins: Vector2 = Vector2.ZERO) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if margins.x > 0.0 or margins.y > 0.0:
		sb.content_margin_left = margins.x
		sb.content_margin_right = margins.x
		sb.content_margin_top = margins.y
		sb.content_margin_bottom = margins.y
	return sb

## StyleBox plat de carte : fond élevé, bordure discrète, rayons moyens, marges de carte.
static func card() -> StyleBoxFlat:
	return flat(SURFACE_ELEVATED, RADIUS_MEDIUM, BORDER, 1, Vector2(CARD_PAD_H, CARD_PAD_V))

## Applique hauteur tactile minimale + police standard à un bouton.
static func style_button(btn: Button, font_size: int = FONT_BUTTON, min_height: int = TOUCH_MIN) -> void:
	btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, float(min_height))
	btn.add_theme_font_size_override("font_size", font_size)

# --- Défilement tactile (M1, retours de test mobile) ---
## Épaisseur des barres de défilement (px) : repère visuel mobile.
const SCROLLBAR_W := 18
## Distance (px) avant qu'un glissé devienne un défilement.
const SCROLL_DEADZONE := 20

## Rend un conteneur défilable adapté au tactile : ascenseurs épais et défilement
## au doigt (handler ScrollTouch attaché, actif même dans une Window/modale).
## TAP = clic, GLISSÉ = défilement. Accepte aussi TextEdit/RichTextLabel
## (ascenseurs épais uniquement).
static func touch_scroll(ctrl: Control) -> void:
	if ctrl is ScrollContainer or ctrl is RichTextLabel or ctrl is TextEdit:
		if ctrl is ScrollContainer:
			(ctrl as ScrollContainer).scroll_deadzone = SCROLL_DEADZONE
		if ctrl.get_node_or_null("_ScrollTouch") == null:
			var touch = _ScrollTouch.new()
			touch.target = ctrl
			ctrl.add_child(touch)
	scrollbar_big(ctrl)

## Ascenseurs épais sur n'importe quel contrôle à barres internes
## (ScrollContainer, TextEdit, RichTextLabel...).
static func scrollbar_big(ctrl: Control, px: int = SCROLLBAR_W) -> void:
	ctrl.add_theme_constant_override("h_scroll", px)
	ctrl.add_theme_constant_override("v_scroll", px)

## Taille de l'écran visible (viewport logique), avec repli sûr.
static func screen_size() -> Vector2:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var root_rect = tree.root.get_visible_rect()
		if root_rect.size.x > 0.0 and root_rect.size.y > 0.0:
			return root_rect.size
	var win_s = DisplayServer.window_get_size()
	if win_s.x > 0:
		return Vector2(win_s)
	return Vector2(450, 800)

## Calcule une dimension de fenêtre modale sécurisée et adaptée à la taille de l'écran (mobile portrait ou écran large).
static func adapt_modal_size(win: Window, base_w: float = 410.0, base_h: float = 560.0) -> void:
	var screen = screen_size()
	var screen_w = screen.x
	var screen_h = screen.y

	var is_landscape: bool = (screen_w / maxf(1.0, screen_h)) >= 1.15 and screen_w >= 560.0
	var max_w = 480.0 if is_landscape else 420.0
	var factor_w = 0.46 if is_landscape else 0.94
	var target_w = int(clampf(screen_w * factor_w, 320.0, minf(base_w, max_w)))
	var target_h = int(clampf(screen_h * 0.88, 380.0, base_h))
	win.size = Vector2i(target_w, target_h)

## Prépare un dialogue de confirmation (ConfirmationDialog/AcceptDialog) pour
## mobile : texte multilignes (autowrap) et largeur bornée à l'écran. À appeler
## AVANT popup_centered() : le dialogue s'ouvre alors à cette taille exacte.
static func adapt_dialog(dialog: AcceptDialog, base_w: float = 390.0, base_h: float = 320.0) -> void:
	if dialog == null or not is_instance_valid(dialog):
		return
	dialog.dialog_autowrap = true
	# wrap_controls (défaut) ferait élargir le dialogue jusqu'au minimum de son
	# contenu (texte non replié) : on impose notre largeur bornée à la place.
	dialog.wrap_controls = false
	# Le Label interne conserve sinon une largeur minimale égale au texte (Godot
	# clampe la taille d'un Control à son minimum) : clip_text la ramène à 1 px,
	# l'autowrap replie alors le texte sur la largeur du dialogue.
	var lbl := dialog.get_label()
	if lbl != null:
		lbl.clip_text = true
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2.ZERO
	var screen = screen_size()
	var is_landscape: bool = (screen.x / maxf(1.0, screen.y)) >= 1.15 and screen.x >= 560.0
	var max_w = 480.0 if is_landscape else 420.0
	var factor_w = 0.5 if is_landscape else 0.92
	var target_w = int(clampf(screen.x * factor_w, 300.0, minf(base_w, max_w)))
	var target_h = int(clampf(screen.y * 0.5, 200.0, base_h))
	# NB : ne JAMAIS poser clip_text sur les boutons du dialogue — cela annule leur
	# largeur minimale et les écrase. On réduit seulement la police si la rangée
	# de boutons dépasse la largeur cible.
	if dialog.get_contents_minimum_size().x > float(target_w) - 8.0:
		dialog.add_theme_font_size_override("font_size", FONT_CAPTION)
	dialog.size = Vector2i(target_w, target_h)
	# popup_centered() sans argument repart de min_size : on l'aligne sur la cible.
	dialog.min_size = Vector2i(target_w, target_h)

## Initialise la police vectorielle universelle et les polices de secours d'icônes/symboles/émojis
## garantissant un rendu identique, exhaustif et net sur toutes les plateformes (Web, Android, iOS, Desktop).
static func setup_global_fonts() -> void:
	var sans_path := "res://assets/NotoSans-Regular.ttf"
	var symbols_path := "res://assets/NotoSansSymbols2-Regular.ttf"
	var emoji_path := "res://assets/NotoEmoji.ttf"
	if ResourceLoader.exists(sans_path):
		var sans := load(sans_path) as FontFile
		var fallbacks: Array[Font] = []
		if ResourceLoader.exists(symbols_path):
			var symbols := load(symbols_path) as FontFile
			if symbols:
				fallbacks.append(symbols)
		if ResourceLoader.exists(emoji_path):
			var emoji := load(emoji_path) as FontFile
			if emoji:
				fallbacks.append(emoji)
		if sans:
			sans.fallbacks = fallbacks
			ThemeDB.fallback_font = sans
