class_name ValueNoise
extends RefCounted

## Smoothed value noise + fBm, ported from the ForestFirewallpaper renderer.
##
## This is deliberately a hand-rolled port rather than Godot's built-in
## FastNoiseLite: the wallpaper's terrain thresholds (river bands, pond cutoff,
## biome multipliers) are tuned against *this* noise's exact distribution, and
## swapping in a different noise function would quietly change the look of every
## forest we generate.
##
## One intentional divergence from the JavaScript original: JS computes the hash
## with float64 multiplies that overflow 2^53 and silently lose precision before
## being truncated to int32. Here the same arithmetic runs as exact 32-bit
## integer math. The avalanche quality is equivalent-or-better and the visual
## result is statistically identical -- but individual cells will not match the
## wallpaper's output for a given seed. That is fine: the seed is randomised per
## run anyway, and nothing depends on cross-implementation cell parity.

const MASK32: int = 0xFFFFFFFF
const INV_24BIT: float = 1.0 / float(0xFFFFFF)


## Deterministic 32-bit hash of a grid coordinate, returned as 0.0 .. 1.0.
static func hash2(x: int, y: int, seed_value: int) -> float:
	var h: int = (
		((x * 374761393) & MASK32)
		^ ((y * 668265263) & MASK32)
		^ ((seed_value * 982451653) & MASK32)
	) & MASK32
	h = (h ^ (h >> 13)) & MASK32
	h = (h * 1274126177) & MASK32
	h = (h ^ (h >> 16)) & MASK32
	return float(h & 0xFFFFFF) * INV_24BIT


## Bilinearly interpolated value noise with smoothstep easing.
static func value_noise(x: float, y: float, seed_value: int) -> float:
	var ix: int = int(floor(x))
	var iy: int = int(floor(y))
	var fx: float = x - float(ix)
	var fy: float = y - float(iy)
	# smoothstep: 3t^2 - 2t^3
	var sx: float = fx * fx * (3.0 - 2.0 * fx)
	var sy: float = fy * fy * (3.0 - 2.0 * fy)

	var c00: float = hash2(ix, iy, seed_value)
	var c10: float = hash2(ix + 1, iy, seed_value)
	var c01: float = hash2(ix, iy + 1, seed_value)
	var c11: float = hash2(ix + 1, iy + 1, seed_value)

	var top: float = c00 + (c10 - c00) * sx
	var bot: float = c01 + (c11 - c01) * sx
	return top + (bot - top) * sy


## Fractal Brownian motion: octaves of value noise at doubling frequency and
## 0.55x falling amplitude, normalised back to 0.0 .. 1.0.
static func fbm(x: float, y: float, seed_value: int, octaves: int) -> float:
	var v: float = 0.0
	var amp: float = 1.0
	var freq: float = 1.0
	var total: float = 0.0
	for i in octaves:
		v += amp * value_noise(x * freq, y * freq, seed_value + i * 71)
		total += amp
		amp *= 0.55
		freq *= 2.0
	return v / total
