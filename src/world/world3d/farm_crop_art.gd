class_name FarmCropArt
extends RefCounted

## Original faceted crop silhouettes, shared by every bed of the same stage.
static var _cache: Dictionary = {}

static func mesh(crop: StringName, stage: int) -> Mesh:
	var key: String = "%s:%d" % [crop, stage]
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	if crop == &"hops" and stage >= 2:
		# A low string trellis makes hops readable beside the golden wheat.
		for x in [0.2, 0.8]:
			mb.add_cylinder(Vector3(x, 0, 0.5), 0.026, 0.02, 0.94, 5, Color("8c6540"))
		mb.add_limb(Vector3(0.16, 0.87, 0.5), Vector3(0.84, 0.87, 0.5), 0.021, 0.021, 4, Color("b29463"))
		for n in range(3):
			var x: float = 0.25 + n * 0.25
			mb.add_limb(Vector3(x, 0.02, 0.5), Vector3(x, 0.87, 0.5), 0.007, 0.007, 3, Color("c0b589"))
			for leaf in range(4 if stage == 3 else 3):
				var y: float = 0.18 + leaf * 0.16
				var side: float = -1.0 if leaf % 2 == 0 else 1.0
				mb.add_blob(Vector3(x + side * 0.065, y, 0.5), Vector3(0.115, 0.075, 0.11), 2, 5, Color("49733a").lightened(leaf * 0.06))
				if stage == 3:
					mb.add_blob(Vector3(x + side * 0.09, y - 0.065, 0.61), Vector3(0.043, 0.065, 0.043), 2, 5, Color("b0be59"))
	else:
		for row in range(3):
			for n in range(4):
				var x: float = 0.2 + row * 0.3
				var z: float = 0.14 + n * 0.235
				var tall: float = [0.0, 0.15, 0.38, 0.57][stage] * (0.90 + ((row + n) % 3) * 0.08)
				var stem: Color = Color("af9444") if stage == 3 else Color("59803a")
				var tip := Vector3(x + 0.018, tall, z)
				mb.add_limb(Vector3(x, 0, z), tip, 0.012, 0.006, 3, stem)
				for side in [-1.0, 1.0]:
					mb.add_tri(Vector3(x, tall * 0.22, z), Vector3(x + side * 0.09, tall * 0.65, z + 0.03), Vector3(x + side * 0.018, tall * 0.48, z - 0.02), stem.lightened(0.12))
				if stage >= 2:
					mb.add_blob(tip, Vector3(0.031, 0.087 if stage == 3 else 0.05, 0.035), 3, 4, Color("e6c878") if stage == 3 else Color("8ba34d"))
	var result: Mesh = mb.commit()
	_cache[key] = result
	return result
