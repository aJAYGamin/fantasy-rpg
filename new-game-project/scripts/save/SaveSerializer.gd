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
		"unlock_level": s.unlock_level,
		"category": int(s.category),
		"source_path": s.source_path,
		"hp_cost_percent": s.hp_cost_percent,
		"resonance_cost": s.resonance_cost,
		"hit_count": s.hit_count,
		"pierce": s.pierce,
		"ally_heal_power": s.ally_heal_power,
		"bonus_condition": int(s.bonus_condition),
		"bonus_multiplier": s.bonus_multiplier,
		"override_element": int(s.override_element),
		"override_super": s.override_super,
		"scale_with": int(s.scale_with),
		"scale_more_is_stronger": s.scale_more_is_stronger,
		"self_debuff": s.self_debuff,
		"recoil_percent": s.recoil_percent,
		"miss_chance": s.miss_chance,
		"target_buff": s.target_buff,
		"charge_turns": s.charge_turns,
		"delay_rounds": s.delay_rounds,
		"recharge_turns": s.recharge_turns,
		"effect_turns": s.effect_turns,
		"is_resonance": s.is_resonance,
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
	# Defaults to 1 so a save written before P8 loads with every skill known,
	# rather than silently locking the player out of skills they already had.
	s.unlock_level = int(d.get("unlock_level", 1))
	# Pre-moveset saves have no category; ATTACK is the enum default and matches
	# how those saves' skills were laid out (attacks first).
	s.category = int(d.get("category", Skill.SkillCategory.ATTACK))
	s.resonance_gain_override = float(d.get("resonance_gain_override", -1.0))
	s.source_path = String(d.get("source_path", ""))
	# Spec B options. Every default means "off", so a save written before they
	# existed loads each move exactly as it was.
	s.hp_cost_percent = float(d.get("hp_cost_percent", 0.0))
	s.resonance_cost = float(d.get("resonance_cost", 0.0))
	s.hit_count = int(d.get("hit_count", 1))
	s.pierce = float(d.get("pierce", 0.0))
	s.ally_heal_power = float(d.get("ally_heal_power", 0.0))
	s.bonus_condition = int(d.get("bonus_condition", Skill.BonusCondition.NONE))
	s.bonus_multiplier = float(d.get("bonus_multiplier", 1.5))
	s.override_element = int(d.get("override_element", ElementalSystem.Element.NORMAL))
	s.override_super = bool(d.get("override_super", false))
	s.scale_with = int(d.get("scale_with", Skill.ScaleWith.NONE))
	s.scale_more_is_stronger = bool(d.get("scale_more_is_stronger", true))
	s.self_debuff = String(d.get("self_debuff", ""))
	s.recoil_percent = float(d.get("recoil_percent", 0.0))
	s.miss_chance = float(d.get("miss_chance", 0.0))
	s.target_buff = String(d.get("target_buff", ""))
	# Spec C options — the same "off" defaults for a save written before them.
	s.charge_turns = int(d.get("charge_turns", 0))
	s.delay_rounds = int(d.get("delay_rounds", 0))
	s.recharge_turns = int(d.get("recharge_turns", 0))
	s.effect_turns = int(d.get("effect_turns", 0))
	s.is_resonance = bool(d.get("is_resonance", false))
	return s

const MOVE_LIBRARY := "res://data/skills/"

## skill_name -> library path, used to re-link saves made before moves had
## files. Built from ResourceLoader.list_directory rather than DirAccess: in an
## exported build text resources are remapped, and a raw directory listing
## shows "foo.tres.remap" instead of "foo.tres".
static func move_library_index() -> Dictionary:
	var index := {}
	for f in ResourceLoader.list_directory(MOVE_LIBRARY):
		if not f.ends_with(".tres"):
			continue
		var s = load(MOVE_LIBRARY + f)
		if s is Skill:
			# Last wins, same as before — but a name collision between two
			# library files would otherwise silently drop one of them from the
			# index with no signal at all.
			if index.has(s.skill_name):
				push_warning("move_library_index: \"%s\" is defined by both %s and %s — the index keeps the latter" % [s.skill_name, index[s.skill_name], MOVE_LIBRARY + f])
			index[s.skill_name] = MOVE_LIBRARY + f
	return index

## Rebuilds one saved pool entry. What the move DOES comes from its library file
## when that file exists — so an edited move reaches existing saves. When the
## file is gone, the saved dictionary is the snapshot, so a save never breaks.
##
## When this hero learns the move (unlock_level, category) ALWAYS comes from the
## save: library files carry neutral defaults, and taking them from the file
## would unlock every move at level 1.
##
## The file is duplicated, never used directly: load() returns Godot's cached
## object, and handing it out would put every hero who knows the move back onto
## one shared object.
##
## A save is untrusted input: `source_path` only ever loads when it points
## inside the move library. Anything else — a stale path, a corrupted save, a
## path that happens to resolve to some other resource in the project — falls
## back to the snapshot instead of load()ing whatever the save file names.
static func resolve_saved_skill(d: Dictionary, index: Dictionary) -> Skill:
	var path := ""
	if d.has("source_path"):
		path = String(d["source_path"])
	else:
		# Saved before moves had files: re-link by name.
		path = String(index.get(String(d.get("skill_name", "")), ""))
	if path != "" and path.begins_with(MOVE_LIBRARY) and ResourceLoader.exists(path):
		var template = load(path)
		if template is Skill:
			var copy: Skill = template.duplicate(true)
			copy.source_path = path
			copy.unlock_level = int(d.get("unlock_level", 1))
			copy.category = int(d.get("category", Skill.SkillCategory.ATTACK))
			return copy
	return deserialize_skill(d)

# --- Item ---
static func serialize_item(item: Item) -> Dictionary:
	return {
		"item_name": item.item_name,
		"description": item.description,
		"item_type": int(item.item_type),
		"target_type": int(item.target_type),
		"effect_value": item.effect_value,
		"effect_stat": item.effect_stat,
		"cures": item.cures,
		"quantity": item.quantity,
		"price": item.price,
	}

static func deserialize_item(d: Dictionary) -> Item:
	var i = Item.new()
	i.item_name = d.get("item_name", "")
	i.description = d.get("description", "")
	i.item_type = int(d.get("item_type", 0))
	i.target_type = int(d.get("target_type", 0))
	i.effect_value = int(d.get("effect_value", 0))
	i.effect_stat = d.get("effect_stat", "")
	# Defaults to [] for pre-cleansing saves; those only contained the old
	# Antidote, which the migration below re-points at poison.
	var saved_cures: Array = d.get("cures", [])
	var typed_cures: Array[String] = []
	for c in saved_cures:
		typed_cures.append(String(c))
	if typed_cures.is_empty() and int(d.get("item_type", 0)) == Item.ItemType.ANTIDOTE:
		# Legacy save: an ANTIDOTE with no cures list would load inert.
		typed_cures.append(StatusSystem.POISON)
	i.cures = typed_cures
	i.quantity = int(d.get("quantity", 1))
	# Saves written before prices were stored: the catalog's price, so what the
	# player carries can be sold again (it loaded at 0 and vanished from Sell).
	i.price = int(d.get("price", ItemFactory.DEFS.get(i.item_name, {}).get("price", 0)))
	return i

# --- Equipment ---
static func serialize_equipment(eq: Equipment) -> Dictionary:
	return {
		"equipment_name": eq.equipment_name,
		"description": eq.description,
		"slot": int(eq.slot),
		"rarity": int(eq.rarity),
		"stat_bonuses": eq.stat_bonuses.duplicate(true),
		"class_restriction": eq.class_restriction.duplicate(),
		"element_restriction": eq.element_restriction.duplicate(),
		"price": eq.price,
	}

static func deserialize_equipment(d: Dictionary) -> Equipment:
	var e = Equipment.new()
	e.equipment_name = d.get("equipment_name", "")
	e.description = d.get("description", "")
	e.slot = int(d.get("slot", 0))
	e.rarity = int(d.get("rarity", 0))
	var bonuses := {}
	var raw_bonuses: Dictionary = d.get("stat_bonuses", {})
	for k in raw_bonuses:
		bonuses[String(k)] = int(raw_bonuses[k])
	e.stat_bonuses = bonuses
	var cls: Array[String] = []
	for c in d.get("class_restriction", []):
		cls.append(String(c))
	e.class_restriction = cls
	var els: Array[int] = []
	for el in d.get("element_restriction", []):
		els.append(int(el))
	e.element_restriction = els
	# Saves written before prices were stored: the catalog's price (worked out
	# when a piece is made), or 0 for gear it doesn't know.
	if d.has("price"):
		e.price = int(d["price"])
	elif EquipmentFactory.has_equipment(e.equipment_name):
		e.price = EquipmentFactory.create(e.equipment_name).price
	return e

# --- Inventory ---
static func serialize_inventory(inv: Inventory) -> Dictionary:
	var items_data: Array = []
	var equipment_data: Array = []
	var weapon = null
	var armor = null
	var accessories: Array = []
	if inv != null:
		for item in inv.items:
			items_data.append(serialize_item(item))
		for eq in inv.equipment:
			equipment_data.append(serialize_equipment(eq))
		if inv.equipped_weapon != null:
			weapon = serialize_equipment(inv.equipped_weapon)
		if inv.equipped_armor != null:
			armor = serialize_equipment(inv.equipped_armor)
		for a in inv.equipped_accessories:
			accessories.append(serialize_equipment(a) if a != null else null)
	return {
		"items": items_data,
		"equipment": equipment_data,
		"equipped_weapon": weapon,
		"equipped_armor": armor,
		"equipped_accessories": accessories,
	}

static func deserialize_inventory(d: Dictionary) -> Inventory:
	var inv = Inventory.new()
	var typed: Array[Item] = []
	for item_dict in d.get("items", []):
		typed.append(deserialize_item(item_dict))
	inv.items = typed

	var typed_eq: Array[Equipment] = []
	for eq_dict in d.get("equipment", []):
		typed_eq.append(deserialize_equipment(eq_dict))
	inv.equipment = typed_eq

	var weapon = d.get("equipped_weapon", null)
	inv.equipped_weapon = deserialize_equipment(weapon) if weapon is Dictionary else null
	var armor = d.get("equipped_armor", null)
	inv.equipped_armor = deserialize_equipment(armor) if armor is Dictionary else null

	var accessories: Array[Equipment] = [null, null, null]
	var acc_data: Array = d.get("equipped_accessories", [])
	for i in range(min(acc_data.size(), accessories.size())):
		var a = acc_data[i]
		accessories[i] = deserialize_equipment(a) if a is Dictionary else null
	inv.equipped_accessories = accessories
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
		"equipped_attacks": c.equipped_attacks.duplicate(),
		"equipped_specials": c.equipped_specials.duplicate(),
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

	# Moves load by reference (see resolve_saved_skill). The name index is only
	# needed for saves written before moves had files, so it is built lazily.
	var typed_skills: Array[Skill] = []
	var index := {}
	var index_built := false
	for sd in d.get("skills", []):
		if not sd.has("source_path") and not index_built:
			index = move_library_index()
			index_built = true
		typed_skills.append(resolve_saved_skill(sd, index))
	c.skills = typed_skills
	# Restore the loadout, then repair it: a save from before the loadout existed
	# has no slots, and a pool that changed shape could leave a slot pointing at a
	# skill that is now the wrong category or not yet learned. prune + auto_equip
	# always leaves a playable loadout rather than an empty attack menu.
	var eq_a = d.get("equipped_attacks", null)
	var eq_s = d.get("equipped_specials", null)
	if eq_a is Array:
		for i in mini(eq_a.size(), c.equipped_attacks.size()):
			c.equipped_attacks[i] = int(eq_a[i])
	if eq_s is Array:
		for i in mini(eq_s.size(), c.equipped_specials.size()):
			c.equipped_specials[i] = int(eq_s[i])
	c.prune_equipped()
	c.auto_equip_unslotted()

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

# --- Roamers ---
# One overworld enemy of the map a save was made on, as GameManager keeps it:
# {id, group_index, position: Vector2, home: Rect2, home_poly: PackedVector2Array}.
# JSON has no vectors, so they travel as plain number lists.
static func serialize_roamer_state(s: Dictionary) -> Dictionary:
	var pos: Vector2 = s.get("position", Vector2.ZERO)
	var home: Rect2 = s.get("home", Rect2())
	var poly: Array = []
	for p in s.get("home_poly", PackedVector2Array()):
		poly.append([p.x, p.y])
	return {
		"id": int(s.get("id", -1)),
		"group_index": int(s.get("group_index", -1)),
		"position": [pos.x, pos.y],
		"home": [home.position.x, home.position.y, home.size.x, home.size.y],
		"home_poly": poly,
	}

## A save is untrusted input: an entry whose position or area doesn't read back
## gets group_index -1, which the overworld's restore skips, rather than being
## placed somewhere made up.
static func deserialize_roamer_state(d: Dictionary) -> Dictionary:
	var pos = _numbers(d.get("position"), 2)
	var home = _numbers(d.get("home"), 4)
	var poly := PackedVector2Array()
	var raw_poly = d.get("home_poly", [])
	if raw_poly is Array:
		for p in raw_poly:
			var xy = _numbers(p, 2)
			if xy != null:
				poly.append(Vector2(xy[0], xy[1]))
	var valid: bool = pos != null and home != null
	return {
		"id": _whole(d.get("id"), -1),
		"group_index": _whole(d.get("group_index"), -1) if valid else -1,
		"position": Vector2(pos[0], pos[1]) if pos != null else Vector2.ZERO,
		"home": Rect2(home[0], home[1], home[2], home[3]) if home != null else Rect2(),
		"home_poly": poly,
	}

## `v` as a whole number, or `fallback` when it isn't a number.
static func _whole(v, fallback: int) -> int:
	return int(v) if (v is float or v is int) else fallback

## `v` as `count` floats, or null when it isn't a list of that many numbers.
static func _numbers(v, count: int):
	if not (v is Array) or v.size() != count:
		return null
	var out: Array[float] = []
	for n in v:
		if not (n is float or n is int):
			return null
		out.append(float(n))
	return out

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
