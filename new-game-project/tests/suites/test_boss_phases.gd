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
	b.phases[1].stat_multipliers = {"attack": 2.0}
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
	b.phases[1].stat_multipliers = {"defense": 2.0, "magic": 2.0, "arcane": 2.0, "speed": 2.0}
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
	b.phases[1].stat_multipliers = {"attack": 2.0}
	b.phases[2].stat_multipliers = {"speed": 2.0}
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
