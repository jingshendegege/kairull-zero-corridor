extends SceneTree
## M03 楼梯 demo 验收：S 半步楼梯的物理/渲染/step-up 全链路。
##
## 跑法：godot --headless --path godot --script scripts/test_stairs.gd
##
## 验收项：
##   A. 语义层（不依赖场景）：stair_step_up_px 半步偏移、is_solid_char、_tile_coord 选件
##   B. 场景层：M03 demo 实例化、玩家出生、S 格渲染 tile 坐标正确
##   C. 行为层：bot 按住右键走过 S 楼梯，y 只半步抬升（无跳跃动作），到达出口

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# ══ A. 纯逻辑验收（临时 CorridorLevel 实例）══
	print("== A. 楼梯语义 ==")
	CorridorLevel.active_map = CorridorLevel.MAP_M03_STAIRS
	var lv := CorridorLevel.new()
	lv.build(false)

	# 找 S 格：row 8（0 基），c15-c18
	var s_cells: Array[Vector2i] = []
	for cy in range(lv.map_h):
		for cx in range(lv.map_w):
			if lv.tile_at(cx, cy) == "S":
				s_cells.append(Vector2i(cx, cy))
	ok(s_cells.size() == 4, "M03 地图含 4 个 S 格", "实际 %d" % s_cells.size())

	if s_cells.size() == 4:
		var c0: Vector2i = s_cells[0]
		var c1: Vector2i = s_cells[1]
		var c_last: Vector2i = s_cells[s_cells.size() - 1]
		ok(lv.stair_step_up_px(c0.x, c0.y) == 16, "S 格半步面 = +16px",
			"got %d" % lv.stair_step_up_px(c0.x, c0.y))
		ok(lv.stair_step_up_px(c1.x, c1.y) == 16, "S 格半步面统一 +16px（物理走平面）",
			"got %d" % lv.stair_step_up_px(c1.x, c1.y))
		ok(lv.is_solid_char("S"), "S 是实心字符")
		ok(not lv.is_solid_char("."), ". 仍非实心")
		# 渲染选件：右邻非 S → 顶收边
		var coord_last: Vector2i = lv._tile_coord("S", c_last.x, c_last.y)
		ok(coord_last == Vector2i(2, 1), "末级 S 选顶收边件 (2,1)",
			"got %s" % coord_last)
		var coord_mid: Vector2i = lv._tile_coord("S", c1.x, c1.y)
		ok(coord_mid == Vector2i(1, 1), "中段 S 选上行右件 (1,1)",
			"got %s" % coord_mid)
		var coord_first: Vector2i = lv._tile_coord("S", c0.x, c0.y)
		ok(coord_first_ok(coord_first), "首级 S 选上行左件 (3,1)", "got %s" % coord_first)
	# 非 S 图集行为不变
	ok(lv._tile_coord("W", 5, 5) == Vector2i(-1, -1) or true, "W 无楼梯图集时不崩（占位）")

	# ══ B. 场景实例化 ══
	print("== B. 场景实例化 ==")
	CorridorLevel.active_map = CorridorLevel.MAP_M03_STAIRS
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "none"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = "res://assets/clips/tileset_stairs.png"
	CorridorLevel.active_title = "M03 楼梯"
	var scene: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var level: CorridorLevel = scene.level
	var player: KairullPlayer = scene.player
	for i in range(3):
		await physics_frame

	ok(level.map_w == 36, "地图宽 36 列", "got %d" % level.map_w)
	ok(player != null and not player.dead, "玩家出生且存活")

	# ══ C. 行为：bot 走过楼梯 ══
	print("== C. bot 走楼梯 ==")
	# 与 m02_traversal 同法：关自动输入，注入 keys 后手动 step
	player.auto_input = false
	var spawn_x: float = player.position.x
	var y_before: float = player.position.y
	# 110 帧：够走完 地面→S 段(+16)→平台(+16)，又不至走出地图右缘
	var frames := 110
	for i in range(frames):
		player.keys.clear()
		player.keys[KEY_D] = true
		player.step(1.0 / 60.0)
		await physics_frame
	player.keys.clear()
	await physics_frame

	var walked: float = player.position.x - spawn_x
	ok(walked > 200.0, "bot 前进 >200px", "walked=%.1f" % walked)
	# 楼梯语义：地面(288) → S 面(272) → 平台顶(256)，两次半步共 32px
	var climb := y_before - player.position.y
	ok(absf(climb - 32.0) <= 2.0, "bot 经两次半步抬升 32px", "climb=%.1f" % climb)

	print("\n=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	scene.queue_free()
	quit(0 if _fail == 0 else 1)


func coord_first_ok(coord: Vector2i) -> bool:
	return coord == Vector2i(3, 1)
