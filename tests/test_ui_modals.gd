extends SceneTree

const OCREditorModal = preload("res://src/ui/components/OCREditorModal.gd")
const ChessComImportModal = preload("res://src/ui/components/ChessComImportModal.gd")
const PGNModal = preload("res://src/ui/components/PGNModal.gd")
const SettingsModal = preload("res://src/ui/components/SettingsModal.gd")
const EngineHubModal = preload("res://src/ui/components/EngineHubModal.gd")
const ModelHubModal = preload("res://src/ui/components/ModelHubModal.gd")
const LibraryModal = preload("res://src/ui/components/LibraryModal.gd")
const PromotionModal = preload("res://src/ui/components/PromotionModal.gd")

func _init() -> void:
	print("[TEST] --- Démarrage du test de conformité et flexibilité des fenêtres modales ---")
	
	var modals = [
		{"name": "OCREditorModal", "script": OCREditorModal},
		{"name": "ChessComImportModal", "script": ChessComImportModal},
		{"name": "PGNModal", "script": PGNModal},
		{"name": "SettingsModal", "script": SettingsModal},
		{"name": "EngineHubModal", "script": EngineHubModal},
		{"name": "ModelHubModal", "script": ModelHubModal},
		{"name": "LibraryModal", "script": LibraryModal},
		{"name": "PromotionModal", "script": PromotionModal}
	]

	for m_info in modals:
		var name = m_info["name"]
		var modal: Window = m_info["script"].new()
		root.add_child(modal)
		
		# Vérifier les dimensions par défaut
		print("  -> %s : Taille définie = %s" % [name, str(modal.size)])
		assert(modal.size.x <= 420, "%s est trop large pour un écran 450px !" % name)
		
		# Vérifier qu'aucun conteneur horizontal ne force une largeur démesurée
		_check_node_responsiveness(modal, name)
		
		modal.queue_free()
		print("  -> %s : OK ✓" % name)

	print("[TEST] --- Tous les tests de réactivité et d'affichage des modales ont RÉUSSI (100% conformes) ! ---")
	quit(0)

func _check_node_responsiveness(node: Node, modal_name: String) -> void:
	if node is ScrollContainer:
		var sc = node as ScrollContainer
		assert(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, 
			"%s contient un ScrollContainer avec défilement horizontal non désactivé !" % modal_name)

	for child in node.get_children():
		_check_node_responsiveness(child, modal_name)
