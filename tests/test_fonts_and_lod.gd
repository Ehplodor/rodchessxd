extends SceneTree

func _init() -> void:
	print("[TEST] --- Vérification des polices, glyphes universels et résolution LOD ---")
	
	# 1. Initialiser le fallback global
	DesignTokens.setup_global_fonts()
	var font: Font = ThemeDB.fallback_font
	assert(font != null, "ThemeDB.fallback_font doit être défini !")
	
	var chars_to_test = [
		"★", "✓", "✕", "✖", "⭐", "✅", "✨", "⚡", "🤖", "📊", "⚪", "⚫",
		"♔", "♕", "♖", "♗", "♘", "♙", "♟️", "🔄", "📥", "📚", "⚙️", "➔"
	]
	
	print("Vérification du support des glyphes :")
	for ch in chars_to_test:
		var has_it = font.has_char(ch.unicode_at(0))
		print("  '%s' (U+%04X) -> %s" % [ch, ch.unicode_at(0), "OK" if has_it else "MANQUANT"])
		assert(has_it, "Le glyphe '%s' doit être supporté par la police !" % ch)
	
	print("  -> Tous les glyphes de l'interface sont 100% supportés ! ✓")
	
	# 2. Vérifier les dimensions et LOD du ChessBoard2D
	var board = ChessBoard2D.new()
	root.add_child(board)
	board._ready()
	board.size = Vector2(800, 800)
	board._notification(Control.NOTIFICATION_RESIZED)
	
	assert(board.board_size == 800.0, "board_size doit être 800")
	assert(board.square_size == 100.0, "square_size doit être 100")
	
	# Vérifier les sprites et textures
	assert(board.piece_sprites.size() == 64, "64 TextureRect doivent être créés")
	var tr0: TextureRect = board.piece_sprites[0]
	assert(tr0.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "Le filtrage linéaire avec mipmaps doit être actif")
	
	board.free()
	print("  -> Vérification LOD et filtrage des pièces validée ! ✓")
	
	print("🎉 VALIDATION POLICES ET LOD ACCOMPLIE AVEC SUCCÈS (100% OK) !")
	quit(0)
