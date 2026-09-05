extends SceneTree

const GameAnalyzer = preload("res://src/engine/GameAnalyzer.gd")

func _init() -> void:
	print("--- Test du modèle de calibration ELO & Précision CAPS2 ---")
	var analyzer = GameAnalyzer.new()

	# Cas 1 : Débutant avec plusieurs gaffes (25 coups, 52% précision, ACPL 120, 4 gaffes)
	var elo_beginner = analyzer._estimate_elo(52.0, 120.0, {"blunder": 4, "mistake": 3}, 25)
	print("1. Joueur Débutant (52%% préc, 4 gaffes) : Est. %d ELO (Attendu: 600-850)" % elo_beginner)
	assert(elo_beginner >= 600 and elo_beginner <= 850, "Échec estimation débutant")

	# Cas 2 : Joueur de Club intermédiaire (30 coups, 78% précision, ACPL 52, 1 gaffe)
	var elo_club = analyzer._estimate_elo(78.0, 52.0, {"blunder": 1, "mistake": 2}, 30)
	print("2. Joueur de Club (78%% préc, 1 gaffe)     : Est. %d ELO (Attendu: 1300-1550)" % elo_club)
	assert(elo_club >= 1300 and elo_club <= 1550, "Échec estimation club")

	# Cas 3 : Maître National (40 coups, 94% précision, ACPL 22, 0 gaffe, 1 erreur)
	var elo_master = analyzer._estimate_elo(94.0, 22.0, {"blunder": 0, "mistake": 1}, 40)
	print("3. Maître National (94%% préc, 0 gaffe)    : Est. %d ELO (Attendu: 2050-2300)" % elo_master)
	assert(elo_master >= 2050 and elo_master <= 2300, "Échec estimation maître")

	# Cas 4 : Grand-Maître d'Élite (50 coups, 98.2% précision, ACPL 12, 0 gaffe, 0 erreur)
	var elo_gm = analyzer._estimate_elo(98.2, 12.0, {"blunder": 0, "mistake": 0}, 50)
	print("4. Grand-Maître (98.2%% préc, 0 gaffe)     : Est. %d ELO (Attendu: 2450-2700)" % elo_gm)
	assert(elo_gm >= 2450 and elo_gm <= 2700, "Échec estimation GM")

	# Cas 5 : Ouverture courte (4 coups seulement, 99% précision car coups théoriques)
	var elo_short = analyzer._estimate_elo(99.0, 6.0, {"blunder": 0, "mistake": 0}, 4)
	print("5. Ouverture courte (4 coups, 99%% préc)   : Est. %d ELO (Attendu: 1500-1700 avec amortisseur)" % elo_short)
	assert(elo_short >= 1500 and elo_short <= 1700, "Échec amortisseur partie courte (doit être ~1600 ELO et non 2800 !)")

	print("\n>>> MODÈLE D'ESTIMATION ELO ET PRÉCISION CAPS2 VALIDÉ À 100%% AVEC SUCCÈS ! <<<")
	quit(0)
