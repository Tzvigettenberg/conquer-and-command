class_name Cursors
extends RefCounted
## Procedurally drawn mouse cursors (32x32) so the pointer shows what you have
## "equipped": attack crosshair, guard shield, build, beacon, capture flag,
## rally, general's power star, superweapon reticle.

static var cache: Dictionary = {}

static func apply(kind: String) -> void:
	if kind == "" or kind == "arrow":
		Input.set_custom_mouse_cursor(null)
		return
	var tex := get_tex(kind)
	if tex == null:
		Input.set_custom_mouse_cursor(null)
		return
	var hot := Vector2(16, 16)
	if kind == "build":
		hot = Vector2(4, 4)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, hot)

static func get_tex(kind: String) -> ImageTexture:
	if cache.has(kind):
		return cache[kind]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"attack":
			_crosshair(img, Color(1.0, 0.25, 0.2))
		"force":
			_crosshair(img, Color(1.0, 0.6, 0.1))
			_line(img, Vector2(6, 6), Vector2(26, 26), Color(1.0, 0.6, 0.1))
		"guard":
			_shield(img, Color(0.4, 0.85, 1.0))
		"build":
			_build(img, Color(1.0, 0.85, 0.3))
		"beacon":
			_circle(img, Vector2(16, 16), 11, Color(0.4, 0.9, 1.0), 2)
			_circle(img, Vector2(16, 16), 4, Color(0.4, 0.9, 1.0), 2)
		"capture", "rally":
			_flag(img, Color(1.0, 0.5, 0.9) if kind == "capture" else Color(0.5, 1.0, 0.5))
		"power":
			_star(img, Color(1.0, 0.85, 0.2))
		"sw":
			_crosshair(img, Color(0.6, 0.9, 1.0))
			_circle(img, Vector2(16, 16), 14, Color(0.6, 0.9, 1.0), 2)
		"amove":
			_crosshair(img, Color(1.0, 0.5, 0.3))
			_line(img, Vector2(16, 2), Vector2(16, 8), Color(1.0, 0.5, 0.3))
		"repair":
			_build(img, Color(0.5, 1.0, 0.5))
		_:
			return null
	_outline(img)
	var t := ImageTexture.create_from_image(img)
	cache[kind] = t
	return t

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)

static func _line(img: Image, a: Vector2, b: Vector2, c: Color, w := 2) -> void:
	var n := int(a.distance_to(b)) + 1
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		for dy in range(w):
			for dx in range(w):
				_px(img, int(p.x) + dx, int(p.y) + dy, c)

static func _circle(img: Image, c: Vector2, r: int, col: Color, w := 2) -> void:
	for y in range(32):
		for x in range(32):
			var d := Vector2(x, y).distance_to(c)
			if d >= r - w * 0.5 and d <= r + w * 0.5:
				_px(img, x, y, col)

static func _crosshair(img: Image, col: Color) -> void:
	_circle(img, Vector2(16, 16), 9, col, 2)
	_line(img, Vector2(16, 3), Vector2(16, 9), col)
	_line(img, Vector2(16, 23), Vector2(16, 29), col)
	_line(img, Vector2(3, 16), Vector2(9, 16), col)
	_line(img, Vector2(23, 16), Vector2(29, 16), col)
	_px(img, 16, 16, col)
	_px(img, 17, 16, col)
	_px(img, 16, 17, col)
	_px(img, 17, 17, col)

static func _shield(img: Image, col: Color) -> void:
	for y in range(4, 29):
		var t := float(y - 4) / 24.0
		var half := 10.0 if t < 0.45 else 10.0 * (1.0 - (t - 0.45) / 0.55)
		for x in range(32):
			var dx := absf(x - 16.0)
			if dx <= half:
				var edge := dx > half - 2.0 or y < 6 or (t > 0.45 and dx > half - 2.5)
				_px(img, x, y, col if edge else Color(col.r, col.g, col.b, 0.35))
	_line(img, Vector2(12, 14), Vector2(15, 18), Color(1, 1, 1), 2)
	_line(img, Vector2(15, 18), Vector2(21, 10), Color(1, 1, 1), 2)

static func _build(img: Image, col: Color) -> void:
	# small square footprint + arrow pointer
	for y in range(14, 30):
		for x in range(14, 30):
			var edge := x < 16 or x > 27 or y < 16 or y > 27
			_px(img, x, y, col if edge else Color(col.r, col.g, col.b, 0.3))
	_line(img, Vector2(3, 3), Vector2(12, 12), Color(1, 1, 1), 2)
	_line(img, Vector2(3, 3), Vector2(10, 4), Color(1, 1, 1), 2)
	_line(img, Vector2(3, 3), Vector2(4, 10), Color(1, 1, 1), 2)

static func _flag(img: Image, col: Color) -> void:
	_line(img, Vector2(10, 4), Vector2(10, 28), Color(0.95, 0.95, 0.95), 2)
	for y in range(5, 15):
		for x in range(12, 26 - (y - 5) / 2):
			_px(img, x, y, col)

static func _star(img: Image, col: Color) -> void:
	for y in range(32):
		for x in range(32):
			var v := Vector2(x - 16, y - 16)
			var ang := atan2(v.y, v.x)
			var rad := v.length()
			var star := 7.0 + 6.0 * cos(5.0 * ang + PI * 0.5)
			if rad <= star:
				_px(img, x, y, col)

## Dark outline so the cursor reads on any background.
static func _outline(img: Image) -> void:
	var src := img.duplicate()
	for y in range(32):
		for x in range(32):
			if src.get_pixel(x, y).a > 0.1:
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < 32 and ny < 32 and src.get_pixel(nx, ny).a > 0.1:
						near = true
			if near:
				img.set_pixel(x, y, Color(0, 0, 0, 0.75))
