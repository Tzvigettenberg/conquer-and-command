class_name MenuTheme
extends RefCounted
## Zero Hour-flavoured look for the front end: gunmetal panels with a thin
## brass edge, amber titles, chunky bevelled buttons that glow on hover.

const STEEL := Color(0.09, 0.1, 0.12, 0.94)
const STEEL_LIGHT := Color(0.16, 0.18, 0.21, 1.0)
const STEEL_DARK := Color(0.05, 0.06, 0.07, 1.0)
const BRASS := Color(0.78, 0.6, 0.25)
const BRASS_DIM := Color(0.45, 0.36, 0.18)
const AMBER := Color(1.0, 0.78, 0.35)
const TEXT := Color(0.88, 0.87, 0.8)
const TEXT_DIM := Color(0.62, 0.62, 0.58)

static func panel_style(bg := STEEL, border := BRASS_DIM, margin := 14.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.border_width_top = 3
	s.set_corner_radius_all(2)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 10
	return s

static func button_style(bg: Color, border: Color, pressed := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = 1 if pressed else 2
	s.border_width_bottom = 2 if pressed else 1
	s.border_width_left = 1
	s.border_width_right = 1
	s.set_corner_radius_all(2)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	s.skew = Vector2(0.12, 0.0)   # the angled Generals button cut
	return s

static func field_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = STEEL_DARK
	s.border_color = BRASS_DIM
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s

static func build() -> Theme:
	var t := Theme.new()
	# buttons
	t.set_stylebox("normal", "Button", button_style(STEEL_LIGHT, BRASS_DIM))
	t.set_stylebox("hover", "Button", button_style(Color(0.24, 0.24, 0.24), BRASS))
	t.set_stylebox("pressed", "Button", button_style(Color(0.12, 0.12, 0.13), BRASS, true))
	t.set_stylebox("disabled", "Button", button_style(Color(0.1, 0.1, 0.11), Color(0.25, 0.25, 0.25)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", AMBER)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.42))
	t.set_font_size("font_size", "Button", 15)
	# option buttons / dropdowns
	for cls in ["OptionButton", "CheckButton", "MenuButton"]:
		t.set_stylebox("normal", cls, button_style(STEEL_LIGHT, BRASS_DIM))
		t.set_stylebox("hover", cls, button_style(Color(0.24, 0.24, 0.24), BRASS))
		t.set_stylebox("pressed", cls, button_style(Color(0.12, 0.12, 0.13), BRASS, true))
		t.set_stylebox("disabled", cls, button_style(Color(0.1, 0.1, 0.11), Color(0.25, 0.25, 0.25)))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, AMBER)
		t.set_font_size("font_size", cls, 14)
	var pop := panel_style(Color(0.08, 0.09, 0.1, 0.98), BRASS_DIM, 4.0)
	pop.shadow_size = 6
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", button_style(Color(0.25, 0.22, 0.14), BRASS))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", AMBER)
	# text fields
	t.set_stylebox("normal", "LineEdit", field_style())
	var focus := field_style()
	focus.border_color = BRASS
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", AMBER)
	# labels
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 14)
	# panels
	t.set_stylebox("panel", "PanelContainer", panel_style())
	return t

## Big amber headline in the Generals style (with a brass rule under it).
static func headline(text: String, size := 40) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", AMBER)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var rule := ColorRect.new()
	rule.color = BRASS
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	return v

## Section header: small brass caps text with a rule, like the "GAME SETUP" bars.
static func section(text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", BRASS)
	h.add_child(l)
	var rule := ColorRect.new()
	rule.color = BRASS_DIM
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rule)
	return h
