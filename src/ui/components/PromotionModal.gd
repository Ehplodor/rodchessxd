class_name PromotionModal
extends Window
## PromotionModal.gd - Dialogue de choix de promotion de pion (Dame, Tour, Fou, Cavalier)
## Adapté au mobile tactile avec touches larges (DesignTokens) et textures haute définition.

signal piece_selected(piece_type: int)
signal canceled

var piece_color: int = ChessPiece.PieceColor.WHITE
var has_selected: bool = false

func _init(p_color: int = ChessPiece.PieceColor.WHITE) -> void:
	piece_color = p_color

func _ready() -> void:
	title = "Promotion du pion"
	exclusive = true
	unresizable = true
	borderless = false
	
	close_requested.connect(_on_close_requested)
	_setup_ui()

func _on_close_requested() -> void:
	if not has_selected:
		canceled.emit()
	queue_free()

func _setup_ui() -> void:
	DesignTokens.adapt_modal_size(self, 380, 160)
	var btn_size: float = 72.0

	var bg_panel = PanelContainer.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = DesignTokens.flat(DesignTokens.BG_DEEP, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 10))
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_left = 10
	root_vbox.offset_top = 8
	root_vbox.offset_right = -10
	root_vbox.offset_bottom = -8
	root_vbox.add_theme_constant_override("separation", 10)
	bg_panel.add_child(root_vbox)

	var title_lbl = Label.new()
	title_lbl.text = "Choisissez votre nouvelle pièce :"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	root_vbox.add_child(title_lbl)

	var pieces_row = HBoxContainer.new()
	pieces_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pieces_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pieces_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(pieces_row)

	var choices = [
		{"type": ChessPiece.Type.QUEEN, "name": "Dame"},
		{"type": ChessPiece.Type.KNIGHT, "name": "Cavalier"},
		{"type": ChessPiece.Type.ROOK, "name": "Tour"},
		{"type": ChessPiece.Type.BISHOP, "name": "Fou"}
	]

	for item in choices:
		var btn = Button.new()
		# Largeur extensible (min 0) : jamais de débordement si l'écran est étroit.
		btn.custom_minimum_size = Vector2(0, btn_size)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = item["name"]
		
		# Style moderne tactile
		var normal_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
				DesignTokens.BORDER, 1)
		var pressed_style = DesignTokens.flat(DesignTokens.PRIMARY_BG, DesignTokens.RADIUS_SMALL,
				DesignTokens.PRIMARY_BORDER, 2)
		var hover_style = DesignTokens.flat(DesignTokens.BTN_BG_HOVER, DesignTokens.RADIUS_SMALL,
				DesignTokens.BTN_BORDER_ACTIVE, 1)
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		# Icône graphique de la pièce
		var tex_path = ChessPiece.asset_path(item["type"], piece_color)
		if ResourceLoader.exists(tex_path):
			btn.icon = load(tex_path)
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var p_type = item["type"]
		btn.pressed.connect(func():
			has_selected = true
			piece_selected.emit(p_type)
			queue_free()
		)
		pieces_row.add_child(btn)
