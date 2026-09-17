class_name RtsCamera
extends Node3D
## Generals-style camera: scroll-zoom, edge/arrow-key/right-drag scrolling, middle-drag rotate/tilt, Q/E or numpad 4/6 rotate, numpad 8/2 zoom, numpad 5 reset.

const PITCH_DEG := 54.0
const MIN_H := 34.0
const MAX_H := 150.0
const EDGE := 14

var cam: Camera3D
var height := 85.0
var yaw := 0.0
var pitch := PITCH_DEG
var map_size := 400.0
var target := Vector3.ZERO
var dragging := false
var drag_last := Vector2.ZERO
var enabled := true
var edge_scroll := true

func setup(size: float, start: Vector2) -> void:
	map_size = size
	target = Vector3(start.x, 0, start.y)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.near = 1.0
	cam.far = 1200.0
	add_child(cam)
	cam.current = true
	_apply()

func _apply() -> void:
	position = target
	rotation.y = yaw
	var back := height / tan(deg_to_rad(pitch))
	cam.position = Vector3(0, height, back)
	cam.rotation_degrees = Vector3(-pitch, 0, 0)

func _unhandled_input(ev: InputEvent) -> void:
	if not enabled:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			height = clampf(height * 0.88, MIN_H, MAX_H)
			_apply()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			height = clampf(height * 1.14, MIN_H, MAX_H)
			_apply()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
			drag_last = mb.position
	elif ev is InputEventMouseMotion and dragging:
		# middle-drag rotates the camera (Generals); right-drag scrolling is driven by the controller
		var mm := ev as InputEventMouseMotion
		var d := mm.position - drag_last
		drag_last = mm.position
		yaw -= d.x * 0.006
		pitch = clampf(pitch + d.y * 0.15, 38.0, 68.0)
		_apply()

## Scroll by a screen-space mouse delta (right-drag).
func pan_screen(d: Vector2) -> void:
	var k := height * 0.0016
	_pan(Vector2(-d.x, d.y) * k)

func reset_view() -> void:
	yaw = 0.0
	pitch = PITCH_DEG
	height = 85.0
	_apply()

func _pan(v: Vector2) -> void:
	var f := Vector3(sin(yaw), 0, cos(yaw))
	var r := Vector3(cos(yaw), 0, -sin(yaw))
	target += r * v.x - f * v.y
	target.x = clampf(target.x, 0.0, map_size)
	target.z = clampf(target.z, 0.0, map_size)
	_apply()

func _process(dt: float) -> void:
	if not enabled:
		return
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP):
		v.y += 1
	if Input.is_key_pressed(KEY_DOWN):
		v.y -= 1
	if Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if edge_scroll and get_window().has_focus():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		if mp.x >= 0 and mp.y >= 0 and mp.x <= vs.x and mp.y <= vs.y:
			if mp.x < EDGE:
				v.x -= 1
			elif mp.x > vs.x - EDGE:
				v.x += 1
			if mp.y < EDGE:
				v.y += 1
			elif mp.y > vs.y - EDGE:
				v.y -= 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_KP_4):
		yaw += dt * 1.5
		_apply()
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_KP_6):
		yaw -= dt * 1.5
		_apply()
	if Input.is_key_pressed(KEY_KP_8):
		height = clampf(height * (1.0 - dt * 1.2), MIN_H, MAX_H)
		_apply()
	if Input.is_key_pressed(KEY_KP_2):
		height = clampf(height * (1.0 + dt * 1.2), MIN_H, MAX_H)
		_apply()
	if Input.is_key_pressed(KEY_KP_5):
		reset_view()
	if v != Vector2.ZERO:
		_pan(v * dt * height * 0.9)

func jump_to(p: Vector2) -> void:
	target = Vector3(p.x, 0, p.y)
	_apply()

## Ground position under a screen point (plane y = 0).
func ground_at(screen: Vector2) -> Vector2:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return Vector2(-1, -1)
	return Vector2(hit.x, hit.z)

func to_screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p)

func is_behind(p: Vector3) -> bool:
	return cam.is_position_behind(p)

## Ground-space corners of the current view (for the minimap frustum).
func view_corners() -> PackedVector2Array:
	var vs := get_viewport().get_visible_rect().size
	var out := PackedVector2Array()
	for c in [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(0, vs.y)]:
		var g := ground_at(c)
		if g.x < 0:
			g = Vector2(target.x, target.z) + Vector2(0, -600)
		out.append(g)
	return out
