class_name SaveSerializer
extends RefCounted

## Pure static (de)serialization between in-memory Resources and plain Dictionaries
## that can round-trip through JSON. Phase S1 — option 1B (full serialization)
## so any future Character/Skill mutation (equipment, learned skills, etc.) is
## already in the wire format.

# --- Skill ---
static func serialize_skill(s: Skill) -> Dictionary:
	return {
		"skill_name": s.skill_name,
		"description": s.description,
		"mp_cost": s.mp_cost,
		"skill_type": int(s.skill_type),
		"attack_type": int(s.attack_type),
		"status_type": int(s.status_type),
		"target_type": int(s.target_type),
		"power": s.power,
		"element": int(s.element),
		"secondary_element": int(s.secondary_element),
		"status_to_apply": s.status_to_apply,
		"status_chance": s.status_chance,
		"resonance_gain_override": s.resonance_gain_override,
	}

static func deserialize_skill(d: Dictionary) -> Skill:
	var s = Skill.new()
	s.skill_name = d.get("skill_name", "")
	s.description = d.get("description", "")
	s.mp_cost = int(d.get("mp_cost", 0))
	s.skill_type = int(d.get("skill_type", 0))
	s.attack_type = int(d.get("attack_type", 0))
	s.status_type = int(d.get("status_type", 0))
	s.target_type = int(d.get("target_type", 0))
	s.power = float(d.get("power", 1.0))
	s.element = int(d.get("element", 0))
	s.secondary_element = int(d.get("secondary_element", 0))
	s.status_to_apply = d.get("status_to_apply", "")
	s.status_chance = float(d.get("status_chance", 0.0))
	s.resonance_gain_override = float(d.get("resonance_gain_override", -1.0))
	return s

# --- Item ---
static func serialize_item(item: Item) -> Dictionary:
	return {
		"item_name": item.item_name,
		"description": item.description,
		"item_type": int(item.item_type),
		"target_type": int(item.target_type),
		"effect_value": item.effect_value,
		"effect_stat": item.effect_stat,
		"quantity": item.quantity,
	}

static func deserialize_item(d: Dictionary) -> Item:
	var i = Item.new()
	i.item_name = d.get("item_name", "")
	i.description = d.get("description", "")
	i.item_type = int(d.get("item_type", 0))
	i.target_type = int(d.get("target_type", 0))
	i.effect_value = int(d.get("effect_value", 0))
	i.effect_stat = d.get("effect_stat", "")
	i.quantity = int(d.get("quantity", 1))
	return i

# --- Inventory ---
static func serialize_inventory(inv: Inventory) -> Dictionary:
	var items_data: Array = []
	if inv != null:
		for item in inv.items:
			items_data.append(serialize_item(item))
	return {"items": items_data}

static func deserialize_inventory(d: Dictionary) -> Inventory:
	var inv = Inventory.new()
	var typed: Array[Item] = []
	for item_dict in d.get("items", []):
		typed.append(deserialize_item(item_dict))
	inv.items = typed
	return inv

# --- Character ---
static func serialize_character(c: Character) -> Dictionary:
	var skill_data: Array = []
	for skill in c.skills:
		skill_data.append(serialize_skill(skill))
	var status_data: Array = []
	for s in c.status_effects:
		status_data.append(s)
	var dict: Dictionary = {
		"character_name": c.character_name,
		"character_class": c.character_class,
		"base_hp": c.base_hp,
		"base_mp": c.base_mp,
		"base_attack": c.base_attack,
		"base_defense": c.base_defense,
		"base_magic": c.base_magic,
		"base_arcane": c.base_arcane,
		"base_speed": c.base_speed,
		"element": int(c.element),
		"secondary_element": int(c.secondary_element),
		"extra_weakness": int(c.extra_weakness),
		"extra_resistance": int(c.extra_resistance),
		"level": c.level,
		"current_hp": c.current_hp,
		"current_mp": c.current_mp,
		"resonance_meter": c.resonance_meter,
		"experience": c.experience,
		"experience_to_next": c.experience_to_next,
		"status_effects": status_data,
		"skills": skill_data,
		"inventory": serialize_inventory(c.inventory),
	}
	# Hero-specific meta (used by ResonanceMenu / StatsScreen)
	if c.has_meta("ultimate_name"):
		dict["ultimate_name"] = c.get_meta("ultimate_name")
	if c.has_meta("ultimate_desc"):
		dict["ultimate_desc"] = c.get_meta("ultimate_desc")
	if c.has_meta("bio"):
		dict["bio"] = c.get_meta("bio")
	return dict

static func deserialize_character(d: Dictionary) -> Character:
	var c = Character.new()
	c.character_name = d.get("character_name", "")
	c.character_class = d.get("character_class", "")
	c.base_hp = int(d.get("base_hp", 100))
	c.base_mp = int(d.get("base_mp", 50))
	c.base_attack = int(d.get("base_attack", 10))
	c.base_defense = int(d.get("base_defense", 5))
	c.base_magic = int(d.get("base_magic", 5))
	c.base_arcane = int(d.get("base_arcane", 5))
	c.base_speed = int(d.get("base_speed", 10))
	c.element = int(d.get("element", 0))
	c.secondary_element = int(d.get("secondary_element", 0))
	c.extra_weakness = int(d.get("extra_weakness", 0))
	c.extra_resistance = int(d.get("extra_resistance", 0))
	c.level = int(d.get("level", 1))
	# current_hp/mp default to max if missing; they're NOT @export so survive level set
	c.current_hp = int(d.get("current_hp", c.max_hp()))
	c.current_mp = int(d.get("current_mp", c.max_mp()))
	c.resonance_meter = float(d.get("resonance_meter", 0.0))
	c.experience = int(d.get("experience", 0))
	c.experience_to_next = int(d.get("experience_to_next", 100))

	var typed_status: Array[String] = []
	for s in d.get("status_effects", []):
		typed_status.append(str(s))
	c.status_effects = typed_status

	var typed_skills: Array[Skill] = []
	for sd in d.get("skills", []):
		typed_skills.append(deserialize_skill(sd))
	c.skills = typed_skills

	var inv_dict = d.get("inventory", {})
	if inv_dict is Dictionary:
		c.inventory = deserialize_inventory(inv_dict)
	else:
		c.inventory = Inventory.new()

	if d.has("ultimate_name"):
		c.set_meta("ultimate_name", d["ultimate_name"])
	if d.has("ultimate_desc"):
		c.set_meta("ultimate_desc", d["ultimate_desc"])
	if d.has("bio"):
		c.set_meta("bio", d["bio"])
	return c

# --- Party convenience ---
static func serialize_party(party_arr) -> Array:
	var arr: Array = []
	for c in party_arr:
		arr.append(serialize_character(c))
	return arr

static func deserialize_party(arr) -> Array[Character]:
	var party: Array[Character] = []
	for cd in arr:
		party.append(deserialize_character(cd))
	return party
