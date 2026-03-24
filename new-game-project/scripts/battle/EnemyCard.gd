class_name EnemyCard
extends Control

## EnemyCard.gd
## Displays enemy info in battle: name, rarity gem, HP bar, status effects
## Attach to a Control node sized ~180x80

@onready var name_label      = $VBox/TopRow/NameLabel
@onready var rarity_gem      = $VBox/TopRow/RarityGem
@onready var hp_bar          = $VBox/HPBar
@onready var hp_label        = $VBox/HPLabel
@onready var status_row      = $VBox/StatusRow

var enemy: Enemy

func setup(e: Enemy):
	enemy = e
	_update_display()
	# Connect to take damage updates
	pass

func _update_display():
	if enemy == null:
		return

	# Name
	name_label.text = enemy.character_name

	# Rarity gem color
	rarity_gem.color = enemy.get_rarity_color()
	rarity_gem.tooltip_text = enemy.get_rarity_name()

	# HP bar
	hp_bar.max_value = enemy.max_hp()
	hp_bar.value = enemy.current_hp

	# HP numbers
	hp_label.text = "%d / %d" % [enemy.current_hp, enemy.max_hp()]

	# Color HP bar based on percentage
	var hp_percent = float(enemy.current_hp) / float(enemy.max_hp())
	var bar_style = hp_bar.get_theme_stylebox("fill").duplicate()
	if hp_percent > 0.5:
		bar_style.bg_color = Color(0.2, 0.8, 0.3)   # Green
	elif hp_percent > 0.25:
		bar_style.bg_color = Color(0.9, 0.6, 0.1)   # Orange
	else:
		bar_style.bg_color = Color(0.9, 0.2, 0.2)   # Red

	# Status effects — only show if any exist
	_update_status_icons()

func _update_status_icons():
	# Clear existing icons
	for child in status_row.get_children():
		child.queue_free()

	if enemy.status_effects.is_empty():
		status_row.hide()
		return

	status_row.show()
	for effect in enemy.status_effects:
		var icon = Label.new()
		icon.text = _get_status_icon(effect)
		icon.tooltip_text = effect.capitalize()
		icon.add_theme_font_size_override("font_size", 12)
		status_row.add_child(icon)

func _get_status_icon(effect: String) -> String:
	match effect:
		"poison":      return "☠"
		"burn":        return "🔥"
		"freeze":      return "❄"
		"stun":        return "⚡"
		"regenerate":  return "💚"
		"defending":   return "🛡"
		_:             return "?"

func refresh():
	_update_display()
