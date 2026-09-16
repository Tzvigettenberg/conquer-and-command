class_name Vision
extends RefCounted
## Per-player visibility grid (server). FCELL metres per cell.

const FCELL := 4.0

var size := 100
var vis := PackedByteArray()      # 1 = visible this update
var reveals: Array = []           # [{pos, radius, until}] temporary reveals (spy satellite)

func setup(map_size_m: float) -> void:
	size = int(ceil(map_size_m / FCELL))
	vis.resize(size * size)
	vis.fill(0)

func clear() -> void:
	vis.fill(0)

func stamp(p: Vector2, radius: float) -> void:
	var cx := p.x / FCELL
	var cy := p.y / FCELL
	var r := radius / FCELL
	var x0 := maxi(0, int(floor(cx - r)))
	var x1 := mini(size - 1, int(ceil(cx + r)))
	var y0 := maxi(0, int(floor(cy - r)))
	var y1 := mini(size - 1, int(ceil(cy + r)))
	var r2 := r * r
	for y in range(y0, y1 + 1):
		var dy := (y + 0.5) - cy
		for x in range(x0, x1 + 1):
			var dx := (x + 0.5) - cx
			if dx * dx + dy * dy <= r2:
				vis[y * size + x] = 1

func visible(p: Vector2) -> bool:
	var x := clampi(int(p.x / FCELL), 0, size - 1)
	var y := clampi(int(p.y / FCELL), 0, size - 1)
	return vis[y * size + x] == 1

## Bit-pack for network (8 cells per byte).
func packed() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize((size * size + 7) / 8)
	out.fill(0)
	for i in range(size * size):
		if vis[i] == 1:
			out[i >> 3] = out[i >> 3] | (1 << (i & 7))
	return out
