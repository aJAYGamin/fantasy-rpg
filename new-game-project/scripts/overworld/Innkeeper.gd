class_name Innkeeper
extends NPC

## An NPC that offers a paid rest (full HP/MP for gold) through dialogue. Reuses the
## DialogueManager choice + event hooks: choosing "Rest" fires an "inn_rest" event.

var _offering: bool = false

func _ready() -> void:
	super._ready()
	DialogueManager.dialogue_event.connect(_on_inn_event)
	DialogueManager.dialogue_ended.connect(_on_inn_ended)

func interact() -> void:
	_offering = true
	var cost := GameManager.inn_rest_cost()
	if GameManager.can_afford(cost):
		DialogueManager.play([
			{"id": "offer", "speaker": npc_name,
				"text": "Care to rest? A room is %d gold — you'll wake fully restored." % cost,
				"choices": [
					{"label": "Rest (%d G)" % cost, "next": "rest"},
					{"label": "Maybe later.", "next": null},
				]},
			{"id": "rest", "speaker": npc_name, "text": "Sleep well, traveler.", "event": "inn_rest", "next": "done"},
			{"id": "done", "speaker": "", "text": "The party rests through the night and recovers fully.", "next": null},
		])
	else:
		DialogueManager.play_lines(npc_name, ["A room's %d gold, friend. Come back when your purse is heavier." % cost])

func _on_inn_event(event_name: String) -> void:
	if _offering and event_name == "inn_rest":
		GameManager.inn_rest()

func _on_inn_ended() -> void:
	_offering = false
