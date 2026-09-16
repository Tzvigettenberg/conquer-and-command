class_name MapView
extends Node3D
## Terrain, map props, lighting and the fog-of-war overlay.

const TERRAIN_SHADER := """
shader_type spatial;
uniform float map_size = 400.0;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform sampler2D road_tex : filter_linear;
void fragment() {
	vec2 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 uv = wp / map_size;
	float n1 = texture(noise_tex, wp * 0.004).r;
	float n2 = texture(noise_tex, wp * 0.05).r;
	float n3 = texture(noise_tex, wp * 0.25).r;
	vec3 sand = vec3(0.52, 0.45, 0.31);
	vec3 dark = vec3(0.38, 0.32, 0.22);
	vec3 dry = vec3(0.46, 0.45, 0.31);
	vec3 col = mix(sand, dark, smoothstep(0.35, 0.7, n1));
	col = mix(col, dry, smoothstep(0.55, 0.9, n2) * 0.25);
	col *= 0.88 + 0.2 * n3;
	float road = texture(road_tex, uv).r;
	col = mix(col, vec3(0.42, 0.36, 0.28), road * 0.85);
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
	mat.sky_top_color = Color(0.35, 0.55, 0.85)
	mat.sky_horizon_color = Color(0.8, 0.8, 0.75)
	mat.ground_bottom_color = Color(0.5, 0.45, 0.35)
	mat.ground_horizon_color = Color(0.75, 0.7, 0.6)
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = false
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.0
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

func _build_terrain() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size + 800.0, size + 800.0)
	pm.subdivide_depth = 8
	pm.subdivide_width = 8
	mi.mesh = pm
	mi.position = Vector3(size * 0.5, 0, size * 0.5)
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("map_size", size)
	mat.set_shader_parameter("noise_tex", _noise_texture())
	# roads texture
	road_img = Image.create(256, 256, false, Image.FORMAT_R8)
	road_img.fill(Color.BLACK)
	for r in map.get("roads", []):
		_paint_road(r["a"], r["b"])
	var rt := ImageTexture.create_from_image(road_img)
	mat.set_shader_parameter("road_tex", rt)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

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

func _build_props() -> void:
	for pr in map["props"]:
		var n := Visuals.make_prop(pr["m"], pr["fp"], pr["yaw"], pr.get("kind", ""))
		var p: Vector2 = pr["p"]
		n.position = Vector3(p.x, 0, p.y)
		add_child(n)

func _build_fog() -> void:
	fog_cells = int(ceil(size / Vision.FCELL))
	explored.resize(fog_cells * fog_cells)
	explored.fill(0)
	visible_cells.resize(fog_cells * fog_cells)
	visible_cells.fill(0)
	fog_img = Image.create(fog_cells, fog_cells, false, Image.FORMAT_RG8)
	fog_img.fill(Color(0, 0, 0))
	fog_tex = ImageTexture.create_from_image(fog_img)
	shroud_plane = _fog_plane(0, 27.0)
	dim_plane = _fog_plane(1, 0.2)

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

func fog_visible(p: Vector2) -> bool:
	var x := clampi(int(p.x / Vision.FCELL), 0, fog_cells - 1)
	var y := clampi(int(p.y / Vision.FCELL), 0, fog_cells - 1)
	return visible_cells[y * fog_cells + x] == 1

func is_explored(p: Vector2) -> bool:
	var x := clampi(int(p.x / Vision.FCELL), 0, fog_cells - 1)
	var y := clampi(int(p.y / Vision.FCELL), 0, fog_cells - 1)
	return explored[y * fog_cells + x] == 1

func reveal_all() -> void:
	explored.fill(1)
	visible_cells.fill(1)
	fog_img.fill(Color(1, 1, 0))
	fog_tex.update(fog_img)
