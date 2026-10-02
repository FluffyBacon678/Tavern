class_name SaveSlotDetails
extends RefCounted

static func kind(summary: Dictionary) -> String:
	var level: String = String(summary.get("level", ""))
	var def: LevelDef = LevelCatalog.get_level(StringName(level)) if not level.is_empty() else null
	return "Tutorial" if def != null and def.is_tutorial else ("Demo scenario" if not level.is_empty() else "Sandbox")

static func contents(summary: Dictionary) -> String:
	var completed: int = 0
	var blueprints: int = 0
	for row in summary.get("buildings", []):
		if row.get("built", false):
			completed += 1
		else:
			blueprints += 1
	var text: String = "%d built · %d stock piles · %d staff" % [completed,
		summary.get("items", []).size(), summary.get("pawns", []).size()]
	if blueprints > 0:
		text += " · %d blueprints" % blueprints
	return text
