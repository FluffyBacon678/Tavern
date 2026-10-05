class_name PawnWorkArt
extends RefCounted

## Cached presentation meshes only: no items, equipment, dice or job state.
static var _rod: Mesh
static var _marker: Mesh
static var _marker_material: StandardMaterial3D


static func rod(material: Material) -> MeshInstance3D:
	if _rod == null:
		var mb := MeshBuilder.new()
		var hand := Vector3(0.18, -0.065, 0.29)
		var tip := hand + Vector3(0, 0.70, 1.10)
		mb.add_limb(hand - Vector3(0, 0.10, 0.16), tip, 0.018, 0.006, 5, Color("957043"))
		mb.add_limb(hand - Vector3(0, 0.07, 0.11), hand + Vector3(0, 0.07, 0.11),
			0.024, 0.024, 5, Color("49372a"))
		mb.add_limb(tip, tip + Vector3(0, -0.82, 0.10), 0.0025, 0.0025, 3, Color("e2d8b7"))
		mb.add_blob(tip + Vector3(0, -0.80, 0.10), Vector3(0.015, 0.025, 0.015), 2, 5, Color("ae4b3c"))
		_rod = mb.commit()
	var mi := MeshInstance3D.new()
	mi.name = "WorkRod"
	mi.mesh = _rod
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func keeper_marker() -> MeshInstance3D:
	if _marker == null:
		var mb := MeshBuilder.new()
		for i in range(16):
			var a: float = TAU * float(i) / 16.0
			var b: float = a + TAU / 16.0 * 0.75
			var inner_a := Vector3(cos(a) * 0.24, 0.012, sin(a) * 0.24)
			var outer_a := Vector3(cos(a) * 0.28, 0.012, sin(a) * 0.28)
			var inner_b := Vector3(cos(b) * 0.24, 0.012, sin(b) * 0.24)
			var outer_b := Vector3(cos(b) * 0.28, 0.012, sin(b) * 0.28)
			mb.add_quad(inner_a, inner_b, outer_b, outer_a, TavernTheme.CANDLE)
		_marker = mb.commit()
		_marker_material = StandardMaterial3D.new()
		_marker_material.vertex_color_use_as_albedo = true
		_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.name = "KeeperMarker"
	mi.mesh = _marker
	mi.material_override = _marker_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
