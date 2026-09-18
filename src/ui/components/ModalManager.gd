class_name ModalManager
extends RefCounted
## ModalManager.gd — cycle de vie des modales `Window` de l'écran principal.
##
## Une seule modale à la fois (les autres sont fermées), taille bornée au viewport
## (94 % × 92 %). Les fenêtres restent ajoutées comme enfants directs du propriétaire
## pour préserver la recherche par `get_children()` (tests d'intégration UI).

var _owner: Control = null
var current: Window = null

func _init(owner: Control) -> void:
	_owner = owner

func open(modal_node: Window) -> void:
	if _owner == null or modal_node == null:
		return
	if current != null and is_instance_valid(current):
		current.hide()
		current.queue_free()
	current = modal_node
	_owner.add_child(modal_node)
	var viewport := _owner.get_viewport()
	if viewport != null:
		var vis: Vector2 = viewport.get_visible_rect().size
		if vis.x > 0.0 and vis.y > 0.0:
			var max_w := int(vis.x * 0.94)
			var max_h := int(vis.y * 0.92)
			modal_node.size = Vector2i(
					mini(modal_node.size.x, max_w), mini(modal_node.size.y, max_h))
	modal_node.popup_centered(modal_node.size)
