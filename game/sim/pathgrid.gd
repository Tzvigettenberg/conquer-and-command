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

## Cells covered by a footprint (w,h in cells) centred at world position p,
## rotated by yaw (radians). Axis-aligned footprints map exactly onto the grid;
## rotated ones block every cell whose centre falls inside the rotated rectangle
## (slightly inflated so edges are sealed).
static func footprint_cells(p: Vector2, fp: Vector2i, yaw := 0.0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if absf(wrapf(yaw, -PI, PI)) < 0.001:
		var origin := Vector2i(int(round(p.x / CELL - fp.x * 0.5)), int(round(p.y / CELL - fp.y * 0.5)))
		for y in range(fp.y):
			for x in range(fp.x):
				out.append(origin + Vector2i(x, y))
		return out
	var half := Vector2(fp) * CELL * 0.5
	var r := half.length() + CELL
	var c0 := Vector2i(int(floor((p.x - r) / CELL)), int(floor((p.y - r) / CELL)))
	var c1 := Vector2i(int(ceil((p.x + r) / CELL)), int(ceil((p.y + r) / CELL)))
	var cs := cos(-yaw)
	var sn := sin(-yaw)
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var d := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL) - p
			var lx := d.x * cs - d.y * sn
			var ly := d.x * sn + d.y * cs
			if absf(lx) <= half.x + 0.7 and absf(ly) <= half.y + 0.7:
				out.append(Vector2i(x, y))
	return out

## Snap a footprint centre so an unrotated footprint aligns to the grid.
static func snap_center(p: Vector2, fp: Vector2i, yaw := 0.0) -> Vector2:
	if absf(wrapf(yaw, -PI, PI)) >= 0.001:
		return Vector2(round(p.x), round(p.y))
	var origin := Vector2i(int(round(p.x / CELL - fp.x * 0.5)), int(round(p.y / CELL - fp.y * 0.5)))
	return Vector2((origin.x + fp.x * 0.5) * CELL, (origin.y + fp.y * 0.5) * CELL)

## Distance from a point to the edge of a (possibly rotated) footprint rectangle.
static func rect_dist(p: Vector2, center: Vector2, fp: Vector2i, yaw := 0.0) -> float:
	var half := Vector2(fp) * CELL * 0.5
	var d := p - center
	var cs := cos(-yaw)
	var sn := sin(-yaw)
	var lx := d.x * cs - d.y * sn
	var ly := d.x * sn + d.y * cs
	var dx := maxf(absf(lx) - half.x, 0.0)
	var dy := maxf(absf(ly) - half.y, 0.0)
	return sqrt(dx * dx + dy * dy)

func footprint_free(p: Vector2, fp: Vector2i, margin := 0, yaw := 0.0) -> bool:
	var cells := footprint_cells(p, fp, yaw)
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

## Nearest free cell adjacent to a set of footprint cells (for units that need to reach a building).
func approach_cell(from: Vector2, cells: Array[Vector2i]) -> Vector2i:
	var inside := {}
	for c in cells:
		inside[c] = true
	var best := Vector2i(-1, -1)
	var best_d := 1e18
	for c in cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cc := c + Vector2i(dx, dy)
				if inside.has(cc) or not in_bounds(cc) or is_solid(cc):
					continue
				var d := center_of(cc).distance_squared_to(from)
				if d < best_d:
					best_d = d
					best = cc
	if best.x < 0:
		if cells.is_empty():
			return cell_of(from)
		return nearest_free(cells[0])
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
