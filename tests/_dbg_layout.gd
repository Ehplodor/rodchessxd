extends SceneTree

func _probe(ms, tag: String) -> void:
	await process_frame
	var cont = ms.board_container
	var cb = ms.chess_board
	var eb = ms.eval_bar
	var vs = ms.main_scroll
	var ctr = cont.get_global_rect()
	var bbr = cb.get_global_rect(); var er = eb.get_global_rect()
	# Le plateau doit rester carré et à pleine largeur ; MainScroll fournit le
	# défilement vertical (vmax > page) sans jamais écraser l'échiquier.
	print("%-14s viewport=%s board=(w%.0f h%.0f carre=%s) cont=(%.0f..%.0f) evalEnd=%.0f scroll(vmax=%.0f page=%.0f)" % [
		tag, ms.get_viewport_rect().size, bbr.size.x, bbr.size.y,
		str(is_equal_approx(bbr.size.x, bbr.size.y)), ctr.position.x, ctr.end.x,
		er.end.x, vs.get_v_scroll_bar().max_value, vs.get_v_scroll_bar().page])

func _init() -> void:
	await create_timer(0.1).timeout
	var root = get_root()
	var ms = load("res://src/ui/Main.tscn").instantiate()
	ms.name = "Main"
	root.add_child(ms)
	await create_timer(0.4).timeout
	# NB : ne PAS forcer ms.size (Main est ancré plein écran) — sinon on mesure
	# une taille physique artificielle au lieu du viewport logique réel.
	var sizes := [Vector2(390,844), Vector2(360,740), Vector2(320,700), Vector2(844,390), Vector2(700,380)]
	for s in sizes:
		root.get_window().size = Vector2i(s.x, s.y)
		await process_frame
		ms._check_and_update_layout()
		await process_frame
		await process_frame
		_probe(ms, "%dx%d" % [int(s.x), int(s.y)])
	ms.queue_free()
	quit(0)
