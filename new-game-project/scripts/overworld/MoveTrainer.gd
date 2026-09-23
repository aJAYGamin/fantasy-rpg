class_name MoveTrainer
extends NPC

## A town/city NPC who rearranges a character's moves as often as the player
## likes — the unrestricted counterpart to a campfire.
##
## Greets first, then opens the loadout screen when the dialogue closes, the
## same pattern Shopkeeper uses so talking to anyone feels consistent.

var _opening: bool = false

func _ready() -> void:
	prompt_text = "✦ Talk"
	super._ready()
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

func interact() -> void:
	_opening = true
	var greeting: Array[String] = []
	for line in lines:
		greeting.append(line)
	if greeting.is_empty():
		greeting.append("Your techniques are yours to arrange. Tell me what you'd carry.")
	DialogueManager.play_lines(npc_name, greeting)

func _on_dialogue_ended() -> void:
	# Only the trainer the player actually spoke to has _opening set, so other
	# trainers in the scene ignore this shared signal.
	if not _opening:
		return
	_opening = false
	_open_loadout()

func _open_loadout() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80
	var screen := LoadoutScreen.new()
	layer.add_child(screen)
	get_tree().current_scene.add_child(layer)
	screen.setup(LoadoutEditor.Mode.TRAINER)
	screen.closed.connect(func():
		if is_instance_valid(layer):
			layer.queue_free())
