# Adult medieval character reference pass — 2026-10-03

The supplied character image is the visual target for this pass. Its UI and
combat statistics are not requirements. Original procedural geometry now gives
the ordinary keeper and modular staff a higher waist, smaller head, quieter
angular face, slimmer hands and taller boots. No external models or textures
were copied or imported.

![Actual Godot keeper and waiter](../.verification/reference_character_20261003/reference_three_quarter.png)

The comparison uses production `PawnMesh` geometry and local fixture dyes:
cream, burgundy, olive and brown. Both figures share the same body, skin and
hair. The right figure uses the real waiter role's cap and the existing house
waistcoat/waist apron. These colours do not overwrite the player's saved dyes.

## Shape and clothing

- Ordinary heads use a smaller baked scale, with smaller muted eyes, straight
  brows, a longer bridge with a flat nose tip, a narrow jaw and neutral lips.
- Compressing the garment's vertical span raises its belt and hem while
  keeping its neck at the existing shoulder. Apron bibs, waistbands, ties,
  jewellery and buttons move with the garment; luggage anchors remain fixed.
- A closed faceted hip section fills the space beneath the shorter tunic.
  It follows the torso, keeping the moving thighs covered at maximum stride.
- Arms are narrower and slightly longer. Four broad finger-edge sections
  replace eight tiny sections; the hand and bent thumb remain closed meshes.
- Boots have a taller calf and one broad cuff. Waist aprons extend farther down
  the thighs, matching the reference's practical tavern clothing.

The initial attempt extended each thigh above its hip pivot. A maximum-stride
side render exposed the ends through the tunic; that version was replaced by
the torso-owned hip section. Front, back and gait captures were inspected again.
Covered hair also received symmetric side/rear clearance after a rear render
exposed a scalp wedge beneath the waiter's cap. Hat geometry and triangle
counts remain unchanged by that correction.

![Actual maximum-stride clearance](../.verification/reference_character_20261003/reference_walking_side.png)

## Measured result

| Measurement | Result |
|---|---:|
| Bare ordinary fixture | 1,048 triangles |
| Waiter fixture | 1,060 triangles |
| Ordinary fixture belt / standing height | 57.6% |
| Waiter fixture waistband / standing height | 57.2% |
| Largest of 320 job uniforms | 1,096 triangles |
| Largest of 128 fully equipped staff travel kits | 1,364 triangles |
| Largest of 96 fully equipped keeper kits | 1,364 triangles |
| Largest original hat/cape/backpack keeper combination | 1,386 triangles |
| Existing 128 adventurer variants | 1,393 maximum, unchanged |

Each body remains one surface with six unit-scale bones, finite unit normals,
exact standing floor contact and the original carry anchor. The reference
fixture's visual height is 0.9888 world units (keeper) / 0.9929 (waiter). Its
reported head-part height includes neck, hair and headwear; it is not an
anatomical head-length measurement.

## Verification

The reference showcase, character smoke, wardrobe smoke and staff uniform smoke
pass. Windowed character/wardrobe checks retain actual Full body, Face and Hands
framing at 1280×720, 1024×768, 1440×900 and 2560×1080. Separate engine processes
restore exact appearance, equipment and rendered staff meshes. Existing gameplay,
polish and adventurer regressions pass.

The three-day house report matches the immediate pre-pass baseline in all 21
day, item and reconciliation lines: 3,743g final gold; bread 56, beer 76, water
37, fish 63 and wheat 72 produced. All 16 item differences remain zero.
The five real player-save files retain their pre-pass SHA256 hashes.

The reference harness initially failed its waistband measurement. Actual mesh
colour readback showed RGBA8 truncation: authored red 0.77999997 becomes
0.77647060 (198.9 → 198/255). It now permits one encoded colour step while
retaining the rear-torso filter, reports the matched vertices and fails visibly
if the waistband is absent. Geometry, framing and budget checks were retained.

Logs and screenshots are under `.verification/reference_character_20261003/`.
The showcase is development-only and starts an isolated test session. Its tray
and stools are clearly labelled pose fixtures; the two beer mugs use the real
item mesh library. Seated captures are static clearance diagnostics, because
the current six-part rig has no knee/elbow articulation or sitting animation.

```powershell
$godot = '../_tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --import
& $godot --path . res://dev/reference_character_showcase.tscn -- prefix=res://.verification/reference_character_20261003/reference
& $godot --path . res://dev/character_smoke.tscn
& $godot --path . res://dev/wardrobe_smoke.tscn
& $godot --headless --path . res://dev/staff_uniform_smoke.tscn
```

## Scope

UI, saved profile schema, clothing IDs/ownership, job behaviour, prices and
simulation randomness are unchanged. All current modular staff uniforms and
ordinary keeper outfits receive the new base. Older unmodified adventurer
armour/robe presets retain their existing bodies and faces; extending this
direction to those bespoke cuts is a subsequent art pass. Mobile hardware
performance and a fuller articulated animation rig remain unverified work.
