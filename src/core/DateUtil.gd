class_name DateUtil
extends RefCounted
## DateUtil.gd — normalisation et calcul de dates ISO robustes.
## Les dates PGN peuvent être « 2026.08.30 » ou inconnues (« 2026.??.?? ») : on les
## normalise en « AAAA-MM-JJ » et on n'appelle jamais l'API système avec une chaîne
## invalide (sinon Godot loggue « Invalid ISO 8601 date string »).

## Renvoie « AAAA-MM-JJ » si la date est exploitable, sinon "".
static func normalize(date_text: String) -> String:
	var d := date_text.strip_edges().replace(".", "-").replace("/", "-")
	if d.length() < 10:
		return ""
	var y := d.substr(0, 4)
	var mo := d.substr(5, 2)
	var da := d.substr(8, 2)
	if not (y.is_valid_int() and mo.is_valid_int() and da.is_valid_int()):
		return ""
	var year := int(y)
	var month := int(mo)
	var day := int(da)
	if year < 1 or month < 1 or month > 12 or day < 1 or day > 31:
		return ""
	return "%04d-%02d-%02d" % [year, month, day]

## Index de jour (jours depuis l'époque), ou -1 si la date est inexploitable.
static func day_index(date_text: String) -> int:
	var iso := normalize(date_text)
	if iso == "":
		return -1
	var unix := Time.get_unix_time_from_datetime_string(iso + "T00:00:00")
	if unix <= 0:
		return -1
	return int(unix / 86400.0)

## Ajoute `days` jours à une date ISO (renvoie l'entrée si inexploitable).
static func add_days(date_text: String, days: int) -> String:
	var idx := day_index(date_text)
	if idx < 0:
		return date_text
	return Time.get_date_string_from_unix_time(idx * 86400 + days * 86400)
