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
