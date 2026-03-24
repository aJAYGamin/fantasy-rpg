class_name HeroCard
extends Control

## HeroCard.gd
## Shows hero HP, MP, resonance meter, and status effects in battle

@onready var name_label       = $VBox/NameLabel
@onready var hp_bar           = $VBox/HPRow/HPBar
@onready var hp_label         = $VBox/HPRow/HPLabel
@onready var mp_bar           = $VBox/MPRow/MPBar
@onready var mp_label         = $VBox/MPRow/MPLabel
@onready var resonance_bar    = $VBox/ResonanceRow/ResonanceBar
@onready var resonance_label  = $VBox/ResonanceRow/ResonanceLabel
@onready var ultimate_icon    = $VBox/UltimateIcon
@onready var status_row       = $VBox/StatusRow

var hero: Character
var resonance_system: ResonanceSystem

func setup(h: Character, res_system: ResonanceSystem):
	hero = h
	resonance_system = res_system
	name_label.text = hero.character_name
	_update_display()

	# Connect resonance updates
	if resonance_system:
		resonance_system.resonance_changed.connect(_on_resonance_changed)
		resonance_system.resonance_full.connect(_on_resonance_full)

func _update_display():
	if hero == null:
		return

	# HP
	hp_bar.max_value = hero.max_hp()
	hp_bar.value = hero.current_hp
	hp_label.text = "%d/%d" % [hero.current_hp, hero.max_hp()]

	# Color HP bar
	var hp_pct = float(hero.current_hp) / float(hero.max_hp())
	if hp_pct > 0.5:
		hp_bar.modulate = Color(0.2, 0.9, 0.3)
	elif hp_pct > 0.25:
		hp_bar.modulate = Color(1.0, 0.65, 0.1)
	else:
		hp_bar.modulate = Color(1.0, 0.2, 0.2)

	# MP
	mp_bar.max_value = hero.max_mp()
	mp_bar.value = hero.current_mp
	mp_label.text = "%d/%d" % [hero.current_mp, hero.max_mp()]

	# Resonance
	if resonance_system:
		var res_pct = resonance_system.get_resonance_percent(hero)
		resonance_bar.value = res_pct * 100
		var is_full = resonance_system.is_full(hero)
		ultimate_icon.visible = is_full
		resonance_bar.modulate = Color(0.78, 0.5, 1.0) if not is_full else Color(1.0, 0.85, 1.0)

	# Status effects
	_update_status_icons()

func _on_resonance_changed(character: Character, _value: float):
	if character == hero:
		_update_display()

func _on_resonance_full(character: Character):
	if character == hero:
		# Flash the resonance bar to alert the player
		var tween = create_tween()
		tween.set_loops(3)
		tween.tween_property(resonance_bar, "modulate", Color(1.0, 1.0, 1.0), 0.2)
		tween.tween_property(resonance_bar, "modulate", Color(0.78, 0.5, 1.0), 0.2)

func _update_status_icons():
	for child in status_row.get_children():
		child.queue_free()

	if hero.status_effects.is_empty():
		status_row.hide()
		return

	status_row.show()
	for effect in hero.status_effects:
		var icon = Label.new()
		icon.add_theme_font_size_override("font_size", 12)
		icon.text = _get_status_icon(effect)
		icon.tooltip_text = effect.capitalize()
		status_row.add_child(icon)

func _get_status_icon(effect: String) -> String:
	match effect:
		"poison":     return "☠"
		"burn":       return "🔥"
		"freeze":     return "❄"
		"stun":       return "⚡"
		"regenerate": return "💚"
		"defending":  return "🛡"
		_:            return "?"

func refresh():
	_update_display()
