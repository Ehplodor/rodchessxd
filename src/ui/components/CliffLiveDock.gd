class_name CliffLiveDock
extends PanelContainer
## CliffLiveDock.gd — Cockpit CHESS-CLIFF « Super Live » (V2.4).
##
## Visualisation du duel cognitif :
## - Profil altimétrique miroir (CliffDuelGraph) avec baseline centrale
## - Ruban synchronisé bi-piste (CliffDualRibbon : Noirs au-dessus, Blancs en-dessous)
## - Faisceau d'étranglement Venturi (CliffSurvivalTunnel : tunnel de liberté & asphyxie)
## - Espace des Phases 2D (CliffPhaseSpace2D : 3 modes sélectionnables par onglets) :
##     1. 🤼 Bras de Fer : D_Blancs (X) vs D_Noirs (Y) avec quadrants
##     2. 🌐 Équateur : Éval (X) vs Tension signée (Y : Nord = Blancs, Sud = Noirs)
##     3. ⚡ Ravin Vectoriel : Éval (X) vs Tension globale (Y) + Vecteurs de chute
## - Badges de nature de coups (🧗 Vital, 🛡️ Forcé, ⚡ Attaque, 🟢 Sûr)
## - Jauges cognitives segmentées par pistes
## - Récit dynamique pas-à-pas et global
## Conçu mobile-first (portrait ≤ 450 px logiques).

signal stop_requested
signal replay_toggled(playing: bool)
signal full_game_requested
signal close_requested
signal step_selected(idx: int, fen: String, uci: String)

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffLineReport = preload("res://src/engine/CliffLineReport.gd")
const DesignTokens = preload("res://src/ui/theme/DesignTokens.gd")

## Jauge cognitive segmentée par pistes (dessinée).
class CliffGauge extends Control:
	var p_survie: float = 1.0
	var indice_d: int = 0
	var piste: int = 0
	var side_label: String = ""

	func _init() -> void:
		custom_minimum_size = Vector2(0, 32)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_values(p_p_survie: float, p_indice_d: int, p_piste: int) -> void:
		p_survie = p_p_survie
		indice_d = p_indice_d
		piste = p_piste
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var w := size.x
		var h := 13.0
		# Segments de piste par indice D croissant (0=sûr/gauche à 100=danger/droite).
		var d_zones := [
			[0.0, float(CliffTypes.D_AUTOROUTE_MAX), CliffTypes.Piste.AUTOROUTE],
			[float(CliffTypes.D_AUTOROUTE_MAX), float(CliffTypes.D_CHEMIN_MAX), CliffTypes.Piste.CHEMIN],
			[float(CliffTypes.D_CHEMIN_MAX), float(CliffTypes.D_CORNICHE_MAX), CliffTypes.Piste.CORNICHE],
			[float(CliffTypes.D_CORNICHE_MAX), float(CliffTypes.D_RASOIR_MAX), CliffTypes.Piste.FIL_DU_RASOIR],
			[float(CliffTypes.D_RASOIR_MAX), 100.0, CliffTypes.Piste.CHAMP_DE_MINES]
		]
		for z in d_zones:
			var x0: float = (float(z[0]) / 100.0) * w
			var x1: float = (float(z[1]) / 100.0) * w
			var col: Color = CliffTypes.get_piste_color(int(z[2]))
			draw_rect(Rect2(x0, 2.0, maxf(1.0, x1 - x0), h), Color(col.r, col.g, col.b, 0.35))
		draw_rect(Rect2(0, 2.0, w, h), Color(0.6, 0.65, 0.75, 0.45), false, 1.0)

		# Curseur D (0..100) — aligné directement sur la difficulté cognitive
		var t := clampf(float(indice_d) / 100.0, 0.0, 1.0)
		var px := t * w
		draw_line(Vector2(px, 0.0), Vector2(px, 2.0 + h + 2.0), Color.WHITE, 2.0, true)
		draw_circle(Vector2(px, 2.0 + h * 0.5), 4.0, CliffTypes.get_piste_color(piste))
		var lbl := "%s  D=%d (%s)" % [side_label, indice_d, CliffTypes.get_piste_name(piste)]
		draw_string(font, Vector2(2.0, h + 13.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.85, 0.88, 0.94, 1.0))

## Duel topographique (profil altimétrique miroir) avec baseline centrale.
class CliffDuelGraph extends Control:
	signal bar_clicked(idx: int)

	var plies_data: Array = []
	var deltas: Array = []
	var baits: Array = []
	var current: int = -1
	var hovered: int = -1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 46)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_data(p_deltas: Array, p_baits: Array) -> void:
		deltas = p_deltas
		baits = p_baits
		queue_redraw()

	func set_plies(p_plies: Array) -> void:
		plies_data = p_plies
		deltas.clear()
		baits.clear()
		for p in p_plies:
			deltas.append(float(p.get("delta_chute", 0.0)))
			baits.append(float(p.get("bait", 0.0)))
		queue_redraw()

	func set_current(idx: int) -> void:
		current = idx
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var n := plies_data.size() if not plies_data.is_empty() else deltas.size()
		if n == 0:
			return
		var w := size.x / float(n)
		if event is InputEventMouseMotion:
			var hov := clampi(int(event.position.x / w), 0, n - 1)
			if hov != hovered:
				hovered = hov
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var clicked := clampi(int(event.position.x / w), 0, n - 1)
			bar_clicked.emit(clicked)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hovered = -1
			queue_redraw()

	func _draw() -> void:
		var n := plies_data.size() if not plies_data.is_empty() else deltas.size()
		if n == 0:
			return
		var font := ThemeDB.fallback_font
		var w := size.x / float(n)
		var y_mid := size.y * 0.5

		# Fond topo sombre
		draw_rect(Rect2(0, 0, size.x, size.y), Color(0.04, 0.06, 0.11, 0.75), true)

		# Filigranes discrets
		draw_string(font, Vector2(4, y_mid - 4), "⚪ Blancs", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.75, 0.85, 0.35))
		draw_string(font, Vector2(4, y_mid + 11), "⚫ Noirs", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.75, 0.85, 0.35))

		# Ligne médiane (baseline 0)
		draw_line(Vector2(0, y_mid), Vector2(size.x, y_mid), Color(0.4, 0.45, 0.55, 0.5), 1.0)

		for i in range(n):
			var is_white := (i % 2 == 0)
			var piste: int = CliffTypes.Piste.AUTOROUTE
			var d_val := 0
			var delta := float(deltas[i]) if i < deltas.size() else 0.0
			var bait := float(baits[i]) if i < baits.size() else 0.0
			var is_vital := false

			if i < plies_data.size():
				var p: Dictionary = plies_data[i]
				is_white = bool(p.get("is_white", (i % 2 == 0)))
				piste = int(p.get("piste", CliffTypes.Piste.AUTOROUTE))
				d_val = int(p.get("indice_d", 0))
				is_vital = bool(p.get("is_vital", false))

			var col := CliffTypes.get_piste_color(piste)
			var ratio := clampf(float(d_val) / 100.0 if d_val > 0 else delta, 0.12, 1.0)
			var max_h := y_mid - 3.0
			var bar_h := ratio * max_h
			var bar_x := float(i) * w + 1.0
			var bar_w := maxf(2.0, w - 2.0)

			if is_white:
				# Blancs montent vers le haut
				var rect := Rect2(bar_x, y_mid - bar_h, bar_w, bar_h)
				draw_rect(rect, Color(col.r, col.g, col.b, 0.85))
				if is_vital:
					draw_line(Vector2(bar_x, y_mid - bar_h), Vector2(bar_x + bar_w, y_mid - bar_h), Color.WHITE, 2.0)
			else:
				# Noirs descendent vers le bas
				var rect := Rect2(bar_x, y_mid, bar_w, bar_h)
				draw_rect(rect, Color(col.r, col.g, col.b, 0.85))
				if is_vital:
					draw_line(Vector2(bar_x, y_mid + bar_h), Vector2(bar_x + bar_w, y_mid + bar_h), Color.WHITE, 2.0)

			# Marqueur piège (bait)
			if bait >= CliffTypes.BAIT_THRESHOLD:
				var cx := bar_x + bar_w * 0.5
				var ty := (y_mid - bar_h - 2.0) if is_white else (y_mid + bar_h + 2.0)
				draw_circle(Vector2(cx, ty), 2.5, Color("#f59e0b"))

			# Surbrillance sélection / hover
			if i == current:
				draw_rect(Rect2(float(i) * w, 0.0, maxf(1.0, w), size.y), Color(1, 1, 1, 0.22))
				draw_rect(Rect2(float(i) * w, 0.0, maxf(1.0, w), size.y), Color("#c084fc"), false, 1.5)
			elif i == hovered:
				draw_rect(Rect2(float(i) * w, 0.0, maxf(1.0, w), size.y), Color(1, 1, 1, 0.12))

## Faisceau d'Étranglement Venturi (Tunnel de Survie & Asphyxie Spatiale).
## Dessine deux flux de liberté décisionnelle : large quand le joueur respire,
## étranglé jusqu'au fil d'un pixel en cas de coup unique vital ou de corniche critique.
class CliffSurvivalTunnel extends Control:
	signal step_clicked(idx: int)

	var plies_data: Array = []
	var current: int = -1
	var hovered: int = -1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 38)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_plies(p_plies: Array) -> void:
		plies_data = p_plies
		queue_redraw()

	func set_current(idx: int) -> void:
		current = idx
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var n := plies_data.size()
		if n == 0:
			return
		var w := size.x / float(n)
		if event is InputEventMouseMotion:
			var hov := clampi(int(event.position.x / w), 0, n - 1)
			if hov != hovered:
				hovered = hov
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var clicked := clampi(int(event.position.x / w), 0, n - 1)
			step_clicked.emit(clicked)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hovered = -1
			queue_redraw()

	func _draw() -> void:
		var n := plies_data.size()
		if n == 0:
			return
		var font := ThemeDB.fallback_font
		var w := size.x / float(n)
		var h_total := size.y
		var y_mid := h_total * 0.5

		# Fond gorge rocheuse sombre
		draw_rect(Rect2(0, 0, size.x, size.y), Color(0.03, 0.05, 0.09, 0.85), true)

		# Ligne de démarcation centrale
		draw_line(Vector2(0, y_mid), Vector2(size.x, y_mid), Color(0.3, 0.35, 0.45, 0.35), 1.0)

		# Filigranes discrets sur les berges
		draw_string(font, Vector2(3, 9), "⚫ Étranglement Noirs", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.65, 0.7, 0.8, 0.35))
		draw_string(font, Vector2(3, h_total - 3), "⚪ Étranglement Blancs", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.65, 0.7, 0.8, 0.35))

		var y_black_center := y_mid * 0.5
		var y_white_center := y_mid + (h_total - y_mid) * 0.5

		var white_radii: Array[float] = []
		var black_radii: Array[float] = []
		var white_cols: Array[Color] = []
		var black_cols: Array[Color] = []

		var last_w_r := 7.0
		var last_b_r := 7.0

		for i in range(n):
			var p: Dictionary = plies_data[i]
			var is_white := bool(p.get("is_white", (i % 2 == 0)))
			var d_val := int(p.get("indice_d", 0))
			var is_vital := bool(p.get("is_vital", false))
			var piste: int = int(p.get("piste", CliffTypes.Piste.AUTOROUTE))
			var p_col := CliffTypes.get_piste_color(piste)

			# Liberté : 1.0 (largeur max) -> 0.0 (étranglement)
			var freedom := clampf(1.0 - (float(d_val) / 100.0), 0.05, 1.0)
			if is_vital:
				freedom = 0.06 # Fil du funambule

			var cur_r := lerpf(1.5, 7.5, freedom)

			if is_white:
				last_w_r = cur_r
				white_radii.append(cur_r)
				white_cols.append(p_col)
				black_radii.append(last_b_r)
				black_cols.append(black_cols.back() if not black_cols.is_empty() else Color(0.4, 0.45, 0.55, 0.5))
			else:
				last_b_r = cur_r
				black_radii.append(cur_r)
				black_cols.append(p_col)
				white_radii.append(last_w_r)
				white_cols.append(white_cols.back() if not white_cols.is_empty() else Color(0.4, 0.45, 0.55, 0.5))

		# Tracé des flux continus
		for i in range(n):
			var x0 := float(i) * w
			var x1 := x0 + w
			var cx := x0 + w * 0.5
			var rw0 := white_radii[i]
			var rw1 := white_radii[mini(i + 1, n - 1)]
			var rb0 := black_radii[i]
			var rb1 := black_radii[mini(i + 1, n - 1)]

			var p: Dictionary = plies_data[i]
			var is_white := bool(p.get("is_white", (i % 2 == 0)))
			var is_vital := bool(p.get("is_vital", false))
			var d_val := int(p.get("indice_d", 0))

			# Conduit Noir
			var b_col: Color = black_cols[i]
			if not is_white and (is_vital or d_val >= CliffTypes.D_CHEMIN_MAX):
				b_col = Color("#f59e0b") if is_vital else Color("#ef4444")
				draw_rect(Rect2(x0, 0, w, y_mid), Color(0.9, 0.15, 0.15, 0.14), true)

			var b_poly := PackedVector2Array([
				Vector2(x0, y_black_center - rb0),
				Vector2(x1, y_black_center - rb1),
				Vector2(x1, y_black_center + rb1),
				Vector2(x0, y_black_center + rb0)
			])
			draw_colored_polygon(b_poly, Color(b_col.r, b_col.g, b_col.b, 0.85))
			draw_line(Vector2(x0, y_black_center), Vector2(x1, y_black_center), Color(1, 1, 1, 0.22), 1.0)

			# Conduit Blanc
			var w_col: Color = white_cols[i]
			if is_white and (is_vital or d_val >= CliffTypes.D_CHEMIN_MAX):
				w_col = Color("#f59e0b") if is_vital else Color("#ef4444")
				draw_rect(Rect2(x0, y_mid, w, h_total - y_mid), Color(0.9, 0.15, 0.15, 0.14), true)

			var w_poly := PackedVector2Array([
				Vector2(x0, y_white_center - rw0),
				Vector2(x1, y_white_center - rw1),
				Vector2(x1, y_white_center + rw1),
				Vector2(x0, y_white_center + rw0)
			])
			draw_colored_polygon(w_poly, Color(w_col.r, w_col.g, w_col.b, 0.85))
			draw_line(Vector2(x0, y_white_center), Vector2(x1, y_white_center), Color(1, 1, 1, 0.22), 1.0)

			# Balise d'étranglement critique
			if is_vital:
				var vy := y_white_center if is_white else y_black_center
				draw_circle(Vector2(cx, vy), 3.0, Color.WHITE)
				draw_arc(Vector2(cx, vy), 4.5, 0, TAU, 12, Color("#f59e0b"), 1.5)

			# Curseur pas sélectionné / survol
			if i == current:
				draw_rect(Rect2(x0, 0.0, w, h_total), Color(1, 1, 1, 0.20))
				draw_rect(Rect2(x0, 0.0, w, h_total), Color("#c084fc"), false, 1.5)
			elif i == hovered:
				draw_rect(Rect2(x0, 0.0, w, h_total), Color(1, 1, 1, 0.10))

## Espace des Phases 2D (Trajectoire Continue de la Partie).
## Permet de visualiser le chemin unique de la partie selon 5 modes :
## 1. COUP_COMPLET : Échelle au coup complet N (D_w vs D_b)
## 2. TENSION_LATENTE : Demi-coup t (D_actif vs D_latent de l'adversaire)
## 3. BRAS_DE_FER : D_Blancs (X) vs D_Noirs (Y) interpolé
## 4. EQUATEUR : Éval (X) vs Tension signée (Y : Nord = Blancs, Sud = Noirs)
## 5. RAVIN_VECTOR : Éval (X) vs Tension globale (Y) + Vecteurs de chute
class CliffPhaseSpace2D extends Control:
	enum PhaseMode { COUP_COMPLET, TENSION_LATENTE, BRAS_DE_FER, EQUATEUR, RAVIN_VECTOR }

	signal step_clicked(idx: int)
	signal mode_changed(new_mode: int)

	var mode: int = PhaseMode.COUP_COMPLET
	var plies_data: Array = []
	var current: int = -1
	var hovered: int = -1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 118)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_mode(p_mode: int) -> void:
		mode = p_mode
		mode_changed.emit(mode)
		queue_redraw()

	func set_plies(p_plies: Array) -> void:
		plies_data = p_plies
		queue_redraw()

	func set_current(idx: int) -> void:
		current = idx
		queue_redraw()

	func _build_full_moves() -> Array[Dictionary]:
		var res: Array[Dictionary] = []
		var n: int = plies_data.size()
		var i: int = 0
		var move_num: int = 1
		while i < n:
			var pw: Dictionary = plies_data[i]
			var pb: Dictionary = {}
			if i + 1 < n:
				pb = plies_data[i + 1]
			var dw: float = float(pw.get("indice_d", 0))
			var db: float = float(pb.get("indice_d", pw.get("pression_d", 15))) if not pb.is_empty() else float(pw.get("pression_d", 15))
			var vital_w: bool = bool(pw.get("is_vital", false))
			var vital_b: bool = bool(pb.get("is_vital", false)) if not pb.is_empty() else false
			var san_w: String = str(pw.get("san", pw.get("move_uci", "?")))
			var san_b: String = str(pb.get("san", pb.get("move_uci", ""))) if not pb.is_empty() else ""
			res.append({
				"move_num": move_num,
				"d_w": dw,
				"d_b": db,
				"white_ply": i,
				"black_ply": i + 1 if not pb.is_empty() else -1,
				"is_vital": vital_w or vital_b,
				"san_w": san_w,
				"san_b": san_b,
				"piste_w": int(pw.get("piste", 0)),
				"piste_b": int(pb.get("piste", 0)) if not pb.is_empty() else 0
			})
			i += 2
			move_num += 1
		return res

	func _get_latent_d(idx: int, want_white: bool) -> float:
		var cur_p: Dictionary = plies_data[idx]
		var is_cur_white := bool(cur_p.get("is_white", (idx % 2 == 0)))
		# Si la position courante a déjà le calcul synchrone d_latent_opponent pour le camp demandé
		if cur_p.has("d_latent_opponent") and is_cur_white != want_white:
			return float(cur_p["d_latent_opponent"])
		if idx + 1 < plies_data.size():
			var next_p: Dictionary = plies_data[idx + 1]
			if bool(next_p.get("is_white", ((idx + 1) % 2 == 0))) == want_white:
				return float(next_p.get("indice_d", 0))
		if cur_p.has("pression_d") and int(cur_p["pression_d"]) > 0:
			return float(cur_p["pression_d"])
		return _get_neighbor_d(idx, want_white)

	func _get_neighbor_d(idx: int, want_white: bool) -> float:
		var offsets: Array[int] = [0, -1, 1, -2, 2, -3, 3]
		for offset in offsets:
			var k: int = idx + offset
			if k >= 0 and k < plies_data.size():
				var p: Dictionary = plies_data[k]
				if bool(p.get("is_white", (k % 2 == 0))) == want_white:
					return float(p.get("indice_d", 0))
		return 15.0

	func _get_point_coords(idx: int, w: float, h: float, pad_l: float, pad_t: float) -> Vector2:
		if mode == PhaseMode.COUP_COMPLET:
			var full_moves: Array[Dictionary] = _build_full_moves()
			if idx >= 0 and idx < full_moves.size():
				var fm: Dictionary = full_moves[idx]
				var d_w := float(fm.get("d_w", 0))
				var d_b := float(fm.get("d_b", 0))
				var px := pad_l + clampf(d_w / 100.0, 0.0, 1.0) * w
				var py := pad_t + (1.0 - clampf(d_b / 100.0, 0.0, 1.0)) * h
				return Vector2(px, py)
			return Vector2.ZERO

		var p: Dictionary = plies_data[idx]
		var is_white := bool(p.get("is_white", (idx % 2 == 0)))
		var d_val := float(p.get("indice_d", 0))
		var eval_raw := float(p.get("score_cp", p.get("eval_cp", 0))) / 100.0

		match mode:
			PhaseMode.TENSION_LATENTE:
				var d_w := d_val if is_white else _get_latent_d(idx, true)
				var d_b := _get_latent_d(idx, false) if is_white else d_val
				var px := pad_l + clampf(d_w / 100.0, 0.0, 1.0) * w
				var py := pad_t + (1.0 - clampf(d_b / 100.0, 0.0, 1.0)) * h
				return Vector2(px, py)

			PhaseMode.BRAS_DE_FER:
				var d_w := d_val if is_white else _get_neighbor_d(idx, true)
				var d_b := d_val if not is_white else _get_neighbor_d(idx, false)
				var px := pad_l + clampf(d_w / 100.0, 0.0, 1.0) * w
				var py := pad_t + (1.0 - clampf(d_b / 100.0, 0.0, 1.0)) * h
				return Vector2(px, py)

			PhaseMode.EQUATEUR:
				var norm_eval := clampf(eval_raw / 4.0, -1.0, 1.0)
				var px := pad_l + (norm_eval * 0.5 + 0.5) * w
				var y_mid := pad_t + h * 0.5
				var sign_d := d_val if is_white else -d_val
				var py := y_mid - (sign_d / 100.0) * (h * 0.46)
				return Vector2(px, py)

			PhaseMode.RAVIN_VECTOR:
				var norm_eval := clampf(eval_raw / 4.0, -1.0, 1.0)
				var px := pad_l + (norm_eval * 0.5 + 0.5) * w
				var py := pad_t + (1.0 - clampf(d_val / 100.0, 0.0, 1.0)) * h
				return Vector2(px, py)

		return Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		var n := plies_data.size()
		if n == 0:
			return
		var pad_l := 16.0
		var pad_r := 16.0
		var pad_t := 14.0
		var pad_b := 14.0
		var w := size.x - pad_l - pad_r
		var h := size.y - pad_t - pad_b

		var is_full_move := (mode == PhaseMode.COUP_COMPLET)
		var full_moves: Array = _build_full_moves() if is_full_move else []
		var count := full_moves.size() if is_full_move else n

		if event is InputEventMouseMotion:
			var m_pos: Vector2 = (event as InputEventMouseMotion).position
			var closest := -1
			var min_dist := 9999.0
			for i in range(count):
				var pt := _get_point_coords(i, w, h, pad_l, pad_t)
				var d := m_pos.distance_to(pt)
				if d < min_dist and d < 32.0:
					min_dist = d
					closest = i
			if closest != hovered:
				hovered = closest
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var m_pos: Vector2 = (event as InputEventMouseButton).position
			var closest := -1
			var min_dist := 9999.0
			for i in range(count):
				var pt := _get_point_coords(i, w, h, pad_l, pad_t)
				var d := m_pos.distance_to(pt)
				if d < min_dist and d < 32.0:
					min_dist = d
					closest = i
			if closest != -1:
				current = closest
				var ply_idx := closest
				var fen_target := ""
				var uci_target := ""
				if is_full_move and closest < full_moves.size():
					var fm: Dictionary = full_moves[closest]
					ply_idx = int(fm.get("white_ply", 0))
					if ply_idx < plies_data.size():
						var p_step: Dictionary = plies_data[ply_idx]
						fen_target = str(p_step.get("fen_after", p_step.get("fen_before", "")))
						uci_target = str(p_step.get("move_uci", ""))
				elif closest < plies_data.size():
					var p_step: Dictionary = plies_data[closest]
					fen_target = str(p_step.get("fen_after", p_step.get("fen_before", "")))
					uci_target = str(p_step.get("move_uci", ""))
				step_clicked.emit(ply_idx)
				queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hovered = -1
			queue_redraw()

	func _draw() -> void:
		var n := plies_data.size()
		var font := ThemeDB.fallback_font
		var pad_l := 16.0
		var pad_r := 16.0
		var pad_t := 14.0
		var pad_b := 14.0
		var w := size.x - pad_l - pad_r
		var h := size.y - pad_t - pad_b
		if w <= 10.0 or h <= 10.0:
			return

		# 1. Fond du cadre
		draw_rect(Rect2(pad_l, pad_t, w, h), Color(0.08, 0.10, 0.16, 0.75))
		draw_rect(Rect2(pad_l, pad_t, w, h), Color(0.25, 0.32, 0.45, 0.5), false, 1.0)

		# 2. Grilles et repères selon le mode
		match mode:
			PhaseMode.COUP_COMPLET, PhaseMode.TENSION_LATENTE, PhaseMode.BRAS_DE_FER:
				# Diagonale d'équilibre (X = Y)
				draw_dashed_line(Vector2(pad_l, pad_t + h), Vector2(pad_l + w, pad_t), Color(0.4, 0.48, 0.65, 0.4), 1.0, 6.0)
				# Lignes médianes D=50
				draw_dashed_line(Vector2(pad_l + w * 0.5, pad_t), Vector2(pad_l + w * 0.5, pad_t + h), Color(0.3, 0.35, 0.45, 0.3), 1.0, 4.0)
				draw_dashed_line(Vector2(pad_l, pad_t + h * 0.5), Vector2(pad_l + w, pad_t + h * 0.5), Color(0.3, 0.35, 0.45, 0.3), 1.0, 4.0)
				# Quadrants
				draw_string(font, Vector2(pad_l + 4, pad_t + 12), "Noirs en charge", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.75, 0.85, 0.35))
				draw_string(font, Vector2(pad_l + w - 4, pad_t + h - 4), "Blancs en charge", HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, Color(0.7, 0.75, 0.85, 0.35))
				draw_string(font, Vector2(pad_l + w - 4, pad_t + 12), "Combat total", HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, Color(0.9, 0.4, 0.4, 0.35))
				draw_string(font, Vector2(pad_l + 4, pad_t + h - 4), "Calme plat", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.8, 0.5, 0.35))

				if mode == PhaseMode.COUP_COMPLET:
					draw_string(font, Vector2(pad_l + w * 0.5, pad_t + 10), "♟️ Tour N (X=D_Blanc, Y=D_Noir)", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0.75, 0.8, 0.95, 0.3))
				elif mode == PhaseMode.TENSION_LATENTE:
					draw_string(font, Vector2(pad_l + w * 0.5, pad_t + 10), "⚡ Tension Latente & Surprise (X=D_Blanc, Y=D_Noir)", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0.75, 0.8, 0.95, 0.3))

			PhaseMode.EQUATEUR:
				# Équateur Y=0
				var y_eq := pad_t + h * 0.5
				draw_line(Vector2(pad_l, y_eq), Vector2(pad_l + w, y_eq), Color(0.45, 0.55, 0.75, 0.7), 1.5)
				# Méridien Éval=0
				var x_mer := pad_l + w * 0.5
				draw_dashed_line(Vector2(x_mer, pad_t), Vector2(x_mer, pad_t + h), Color(0.35, 0.45, 0.6, 0.4), 1.0, 4.0)
				draw_string(font, Vector2(pad_l + 4, pad_t + 12), "Nord : Blancs sous tension", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.9, 1.0, 0.4))
				draw_string(font, Vector2(pad_l + 4, pad_t + h - 4), "Sud : Noirs sous tension", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.75, 0.85, 0.4))

			PhaseMode.RAVIN_VECTOR:
				var x_mer := pad_l + w * 0.5
				draw_dashed_line(Vector2(x_mer, pad_t), Vector2(x_mer, pad_t + h), Color(0.35, 0.45, 0.6, 0.4), 1.0, 4.0)
				# Ligne D=50
				draw_dashed_line(Vector2(pad_l, pad_t + h * 0.5), Vector2(pad_l + w, pad_t + h * 0.5), Color(0.3, 0.35, 0.45, 0.3), 1.0, 4.0)
				draw_string(font, Vector2(pad_l + w - 4, pad_t + 12), "Ravin & Vecteurs de Chute", HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, Color(0.95, 0.5, 0.5, 0.45))

		if n == 0:
			return

		# 3. Traitement spécifique du mode COUP_COMPLET
		if mode == PhaseMode.COUP_COMPLET:
			var full_moves: Array[Dictionary] = _build_full_moves()
			var m_count := full_moves.size()
			var pts: PackedVector2Array = []
			for i in range(m_count):
				pts.append(_get_point_coords(i, w, h, pad_l, pad_t))

			# Ligne continue entre coups complets
			if pts.size() >= 2:
				for i in range(pts.size() - 1):
					var p0 := pts[i]
					var p1 := pts[i + 1]
					var fm_step: Dictionary = full_moves[i]
					var p_col: Color = CliffTypes.get_piste_color(maxi(int(fm_step.get("piste_w", 0)), int(fm_step.get("piste_b", 0))))
					draw_line(p0, p1, Color(p_col.r, p_col.g, p_col.b, 0.8), 2.0, true)

			# Nœuds du coup complet
			for i in range(m_count):
				var pt := pts[i]
				var fm: Dictionary = full_moves[i]
				var is_v: bool = bool(fm.get("is_vital", false))
				if is_v:
					draw_arc(pt, 8.0, 0, TAU, 16, Color("#f59e0b"), 2.0)
				draw_circle(pt, 4.5, Color("#38bdf8"))
				draw_arc(pt, 4.5, 0, TAU, 16, Color.WHITE, 1.2)

				if i == current:
					draw_arc(pt, 9.5, 0, TAU, 20, Color("#c084fc"), 2.0)
					draw_dashed_line(Vector2(pad_l, pt.y), Vector2(pad_l + w, pt.y), Color(0.75, 0.5, 1.0, 0.4), 1.0, 3.0)
					draw_dashed_line(Vector2(pt.x, pad_t), Vector2(pt.x, pad_t + h), Color(0.75, 0.5, 1.0, 0.4), 1.0, 3.0)

				if i == hovered:
					draw_arc(pt, 7.0, 0, TAU, 16, Color.WHITE, 1.5)
					var m_num: int = int(fm.get("move_num", 1))
					var sw_txt: String = str(fm.get("san_w", ""))
					var sb_txt: String = str(fm.get("san_b", ""))
					var dw_num: int = int(fm.get("d_w", 0))
					var db_num: int = int(fm.get("d_b", 0))
					var tip := "%d. %s / %s (Dw=%d, Db=%d)" % [m_num, sw_txt, sb_txt, dw_num, db_num]
					draw_string(font, pt + Vector2(6, -6), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.95))
			return

		# 4. Traitement standard des modes par demi-coup
		var pts: PackedVector2Array = []
		for i in range(n):
			pts.append(_get_point_coords(i, w, h, pad_l, pad_t))

		# Tracé de la ligne continue unique (le chemin de la partie)
		if pts.size() >= 2:
			for i in range(pts.size() - 1):
				var p0 := pts[i]
				var p1 := pts[i + 1]
				var step_i: Dictionary = plies_data[i]
				var p_col: Color = CliffTypes.get_piste_color(int(step_i.get("piste", 0)))
				draw_line(p0, p1, Color(p_col.r, p_col.g, p_col.b, 0.75), 2.0, true)

		# Vecteurs de chute (spécifique au mode RAVIN_VECTOR)
		if mode == PhaseMode.RAVIN_VECTOR:
			for i in range(n):
				var p: Dictionary = plies_data[i]
				var delta := float(p.get("delta_chute", 0.0))
				if delta >= 0.12:
					var pt := pts[i]
					var is_white := bool(p.get("is_white", (i % 2 == 0)))
					var v_len := clampf(delta * 55.0, 10.0, 42.0)
					var dir_x := -1.0 if is_white else 1.0
					var end_pt := pt + Vector2(dir_x * v_len, 4.0)
					var col_v := Color("#ef4444") if delta >= 0.25 else Color("#f59e0b")
					draw_line(pt, end_pt, col_v, 2.0, true)
					var perp := Vector2(0, 1)
					draw_colored_polygon(PackedVector2Array([
						end_pt,
						end_pt - Vector2(dir_x * 5.0, 0) + perp * 3.0,
						end_pt - Vector2(dir_x * 5.0, 0) - perp * 3.0
					]), col_v)

		# Rendu des nœuds (demi-coups)
		for i in range(n):
			var pt := pts[i]
			var p: Dictionary = plies_data[i]
			var is_white := bool(p.get("is_white", (i % 2 == 0)))
			var is_vital := bool(p.get("is_vital", false))
			var col_node := Color.WHITE if is_white else Color(0.12, 0.15, 0.22)
			var border_node := Color.BLACK if is_white else Color(0.85, 0.88, 0.95)

			# Halo de choc ou de surprise cognitive
			var s_nature: int = int(p.get("surprise_nature", CliffTypes.SurpriseNature.NORMAL))
			if s_nature == CliffTypes.SurpriseNature.SHOCK:
				draw_arc(pt, 9.0, 0, TAU, 16, Color("#ef4444"), 2.2)
			elif s_nature == CliffTypes.SurpriseNature.SURPRISE:
				draw_arc(pt, 7.5, 0, TAU, 16, Color("#f59e0b"), 1.8)
			elif s_nature == CliffTypes.SurpriseNature.MIRACLE or s_nature == CliffTypes.SurpriseNature.RELIEF:
				draw_arc(pt, 7.5, 0, TAU, 16, Color("#10b981"), 1.8)

			if is_vital:
				draw_arc(pt, 7.0, 0, TAU, 16, Color("#f59e0b"), 2.0)

			draw_circle(pt, 4.0, col_node)
			draw_arc(pt, 4.0, 0, TAU, 16, border_node, 1.2)

			if i == current:
				draw_arc(pt, 8.5, 0, TAU, 20, Color("#c084fc"), 2.0)
				draw_dashed_line(Vector2(pad_l, pt.y), Vector2(pad_l + w, pt.y), Color(0.75, 0.5, 1.0, 0.4), 1.0, 3.0)
				draw_dashed_line(Vector2(pt.x, pad_t), Vector2(pt.x, pad_t + h), Color(0.75, 0.5, 1.0, 0.4), 1.0, 3.0)

			if i == hovered:
				draw_arc(pt, 6.0, 0, TAU, 16, Color.WHITE, 1.5)
				var san_str := str(p.get("san", p.get("move_uci", "?")))
				var d_num := int(p.get("indice_d", 0))
				var tip := ""
				var s_icon := CliffTypes.get_surprise_icon(s_nature)
				var s_suffix := (" " + s_icon) if s_icon != "" else ""
				if mode == PhaseMode.TENSION_LATENTE:
					var d_latent := int(_get_latent_d(i, not is_white))
					tip = "#%d %s%s (D_actif=%d, D_latent=%d)" % [i + 1, san_str, s_suffix, d_num, d_latent]
				else:
					tip = "#%d %s%s (D=%d)" % [i + 1, san_str, s_suffix, d_num]
				draw_string(font, pt + Vector2(6, -6), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.95))

var _source_label: Label
var _status_label: Label
var _btn_stop: Button
var _progress: ProgressBar
var _gauge_white: CliffGauge
var _gauge_black: CliffGauge
var _ribbon: HBoxContainer
var _ribbon_scroll: ScrollContainer
var _profile: CliffDuelGraph
var _tunnel: CliffSurvivalTunnel
var _phase_space: CliffPhaseSpace2D
var _btn_mode_coup: Button
var _btn_mode_latent: Button
var _btn_mode_bras: Button
var _btn_mode_equateur: Button
var _btn_mode_ravin: Button
var _narrative: Label
var _btn_replay: Button
var _btn_full: Button
var _btn_close: Button
var _chips: Array[Button] = []
var _ply_pistes: Array[int] = []
var _deltas: Array = []
var _baits: Array = []
var _current_step: int = -1
var _replaying: bool = false
var _stale: bool = false
var _report: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.16, 0.96)
	sb.border_color = Color(0.35, 0.25, 0.55, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(DesignTokens.RADIUS_MEDIUM)
	sb.content_margin_left = DesignTokens.SPACE_S
	sb.content_margin_right = DesignTokens.SPACE_S
	sb.content_margin_top = DesignTokens.SPACE_XS
	sb.content_margin_bottom = DesignTokens.SPACE_XS
	add_theme_stylebox_override("panel", sb)
	_build()
	clear()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# 1. En-tête
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "🏔️ CHESS-CLIFF · Super Live"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	title.add_theme_color_override("font_color", Color("#c084fc"))
	header.add_child(title)
	_btn_stop = Button.new()
	_btn_stop.text = "⏹ Stop"
	_btn_stop.clip_text = true
	_btn_stop.custom_minimum_size = Vector2(66, 40)
	_btn_stop.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_btn_stop.pressed.connect(func(): stop_requested.emit())
	header.add_child(_btn_stop)
	_btn_close = Button.new()
	_btn_close.text = "✖"
	_btn_close.flat = true
	_btn_close.custom_minimum_size = Vector2(32, 40)
	_btn_close.add_theme_font_size_override("font_size", 12)
	_btn_close.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_btn_close.pressed.connect(func(): close_requested.emit())
	header.add_child(_btn_close)
	vbox.add_child(header)

	# Ligne source + statut
	var meta_row := HBoxContainer.new()
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_label = Label.new()
	_source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_label.clip_text = true
	_source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_source_label.add_theme_font_size_override("font_size", 10)
	_source_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	meta_row.add_child(_source_label)
	_status_label = Label.new()
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", DesignTokens.WARNING)
	meta_row.add_child(_status_label)
	vbox.add_child(meta_row)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 4)
	_progress.show_percentage = false
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.14, 0.22, 0.6)
	sb_bg.set_corner_radius_all(2)
	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = Color("#c084fc")
	sb_fill.set_corner_radius_all(2)
	_progress.add_theme_stylebox_override("background", sb_bg)
	_progress.add_theme_stylebox_override("fill", sb_fill)
	vbox.add_child(_progress)

	# 2. Duel Altimétrique Topographique (profil miroir)
	_profile = CliffDuelGraph.new()
	_profile.bar_clicked.connect(func(idx: int):
		if idx >= 0 and idx < _chips.size():
			_chips[idx].pressed.emit()
	)
	vbox.add_child(_profile)

	# 3. Ruban bi-piste synchronisé (Noirs en haut ⚫, Blancs en bas ⚪)
	var ribbon_row := HBoxContainer.new()
	ribbon_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon_row.add_theme_constant_override("separation", 3)

	var side_labels := VBoxContainer.new()
	side_labels.add_theme_constant_override("separation", 2)
	side_labels.custom_minimum_size = Vector2(16, 54)
	var lbl_b := Label.new()
	lbl_b.text = "⚫"
	lbl_b.custom_minimum_size = Vector2(16, 26)
	lbl_b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_b.add_theme_font_size_override("font_size", 10)
	side_labels.add_child(lbl_b)

	var lbl_w := Label.new()
	lbl_w.text = "⚪"
	lbl_w.custom_minimum_size = Vector2(16, 26)
	lbl_w.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_w.add_theme_font_size_override("font_size", 10)
	side_labels.add_child(lbl_w)
	ribbon_row.add_child(side_labels)

	_ribbon_scroll = ScrollContainer.new()
	_ribbon_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ribbon_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ribbon_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_ribbon_scroll.custom_minimum_size = Vector2(0, 56)
	DesignTokens.touch_scroll(_ribbon_scroll)
	_ribbon = HBoxContainer.new()
	_ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ribbon.add_theme_constant_override("separation", 3)
	_ribbon_scroll.add_child(_ribbon)
	ribbon_row.add_child(_ribbon_scroll)
	vbox.add_child(ribbon_row)

	# 4. Faisceau d'Étranglement Venturi (Tunnel de Survie)
	_tunnel = CliffSurvivalTunnel.new()
	_tunnel.step_clicked.connect(func(idx: int):
		if idx >= 0 and idx < _chips.size():
			_chips[idx].pressed.emit()
	)
	vbox.add_child(_tunnel)

	# 5. Espace des Phases 2D : Sélecteur 5 modes + Canvas
	var mode_scroll := ScrollContainer.new()
	mode_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mode_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	mode_scroll.custom_minimum_size = Vector2(0, 26)
	DesignTokens.touch_scroll(mode_scroll)

	var mode_bar := HBoxContainer.new()
	mode_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_bar.add_theme_constant_override("separation", 3)

	var lbl_phase := Label.new()
	lbl_phase.text = "🧭 2D :"
	lbl_phase.add_theme_font_size_override("font_size", 10)
	lbl_phase.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	mode_bar.add_child(lbl_phase)

	_btn_mode_coup = _make_phase_button("♟️ Coup", CliffPhaseSpace2D.PhaseMode.COUP_COMPLET)
	_btn_mode_latent = _make_phase_button("⚡ Latent", CliffPhaseSpace2D.PhaseMode.TENSION_LATENTE)
	_btn_mode_bras = _make_phase_button("🤼 Duel", CliffPhaseSpace2D.PhaseMode.BRAS_DE_FER)
	_btn_mode_equateur = _make_phase_button("🌐 Équateur", CliffPhaseSpace2D.PhaseMode.EQUATEUR)
	_btn_mode_ravin = _make_phase_button("🏹 Ravin", CliffPhaseSpace2D.PhaseMode.RAVIN_VECTOR)

	mode_bar.add_child(_btn_mode_coup)
	mode_bar.add_child(_btn_mode_latent)
	mode_bar.add_child(_btn_mode_bras)
	mode_bar.add_child(_btn_mode_equateur)
	mode_bar.add_child(_btn_mode_ravin)
	mode_scroll.add_child(mode_bar)
	vbox.add_child(mode_scroll)

	_phase_space = CliffPhaseSpace2D.new()
	_phase_space.step_clicked.connect(func(idx: int):
		if idx >= 0 and idx < _chips.size():
			_chips[idx].pressed.emit()
	)
	vbox.add_child(_phase_space)
	_update_phase_buttons_style()

	# 6. Jauges duales globales
	_gauge_white = CliffGauge.new()
	_gauge_white.side_label = "BLANCS"
	_gauge_black = CliffGauge.new()
	_gauge_black.side_label = "NOIRS"
	vbox.add_child(_gauge_white)
	vbox.add_child(_gauge_black)

	# 7. Récit + actions
	_narrative = Label.new()
	_narrative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narrative.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_narrative.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	vbox.add_child(_narrative)

	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 4)
	_btn_replay = _make_action("▶ Rejouer", func(): _toggle_replay())
	actions.add_child(_btn_replay)
	_btn_full = _make_action("🔎 Toute la partie", func(): full_game_requested.emit())
	actions.add_child(_btn_full)
	vbox.add_child(actions)

func _make_action(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	b.pressed.connect(cb)
	return b

func _make_phase_button(text: String, target_mode: int) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(0, 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 9)
	b.pressed.connect(func():
		if is_instance_valid(_phase_space):
			_phase_space.set_mode(target_mode)
		_update_phase_buttons_style()
	)
	return b

func _update_phase_buttons_style() -> void:
	var cur_m: int = _phase_space.mode if is_instance_valid(_phase_space) else 0
	var btns := [_btn_mode_coup, _btn_mode_latent, _btn_mode_bras, _btn_mode_equateur, _btn_mode_ravin]
	var modes: Array[int] = [
		CliffPhaseSpace2D.PhaseMode.COUP_COMPLET,
		CliffPhaseSpace2D.PhaseMode.TENSION_LATENTE,
		CliffPhaseSpace2D.PhaseMode.BRAS_DE_FER,
		CliffPhaseSpace2D.PhaseMode.EQUATEUR,
		CliffPhaseSpace2D.PhaseMode.RAVIN_VECTOR
	]
	for i in range(btns.size()):
		var b: Button = btns[i]
		if not is_instance_valid(b):
			continue
		var is_active: bool = (modes[i] == cur_m)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.24, 0.18, 0.38, 0.95) if is_active else Color(0.10, 0.13, 0.20, 0.8)
		sb.border_color = Color("#c084fc") if is_active else Color(0.3, 0.35, 0.45, 0.5)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", Color.WHITE if is_active else DesignTokens.TEXT_MUTED)

# --- API publique -------------------------------------------------------

func clear() -> void:
	_report = {}
	_stale = false
	_replaying = false
	_ply_pistes.clear()
	_deltas.clear()
	_baits.clear()
	_current_step = -1
	if is_instance_valid(_ribbon):
		for c in _ribbon.get_children():
			c.queue_free()
		_chips.clear()
	if is_instance_valid(_profile):
		_profile.set_data([], [])
		_profile.plies_data.clear()
	if is_instance_valid(_tunnel):
		_tunnel.set_plies([])
		_tunnel.set_current(-1)
	if is_instance_valid(_phase_space):
		_phase_space.set_plies([])
		_phase_space.set_current(-1)
	if is_instance_valid(_narrative):
		_narrative.text = ""
	if is_instance_valid(_source_label):
		_source_label.text = ""
	if is_instance_valid(_status_label):
		_status_label.text = ""
	if is_instance_valid(_progress):
		_progress.visible = false
	if is_instance_valid(_btn_replay):
		_btn_replay.text = "▶ Rejouer"
		_btn_replay.disabled = true
	if is_instance_valid(_btn_full):
		_btn_full.disabled = false
	if is_instance_valid(_gauge_white):
		_gauge_white.set_values(1.0, 0, CliffTypes.Piste.AUTOROUTE)
	if is_instance_valid(_gauge_black):
		_gauge_black.set_values(1.0, 0, CliffTypes.Piste.AUTOROUTE)
	visible = false

## Bascule sur l'état « calcul en cours » (n/N).
func show_computing(cur: int, total: int) -> void:
	visible = true
	_status_label.text = "Calcul…"
	_progress.visible = true
	_progress.max_value = float(maxi(1, total))
	_progress.value = float(cur)

func set_source_label(text: String) -> void:
	if is_instance_valid(_source_label):
		_source_label.text = text

func set_stale(is_stale: bool) -> void:
	_stale = is_stale
	if is_instance_valid(_status_label):
		_status_label.text = "⚠ Obsolète – relancer" if is_stale else ""

## Mise à jour progressive pendant le calcul (aperçu vivant).
func set_step(step: Dictionary) -> void:
	visible = true
	_status_label.text = "Calcul…"
	var idx := int(step.get("step", _ply_pistes.size()))
	_append_chip(step, idx)
	_current_step = idx
	_profile.set_current(idx)
	if is_instance_valid(_tunnel):
		var plies_arr: Array = _report.get("plies", [])
		if idx >= plies_arr.size():
			plies_arr.append(step)
		_tunnel.set_plies(plies_arr)
		_tunnel.set_current(idx)
	if is_instance_valid(_phase_space):
		var plies_arr2: Array = _report.get("plies", [])
		_phase_space.set_plies(plies_arr2)
		_phase_space.set_current(idx)
	var piste: int = int(step.get("piste", CliffTypes.Piste.AUTOROUTE))
	var side_is_white: bool = bool(step.get("is_white", true))
	var g := _gauge_white if side_is_white else _gauge_black
	g.set_values(float(step.get("p_survie", 1.0)), int(step.get("indice_d", 0)), piste)

## Rapport final : reconstruit jauges, ruban, profil, tunnel, espace 2D, récit.
func set_report(report: Dictionary) -> void:
	clear()
	_report = report
	if report.is_empty() or not report.has("summary_white"):
		return
	visible = true
	_status_label.text = "Terminé"
	_btn_replay.disabled = false

	var plies: Array = report.get("plies", [])
	for i in range(plies.size()):
		_append_chip(plies[i], i)
	_current_step = -1
	_profile.set_plies(plies)
	_profile.set_current(-1)
	if is_instance_valid(_tunnel):
		_tunnel.set_plies(plies)
		_tunnel.set_current(-1)
	if is_instance_valid(_phase_space):
		_phase_space.set_plies(plies)
		_phase_space.set_current(-1)

	var sw: Dictionary = report.get("summary_white", {})
	var sb: Dictionary = report.get("summary_black", {})
	_gauge_white.set_values(float(sw.get("p_survie_ligne", 1.0)), int(sw.get("indice_d", 0)),
			int(sw.get("global_piste", CliffTypes.Piste.AUTOROUTE)))
	_gauge_black.set_values(float(sb.get("p_survie_ligne", 1.0)), int(sb.get("indice_d", 0)),
			int(sb.get("global_piste", CliffTypes.Piste.AUTOROUTE)))

	var rep := CliffLineReport.from_dict(report)
	_narrative.text = "« " + rep.get_narrative_summary() + " »"
	_narrative.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)

## Applique un pas courant : surligne la pastille, met à jour profil, tunnel, espace 2D, récit et jauges.
func highlight_step(idx: int) -> void:
	_current_step = idx
	_profile.set_current(idx)
	if is_instance_valid(_tunnel):
		_tunnel.set_current(idx)
	if is_instance_valid(_phase_space):
		_phase_space.set_current(idx)
	for i in range(_chips.size()):
		var is_cur := (i == idx)
		var p_col: Color = CliffTypes.get_piste_color(_ply_pistes[i])
		_chips[i].add_theme_color_override("font_color", Color.WHITE if is_cur else p_col)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.22, 0.28, 0.42, 0.95) if is_cur else Color(0.10, 0.14, 0.22, 0.90)
		sb.border_color = Color("#c084fc") if is_cur else p_col
		sb.set_border_width_all(2 if is_cur else 1)
		sb.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		_chips[i].add_theme_stylebox_override("normal", sb)

	# Défilement automatique du ruban bi-piste pour centrer le coup actif
	if is_instance_valid(_ribbon_scroll) and idx >= 0 and idx < _chips.size():
		var chip: Control = _chips[idx]
		var col_parent := chip.get_parent() as Control
		var target_ctrl: Control = col_parent if col_parent != null else chip
		_ribbon_scroll.ensure_control_visible(target_ctrl)

	var plies: Array = _report.get("plies", [])
	var sw: Dictionary = _report.get("summary_white", {})
	var sb: Dictionary = _report.get("summary_black", {})
	if idx >= 0 and idx < plies.size():
		var step: Dictionary = plies[idx]
		var side_is_white: bool = bool(step.get("is_white", true))
		if side_is_white:
			_gauge_white.set_values(float(step.get("p_survie", 1.0)), int(step.get("indice_d", 0)),
					int(step.get("piste", CliffTypes.Piste.AUTOROUTE)))
			_gauge_black.set_values(float(sb.get("p_survie_ligne", 1.0)), int(sb.get("indice_d", 0)),
					int(sb.get("global_piste", CliffTypes.Piste.AUTOROUTE)))
		else:
			_gauge_black.set_values(float(step.get("p_survie", 1.0)), int(step.get("indice_d", 0)),
					int(step.get("piste", CliffTypes.Piste.AUTOROUTE)))
			_gauge_white.set_values(float(sw.get("p_survie_ligne", 1.0)), int(sw.get("indice_d", 0)),
					int(sw.get("global_piste", CliffTypes.Piste.AUTOROUTE)))

		# Récit contextuel du coup sélectionné
		var expl := str(step.get("explanation", ""))
		if expl == "":
			var san_m := str(step.get("san", step.get("move_uci", "?")))
			var p_name := CliffTypes.get_piste_name(int(step.get("piste", 0)))
			var d_val := int(step.get("indice_d", 0))
			var surv := int(round(float(step.get("p_survie", 1.0)) * 100.0))
			expl = "Coup #%d (%s) : %s (D=%d) · Survie : %d%%" % [idx + 1, san_m, p_name, d_val, surv]
		_narrative.text = "👉 " + expl
		_narrative.add_theme_color_override("font_color", Color("#f1f5f9"))
	else:
		_gauge_white.set_values(float(sw.get("p_survie_ligne", 1.0)), int(sw.get("indice_d", 0)),
				int(sw.get("global_piste", CliffTypes.Piste.AUTOROUTE)))
		_gauge_black.set_values(float(sb.get("p_survie_ligne", 1.0)), int(sb.get("indice_d", 0)),
				int(sb.get("global_piste", CliffTypes.Piste.AUTOROUTE)))
		if not _report.is_empty():
			var rep := CliffLineReport.from_dict(_report)
			_narrative.text = "« " + rep.get_narrative_summary() + " »"
			_narrative.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)

func _toggle_replay() -> void:
	_replaying = not _replaying
	_btn_replay.text = "⏸ Pause" if _replaying else "▶ Rejouer"
	replay_toggled.emit(_replaying)

func is_replaying() -> bool:
	return _replaying

func stop_replay() -> void:
	_replaying = false
	if is_instance_valid(_btn_replay):
		_btn_replay.text = "▶ Rejouer"

# --- Interne ------------------------------------------------------------

func _append_chip(step: Dictionary, idx: int) -> void:
	var san: String = str(step.get("san", step.get("move_uci", "?")))
	var piste: int = int(step.get("piste", CliffTypes.Piste.AUTOROUTE))
	var col := CliffTypes.get_piste_color(piste)
	var is_white: bool = bool(step.get("is_white", (idx % 2 == 0)))
	var is_vital: bool = bool(step.get("is_vital", false))
	var nature: int = int(step.get("move_nature", CliffTypes.MoveNature.VITAL if is_vital else CliffTypes.MoveNature.SAFE))
	var nature_icon: String = CliffTypes.get_nature_icon(nature)
	if nature_icon == "" or nature == CliffTypes.MoveNature.SAFE:
		nature_icon = CliffTypes.get_piste_icon(piste)

	var move_num := int(step.get("ply", idx)) / 2 + 1
	var move_tag := "%d. %s" % [move_num, san] if is_white else "%d... %s" % [move_num, san]

	var btn := Button.new()
	btn.text = "%s %s" % [move_tag, nature_icon]
	btn.tooltip_text = "%s — %s (D=%d)\nNature : %s\nSurvie : %d%%\nRavin Δ : %.2f\nPiège : %.2f" % [
		san, CliffTypes.get_piste_name(piste), int(step.get("indice_d", 0)),
		CliffTypes.get_nature_label(nature),
		int(round(float(step.get("p_survie", 1.0)) * 100.0)),
		float(step.get("delta_chute", 0.0)), float(step.get("bait", 0.0))
	]
	btn.custom_minimum_size = Vector2(56, 26)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", col)
	var border_col := Color("#f59e0b") if is_vital else col
	btn.add_theme_stylebox_override("normal",
			DesignTokens.flat(Color(0.10, 0.14, 0.22, 0.90), DesignTokens.RADIUS_SMALL, border_col, 1 if not is_vital else 2, Vector2(4, 1)))
	btn.add_theme_stylebox_override("hover",
			DesignTokens.flat(Color(0.18, 0.22, 0.32, 0.98), DesignTokens.RADIUS_SMALL, Color.WHITE, 1, Vector2(4, 1)))
	btn.add_theme_stylebox_override("pressed",
			DesignTokens.flat(Color(0.08, 0.12, 0.18, 1.0), DesignTokens.RADIUS_SMALL, border_col, 1, Vector2(4, 1)))

	var step_fen := str(step.get("fen_before", step.get("fen", step.get("fen_after", ""))))
	var step_uci := str(step.get("move_uci", step.get("played_uci", step.get("best_move", ""))))
	btn.pressed.connect(func():
		highlight_step(idx)
		step_selected.emit(idx, step_fen, step_uci)
	)

	# Colonne synchronisée bi-piste (Noir en haut, Blanc en bas)
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 2)
	col_box.custom_minimum_size = Vector2(56, 54)

	var placeholder := Label.new()
	placeholder.text = "·"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.custom_minimum_size = Vector2(56, 26)
	placeholder.add_theme_font_size_override("font_size", 12)
	placeholder.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55, 0.35))

	if is_white:
		col_box.add_child(placeholder)
		col_box.add_child(btn)
	else:
		col_box.add_child(btn)
		col_box.add_child(placeholder)

	_chips.append(btn)
	_ply_pistes.append(piste)
	_deltas.append(float(step.get("delta_chute", 0.0)))
	_baits.append(float(step.get("bait", 0.0)))
	_ribbon.add_child(col_box)
	_profile.set_data(_deltas, _baits)
