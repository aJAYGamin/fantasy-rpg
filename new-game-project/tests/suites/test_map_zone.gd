extends TestSuite

## MapZone (P7p2): drawable Area2D save / transition / no-spawn zones with polygon
## hit-testing. Covers the capability flags and world-space point containment
## (including a transformed/offset zone).

func suite_name() -> String:
	return "MapZone"

func _zone(poly: PackedVector2Array, pos := Vector2.ZERO) -> MapZone:
	var z := MapZone.new()
	z.position = pos
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	z.add_child(cp)
	return z

func _square(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])

func test_defaults() -> void:
	var z := MapZone.new()
	assert_false(z.is_transition(), "blank zone is not a transition")
	assert_false(z.save_on_enter, "save_on_enter defaults false")
	assert_false(z.suppress_spawns, "suppress_spawns defaults false")
	assert_false(z.return_to_origin, "return_to_origin defaults false")
	z.free()

func test_is_transition_via_target_scene() -> void:
	var z := MapZone.new()
	z.target_scene = "res://scenes/MountainPass.tscn"
	assert_true(z.is_transition(), "a target_scene makes the zone a transition")
	z.free()

func test_is_transition_via_return_to_origin() -> void:
	var z := MapZone.new()
	z.return_to_origin = true
	assert_true(z.is_transition(), "return_to_origin makes the zone a transition")
	z.free()

func test_world_polygon_size() -> void:
	var z := _zone(_square(100, 100, 200, 200))
	assert_eq(z.world_polygon().size(), 4, "world polygon mirrors the CollisionPolygon2D")
	z.free()

func test_contains_point_basic() -> void:
	var z := _zone(_square(100, 100, 200, 200))   # spans 100..300
	assert_true(z.contains_point(Vector2(200, 200)), "point inside the polygon")
	assert_false(z.contains_point(Vector2(50, 50)), "point outside the polygon")
	z.free()

func test_contains_point_respects_offset() -> void:
	# Polygon authored at the local origin; the zone is offset, so the world shape moves.
	var z := _zone(_square(0, 0, 200, 200), Vector2(1000, 1000))
	assert_true(z.contains_point(Vector2(1100, 1100)), "inside the offset world shape")
	assert_false(z.contains_point(Vector2(100, 100)), "local-origin point is now outside")
	z.free()

func test_no_polygon_contains_nothing() -> void:
	var z := MapZone.new()   # no CollisionPolygon2D child
	assert_eq(z.world_polygon().size(), 0, "no polygon -> empty")
	assert_false(z.contains_point(Vector2.ZERO), "no polygon -> contains nothing")
	z.free()
