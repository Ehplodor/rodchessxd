extends SceneTree
## Render_PWA_Icons.gd - Génère les icônes PNG 144/180/512 de la PWA depuis res://icon.svg (texture importée).
## Usage : godot --headless --path . --import  puis  godot --headless --path . --script res://tools/render_pwa_icons.gd

func _init() -> void:
	var tex := load("res://icon.svg") as Texture2D
	if tex == null:
		printerr("render_pwa_icons: impossible de charger la texture importee res://icon.svg")
		quit(1)
		return
	var src := tex.get_image()
	if src == null:
		printerr("render_pwa_icons: get_image() a echoue (import SVG requis ?)")
		quit(1)
		return
	var sizes := [144, 180, 512]
	for s in sizes:
		var img := src.duplicate()
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		var out := "res://assets/web/icons/icon-%d.png" % s
		var err: Error = img.save_png(out)
		if err != OK:
			printerr("render_pwa_icons: echec d'ecriture ", out, " (err=", err, ")")
			quit(1)
			return
		print("render_pwa_icons: ", out, " ecrit (", img.get_width(), "x", img.get_height(), ")")
	quit(0)
