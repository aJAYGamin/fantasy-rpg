extends TestSuite

## Boss phases: forward-only advancement, and the five optional phase powers.

func suite_name() -> String:
	return "BossPhases"

## A phase with just a threshold — the other powers are opted into per test.
func _phase(at: float) -> BossPhase:
	var p := BossPhase.new()
	p.enter_at_hp = at
	return p

## A boss with the standard 1.0 / 0.5 / 0.25 ladder and 100 max HP.
func _boss(thresholds: Array = [1.0, 0.5, 0.25]) -> Enemy:
	var e := Enemy.new()
	e.character_name = "Test Warlord"
	e.base_hp = 100
	e.level = 1
	var list: Array[BossPhase] = []
	for t in thresholds:
		list.append(_phase(float(t)))
	e.phases = list
	e.current_hp = e.max_hp()
	return e

# --------------------------------------------------- is_boss

func test_an_enemy_without_phases_is_not_a_boss() -> void:
	var e := Enemy.new()
	e.base_hp = 50
	assert_false(e.is_boss(), "a plain enemy is not a boss")
	assert_eq(e.current_phase(), null, "and has no phase")

func test_an_enemy_with_phases_is_a_boss() -> void:
	assert_true(_boss().is_boss(), "phases are what make an enemy a boss")

# --------------------------------------------------- forward-only advancement

func test_phase_zero_is_entered_at_full_hp() -> void:
	var b := _boss()
	assert_eq(b.active_phase, -1, "starts before any phase")
	assert_true(b.should_advance_phase(), "phase 0 is ready at full HP")
	b.advance_phase()
	assert_eq(b.active_phase, 0, "entered phase 0")
	assert_false(b.should_advance_phase(), "and does not run on into phase 1")

func test_advances_at_the_threshold() -> void:
	var b := _boss()
	b.advance_phase()                 # into phase 0
	b.current_hp = 60
	assert_false(b.should_advance_phase(), "60% is above the 50% threshold")
	b.current_hp = 50
	assert_true(b.should_advance_phase(), "exactly at the threshold advances")
	b.advance_phase()
	assert_eq(b.active_phase, 1, "now in phase 1")

func test_phases_never_regress() -> void:
	# Healing a boss above a threshold must not re-enter an earlier phase, or
	# banners would re-fire and summons would repeat on every oscillation.
	var b := _boss()
	b.advance_phase()
	b.current_hp = 40
	while b.should_advance_phase():
		b.advance_phase()
	assert_eq(b.active_phase, 1, "dropped to phase 1")
	b.current_hp = b.max_hp()
	assert_false(b.should_advance_phase(), "full HP does not advance further")
	assert_eq(b.active_phase, 1, "and does not fall back to phase 0")

func test_does_not_advance_past_the_last_phase() -> void:
	var b := _boss()
	b.current_hp = 1
	var guard := 0
	while b.should_advance_phase() and guard < 50:
		b.advance_phase()
		guard += 1
	assert_eq(b.active_phase, 2, "stops at the last authored phase")
	assert_false(b.should_advance_phase(), "and stays there")

# --------------------------------------------------- Review Focus #5

func test_a_boss_whose_first_phase_is_below_full_hp_tolerates_no_phase() -> void:
	# Authoring slip: phase 0 at 0.8 means a boss at full HP is in NO phase.
	# current_phase() must return null rather than crash, and every consumer
	# must cope — the moveset falls back to the enemy's own skills.
	var b := _boss([0.8, 0.4])
	assert_false(b.should_advance_phase(), "full HP is above the first threshold")
	assert_eq(b.active_phase, -1, "no phase entered")
	assert_eq(b.current_phase(), null, "current_phase is null, not a crash")

# --------------------------------------------------- hp_fraction
#
# RULING (task-1 controller): the brief's original test here asserted only
# `hp_fraction() >= 0.0`, which Character.max_hp()'s `maxi(1, ...)` floor makes
# trivially true — an assert-nothing test. Replaced with assertions on real
# values: full HP is exactly 1.0, half HP is approximately 0.5 (max_hp() rounds,
# hence the tolerance). The `if m <= 0: return 0.0` guard inside hp_fraction()
# is kept — it costs nothing and survives a future change to max_hp() — but it
# is currently UNREACHABLE, since max_hp() can never return <= 0.

func test_hp_fraction_at_full_hp_is_exactly_one() -> void:
	var b := _boss()
	assert_eq(b.hp_fraction(), 1.0, "full HP is fraction 1.0")

func test_hp_fraction_at_half_hp_is_approximately_half() -> void:
	var b := _boss()
	b.current_hp = int(b.max_hp() / 2)
	assert_near(b.hp_fraction(), 0.5, 0.01, "half HP is ~0.5 (max_hp() rounds)")

# --------------------------------------------------- stat multipliers

func test_phase_multiplier_scales_a_combat_stat() -> void:
	var b := _boss()
	b.base_attack = 20
	var before := b.attack_power()
	b.phase_multipliers = {"attack": 2.0}
	assert_eq(b.attack_power(), before * 2, "a phase multiplier doubles ATK")

func test_phase_multiplier_defaults_to_one() -> void:
	var b := _boss()
	b.base_speed = 10
	var before := b.speed()
	b.phase_multipliers = {"attack": 3.0}
	assert_eq(b.speed(), before, "an unlisted stat is untouched")

func test_phase_multiplier_composes_with_a_buff() -> void:
	# It must STACK with buffs/debuffs and difficulty, not replace them.
	var b := _boss()
	b.base_attack = 20
	b.phase_multipliers = {"attack": 2.0}
	var phase_only := b.attack_power()
	b.apply_buff(StatusSystem.STAT_ATK)
	assert_true(b.attack_power() > phase_only, "a buff still applies on top of the phase")

func test_phase_multiplier_composes_with_difficulty() -> void:
	var b := _boss()
	b.base_attack = 20
	b.set_difficulty_multiplier(2.0)
	var difficulty_only := b.attack_power()
	b.phase_multipliers = {"attack": 2.0}
	assert_eq(b.attack_power(), difficulty_only * 2, "phase and difficulty multiply")

# --------------------------------------------------- Review Focus #3

func test_excluded_and_unknown_multiplier_keys_are_ignored() -> void:
	# max_hp is banned from stat_multipliers because it would move the very
	# thresholds that drive the phases. An unknown key must not crash either.
	var b := _boss()
	var hp_before := b.max_hp()
	b.phase_multipliers = {"max_hp": 5.0, "luck": 2.0}
	assert_eq(b.max_hp(), hp_before, "max_hp cannot be changed via stat_multipliers")
	assert_true(b.attack_power() > 0, "an unknown key does not break the stat getters")

# --------------------------------------------------- max HP scaling

func test_max_hp_multiplier_grows_the_pool() -> void:
	var b := _boss()
	var before := b.max_hp()
	b.max_hp_multiplier = 1.5
	assert_eq(b.max_hp(), roundi(before * 1.5), "max HP scales for a transformation")

func test_max_hp_multiplier_defaults_to_one() -> void:
	var b := _boss()
	assert_eq(b.max_hp_multiplier, 1.0, "an untransformed enemy is unscaled")

# --------------------------------------------------- battle-end cleanup

func test_clear_battle_effects_clears_phase_state() -> void:
	# Otherwise a transformed boss leaks its grown HP pool into a later encounter.
	var b := _boss()
	b.phase_multipliers = {"attack": 3.0}
	b.max_hp_multiplier = 2.0
	b.clear_battle_effects()
	assert_true(b.phase_multipliers.is_empty(), "phase multipliers cleared")
	assert_eq(b.max_hp_multiplier, 1.0, "max HP scaling reset")

# --------------------------------------------------- transition engine

## A BattleManager wired to a party and a single boss, without running a battle.
func _manager(boss: Enemy) -> BattleManager:
	var bm := BattleManager.new()
	var hero := Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 100
	hero.level = 1
	hero.current_hp = hero.max_hp()
	var party: Array[Character] = [hero]
	var foes: Array[Character] = [boss]
	bm.party = party
	bm.enemies = foes
	return bm

func test_entering_a_phase_emits_once() -> void:
	var b := _boss()
	var bm := _manager(b)
	var fired: Array = []
	bm.boss_phase_changed.connect(func(_e, p): fired.append(p))
	bm.check_boss_phases()
	assert_eq(fired.size(), 1, "entering phase 0 emits once")
	bm.check_boss_phases()
	assert_eq(fired.size(), 1, "a second check inside the same phase does not re-emit")
	bm.free()

func test_a_hit_crossing_two_thresholds_fires_both_entries() -> void:
	# Changed from an earlier draft: firing only the deepest let a burst-damage
	# party skip a transform entirely, which trivialises the fight.
	var b := _boss()
	var bm := _manager(b)
	bm.check_boss_phases()            # phase 0
	var fired: Array = []
	bm.boss_phase_changed.connect(func(_e, p): fired.append(p))
	b.current_hp = 10                 # crosses 0.5 AND 0.25
	bm.check_boss_phases()
	assert_eq(fired.size(), 2, "both crossed phases fire")
	assert_eq(b.active_phase, 2, "and it ends in the deepest")
	bm.free()

func test_entering_a_phase_applies_its_stat_multipliers() -> void:
	var b := _boss()
	b.base_attack = 20
	# Stats may only change as part of a transformation, so this phase is one.
	b.phases[1].stat_multipliers = {"attack": 2.0}
	b.phases[1].max_hp_multiplier = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	var before := b.attack_power()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(b.attack_power(), before * 2, "phase 1's multiplier is live")
	bm.free()

# Controller-authorised extra (review found only attack_power had a direct
# "a phase multiplier scales this stat" assertion through the engine — this
# would not have caught an implementation that wired only 4 of the 5 getters).
# Fix-round Minor 4 folded speed into the same test: dropping phase_mult from
# speed() would have stayed green otherwise.
func test_entering_a_phase_applies_multipliers_to_defense_magic_arcane_and_speed() -> void:
	var b := _boss()
	b.base_defense = 20
	b.base_magic = 20
	b.base_arcane = 20
	b.base_speed = 20
	# Stats may only change as part of a transformation, so this phase is one.
	b.phases[1].stat_multipliers = {"defense": 2.0, "magic": 2.0, "arcane": 2.0, "speed": 2.0}
	b.phases[1].max_hp_multiplier = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	var before_def := b.defense_power()
	var before_mag := b.magic_power()
	var before_arc := b.arcane_power()
	var before_spd := b.speed()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(b.defense_power(), before_def * 2, "phase 1's DEF multiplier is live")
	assert_eq(b.magic_power(), before_mag * 2, "phase 1's MAG multiplier is live")
	assert_eq(b.arcane_power(), before_arc * 2, "phase 1's ARC multiplier is live")
	assert_eq(b.speed(), before_spd * 2, "phase 1's SPD multiplier is live")
	bm.free()

func test_a_later_phase_replaces_the_previous_multipliers() -> void:
	var b := _boss()
	b.base_attack = 20
	# Both are transformations — the only phases permitted to touch raw stats.
	b.phases[1].stat_multipliers = {"attack": 2.0}
	b.phases[1].max_hp_multiplier = 1.0
	b.phases[2].stat_multipliers = {"speed": 2.0}
	b.phases[2].max_hp_multiplier = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 10
	bm.check_boss_phases()
	assert_eq(b.phase_mult("attack"), 1.0, "phase 1's ATK boost is gone, not accumulated")
	assert_eq(b.phase_mult("speed"), 2.0, "phase 2's SPD boost is live")
	bm.free()

# --------------------------------------------------- _next_turn hook
#
# Fix-round IMPORTANT 1: every test above drives the engine by calling
# check_boss_phases() directly, so none of them would notice if the single
# line wiring it into _next_turn() were ever deleted — confirmed by the
# reviewer, who replaced that line with a comment and watched the full suite
# stay green. This test drives the real gameplay path instead.

func test_next_turn_hook_advances_boss_phases() -> void:
	# current_actor lands on the hero (not the boss), so _next_turn() never
	# reaches _execute_enemy_turn() — which awaits a timer and would hang
	# outside a running SceneTree. That keeps this test synchronous while
	# still exercising the real call: check_boss_phases() is the first
	# statement of _next_turn(), not something this test invokes itself.
	var b := _boss()
	b.active_phase = 0                 # already resolved into phase 0 by hand,
	                                    # bypassing the engine entirely so far
	var bm := _manager(b)
	bm.turn_order = [bm.party[0]]      # hero's turn, never the boss's
	bm.current_turn_index = 0
	b.current_hp = 40                  # crosses the 0.5 threshold into phase 1
	bm._next_turn()
	assert_eq(b.active_phase, 1, "the _next_turn() hook advanced the boss's phase")
	bm.free()

# --------------------------------------------------- transformation

func test_transformation_grows_max_hp_and_refills() -> void:
	var b := _boss()
	b.phases[2].max_hp_multiplier = 1.5
	b.phases[2].restore_hp = true
	var base_max := b.max_hp()
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 10
	bm.check_boss_phases()
	assert_eq(b.max_hp(), roundi(base_max * 1.5), "max HP grew")
	assert_eq(b.current_hp, b.max_hp(), "and the bar is full again")
	bm.free()

func test_transformation_does_not_regress_the_phase() -> void:
	# A refill returns the fraction to 1.0; a recomputing design would drop the
	# boss back to phase 0 here.
	var b := _boss()
	b.phases[2].max_hp_multiplier = 1.5
	b.phases[2].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 10
	bm.check_boss_phases()
	assert_eq(b.active_phase, 2, "still in the transformed phase at full HP")
	bm.free()

func test_transformation_halts_the_cascade() -> void:
	# Four phases, with the transform third. One huge hit must stop AT the
	# transform rather than running on into phase 3.
	var b := _boss([1.0, 0.5, 0.25, 0.1])
	b.phases[2].max_hp_multiplier = 2.0
	b.phases[2].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 1
	bm.check_boss_phases()
	assert_eq(b.active_phase, 2, "stopped at the transform, not phase 3")
	bm.free()

func test_a_later_phase_still_fires_against_the_new_max_hp() -> void:
	var b := _boss([1.0, 0.5, 0.25, 0.1])
	b.phases[2].max_hp_multiplier = 2.0
	b.phases[2].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 1
	bm.check_boss_phases()                      # transform, now at 2x max
	b.current_hp = int(b.max_hp() * 0.05)       # 5% of the NEW pool
	bm.check_boss_phases()
	assert_eq(b.active_phase, 3, "the last phase fires against the new maximum")
	bm.free()

# Fix-round IMPORTANT 2 (controller ruling): NOT a bug. Growing max HP without
# refilling means the SAME current_hp becomes a SMALLER fraction of the new,
# larger pool — the boss genuinely is proportionally closer to death, so later
# phases are correct to fire immediately in the same cascade. Only a refilling
# transformation (restore_hp = true, see test_transformation_halts_the_cascade
# above) resets the fraction to 1.0 and halts the cascade. Pinned here, named
# so it reads as deliberate rather than an oversight, per the spec update at
# .claude/docs/superpowers/specs/2026-09-24-boss-phases-design.md.
func test_a_non_refilling_transformation_does_not_halt_the_cascade() -> void:
	var b := _boss([1.0, 0.5, 0.25, 0.1])
	b.phases[2].max_hp_multiplier = 2.0
	# restore_hp intentionally left at its default false
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 20
	bm.check_boss_phases()
	assert_eq(b.active_phase, 3, "the cascade runs on into phase 3, not halted")
	bm.free()

# --------------------------------------------------- Review Focus #1 and #4

func test_a_dead_boss_does_not_transition() -> void:
	# The worst failure mode here is a corpse that summons reinforcements.
	var b := _boss()
	b.phases[1].max_hp_multiplier = 2.0
	var bm := _manager(b)
	bm.check_boss_phases()
	var fired: Array = []
	bm.boss_phase_changed.connect(func(_e, p): fired.append(p))
	b.current_hp = 0
	bm.check_boss_phases()
	assert_true(fired.is_empty(), "a defeated boss fires no phase entry")
	assert_eq(b.active_phase, 0, "and does not advance")
	bm.free()

func test_transforming_at_one_hp_ends_at_the_new_full() -> void:
	# Guards an ordering slip: reading max_hp() before setting the multiplier
	# would leave the boss on a sliver of its new pool.
	var b := _boss()
	b.phases[1].max_hp_multiplier = 3.0
	b.phases[1].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 1
	bm.check_boss_phases()
	assert_eq(b.current_hp, b.max_hp(), "refilled to the NEW maximum")
	assert_true(b.current_hp > 100, "which is larger than the original pool")
	bm.free()

# --------------------------------------------------- Power 1: moveset

func _skill(name: String) -> Skill:
	var s := Skill.new()
	s.skill_name = name
	s.power = 10.0
	return s

func test_a_phase_moveset_replaces_the_base_skills() -> void:
	var b := _boss()
	b.skills = [_skill("Base Swing")]
	b.phases[1].skills = [_skill("Desperate Cleave")]
	var bm := _manager(b)
	bm.check_boss_phases()
	var opening := EnemyAI.usable_skills(b)
	assert_eq(opening[0].skill_name, "Base Swing", "phase 0 has no list, so base skills are used")
	b.current_hp = 50
	bm.check_boss_phases()
	var wounded := EnemyAI.usable_skills(b)
	assert_eq(wounded.size(), 1, "phase 1 supplies exactly its own list")
	assert_eq(wounded[0].skill_name, "Desperate Cleave", "and it is the phase's skill")
	bm.free()

func test_an_empty_phase_moveset_falls_back_to_base() -> void:
	var b := _boss()
	b.skills = [_skill("Base Swing")]
	var bm := _manager(b)
	bm.check_boss_phases()
	assert_eq(EnemyAI.usable_skills(b)[0].skill_name, "Base Swing", "[] means keep base skills")
	bm.free()

func test_a_non_boss_enemy_uses_its_own_skills() -> void:
	# Guards the enrage removal: ordinary enemies must be entirely unaffected.
	var e := Enemy.new()
	e.base_hp = 50
	e.level = 1
	e.current_hp = 1
	e.skills = [_skill("Bite")]
	var list := EnemyAI.usable_skills(e)
	assert_eq(list.size(), 1, "a plain enemy draws from its own skills")
	assert_eq(list[0].skill_name, "Bite", "even at low HP, with no phases to consult")

func test_a_boss_in_no_phase_uses_its_base_skills() -> void:
	# Review Focus #5 again, at the consumer: current_phase() is null here.
	var b := _boss([0.8, 0.4])
	b.skills = [_skill("Base Swing")]
	assert_eq(EnemyAI.usable_skills(b)[0].skill_name, "Base Swing", "a null phase falls back safely")

func test_choose_action_draws_from_the_phase_moveset() -> void:
	# usable_skills() alone isn't proof _choose_skill actually consults it — a
	# fix that repaired only the emptiness check (enemy.skills.is_empty()) but
	# left the candidate list itself reading enemy.skills would still pass the
	# tests above (they call usable_skills() directly) while quietly handing
	# out the base skill here. Drive the real decision path instead.
	var b := _boss()
	b.skills = [_skill("Base Swing")]
	b.phases[1].skills = [_skill("Desperate Cleave")]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()               # now in phase 1
	var hero := Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 100
	hero.current_hp = 100
	var decision := EnemyAI.choose_action(b, [hero] as Array[Character], [b] as Array[Character])
	assert_eq(decision.get("skill").skill_name, "Desperate Cleave", "choose_action draws from the phase moveset, not the base list")
	bm.free()

func test_choose_action_uses_phase_skills_even_when_base_skills_is_empty() -> void:
	# Guards the other call site: if the emptiness check still reads
	# enemy.skills.is_empty() instead of usable_skills(enemy).is_empty(), a
	# boss with no base moveset but a populated phase moveset would bail out
	# to no action at all instead of using the phase's skills.
	var b := _boss()
	b.skills = []
	b.phases[1].skills = [_skill("Desperate Cleave")]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	var hero := Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 100
	hero.current_hp = 100
	var decision := EnemyAI.choose_action(b, [hero] as Array[Character], [b] as Array[Character])
	assert_ne(decision.get("skill"), null, "phase moveset is used even though base skills is empty")
	assert_eq(decision.get("skill").skill_name, "Desperate Cleave", "and it's the phase's skill")
	bm.free()

func test_a_boss_below_25_percent_hp_is_not_force_enraged() -> void:
	# Guards the enrage removal itself: is_enraged must be false for bosses
	# regardless of HP, or the phase moveset and the old hard-coded enrage
	# would fight each other invisibly.
	var b := _boss()
	b.skills = [_skill("Base Swing")]
	b.current_hp = 10  # 10% HP, well under the old 25% enrage threshold
	var hero := Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 100
	hero.current_hp = 100
	var decision := EnemyAI.choose_action(b, [hero] as Array[Character], [b] as Array[Character])
	assert_false(decision.get("is_enraged"), "bosses no longer use the hard-coded HP enrage")

func test_a_non_boss_enemy_still_enrages_below_25_percent_hp() -> void:
	# Pins the ordinary-enemy path precisely because the boss codepath now
	# diverges from it: an enemy without phases must keep the hard-coded
	# enrage exactly as before, always picking its highest-power damaging skill.
	var e := Enemy.new()
	e.base_hp = 100
	e.level = 1
	var weak := _skill("Weak Jab")
	var heavy := _skill("Heavy Blow")
	heavy.power = 50.0
	e.skills = [weak, heavy]
	e.current_hp = 10  # under 25%
	var hero := Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 100
	hero.current_hp = 100
	var decision := EnemyAI.choose_action(e, [hero] as Array[Character], [e] as Array[Character])
	assert_true(decision.get("is_enraged"), "an ordinary enemy under 25% HP is still enraged")
	assert_eq(decision.get("skill").skill_name, "Heavy Blow", "enraged still picks the highest-power damaging skill")

# --------------------------------------------------- Power 3: summons

const SPEARMAN := "res://data/enemies/goblin_spearman.tres"

func test_a_phase_summons_reinforcements() -> void:
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 2}]
	var bm := _manager(b)
	bm.check_boss_phases()
	assert_eq(bm.enemies.size(), 1, "no adds yet")
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies.size(), 3, "two reinforcements joined the fight")
	bm.free()

func test_summons_inherit_the_boss_level_by_default() -> void:
	var b := _boss()
	b.level = 7
	b.phases[1].summons = [{"path": SPEARMAN, "count": 1}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies[1].level, 7, "an add matches the boss's level")
	bm.free()

func test_an_explicit_summon_level_wins() -> void:
	var b := _boss()
	b.level = 7
	b.phases[1].summons = [{"path": SPEARMAN, "count": 1, "level": 3}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies[1].level, 3, "the spec's level overrides the boss's")
	bm.free()

func test_summons_start_at_full_health() -> void:
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 1}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	var add: Character = bm.enemies[1]
	assert_eq(add.current_hp, add.max_hp(), "an add arrives at full HP")
	bm.free()

func test_summons_enter_the_turn_order() -> void:
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 2}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	bm._build_turn_order()
	assert_eq(bm.turn_order.size(), 4, "hero + boss + two adds all act")
	bm.free()

func test_the_enemy_cap_is_enforced_when_summoning() -> void:
	# Enforced at spawn, NOT at render: _setup_enemy_cards truncates with
	# mini(enemies.size(), 10), which would leave an 11th enemy alive in the
	# fight with no card and no visible HP bar.
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 30}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies.size(), BattleManager.MAX_BATTLE_ENEMIES, "capped at 10 combatants")
	bm.free()

# --------------------------------------------------- Review Focus #2

func test_a_bad_summon_path_is_skipped_without_crashing() -> void:
	# A typo in a .tres must not end the battle.
	var b := _boss()
	b.phases[1].summons = [
		{"path": "res://data/enemies/does_not_exist.tres", "count": 2},
		{"path": "", "count": 1},
		{"path": SPEARMAN, "count": 1},
	]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(bm.enemies.size(), 2, "the good summon still arrives; the bad ones are skipped")
	bm.free()

# --------------------------------------------------- Fix round 1: distinct instances

func test_summons_are_distinct_instances_not_a_shared_template() -> void:
	# A wrong implementation might do `enemies.append(template)` instead of
	# `template.duplicate(true)` — appending the SAME loaded Resource object on
	# every iteration. Enemy is a Resource, so two summons sharing one object
	# would share one HP pool: damaging one would damage both, and area damage
	# would hit the same pool twice. The behavioural check (damage one, assert
	# the sibling's HP is untouched) is the strong form; identity is a supplement.
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 2}]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	var add1: Character = bm.enemies[1]
	var add2: Character = bm.enemies[2]
	assert_ne(add1, add2, "each summon is its own object, not a shared template")
	add1.current_hp = 1
	assert_eq(add2.current_hp, add2.max_hp(), "damaging one summon leaves its sibling's HP untouched")
	bm.free()

# --------------------------------------------------- Fix round 1: cumulative cap

func test_the_enemy_cap_holds_cumulatively_across_phases() -> void:
	# Only a single-spec count:30 case was covered before — this proves the cap
	# also holds when adds already present from an earlier phase are topped up
	# by a later phase's summons, not just within one spec's own loop.
	var b := _boss()
	b.phases[1].summons = [{"path": SPEARMAN, "count": 5}]
	b.phases[2].summons = [{"path": SPEARMAN, "count": 10}]
	var bm := _manager(b)
	bm.check_boss_phases()                       # phase 0, no summons
	assert_eq(bm.enemies.size(), 1, "no adds yet")
	b.current_hp = 50
	bm.check_boss_phases()                       # phase 1: boss + 5 adds
	assert_eq(bm.enemies.size(), 6, "phase 1's five reinforcements joined")
	b.current_hp = 10
	bm.check_boss_phases()                       # phase 2: 10 more requested, capped
	assert_eq(bm.enemies.size(), BattleManager.MAX_BATTLE_ENEMIES, "cumulative total still caps at 10")
	bm.free()

# --------------------------------------------------- Power 4: field effects

func test_a_field_effect_afflicts_a_hero() -> void:
	var b := _boss()
	b.phases[0].turn_effect = "poison"
	b.phases[0].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	var hit := bm.apply_boss_field_effect(b)
	assert_true(hit != null, "a guaranteed effect lands")
	assert_true(hit.is_status("poison"), "and applies its token")
	bm.free()

func test_a_zero_chance_field_effect_never_fires() -> void:
	var b := _boss()
	b.phases[0].turn_effect = "poison"
	b.phases[0].turn_effect_chance = 0.0
	var bm := _manager(b)
	bm.check_boss_phases()
	assert_eq(bm.apply_boss_field_effect(b), null, "chance 0 never fires")
	bm.free()

func test_no_field_effect_when_the_phase_declares_none() -> void:
	var b := _boss()
	var bm := _manager(b)
	bm.check_boss_phases()
	assert_eq(bm.apply_boss_field_effect(b), null, "an empty token is a no-op")
	bm.free()

func test_a_field_effect_never_targets_a_downed_hero() -> void:
	var b := _boss()
	b.phases[0].turn_effect = "poison"
	b.phases[0].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.party[0].current_hp = 0
	bm.check_boss_phases()
	assert_eq(bm.apply_boss_field_effect(b), null, "with no living hero, nothing is afflicted")
	bm.free()

func test_a_field_effect_routes_through_the_status_rules() -> void:
	# Going through _apply_skill_status means element immunity and the mutex
	# one-status rule apply for free. A Fire hero cannot be scorched.
	var b := _boss()
	b.phases[0].turn_effect = "scorched"
	b.phases[0].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.party[0].element = ElementalSystem.Element.FIRE
	bm.check_boss_phases()
	bm.apply_boss_field_effect(b)
	assert_false(bm.party[0].is_status("scorched"), "Fire is immune to scorched")
	bm.free()

func test_a_buff_token_works_as_a_field_effect() -> void:
	var b := _boss()
	b.phases[0].turn_effect = "attack_debuff"
	b.phases[0].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	var hit := bm.apply_boss_field_effect(b)
	assert_true(hit != null, "the effect landed")
	assert_true(StatusSystem.is_effectively_debuffed(hit, StatusSystem.STAT_ATK), "debuff tokens work too")
	bm.free()

# --------------------------------------------------- presentation

func test_a_boss_card_fills_the_row() -> void:
	var b := _boss()
	var scene := BattleScene.new()
	var card := scene._create_enemy_card(b)
	assert_eq(card.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "a boss card fills the row")
	scene.free()

func test_an_ordinary_enemy_card_stays_fixed_width() -> void:
	var e := Enemy.new()
	e.base_hp = 30
	e.level = 1
	var scene := BattleScene.new()
	var card := scene._create_enemy_card(e)
	assert_eq(card.custom_minimum_size.x, 124.0, "a normal card keeps its fixed width")
	scene.free()

## RULING (task-7 controller): the brief's original version of this test ended
## with `assert_true(true, "...")`, which asserts nothing and would pass against
## any implementation, including one where setup() never rebuilds the turn
## order at all. Replaced with real assertions against
## `TurnOrderIndicator.combatant_count()` — a small accessor added for this
## purpose, since the visible 3-slot scrolling display (prev/current/next,
## wrapping) always shows exactly 3 child slots regardless of roster size and
## so can't distinguish a 2-combatant roster from a 3-combatant one. The
## underlying `_turn_order` array is the thing that actually changes size when
## setup() is re-run with a grown roster, so that's what combatant_count()
## exposes.
func test_the_turn_order_panel_is_reseeded_on_a_phase_change() -> void:
	# TurnOrderIndicator.setup() runs once at battle start, so a summoned enemy
	# would fight without ever appearing in the turn order.
	var indicator = load("res://scripts/battle/TurnOrderIndicator.gd").new()
	# GameManager is a live autoload always in the tree, so parenting the
	# indicator to it runs a real _ready() (builds _slot_container etc.) —
	# same idiom as test_stats_screen.gd:_open_screen / test_items_screen.gd:_open_items.
	GameManager.add_child(indicator)
	var hero := Character.new()
	hero.character_name = "Hero"
	hero.base_hp = 50
	hero.level = 1
	hero.current_hp = hero.max_hp()
	var b := _boss()
	var party: Array[Character] = [hero]
	var foes: Array[Character] = [b]
	indicator.setup(party, foes)
	assert_eq(indicator.combatant_count(), 2, "starts tracking hero + boss")
	var add := Enemy.new()
	add.character_name = "Spearman"
	add.base_hp = 20
	add.level = 1
	add.current_hp = add.max_hp()
	foes.append(add)
	indicator.setup(party, foes)
	assert_eq(indicator.combatant_count(), 3, "re-seeding with a grown roster picks up the reinforcement")
	indicator.free()

func test_a_silent_phase_shows_no_banner() -> void:
	var p := BossPhase.new()
	p.banner_text = ""
	assert_eq(p.banner_text, "", "an empty banner_text means transition silently")

# --------------------------------------------------- the first boss

const WARLORD := "res://data/enemies/goblin_warlord.tres"

func test_the_warlord_loads_as_a_boss() -> void:
	var w: Enemy = load(WARLORD)
	assert_true(w != null, "the warlord resource loads")
	assert_true(w.is_boss(), "and it has phases")
	assert_eq(w.phases.size(), 3, "three phases")

func test_the_warlord_exercises_every_power() -> void:
	var w: Enemy = load(WARLORD)
	var summons := false
	var stats := false
	var moveset := false
	var transform := false
	for p in w.phases:
		if not p.summons.is_empty(): summons = true
		if not p.stat_multipliers.is_empty(): stats = true
		if not p.skills.is_empty(): moveset = true
		if p.is_transformation(): transform = true
	assert_true(summons, "a phase summons")
	assert_true(stats, "a phase boosts stats")
	assert_true(moveset, "a phase changes the moveset")
	assert_true(transform, "a phase transforms")

func test_the_warlord_phases_are_in_descending_order() -> void:
	# Forward-only advancement assumes descending thresholds; an out-of-order
	# ladder would make a later phase unreachable.
	var w: Enemy = load(WARLORD)
	for i in range(1, w.phases.size()):
		assert_true(w.phases[i].enter_at_hp <= w.phases[i - 1].enter_at_hp,
			"phase %d's threshold is not above the one before it" % i)

func test_the_warlord_summons_within_the_cap() -> void:
	var w: Enemy = load(WARLORD)
	var total := 1
	for p in w.phases:
		for s in p.summons:
			total += int(s.get("count", 1))
	assert_true(total <= BattleManager.MAX_BATTLE_ENEMIES,
		"the warlord and everything it summons fit in %d slots" % BattleManager.MAX_BATTLE_ENEMIES)

# --------------------------------------------------- Whole-branch review, fix round 2

# Finding 3: the summon cap counted every enemy, corpses included, but
# BattleScene._rebuild_enemy_cards only ever renders get_alive_enemies() — a
# dead add holds no card slot. Filling the row with adds, killing all of
# them, then asking a later phase to summon again proves the cap now tracks
# living combatants, not corpses.
func test_the_summon_cap_counts_only_living_enemies() -> void:
	var b := _boss([1.0, 0.5, 0.25])
	b.phases[1].summons = [{"path": SPEARMAN, "count": 9}]
	b.phases[2].summons = [{"path": SPEARMAN, "count": 5}]
	var bm := _manager(b)
	bm.check_boss_phases()                        # phase 0, no summons
	b.current_hp = 50
	bm.check_boss_phases()                        # phase 1: boss + 9 adds fills the row
	assert_eq(bm.enemies.size(), 10, "phase 1's nine reinforcements filled all 10 slots")
	# Kill every add. The corpses stay in bm.enemies — nothing removes a dead
	# Character from the array, same as a real battle — but must not count
	# toward the cap.
	for i in range(1, bm.enemies.size()):
		bm.enemies[i].current_hp = 0
	assert_eq(bm.get_alive_enemies().size(), 1, "only the boss is still alive")
	b.current_hp = 10
	bm.check_boss_phases()                        # phase 2 tries to summon 5 more
	assert_eq(bm.enemies.size(), 15, "phase 2 could still summon — corpses didn't block it")
	assert_eq(bm.get_alive_enemies().size(), 6, "boss + the five new adds are alive")
	bm.free()

# Finding 1: BattleScene caches max_hp() per character once at battle start so
# bars don't jitter mid-fight, but a transformation raises max_hp() —
# _on_boss_phase_changed must refresh that one cache entry before the card
# row rebuilds, or the bar clamps to a stale (smaller) maximum while
# current_hp sits at the new, larger one. This drives the extracted helper
# (_refresh_max_hp_cache) directly: _on_boss_phase_changed itself reaches
# onready nodes (turn_order_indicator, battle_manager) that only exist once
# the scene is inside a live tree, which a synchronous unit test can't set up.
func test_refresh_max_hp_cache_updates_a_transformed_boss() -> void:
	var b := _boss()
	var scene := BattleScene.new()
	scene._max_hp[b] = b.max_hp()      # simulates the cache taken in start_battle
	var stale_max: float = scene._max_hp[b]

	# Simulate what _enter_boss_phase does for a transformation.
	b.max_hp_multiplier = 1.5
	b.current_hp = b.max_hp()

	scene._refresh_max_hp_cache(b)
	assert_true(scene._max_hp[b] > stale_max, "the cache grew along with the transformation")
	assert_eq(scene._max_hp[b], b.max_hp(), "the cache now matches the transformed maximum")
	scene.free()

# Finding 2: check_boss_phases() can emit boss_phase_changed twice in the same
# synchronous frame (a hit crossing two thresholds), and any other status
# banner can likewise arrive while one is already on screen.
# _show_status_banner used to queue_free() whatever was showing so a new one
# could take over — the first of two cascaded banners was destroyed before it
# ever rendered a frame. The fix queues instead. The full fade timeline needs
# a live SceneTree (awaits process_frame and tweens) that a synchronous test
# can't drive, so — per the brief — this proves the queue's data structure
# directly: what gets enqueued, in what order, and that nothing is dropped.
func test_show_status_banner_queues_behind_an_active_banner() -> void:
	var scene := BattleScene.new()
	scene._banner_active = true   # simulate a banner already on screen
	scene._show_status_banner("First", Color.WHITE, 1.0)
	scene._show_status_banner("Second", Color.RED, 1.0)
	scene._show_status_banner("Third", Color.BLUE, 1.0)
	assert_eq(scene._banner_queue.size(), 3, "nothing was dropped")
	assert_eq(scene._banner_queue[0]["text"], "First", "arrival order preserved (1)")
	assert_eq(scene._banner_queue[1]["text"], "Second", "arrival order preserved (2)")
	assert_eq(scene._banner_queue[2]["text"], "Third", "arrival order preserved (3)")
	scene.free()

# --------------------------------------------------- reachable in play
# The boss existed but was authored unreachable: its fixed encounter was
# referenced by nothing, so nothing in the game could start the fight. These
# pin the wiring, because a scene reference is exactly the kind of thing that
# breaks silently — the castle would just spawn nothing.

func test_the_goblin_castle_spawns_the_warlord() -> void:
	var scene: PackedScene = load("res://scenes/GoblinCastle.tscn")
	assert_true(scene != null, "the castle scene loads")
	var root := scene.instantiate()
	var territories := root.find_child("RoamerTerritories", true, false)
	assert_true(territories != null, "the castle has roamer territories")

	var boss_groups: Array = []
	for t in territories.get_children():
		var grp = t.get("group")
		if grp == null:
			continue
		for template in grp.enemy_pool:
			if template != null and template.is_boss():
				boss_groups.append(grp)
	assert_eq(boss_groups.size(), 1, "exactly one territory carries a boss encounter")
	var g = boss_groups[0]
	assert_true(g.is_fixed, "a boss fight is a FIXED encounter, not a random draw")
	assert_eq(g.enemy_pool.size(), 1, "the warlord fights alone (its adds arrive by phase)")
	assert_eq(g.enemy_pool[0].character_name, "Goblin Warlord", "and it is the warlord")
	root.free()

func test_the_castle_boss_encounter_instantiates_one_boss() -> void:
	var grp: EncounterGroup = load("res://data/encounters/goblin_warlord_fight.tres")
	var spawned := grp.instantiate_encounter(1)
	assert_eq(spawned.size(), 1, "one combatant at the start of the fight")
	assert_true(spawned[0].is_boss(), "and it is a boss")
	assert_eq(spawned[0].active_phase, -1, "a freshly spawned boss has entered no phase yet")
	assert_eq(spawned[0].current_hp, spawned[0].max_hp(), "and starts at full health")

# --------------------------------------------------- the refill pause
# A transformed boss refills its bar in real time, and the turn loop must block
# while it does — otherwise the player attacks into a bar that is still
# climbing, and the refill happens between two frames where nobody sees it.

func test_a_refilling_transformation_reports_a_pause() -> void:
	var b := _boss()
	b.phases[1].max_hp_multiplier = 1.5
	b.phases[1].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()          # into phase 0
	b.current_hp = 50
	var pause: float = bm.check_boss_phases()
	assert_eq(pause, BattleManager.BOSS_REFILL_DURATION, "the caller is told to wait for the refill")
	bm.free()

func test_an_ordinary_phase_reports_no_pause() -> void:
	var b := _boss()
	b.phases[1].stat_multipliers = {"attack": 2.0}
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	assert_eq(bm.check_boss_phases(), 0.0, "a phase with no refill does not stall the fight")
	bm.free()

func test_a_transformation_that_does_not_refill_reports_no_pause() -> void:
	# Nothing visibly climbs, so there is nothing to wait for.
	var b := _boss()
	b.phases[1].max_hp_multiplier = 2.0
	b.phases[1].restore_hp = false
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	assert_eq(bm.check_boss_phases(), 0.0, "a non-refilling transformation needs no pause")
	bm.free()

func test_the_pause_is_not_summed_across_a_cascade() -> void:
	# Two refilling transformations crossed by one hit should wait ONE refill,
	# not two stacked — the bars animate concurrently.
	var b := _boss([1.0, 0.5, 0.25])
	for i in [1, 2]:
		b.phases[i].max_hp_multiplier = 1.2
		b.phases[i].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 1
	assert_eq(bm.check_boss_phases(), BattleManager.BOSS_REFILL_DURATION, "one refill's worth of pause")
	bm.free()

func test_a_dead_boss_reports_no_pause() -> void:
	var b := _boss()
	b.phases[1].max_hp_multiplier = 1.5
	b.phases[1].restore_hp = true
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 0
	assert_eq(bm.check_boss_phases(), 0.0, "a defeated boss does not stall the victory")
	bm.free()


# --------------------------------------------------- stats are transform-only
# A boss's raw numbers may change only as part of becoming a stronger FORM. An
# ordinary later phase escalates through things the player can see and answer —
# summons, buffs, party debuffs — never an invisible multiplier that silently
# rewrites the numbers mid-fight.

func test_a_non_transforming_phase_cannot_change_stats() -> void:
	var b := _boss()
	b.base_attack = 20
	b.phases[1].stat_multipliers = {"attack": 3.0}   # authored, but not a transformation
	var bm := _manager(b)
	bm.check_boss_phases()
	var before := b.attack_power()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(b.active_phase, 1, "the phase was still entered")
	assert_eq(b.attack_power(), before, "but its stat multiplier was ignored")
	bm.free()

func test_a_non_transforming_phase_does_not_strip_an_earlier_transformation() -> void:
	# The boss transformed into a stronger form; a later ordinary phase must not
	# quietly weaken it back out of that form by clearing the multipliers.
	var b := _boss([1.0, 0.5, 0.25])
	b.base_attack = 20
	b.phases[1].max_hp_multiplier = 1.0
	b.phases[1].stat_multipliers = {"attack": 2.0}
	b.phases[2].summons = []                          # ordinary phase, no stats
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	var transformed := b.attack_power()
	b.current_hp = 10
	bm.check_boss_phases()
	assert_eq(b.active_phase, 2, "advanced into the ordinary phase")
	assert_eq(b.attack_power(), transformed, "the transformation's boost survives it")
	bm.free()

func test_a_transformation_may_still_change_stats() -> void:
	var b := _boss()
	b.base_attack = 20
	b.phases[1].max_hp_multiplier = 1.5
	b.phases[1].restore_hp = true
	b.phases[1].stat_multipliers = {"attack": 2.0}
	var bm := _manager(b)
	bm.check_boss_phases()
	var before := b.attack_power()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_eq(b.attack_power(), before * 2, "a stronger form is allowed stronger numbers")
	bm.free()

# --------------------------------------------------- self-buffs on entry
# How an ordinary (non-transforming) phase is meant to escalate: real buffs the
# player can see as chips and answer, rather than the raw stat multipliers only
# a transformation may use.

func test_a_phase_buffs_the_boss_on_entry() -> void:
	var b := _boss()
	b.base_attack = 20
	b.phases[1].self_buffs = ["attack"]
	var bm := _manager(b)
	bm.check_boss_phases()
	var before := b.attack_power()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_true(StatusSystem.is_effectively_buffed(b, StatusSystem.STAT_ATK), "the boss is visibly buffed")
	assert_true(b.attack_power() > before, "and hits harder for it")
	bm.free()

func test_all_five_combat_stats_can_be_self_buffed() -> void:
	var b := _boss()
	b.phases[1].self_buffs = ["attack", "defense", "magic", "arcane", "speed"]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	for stat in [StatusSystem.STAT_ATK, StatusSystem.STAT_DEF, StatusSystem.STAT_MAG,
			StatusSystem.STAT_ARC, StatusSystem.STAT_SPD]:
		assert_true(StatusSystem.is_effectively_buffed(b, stat), "%s is buffed" % stat)
	bm.free()

func test_self_buffs_are_entry_only_not_per_turn() -> void:
	# The distinction that matters: turn_effect repeats every boss turn, a
	# self_buff fires once when the phase is entered.
	var b := _boss()
	b.phases[1].self_buffs = ["attack"]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	# Strip the buff as a dispel would, then run more turns in the same phase.
	b.buffs.clear()
	for i in 3:
		bm.check_boss_phases()
	assert_false(StatusSystem.is_effectively_buffed(b, StatusSystem.STAT_ATK),
		"staying in the phase does not re-apply the buff")
	bm.free()

func test_an_unbuffable_stat_name_is_ignored() -> void:
	var b := _boss()
	b.phases[1].self_buffs = ["luck", "max_hp", "attack"]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_true(StatusSystem.is_effectively_buffed(b, StatusSystem.STAT_ATK),
		"the valid entry still applies alongside the junk ones")
	bm.free()

func test_a_self_buff_cancels_a_debuff_the_party_landed() -> void:
	# Consistent with every other buff in the game: applying one to a debuffed
	# stat cancels the debuff rather than stacking against it.
	var b := _boss()
	b.apply_debuff(StatusSystem.STAT_ATK)
	b.phases[1].self_buffs = ["attack"]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	assert_false(StatusSystem.is_effectively_debuffed(b, StatusSystem.STAT_ATK),
		"the party's debuff was cancelled by the boss buffing that stat")
	bm.free()

func test_self_buffs_clear_at_battle_end() -> void:
	var b := _boss()
	b.phases[1].self_buffs = ["attack"]
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	b.clear_battle_effects()
	assert_false(StatusSystem.is_effectively_buffed(b, StatusSystem.STAT_ATK),
		"a buff does not leak into the next encounter")
	bm.free()

func test_a_phase_can_buff_itself_and_debuff_the_party_on_the_same_stat() -> void:
	# self_buffs (the boss) and turn_effect (a hero) are independent fields, so a
	# phase may raise its own attack while lowering the party's — or pick
	# entirely different stats. Nothing couples the two.
	var b := _boss()
	b.phases[1].self_buffs = ["attack"]
	b.phases[1].turn_effect = "attack_debuff"
	b.phases[1].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	var hit := bm.apply_boss_field_effect(b)
	assert_true(StatusSystem.is_effectively_buffed(b, StatusSystem.STAT_ATK), "the boss buffed its own ATK")
	assert_true(StatusSystem.is_effectively_debuffed(hit, StatusSystem.STAT_ATK), "and debuffed a hero's ATK")
	bm.free()

func test_a_phase_can_buff_and_debuff_different_stats() -> void:
	var b := _boss()
	b.phases[1].self_buffs = ["defense", "speed"]
	b.phases[1].turn_effect = "magic_debuff"
	b.phases[1].turn_effect_chance = 1.0
	var bm := _manager(b)
	bm.check_boss_phases()
	b.current_hp = 50
	bm.check_boss_phases()
	var hit := bm.apply_boss_field_effect(b)
	assert_true(StatusSystem.is_effectively_buffed(b, StatusSystem.STAT_DEF), "boss DEF up")
	assert_true(StatusSystem.is_effectively_buffed(b, StatusSystem.STAT_SPD), "boss SPD up")
	assert_true(StatusSystem.is_effectively_debuffed(hit, StatusSystem.STAT_MAG), "hero MAG down")
	assert_false(StatusSystem.is_effectively_debuffed(hit, StatusSystem.STAT_DEF),
		"the hero's DEF is untouched — the two fields are independent")
	bm.free()
