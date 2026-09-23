class_name Campfire
extends NPC

## A small rest area. Reads "✦ Rest" when usable and "Cannot rest now" while on
## cooldown, so the player learns the rule from the world rather than from a
## menu. Interacting opens the campfire scene (RestScreen).
##
## Availability is global, not per-campfire: one rest, then five battles before
## the next. That means the prompt is honest wherever the player is standing.

func _ready() -> void:
	npc_name = ""                 # a campfire has no name tag, only a prompt
	prompt_text = "✦ Rest"
	super._ready()

func current_prompt() -> String:
	if GameManager.can_rest():
		return prompt_text
	return GameManager.rest_unavailable_text()

func interact() -> void:
	if not GameManager.can_rest():
		# Nothing opens; the floating prompt already says why, and a dialogue box
		# for a refusal would be more friction than information.
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	var screen := RestScreen.new()
	layer.add_child(screen)
	get_tree().current_scene.add_child(layer)
	screen.setup()
	screen.finished.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
		# The prompt flips to "Cannot rest now" the moment the rest is spent.
		_update_tags())
