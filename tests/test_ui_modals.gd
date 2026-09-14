extends SceneTree

# Chemins chargés à l'exécution (`load`) et non via `preload` : les scripts de modales
# référencent les autoloads (GameController, SettingsManager, EngineManager), qui ne
# sont enregistrés qu'au démarrage. Un `preload` les compilerait trop tôt et émettrait
# des erreurs « Identifier not found ».
const MODAL_PATHS := [
	{"name": "OCREditorModal", "path": "res://src/ui/components/OCREditorModal.gd"},
	{"name": "ChessComImportModal", "path": "res://src/ui/components/ChessComImportModal.gd"},
	{"name": "PGNModal", "path": "res://src/ui/components/PGNModal.gd"},
	{"name": "SettingsModal", "path": "res://src/ui/components/SettingsModal.gd"},
	{"name": "EngineHubModal", "path": "res://src/ui/components/EngineHubModal.gd"},
	{"name": "ModelHubModal", "path": "res://src/ui/components/ModelHubModal.gd"},
	{"name": "LibraryModal", "path": "res://src/ui/components/LibraryModal.gd"},
	{"name": "PromotionModal", "path": "res://src/ui/components/PromotionModal.gd"}
]

var _ran := false
var _failures := 0

func _init() -> void:
	print("[TEST] --- Démarrage du test de conformité et flexibilité des fenêtres modales ---")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	for m_info in MODAL_PATHS:
		var name = m_info["name"]
		var script: GDScript = load(m_info["path"])
		if script == null:
			_failures += 1
			printerr("  -> %s : script introuvable (%s)" % [name, m_info["path"]])
			continue
		var modal: Window = script.new()
		root.add_child(modal)

		# Vérifier les dimensions par défaut
		print("  -> %s : Taille définie = %s" % [name, str(modal.size)])
		assert(modal.size.x <= 420, "%s est trop large pour un écran 450px !" % name)

		# Vérifier qu'aucun conteneur horizontal ne force une largeur démesurée
		_check_node_responsiveness(modal, name, float(modal.size.x))

		modal.queue_free()
		print("  -> %s : OK ✓" % name)

	if _failures == 0:
		print("[TEST] --- Tous les tests de réactivité et d'affichage des modales ont RÉUSSI (100% conformes) ! ---")
	else:
		printerr("[TEST] --- ÉCHEC : %d modale(s) en erreur ---" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _check_node_responsiveness(node: Node, modal_name: String, max_w: float) -> void:
	if node is ScrollContainer:
		var sc = node as ScrollContainer
		assert(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, 
			"%s contient un ScrollContainer avec défilement horizontal non désactivé !" % modal_name)

	if node is Control:
		var c = node as Control
		var min_w = c.get_combined_minimum_size().x
		assert(min_w <= max_w + 1.0,
			"%s : Le contrôle %s (%s) impose une largeur minimale de %.1f px > max autorisée %.1f px !" % [modal_name, c.name, c.get_class(), min_w, max_w])

	for child in node.get_children():
		_check_node_responsiveness(child, modal_name, max_w)
