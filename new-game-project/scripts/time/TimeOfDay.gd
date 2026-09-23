class_name TimeOfDay
extends RefCounted

## TimeOfDay — the game's in-world clock (held by GameManager). A scaled clock that
## advances while exploring and is paused during battles / menus / cutscenes (the
## gating lives in GameManager). Pure + testable: no nodes here.
##
## A full game day is 1440 minutes (00:00–24:00). Four phases by time-of-day, plus a
## smooth lighting tint (a CanvasModulate colour) and clock-face text.

enum Phase { DAWN, DAY, DUSK, NIGHT }

# Real-time pacing: how many real seconds make up one in-game hour. Lower = faster
# day/night cycle. 30s/hour => a full day is 12 real minutes (tune to taste).
const REAL_SECONDS_PER_GAME_HOUR := 30.0
const GAME_MINUTES_PER_REAL_SECOND := 60.0 / REAL_SECONDS_PER_GAME_HOUR

const MINUTES_PER_DAY := 1440.0
const START_MINUTES := 480.0   # new games begin at 08:00 (early Day)

# Phase boundaries (minutes since midnight).
const DAWN_START := 300.0    # 05:00
const DAY_START := 480.0     # 08:00
const DUSK_START := 1020.0   # 17:00
const NIGHT_START := 1200.0  # 20:00

# Lighting keyframes for the CanvasModulate, interpolated across the day for a
# smooth night -> dawn -> day -> dusk -> night cycle.
const TINT_KEYS := [
	[0.0, Color(0.42, 0.46, 0.72)],     # deep night
	[DAWN_START, Color(0.45, 0.47, 0.70)],
	[420.0, Color(1.00, 0.80, 0.72)],   # 07:00 dawn glow
	[DAY_START, Color(1.0, 1.0, 1.0)],  # full daylight (neutral)
	[DUSK_START, Color(1.0, 1.0, 1.0)],
	[1140.0, Color(0.97, 0.66, 0.55)],  # 19:00 dusk glow
	[NIGHT_START, Color(0.42, 0.46, 0.72)],
	[MINUTES_PER_DAY, Color(0.42, 0.46, 0.72)],
]

var minutes: float = START_MINUTES

func advance_real(delta_seconds: float) -> void:
	minutes = fposmod(minutes + delta_seconds * GAME_MINUTES_PER_REAL_SECOND, MINUTES_PER_DAY)

## The clock reading a phase begins at.
static func phase_start_minutes(p: int) -> float:
	match p:
		Phase.DAWN: return DAWN_START
		Phase.DAY: return DAY_START
		Phase.DUSK: return DUSK_START
		Phase.NIGHT: return NIGHT_START
	return DAY_START

## Winds the clock FORWARD to the start of a phase, rolling into tomorrow when
## that time has already passed today — resting until dawn at 10pm should land
## on the coming dawn, not rewind eleven hours.
func advance_to_phase(p: int) -> float:
	var target := phase_start_minutes(p)
	var elapsed := target - minutes
	if elapsed <= 0.0:
		elapsed += MINUTES_PER_DAY
	minutes = fposmod(target, MINUTES_PER_DAY)
	return elapsed

func set_minutes(m: float) -> void:
	minutes = fposmod(m, MINUTES_PER_DAY)

func phase() -> int:
	if minutes < DAWN_START or minutes >= NIGHT_START:
		return Phase.NIGHT
	elif minutes < DAY_START:
		return Phase.DAWN
	elif minutes < DUSK_START:
		return Phase.DAY
	return Phase.DUSK

func phase_name() -> String:
	match phase():
		Phase.DAWN: return "Dawn"
		Phase.DAY: return "Day"
		Phase.DUSK: return "Dusk"
		Phase.NIGHT: return "Night"
	return "Day"

# A 12-hour clock string, e.g. "1:24 PM".
func clock_text() -> String:
	var h := int(minutes / 60.0) % 24
	var m := int(minutes) % 60
	var ampm := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, ampm]

# The current screen tint (multiplied over the world via a CanvasModulate).
func tint() -> Color:
	for i in range(TINT_KEYS.size() - 1):
		var a: Array = TINT_KEYS[i]
		var b: Array = TINT_KEYS[i + 1]
		if minutes >= float(a[0]) and minutes <= float(b[0]):
			var span: float = maxf(float(b[0]) - float(a[0]), 0.001)
			return (a[1] as Color).lerp(b[1], (minutes - float(a[0])) / span)
	return TINT_KEYS[TINT_KEYS.size() - 1][1]

# Sun/moon accent colour for the clock widget, per phase.
func phase_color() -> Color:
	match phase():
		Phase.DAWN: return Color(1.0, 0.72, 0.42)
		Phase.DAY: return Color(1.0, 0.86, 0.35)
		Phase.DUSK: return Color(0.97, 0.55, 0.42)
		Phase.NIGHT: return Color(0.70, 0.78, 1.0)
	return Color.WHITE
