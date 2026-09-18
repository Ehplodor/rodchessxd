extends SceneTree
## tests/test_design_tokens_button_states.gd — helpers de styles d'états de boutons.
## Garantit que la factorisation des 4 boutons (STOP/Live/Cliff/Test) reste fidèle :
## fonds, bordures et couleurs de police exactement transmis.

const Tokens = preload("res://src/ui/theme/DesignTokens.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- DesignTokens button states tests ---")

	# state_styles : trois StyleBox distincts avec fonds/bordures explicites.
	var active := Tokens.state_styles(Tokens.RADIUS_SMALL, 1, Vector2(8, 2),
			Color("#7f1d1d"), Color("#ef4444"),
			Color("#991b1b"), Color("#f87171"),
			Color("#450a0a"), Color("#ef4444"))
	var n := active["normal"] as StyleBoxFlat
	var h := active["hover"] as StyleBoxFlat
	var p := active["pressed"] as StyleBoxFlat
	_check(n != null and h != null and p != null, "state_styles renvoie 3 StyleBoxFlat")
	_check(n.bg_color == Color("#7f1d1d"), "normal.bg exact")
	_check(h.bg_color == Color("#991b1b"), "hover.bg exact")
	_check(p.bg_color == Color("#450a0a"), "pressed.bg exact")
	_check(n.border_color == Color("#ef4444"), "normal.border exact")
	_check(n.corner_radius_top_left == Tokens.RADIUS_SMALL, "rayon appliqué")
	_check(n.border_width_left == 1, "épaisseur bordure appliquée")
	_check(is_equal_approx(n.content_margin_left, 8.0), "marge horizontale appliquée")

	# idle_styles : hover/pressed dérivent du normal, seul le fond change.
	var idle := Tokens.idle_styles(Tokens.RADIUS_SMALL, 1, Vector2(6, 2),
			Tokens.BTN_BG, Tokens.BTN_BORDER, Tokens.BTN_BG_HOVER, Tokens.BTN_BG_PRESSED)
	var in_ := idle["normal"] as StyleBoxFlat
	var ih := idle["hover"] as StyleBoxFlat
	var ip := idle["pressed"] as StyleBoxFlat
	_check(in_.bg_color == Tokens.BTN_BG, "idle normal.bg = token")
	_check(ih.bg_color == Tokens.BTN_BG_HOVER, "idle hover.bg = token")
	_check(ip.bg_color == Tokens.BTN_BG_PRESSED, "idle pressed.bg = token")
	_check(ih.border_color == Tokens.BTN_BORDER, "idle hover.border conservée")
	_check(in_ != ih and ih != ip, "idle : instances distinctes")

	# idle_styles avec bordure de survol explicite (analyse primaire).
	var prim := Tokens.idle_styles(Tokens.RADIUS_SMALL, 1, Vector2(10, 2),
			Tokens.PRIMARY_BG, Tokens.PRIMARY_BORDER,
			Tokens.PRIMARY_BG, Tokens.PRIMARY_BG_PRESSED, Tokens.TEXT_PRIMARY)
	_check((prim["hover"] as StyleBoxFlat).border_color == Tokens.TEXT_PRIMARY,
			"idle hover.border override appliquée")
	_check((prim["hover"] as StyleBoxFlat).bg_color == Tokens.PRIMARY_BG,
			"idle hover.bg inchangé quand identique au normal")

	# apply_state : les 7 overrides sont posés sur le bouton.
	var btn := Button.new()
	Tokens.apply_state(btn, active, Color("#34d399"), Color.WHITE, Color("#10b981"), Tokens.FONT_BUTTON)
	_check(btn.has_theme_stylebox_override("normal"), "override normal posé")
	_check(btn.has_theme_stylebox_override("hover"), "override hover posé")
	_check(btn.has_theme_stylebox_override("pressed"), "override pressed posé")
	_check(btn.get_theme_color("font_color") == Color("#34d399"), "font_color posée")
	_check(btn.get_theme_color("font_hover_color") == Color.WHITE, "font_hover_color posée")
	_check(btn.get_theme_font_size("font_size") == Tokens.FONT_BUTTON, "font_size posée")
	btn.free()

	if _failures == 0:
		print("ALL DESIGN TOKENS BUTTON STATES TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("DESIGN TOKENS BUTTON STATES TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
