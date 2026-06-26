extends TestSuite

## RoamerTerritory (P7p2): drawable polygon roamer territories — the node's
## polygon helpers, RoamingEnemy's polygon containment/clamping, and the
## migrated territory nodes in the overworld scenes.

func suite_name() -> String:
	return "RoamerTerritory"

func _territory(poly: PackedVector2Array, pos := Vector2.ZERO) -> RoamerTerritory:
	var t := RoamerTerritory.new()
	t.position = pos
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	t.add_child(cp)
	return t

func _square(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])

# --- RoamerTerritory node ------------------------------------------------------
func test_defaults() -> void:
	var t := RoamerTerritory.new()
	assert_eq(t.group, null, "group defaults null (weighted pick)")
	assert_eq(t.world_polygon().size(), 0, "no polygon child -> empty")
	t.free()

func test_world_polygon_respects_offset() -> void:
	var t := _territory(_square(0, 0, 200, 100), Vector2(1000, 500))
	var poly := t.world_polygon()
	assert_eq(poly.size(), 4, "polygon mirrored")
	assert_eq(poly[0], Vector2(1000, 500), "offset applied to world points")
	assert_eq(poly[2], Vector2(1200, 600), "offset applied to far corner")
	t.free()

func test_centroid_and_bounding_rect() -> void:
	var sq := _square(100, 100, 200, 200)
	assert_eq(RoamerTerritory.centroid(sq), Vector2(200, 200), "centroid of a square is its center")
	assert_eq(RoamerTerritory.bounding_rect(sq), Rect2(100, 100, 200, 200), "bounding rect matches")

# --- RoamingEnemy polygon territory --------------------------------------------
func _triangle() -> PackedVector2Array:
	# Right triangle: (0,0) (400,0) (0,400) — point (300,300) is OUTSIDE it.
	return PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(0, 400)])

func test_polygon_territory_containment() -> void:
	var r := RoamingEnemy.new()
	r.setup(1, null, 0, null, Rect2(), _triangle())
	var inside := Node2D.new()
	inside.global_position = Vector2(50, 50)
	r._player = inside
	assert_true(r._player_in_territory(), "player inside the triangle is tracked")
	var outside := Node2D.new()
	# Inside the bounding box but OUTSIDE the triangle — a rect would wrongly track this.
	outside.global_position = Vector2(300, 300)
	r._player = outside
	assert_false(r._player_in_territory(), "player in bbox but outside polygon is NOT tracked")
	inside.free()
	outside.free()
	r.free()

func test_polygon_clamp_keeps_enemy_inside() -> void:
	var r := RoamingEnemy.new()
	r.setup(1, null, 0, null, Rect2(), _triangle())
	assert_eq(r._clamp_to_home(Vector2(100, 100)), Vector2(100, 100), "inside point unchanged")
	var clamped: Vector2 = r._clamp_to_home(Vector2(500, 500))
	assert_true(Geometry2D.is_point_in_polygon(clamped, r.home_polygon),
		"outside point snaps back inside the polygon")
	r.free()

func test_polygon_sets_bounding_home_rect() -> void:
	var r := RoamingEnemy.new()
	r.setup(1, null, 0, null, Rect2(), _triangle())
	assert_eq(r.home_rect, Rect2(0, 0, 400, 400), "home_rect becomes the polygon's bbox")
	r.free()

func test_rect_territory_still_works() -> void:
	# Legacy path: no polygon — rect containment/clamping unchanged.
	var r := RoamingEnemy.new()
	r.setup(1, null, 0, null, Rect2(1000, 1000, 400, 400))
	var p := Node2D.new()
	p.global_position = Vector2(1200, 1200)
	r._player = p
	assert_true(r._player_in_territory(), "rect territory still tracks")
	assert_eq(r._clamp_to_home(Vector2(300, 300)).x, 1015.0, "rect clamp still insets by half size")
	p.free()
	r.free()

# --- Migrated scene territories -------------------------------------------------
func test_plains_scene_has_territories() -> void:
	# The exact count is map content (the user authors these); the contract is
	# that territories exist and every one has a drawable polygon.
	var scene: Node = (load("res://scenes/OverworldScene.tscn") as PackedScene).instantiate()
	var holder: Node = scene.get_node_or_null("RoamerTerritories")
	assert_ne(holder, null, "plains scene has a RoamerTerritories node")
	if holder != null:
		var count := 0
		for c in holder.get_children():
			if c is RoamerTerritory:
				count += 1
				assert_true((c as RoamerTerritory).world_polygon().size() >= 3,
					"%s has a drawable polygon" % c.name)
		assert_true(count >= 1, "plains has at least one roamer territory (got %d)" % count)
	scene.free()

func test_mountain_pass_has_territories() -> void:
	var scene: Node = (load("res://scenes/MountainPass.tscn") as PackedScene).instantiate()
	var holder: Node = scene.get_node_or_null("RoamerTerritories")
	assert_ne(holder, null, "mountain pass has a RoamerTerritories node")
	if holder != null:
		assert_eq(holder.get_child_count(), 2, "mountain pass has 2 territories")
	scene.free()
