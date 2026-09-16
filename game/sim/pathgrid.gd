class_name PathGrid
extends RefCounted
## Grid pathfinding over the map (AStarGrid2D). Cells are CELL metres.
## Buildings and map obstacles mark cells solid; units steer around each other.

const CELL := 2.0

var size := 200
var astar := AStarGrid2D.new()
var solid_count := PackedInt32Array()   # how many blockers on each cell
var dirty := false

func setup(map_size_m: float) -> void:
	size = int(ceil(map_size_m / CELL))
	astar.region = Rect2i(0, 0, size, size)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL * 0.5, CELL * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.jumping_enabled = true
	astar.update()
	solid_count.resize(size * size)
	solid_count.fill(0)

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / CELL)), 0, size - 1), clampi(int(floor(p.y / CELL)), 0, size - 1))

func center_of(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size

func is_solid(c: Vector2i) -> bool:
	if not in_bounds(c):
		return true
	return solid_count[c.y * size + c.x] > 0

func is_solid_pos(p: Vector2) -> bool:
	return is_solid(cell_of(p))

func set_cells(cells: Array[Vector2i], solid: bool) -> void:
	for c in cells:
		if not in_bounds(c):
			continue
		var i := c.y * size + c.x
		solid_count[i] = maxi(0, solid_count[i] + (1 if solid else -1))
		astar.set_point_solid(c, solid_count[i] > 0)
	dirty = true

func flush() -> void:
	if dirty:
		astar.update()
		dirty = false

## Cells covered by a footprint (w,h in cells) centred at world position p.
static func footprint_cells(p: Vector2, fp: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var origin := Vector2i(int(round(p.x / CELL - fp.x * 0.5)), int(round(p.y / CELL - fp.y * 0.5)))
	for y in range(fp.y):
		for x in range(fp.x):
			out.append(origin + Vector2i(x, y))
	return out

## Snap a footprint centre so the footprint aligns to the grid.
static func snap_center(p: Vector2, fp: Vector2i) -> Vector2:
	var origin := Vector2i(int(round(p.x / CELL - fp.x * 0.5)), int(round(p.y / CELL - fp.y * 0.5)))
	return Vector2((origin.x + fp.x * 0.5) * CELL, (origin.y + fp.y * 0.5) * CELL)

func footprint_free(p: Vector2, fp: Vector2i, margin := 0) -> bool:
	var cells := footprint_cells(p, fp)
	for c in cells:
		for dy in range(-margin, margin + 1):
			for dx in range(-margin, margin + 1):
				var cc := c + Vector2i(dx, dy)
				if not in_bounds(cc) or is_solid(cc):
					return false
	return true

## Nearest non-solid cell to c (spiral search).
func nearest_free(c: Vector2i, max_r := 12) -> Vector2i:
	if not is_solid(c):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := 1e9
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cc := c + Vector2i(dx, dy)
				if in_bounds(cc) and not is_solid(cc):
					var d := float(dx * dx + dy * dy)
					if d < best_d:
						best_d = d
						best = cc
		if best.x >= 0:
			return best
	return c

## Nearest free cell around a footprint (for units that need to reach a building).
func approach_cell(from: Vector2, center: Vector2, fp: Vector2i) -> Vector2i:
	var cells := footprint_cells(center, fp)
	var minx := 1e9
	var miny := 1e9
	var maxx := -1e9
	var maxy := -1e9
	for c in cells:
		minx = minf(minx, c.x)
		miny = minf(miny, c.y)
		maxx = maxf(maxx, c.x)
		maxy = maxf(maxy, c.y)
	var best := Vector2i(-1, -1)
	var best_d := 1e18
	for y in range(int(miny) - 1, int(maxy) + 2):
		for x in range(int(minx) - 1, int(maxx) + 2):
			var c := Vector2i(x, y)
			if x > minx - 1 and x < maxx + 1 and y > miny - 1 and y < maxy + 1:
				continue
			if not in_bounds(c) or is_solid(c):
				continue
			var d := center_of(c).distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = c
	if best.x < 0:
		return nearest_free(cell_of(center))
	return best

## Path in world coordinates (waypoints). Empty if unreachable.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	flush()
	var a := cell_of(from)
	var b := cell_of(to)
	if is_solid(a):
		a = nearest_free(a)
	if is_solid(b):
		b = nearest_free(b)
	var ids := astar.get_id_path(a, b, true)
	var out := PackedVector2Array()
	if ids.size() <= 1:
		if ids.size() == 1:
			out.append(center_of(ids[0]))
		return out
	# string-pull: drop waypoints that are reachable in a straight line
	var pts: Array[Vector2i] = []
	for c in ids:
		pts.append(c)
	var i := 0
	out.append(from)
	while i < pts.size() - 1:
		var j := pts.size() - 1
		var found := false
		while j > i + 1:
			if line_free(pts[i], pts[j]):
				found = true
				break
			j -= 1
		if not found:
			j = i + 1
		out.append(center_of(pts[j]))
		i = j
	# final waypoint is the exact destination when its cell is free
	if not is_solid(cell_of(to)):
		out[out.size() - 1] = to
	return out

## Bresenham line check between cells; true if no solid cell touched.
func line_free(a: Vector2i, b: Vector2i) -> bool:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var c := a
	var guard := 0
	while guard < 1000:
		guard += 1
		if is_solid(c):
			return false
		if c == b:
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			c.x += sx
		if e2 <= dx:
			err += dx
			c.y += sy
	return false
