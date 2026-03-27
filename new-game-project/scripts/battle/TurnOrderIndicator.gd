extends Control

## TurnOrderIndicator.gd
## Shows prev, current, next turns like a slot machine scrolling vertically
## Current turn is bright, prev/next are dimmed

const SLOT_HEIGHT = 70.0
const SLOT_WIDTH = 72.0
const SCROLL_DURATION = 0.35

const HERO_COLOR  = Color(0.25, 0.15, 0.50, 0.85)
const ENEMY_COLOR = Color(0.45, 0.08, 0.08, 0.85)
const BG_COLOR    = Color(0.05, 0.05, 0.08, 0.75)
const ACTIVE_BORDER   = Color(1.0, 0.85, 0.2, 1.0)
const INACTIVE_BORDER = Color(0.35, 0.30, 0.45, 0.7)

var _turn_order: Array[Character] = []
var _current_index: int = 0
var _party: Array[Character] = []
var _slot_container: Control
var _is_scrolling: bool = false

func _ready():
	custom_minimum_size = Vector2(SLOT_WIDTH + 4, SLOT_HEIGHT * 3 + 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Semi-transparent background panel
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Container that scrolls
	_slot_container = Control.new()
	_slot_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_container)

func setup(party: Array[Character], enemies: Array[Character]):
	_party = party
	_build_turn_order(party, enemies)
	_current_index = 0
	_rebuild_slots()

func _build_turn_order(party: Array[Character], enemies: Array[Character]):
	_turn_order.clear()
	for c in party:
		if c.is_alive(): _turn_order.append(c)
	for e in enemies:
		if e.is_alive(): _turn_order.append(e)
	_turn_order.sort_custom(func(a, b): return a.speed() > b.speed())

func _rebuild_slots():
	for child in _slot_container.get_children():
		child.queue_free()
	if _turn_order.is_empty():
		return

	var cinzel = load("res://fonts/Cinzel-Regular.ttf")
	# Build slots for prev, current, next (wrap around)
	var indices = [_get_wrapped(_current_index - 1),
				   _current_index,
				   _get_wrapped(_current_index + 1)]

	for i in range(3):
		var char_idx = indices[i]
		var character = _turn_order[char_idx]
		var slot = _create_slot(character, cinzel, i == 1)
		slot.position = Vector2(2, i * SLOT_HEIGHT + 4)
		_slot_container.add_child(slot)

func _create_slot(character: Character, cinzel, is_active: bool) -> Control:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_WIDTH, SLOT_HEIGHT - 4)

	# Style
	var style = StyleBoxFlat.new()
	var is_hero = _party.has(character)
	style.bg_color = HERO_COLOR if is_hero else ENEMY_COLOR
	style.border_color = ACTIVE_BORDER if is_active else INACTIVE_BORDER
	style.set_border_width_all(2 if is_active else 1)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)

	# Dim inactive slots
	slot.modulate.a = 1.0 if is_active else 0.45

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_child(vbox)

	# Portrait or colored placeholder
	var portrait_rect = TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(36, 36)
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if character.portrait != null:
		portrait_rect.texture = character.portrait
	else:
		# Colored placeholder square
		var placeholder = ColorRect.new()
		placeholder.custom_minimum_size = Vector2(36, 36)
		placeholder.color = Color(0.5, 0.3, 0.8) if _party.has(character) else Color(0.8, 0.2, 0.2)
		vbox.add_child(placeholder)

	if character.portrait != null:
		vbox.add_child(portrait_rect)

	# Name label
	var name_lbl = Label.new()
	name_lbl.text = _truncate(character.character_name)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 9)
	var name_color = Color(1.0, 0.9, 0.5) if is_active else Color(0.95, 0.90, 1.0)
	name_lbl.add_theme_color_override("font_color", name_color)
	if cinzel: name_lbl.add_theme_font_override("font", cinzel)
	vbox.add_child(name_lbl)

	return slot

func set_active(character: Character):
	var idx = _turn_order.find(character)
	if idx == -1:
		return
	if idx == _current_index:
		return
	_scroll_to(idx)

func _scroll_to(new_index: int):
	if _is_scrolling:
		return
	_is_scrolling = true
	var direction = 1 if new_index > _current_index else -1
	var slide_amount = -SLOT_HEIGHT * direction

	# Animate scroll
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUART)
	tween.tween_property(_slot_container, "position:y",
		_slot_container.position.y + slide_amount, SCROLL_DURATION)
	await tween.finished

	_current_index = new_index
	_slot_container.position.y = 0
	_rebuild_slots()
	_is_scrolling = false

func remove_character(character: Character):
	_turn_order.erase(character)
	if _current_index >= _turn_order.size():
		_current_index = 0
	_rebuild_slots()

func _get_wrapped(idx: int) -> int:
	if _turn_order.is_empty():
		return 0
	return ((idx % _turn_order.size()) + _turn_order.size()) % _turn_order.size()

func _truncate(name: String) -> String:
	return name.substr(0, 7) + "." if name.length() > 7 else name
