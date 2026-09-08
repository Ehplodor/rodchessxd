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

# --- Surfaces (du plus sombre au plus clair) ---
const BG_DEEP := Color("#090d16")          ## Fond des fenêtres / zones denses
const BG_BASE := Color("#0b0f17")          ## Fond racine de l'application
const SURFACE := Color("#0f172a")          ## Panneaux, cartes de base
const SURFACE_ELEVATED := Color("#1e293b") ## Badges, cartes actives, chips
const BORDER := Color("#334155")

# --- Boutons chrome (barres, navigation) ---
const BTN_BG := Color("#1f2937")
const BTN_BG_HOVER := Color("#293852")
const BTN_BG_PRESSED := Color("#141f2e")
const BTN_BORDER := Color("#334155")
const BTN_BORDER_ACTIVE := Color("#38bdf8")

# --- Action primaire (AA : blanc ≥ 4,5:1 sur normal & pressé) ---
const PRIMARY_BG := Color("#047857")
const PRIMARY_BG_PRESSED := Color("#065f46")
const PRIMARY_BORDER := Color("#34d399")
const ON_PRIMARY := Color("#ffffff")

# --- Textes (AA ≥ 4,5:1 sur BG_DEEP…SURFACE_ELEVATED) ---
const TEXT_PRIMARY := Color("#f1f5f9")
const TEXT_SECONDARY := Color("#cbd5e1")
const TEXT_MUTED := Color("#94a3b8")

# --- Couleurs sémantiques (texte sur fond sombre) ---
const ACCENT := Color("#38bdf8")
const SUCCESS := Color("#22c55e")
const WARNING := Color("#fbbf24")
const DANGER := Color("#f87171") ## Texte d'erreur lisible sur les surfaces (AA ≥ 5,2:1)
const ERROR_BG := Color("#801c21")
const ERROR_TEXT := Color("#ffe3e3")

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

## Calcule une dimension de fenêtre modale sécurisée et adaptée à la taille de l'écran du mobile.
static func adapt_modal_size(win: Window, base_w: float = 410.0, base_h: float = 560.0) -> void:
	var screen_w = 450.0
	var screen_h = 800.0
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var root_rect = tree.root.get_visible_rect()
		if root_rect.size.x > 0:
			screen_w = root_rect.size.x
			screen_h = root_rect.size.y
	elif DisplayServer.window_get_size().x > 0:
		var win_s = DisplayServer.window_get_size()
		screen_w = win_s.x
		screen_h = win_s.y

	var target_w = int(clampf(screen_w * 0.94, 320.0, minf(base_w, 420.0)))
	var target_h = int(clampf(screen_h * 0.88, 420.0, base_h))
	win.size = Vector2i(target_w, target_h)

## Initialise la police vectorielle universelle et la police de secours d'icônes/émojis
## garantissant un rendu identique et net sur toutes les plateformes (Web, Android, iOS, Desktop).
static func setup_global_fonts() -> void:
	var sans_path := "res://assets/NotoSans-Regular.ttf"
	var emoji_path := "res://assets/NotoEmoji.ttf"
	if ResourceLoader.exists(sans_path) and ResourceLoader.exists(emoji_path):
		var sans := load(sans_path) as FontFile
		var emoji := load(emoji_path) as FontFile
		if sans and emoji:
			sans.fallbacks = [emoji]
			ThemeDB.fallback_font = sans
