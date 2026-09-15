extends SceneTree

func _probe(ms, tag: String) -> void:
	await process_frame
	var col = ms.get_node_or_null("VBox/CenterArea/BoardColumn")
	var cont = ms.get_node_or_null("VBox/CenterArea/BoardColumn/BoardContainer")
	var cb = ms.get_node_or_null("VBox/CenterArea/BoardColumn/BoardContainer/ChessBoard")
	var eb = ms.get_node_or_null("VBox/CenterArea/BoardColumn/BoardContainer/EvalBar")
	var cr = col.get_global_rect(); var ctr = cont.get_global_rect()
	var bbr = cb.get_global_rect(); var er = eb.get_global_rect()
	print("%-12s col=(%.0f..%.0f w%.0f) cont=(%.0f..%.0f) board=(%.0f..%.0f w%.0f) evalEnd=%.0f  ovlLeft=%s" % [
		tag, cr.position.x, cr.end.x, cr.size.x, ctr.position.x, ctr.end.x,
		bbr.position.x, bbr.end.x, bbr.size.x, er.end.x, str(bbr.position.x < er.end.x)])

func _init() -> void:
	await create_timer(0.1).timeout
	var root = get_root()
	var ms = load("res://src/ui/Main.tscn").instantiate()
	ms.name = "Main"
	root.add_child(ms)
	await create_timer(0.4).timeout
	var sizes := [Vector2(390,844), Vector2(360,740), Vector2(320,700), Vector2(844,390), Vector2(700,380)]
	for s in sizes:
		root.get_window().size = Vector2i(s.x, s.y)
		ms.size = s
		await process_frame
		ms._check_and_update_layout()
		await process_frame
		await process_frame
		_probe(ms, "%dx%d" % [int(s.x), int(s.y)])
	ms.queue_free()
	quit(0)
