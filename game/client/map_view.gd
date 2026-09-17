class_name MapView
extends Node3D
## Terrain, map props, lighting and the fog-of-war overlay.

const TERRAIN_SHADER := """
shader_type spatial;
uniform float map_size = 400.0;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D road_tex : filter_linear;
uniform sampler2D fog_tex : filter_linear;
uniform vec3 col_a = vec3(0.42, 0.36, 0.25);
uniform vec3 col_b = vec3(0.30, 0.25, 0.17);
uniform vec3 col_c = vec3(0.36, 0.36, 0.24);
uniform vec3 road_col = vec3(0.30, 0.26, 0.20);
uniform int use_vcol = 0;
uniform int fog_on = 1;
varying vec4 vcol;
void vertex() {
	vcol = COLOR;
}
void fragment() {
	vec2 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 uv = wp / map_size;
	float n1 = texture(noise_tex, wp * 0.004).r;
	float n2 = texture(noise_tex, wp * 0.05).r;
	float n3 = texture(noise_tex, wp * 0.25).r;
	vec3 col = mix(col_a, col_b, smoothstep(0.35, 0.7, n1));
	col = mix(col, col_c, smoothstep(0.55, 0.9, n2) * 0.3);
	col *= 0.85 + 0.25 * n3;
	float road = texture(road_tex, uv).r;
	col = mix(col, road_col, road * 0.85);
	if (use_vcol == 1) {
		// vertex colour = rock / snow tint, alpha = how much of it shows (0 on flat ground)
		vec3 rock = vcol.rgb * (0.8 + 0.35 * n2) * (0.9 + 0.2 * n3);
		col = mix(col, rock, vcol.a);
	}
	// fog of war, all in the ground shader (no floating planes): unexplored = black,
	// explored-but-not-visible = dimmed; hills get it too
	vec2 f = texture(fog_tex, uv).rg;
	float dim = (1.0 - smoothstep(0.2, 0.7, f.r)) * 0.3;
	float shroud = 1.0 - smoothstep(0.15, 0.6, f.g);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { shroud = 1.0; }
	if (fog_on == 0) { dim = 0.0; shroud = 0.0; }
	col = mix(col, vec3(0.02, 0.02, 0.05), dim);
	col = mix(col, vec3(0.0), shroud);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
"""

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D fog_tex : filter_linear;
uniform float map_size = 400.0;
uniform int mode = 0; // 0 = shroud (unexplored -> black), 1 = fog dim (explored, not visible)
void fragment() {
	vec2 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 uv = wp / map_size;
	vec2 f = texture(fog_tex, uv).rg; // r = visible, g = explored
	float a = 0.0;
	if (mode == 0) {
		a = 1.0 - smoothstep(0.15, 0.6, f.g);
		ALBEDO = vec3(0.0);
	} else {
		a = (1.0 - smoothstep(0.2, 0.7, f.r)) * 0.42;
		ALBEDO = vec3(0.02, 0.02, 0.05);
	}
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { a = 1.0; ALBEDO = vec3(0.0); }
	ALPHA = a;
}
"""

var map: Dictionary
var size := 400.0
var fog_img: Image
var fog_tex: ImageTexture
var fog_cells := 100
var explored := PackedByteArray()
var visible_cells := PackedByteArray()
var shroud_plane: MeshInstance3D
var dim_plane: MeshInstance3D
var road_img: Image
var terrain_mat: ShaderMaterial = null
var terrain_mesh: MeshInstance3D = null
var heights := PackedFloat32Array()

func setup(m: Dictionary) -> void:
	map = m
	size = float(m["size"])
	_build_lighting()
	_build_terrain()
	_build_props()
	_build_fog()

func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.3, 0.5, 0.8)
	mat.sky_horizon_color = Color(0.7, 0.72, 0.7)
	mat.ground_bottom_color = Color(0.3, 0.27, 0.22)
	mat.ground_horizon_color = Color(0.5, 0.47, 0.42)
	if map.get("theme", "desert") == "snow":
		mat.sky_top_color = Color(0.45, 0.55, 0.7)
		mat.sky_horizon_color = Color(0.8, 0.82, 0.85)
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.8
	e.ssao_enabled = false
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

func _noise_texture() -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.seed = 3
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	nt.noise = fn
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	return nt

func _terrain_material() -> ShaderMaterial:
	if terrain_mat != null:
		return terrain_mat
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("map_size", size)
	mat.set_shader_parameter("noise_tex", _noise_texture())
	var theme: String = map.get("theme", "desert")
	match theme:
		"snow":
			mat.set_shader_parameter("col_a", Vector3(0.52, 0.56, 0.63))
			mat.set_shader_parameter("col_b", Vector3(0.36, 0.41, 0.49))
			mat.set_shader_parameter("col_c", Vector3(0.47, 0.49, 0.50))
			mat.set_shader_parameter("road_col", Vector3(0.40, 0.38, 0.36))
		"grass":
			mat.set_shader_parameter("col_a", Vector3(0.30, 0.42, 0.18))
			mat.set_shader_parameter("col_b", Vector3(0.20, 0.30, 0.13))
			mat.set_shader_parameter("col_c", Vector3(0.40, 0.40, 0.20))
			mat.set_shader_parameter("road_col", Vector3(0.36, 0.30, 0.22))
	# roads texture
	road_img = Image.create(256, 256, false, Image.FORMAT_R8)
	road_img.fill(Color.BLACK)
	for r in map.get("roads", []):
		_paint_road(r["a"], r["b"])
	mat.set_shader_parameter("road_tex", ImageTexture.create_from_image(road_img))
	terrain_mat = mat
	return mat

func _build_terrain() -> void:
	# flat ground that extends well past the map edge
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size + 800.0, size + 800.0)
	pm.subdivide_depth = 8
	pm.subdivide_width = 8
	mi.mesh = pm
	mi.position = Vector3(size * 0.5, -0.03, size * 0.5)
	mi.material_override = _terrain_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_build_heightmap()

## Raised terrain for the mountain ridges. Each "mountain" prop becomes a dome that
## stays inside its blocked footprint, so the slopes never reach walkable cells.
func _build_heightmap() -> void:
	var res := 2.0
	var n := int(ceil(size / res))
	var w := n + 1
	heights = PackedFloat32Array()
	heights.resize(w * w)
	heights.fill(0.0)
	var peak := 0.0
	var fn := FastNoiseLite.new()
	fn.seed = 11
	fn.frequency = 0.08
	fn.fractal_octaves = 3
	# ridges: capsules with a flat-ish top; the slope ends 0.5 m inside the blocked band
	for rd in map.get("ridges", []):
		var a: Vector2 = rd["a"]
		var b: Vector2 = rd["b"]
		var wd: float = float(rd["w"])
		var h: float = float(rd.get("h", 16.0))
		peak = maxf(peak, h)
		var x0 := maxi(int((minf(a.x, b.x) - wd) / res) - 1, 0)
		var x1 := mini(int((maxf(a.x, b.x) + wd) / res) + 2, n)
		var y0 := maxi(int((minf(a.y, b.y) - wd) / res) - 1, 0)
		var y1 := mini(int((maxf(a.y, b.y) + wd) / res) + 2, n)
		var seed_off := float(rd.get("seed", 0)) * 7.3
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(x * res, y * res)
				# wobble the edge so the ridge isn't a perfect sausage
				var wob := 1.0 + 0.3 * fn.get_noise_2d(p.x * 0.5 + seed_off, p.y * 0.5)
				var d := PathGrid.seg_dist(p, a, b) / (wd * wob)
				if d >= 1.0:
					continue
				var hv := h * (1.0 - pow(d, 2.2)) * (0.75 + 0.25 * (1.0 - d))
				# height varies along the ridge (peaks and saddles)
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
				hv *= 0.62 + 0.38 * (0.5 + 0.5 * sin(t * ab.length() * 0.3 + seed_off)) + 0.15 * fn.get_noise_2d(p.x * 0.15 + seed_off, p.y * 0.15)
				var i := y * w + x
				if hv > heights[i]:
					heights[i] = hv
	# legacy blob mountains (older map dictionaries)
	for pr in map["props"]:
		if pr.get("kind", "") != "mountain":
			continue
		var fp: Vector2i = pr["fp"]
		var p: Vector2 = pr["p"]
		var origin := Vector2(round(p.x / PathGrid.CELL - fp.x * 0.5), round(p.y / PathGrid.CELL - fp.y * 0.5)) * PathGrid.CELL
		var c := origin + Vector2(fp) * PathGrid.CELL * 0.5
		var r := Vector2(fp) * PathGrid.CELL * 0.5 - Vector2(0.6, 0.6)
		var h: float = float(pr.get("h", 14.0))
		peak = maxf(peak, h)
		var x0 := maxi(int((c.x - r.x) / res), 0)
		var x1 := mini(int((c.x + r.x) / res) + 1, n)
		var y0 := maxi(int((c.y - r.y) / res), 0)
		var y1 := mini(int((c.y + r.y) / res) + 1, n)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var dx := (x * res - c.x) / r.x
				var dy := (y * res - c.y) / r.y
				var d2 := dx * dx + dy * dy
				if d2 >= 1.0:
					continue
				var hv := h * (1.0 - d2 * d2)
				var i := y * w + x
				if hv > heights[i]:
					heights[i] = hv
	if peak <= 0.0:
		return
	# rugged detail that fades out toward the foot of the slope
	for y in range(w):
		for x in range(w):
			var i := y * w + x
			if heights[i] > 0.0:
				var k := heights[i] / peak
				heights[i] += fn.get_noise_2d(x * res, y * res) * 3.5 * k + fn.get_noise_2d(x * res * 3.0, y * res * 3.0) * 1.0 * k
				heights[i] = maxf(heights[i], 0.0)
	var theme: String = map.get("theme", "desert")
	var rock := Color(0.36, 0.30, 0.24)
	var top := Color(0.46, 0.41, 0.35)
	match theme:
		"snow":
			rock = Color(0.26, 0.28, 0.34)
			top = Color(0.66, 0.70, 0.78)
		"grass":
			rock = Color(0.30, 0.27, 0.23)
			top = Color(0.40, 0.37, 0.33)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(w):
		for x in range(w):
			var i := y * w + x
			var hv := heights[i]
			var hl := heights[y * w + maxi(x - 1, 0)]
			var hr := heights[y * w + mini(x + 1, n)]
			var hu := heights[maxi(y - 1, 0) * w + x]
			var hd := heights[mini(y + 1, n) * w + x]
			var nrm := Vector3(hl - hr, 2.0 * res, hu - hd).normalized()
			var slope := 1.0 - nrm.y
			var blend := clampf((hv - 0.8) / 4.0, 0.0, 1.0) * clampf(slope * 6.0 + hv / 8.0, 0.0, 1.0)
			var col := rock.lerp(top, clampf((hv / peak - 0.45) * 2.2, 0.0, 1.0) * (1.0 - clampf(slope * 2.5, 0.0, 0.6)))
			st.set_color(Color(col.r, col.g, col.b, blend))
			st.set_normal(nrm)
			st.set_uv(Vector2(x * res, y * res))
			st.add_vertex(Vector3(x * res, hv, y * res))
	for y in range(n):
		for x in range(n):
			var a := y * w + x
			var b := a + 1
			var c := a + w
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := _terrain_material().duplicate() as ShaderMaterial
	mat.set_shader_parameter("use_vcol", 1)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	terrain_mesh = mi

## Terrain height at a world position (0 on flat ground).
func height_at(p: Vector2) -> float:
	if heights.is_empty():
		return 0.0
	var res := 2.0
	var n := int(ceil(size / res))
	var w := n + 1
	var x := clampi(int(p.x / res), 0, n)
	var y := clampi(int(p.y / res), 0, n)
	return heights[y * w + x]

func _paint_road(a: Vector2, b: Vector2) -> void:
	var steps := int(a.distance_to(b) / 1.5) + 1
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / steps)
		var px := int(p.x / size * 256.0)
		var py := int(p.y / size * 256.0)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := px + dx
				var y := py + dy
				if x >= 0 and y >= 0 and x < 256 and y < 256:
					var v := 1.0 - (Vector2(dx, dy).length() / 3.2)
					if v > road_img.get_pixel(x, y).r:
						road_img.set_pixel(x, y, Color(v, 0, 0))

var prop_nodes: Array = []   # [{node, p}] so props can hide under the shroud

func _build_props() -> void:
	for pr in map["props"]:
		if pr.get("kind", "") == "mountain" or pr.get("kind", "") == "civ":
			continue   # drawn as raised terrain / spawned as a garrisonable entity
		var n := Visuals.make_prop(pr["m"], pr["fp"], pr["yaw"], pr.get("kind", ""))
		var p: Vector2 = pr["p"]
		n.position = Vector3(p.x, 0, p.y)
		add_child(n)
		n.visible = false
		prop_nodes.append({"node": n, "p": p})

## Trees, rocks and ruins only show once the ground under them has been explored.
func _update_prop_visibility() -> void:
	for it in prop_nodes:
		var n: Node3D = it["node"]
		var ex := is_explored(it["p"])
		if n.visible != ex:
			n.visible = ex

func _build_fog() -> void:
	fog_cells = int(ceil(size / Vision.FCELL))
	explored.resize(fog_cells * fog_cells)
	explored.fill(0)
	visible_cells.resize(fog_cells * fog_cells)
	visible_cells.fill(0)
	fog_img = Image.create(fog_cells, fog_cells, false, Image.FORMAT_RG8)
	fog_img.fill(Color(0, 0, 0))
	fog_tex = ImageTexture.create_from_image(fog_img)
	_terrain_material().set_shader_parameter("fog_tex", fog_tex)
	if terrain_mesh:
		(terrain_mesh.material_override as ShaderMaterial).set_shader_parameter("fog_tex", fog_tex)

func _fog_plane(mode: int, height: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size + 800.0, size + 800.0)
	mi.mesh = pm
	mi.position = Vector3(size * 0.5, height, size * 0.5)
	var sh := Shader.new()
	sh.code = FOG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("fog_tex", fog_tex)
	mat.set_shader_parameter("map_size", size)
	mat.set_shader_parameter("mode", mode)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2000.0
	add_child(mi)
	return mi

## bits: 1 bit per cell, row-major, from the server.
func update_fog(bits: PackedByteArray) -> void:
	var n := fog_cells * fog_cells
	for i in range(n):
		var v := 1 if (bits[i >> 3] & (1 << (i & 7))) != 0 else 0
		visible_cells[i] = v
		if v == 1:
			explored[i] = 1
		var x := i % fog_cells
		var y := i / fog_cells
		fog_img.set_pixel(x, y, Color(float(v), float(explored[i]), 0.0))
	fog_tex.update(fog_img)
	_update_prop_visibility()

func fog_visible(p: Vector2) -> bool:
	var x := clampi(int(p.x / Vision.FCELL), 0, fog_cells - 1)
	var y := clampi(int(p.y / Vision.FCELL), 0, fog_cells - 1)
	return visible_cells[y * fog_cells + x] == 1

func is_explored(p: Vector2) -> bool:
	var x := clampi(int(p.x / Vision.FCELL), 0, fog_cells - 1)
	var y := clampi(int(p.y / Vision.FCELL), 0, fog_cells - 1)
	return explored[y * fog_cells + x] == 1

## Menu backdrop: no fog at all, not even outside the map.
func disable_fog() -> void:
	_terrain_material().set_shader_parameter("fog_on", 0)
	if terrain_mesh:
		(terrain_mesh.material_override as ShaderMaterial).set_shader_parameter("fog_on", 0)

func reveal_all() -> void:
	explored.fill(1)
	visible_cells.fill(1)
	fog_img.fill(Color(1, 1, 0))
	fog_tex.update(fog_img)
	_update_prop_visibility()
