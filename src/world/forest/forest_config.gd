class_name ForestConfig
extends Resource

## Tunables for forest generation and presentation.
##
## Kept as a Resource rather than constants so the values can be authored in the
## inspector, varied per scene (a lush menu backdrop vs. a sparser in-game world
## map), and saved as .tres presets -- in line with the project rule that content
## is data, not code.
##
## Defaults match ForestFirewallpaper's shipped property values.

@export_group("Density")
## Chance a land cell becomes a tree, before biome modulation.
@export_range(0.0, 1.0, 0.01) var tree_density: float = 0.46
## Chance a non-tree land cell becomes grass, before biome modulation.
@export_range(0.0, 1.0, 0.01) var grass_density: float = 1.0
## Chance a remaining bare cell becomes a rock.
@export_range(0.0, 0.5, 0.01) var rock_density: float = 0.04

@export_group("Features")
@export var show_rivers: bool = true
@export var show_paths: bool = true
@export var show_rocks: bool = true

@export_group("Scale")
## World pixels per grid cell. Smaller means denser, finer detail and more cells.
@export_range(4, 32, 1) var cell_size: int = 10
## World size as a multiple of the viewport, giving the camera room to drift.
## 1.0 means the world exactly fills the screen and cannot pan.
@export_range(1.0, 3.0, 0.05) var world_scale: float = 1.5

@export_group("Noise frequencies")
@export var tree_biome_freq: float = 0.060
@export var grass_biome_freq: float = 0.045
@export var water_freq: float = 0.040
@export var river_freq: float = 0.030
@export var path_freq: float = 0.045

@export_group("Thresholds")
## Raise for less water, lower for more.
@export_range(0.5, 0.95, 0.01) var water_threshold: float = 0.74
## Rivers and paths are narrow *bands* of noise rather than thresholds, which is
## what makes them read as winding lines instead of blobs.
@export var river_band_low: float = 0.478
@export var river_band_high: float = 0.522
@export var path_band_low: float = 0.490
@export var path_band_high: float = 0.510

@export_group("Presentation")
## Pixels per second the camera drifts across the world.
@export_range(0.0, 40.0, 0.5) var drift_speed: float = 5.0
## Peak horizontal sway of a tree canopy, in pixels.
@export_range(0.0, 6.0, 0.1) var sway_amplitude: float = 1.6
@export_range(0.0, 2.0, 0.05) var sway_speed: float = 0.5
## Flat scrim over the whole scene. A procedural forest is busy everywhere at
## once, so foreground text needs something dark underneath it no matter where
## it lands. Raise for readability, lower to show off the forest.
@export_range(0.0, 1.0, 0.01) var scrim_darkness: float = 0.38
## Extra darkening toward the edges, on top of the scrim.
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.62
