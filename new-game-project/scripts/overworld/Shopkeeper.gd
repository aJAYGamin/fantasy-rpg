class_name Shopkeeper
extends NPC

## An NPC that greets the player first, then opens a ShopScreen for its shop_id
## (ShopFactory) once the greeting dialogue closes.

@export var shop_id: String = "apothecary"

var _opening: bool = false

func _ready() -> void:
	super._ready()
	DialogueManager.dialogue_ended.connect(_on_shop_dialogue_ended)

func interact() -> void:
	if not ShopFactory.has_shop(shop_id):
		super.interact()   # no valid shop assigned → behave as a plain NPC
		return
	# Greet first; the shop opens once the greeting dialogue closes (see below).
	_opening = true
	var greeting: Array[String] = []
	for line in lines:
		greeting.append(line)
	if greeting.is_empty():
		greeting.append("Welcome! Take a look at my wares.")
	DialogueManager.play_lines(npc_name, greeting)

func _on_shop_dialogue_ended() -> void:
	# Only the keeper the player just spoke to has _opening set, so other keepers
	# in the scene ignore this shared signal.
	if not _opening:
		return
	_opening = false
	_open_shop()

func _open_shop() -> void:
	# The shop is a full-screen overlay that pauses the world; host it on its own
	# CanvasLayer so it draws above everything.
	var layer := CanvasLayer.new()
	layer.layer = 80
	var screen := ShopScreen.new()
	layer.add_child(screen)
	get_tree().current_scene.add_child(layer)
	screen.setup(shop_id)
	screen.closed.connect(func(): if is_instance_valid(layer): layer.queue_free())
