class_name QuestGiver
extends NPC

## An NPC that hands out (and later receives) a single quest. Talking branches on the
## quest's state:
##   • not yet accepted  → offer it with Accept / Decline choices
##   • active, not done   → a "still in progress" reminder
##   • active, objective met → a turn-in line that grants the reward
##   • already completed  → a brief thank-you
## Accept / turn-in fire through the dialogue "event" hook (see DialogueManager).

@export var quest_id: String = ""

var _talking: bool = false

func _ready() -> void:
	super._ready()
	DialogueManager.dialogue_event.connect(_on_dialogue_event)
	DialogueManager.dialogue_ended.connect(_on_giver_dialogue_ended)

func interact() -> void:
	# No valid quest assigned → behave like a normal chatter NPC.
	if quest_id == "" or not QuestFactory.has_quest(quest_id):
		super.interact()
		return
	_talking = true

	if GameManager.is_quest_done(quest_id):
		DialogueManager.play_lines(npc_name, ["Thank you again, friend. The town owes you a debt."])
		return

	if GameManager.quest_log.is_active(quest_id):
		if GameManager.can_turn_in_quest(quest_id):
			var q := GameManager.quest_log.get_side(quest_id)
			var received: String = q.reward_received_text() if q != null else ""
			var who: String = GameManager.party[0].character_name if not GameManager.party.is_empty() else "You"
			# The NPC gives the reward (node "1" fires the grant event); then a
			# no-speaker system line states what was received; then the NPC signs off.
			var nodes: Array = [
				{"id": "0", "speaker": npc_name, "text": "You did it! Thank you, truly.", "next": "1"},
				{"id": "1", "speaker": npc_name, "text": "Take this for your trouble — you've more than earned it.",
					"event": "quest_turn_in", "next": ("received" if received != "" else "bye")},
			]
			if received != "":
				nodes.append({"id": "received", "speaker": "", "text": "%s received %s." % [who, received], "next": "bye"})
			nodes.append({"id": "bye", "speaker": npc_name, "text": "The town is in your debt. Safe travels, friend.", "next": null})
			DialogueManager.play(nodes)
		else:
			DialogueManager.play_lines(npc_name, ["How goes the hunt? Come back to me once it's done."])
		return

	# Offer the quest.
	var q := QuestFactory.create(quest_id)
	DialogueManager.play([
		{"id": "offer", "speaker": npc_name, "text": q.description,
			"choices": [
				{"label": "I'll help.", "next": "accept"},
				{"label": "Not right now.", "next": "decline"},
			]},
		{"id": "accept", "speaker": npc_name, "text": "Bless you! Your task: %s." % q.objective, "event": "quest_accept", "next": null},
		{"id": "decline", "speaker": npc_name, "text": "I understand. Seek me out if you change your mind.", "next": null},
	])

func _on_dialogue_event(event_name: String) -> void:
	if not _talking:
		return   # only the giver currently in conversation reacts
	match event_name:
		"quest_accept":
			GameManager.accept_quest(quest_id)
		"quest_turn_in":
			GameManager.turn_in_quest(quest_id)

func _on_giver_dialogue_ended() -> void:
	_talking = false
