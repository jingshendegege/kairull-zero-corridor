extends SceneTree
## M03 取件关无头单测：K/U marker 解析、拾取件刷点、取件闸门分支。
## 跑法：godot --headless --path godot --script scripts/test_m03_pickup.gd
## 注：拾取距离判定/出口触发属帧循环行为，由真窗验收与后续 bot 覆盖。

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _restore() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_stair_material = "stone"
	CorridorLevel.active_exit_requires_usb = false


func _init() -> void:
	print("== M03 取件关 ==")
	CorridorLevel.active_map = CorridorLevel.MAP_M03_BACKROOM
	CorridorLevel.active_rooms = CorridorLevel.MAP_M03_BACKROOM_ROOMS
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_tile_style = {"name": "tower"}
	CorridorLevel.active_stair_material = "stone"
	CorridorLevel.active_exit_requires_usb = true

	# 1. 地图解析
	var level := CorridorLevel.new()
	level.build(false)
	ok(level.map_w == 160 and level.map_h == 28, "M03 地图 160×28",
			"%dx%d" % [level.map_w, level.map_h])

	# 2. K/U 刷点 → prop_spawns（3 录音带 + 1 USB + 2 桶 + 2 CRT）
	var kinds := {}
	for ps in level.prop_spawns:
		kinds[ps["kind"]] = int(kinds.get(ps["kind"], 0)) + 1
	ok(int(kinds.get("tape", 0)) == 3, "3 条录音带刷点", str(kinds))
	ok(int(kinds.get("usb", 0)) == 1, "1 个 USB 刷点", str(kinds))
	ok(int(kinds.get("barrel", 0)) == 2, "2 只爆炸桶（储藏间）", str(kinds))
	ok(int(kinds.get("crt", 0)) == 3, "3 台 CRT（门厅 1 + 监控室 2）", str(kinds))

	# 3. marker 已从网格擦除（K/U 不参与渲染/碰撞）
	var leftover := 0
	for r in level.map_h:
		for c in level.map_w:
			var ch: String = level.tile_at(c, r)
			if ch == "K" or ch == "U":
				leftover += 1
	ok(leftover == 0, "K/U 已从网格擦除")

	# 3.5 可破金属墙（b）：实心、4 发打穿整组
	var wall_cell := Vector2i(123, 16)
	ok(level.tile_at(wall_cell.x, wall_cell.y) == "b", "密室墙为可破 b 格")
	ok(level.solid_at(wall_cell.x * 32 + 16, wall_cell.y * 32 + 16), "墙格实心")
	var broke := false
	for i in 4:
		broke = level.damage_wall(wall_cell.x * 32 + 16, wall_cell.y * 32 + 16)
	ok(broke, "4 发子弹打穿墙组")
	ok(level.tile_at(wall_cell.x, wall_cell.y) == ".", "墙组移除后变空气")
	ok(not level.solid_at(wall_cell.x * 32 + 16, wall_cell.y * 32 + 16),
			"墙格不再阻挡")

	# 3.5 精英刷点：X（密室狙击）
	ok(level.elite_spawns.size() == 1, "1 个精英刷点（密室狙击）",
			str(level.elite_spawns))

	# 4. 楼梯与出口结构
	var s_count := 0
	for r in level.map_h:
		for c in level.map_w:
			if level.tile_at(c, r) == "S":
				s_count += 1
	ok(s_count == 12, "两处楼梯井共 12 个 S 格（各 6 级）", str(s_count))
	ok(level.exit_point != Vector2.ZERO, "出口 > 解析")
	ok(level.spawn != Vector2.ZERO, "出生 @ 解析")

	# 5. 楼梯材质行：stone 默认 Row 1 / wood Row 2 / metal Row 3
	ok(level._stair_material_row() == 1, "stone → Row 1")
	CorridorLevel.active_stair_material = "wood"
	ok(level._stair_material_row() == 2, "wood → Row 2")
	CorridorLevel.active_stair_material = "metal"
	ok(level._stair_material_row() == 3, "metal → Row 3")
	CorridorLevel.active_stair_material = "stone"

	# 6. 取件闸门分支（game 不进树，纯逻辑）
	var game: Node2D = load("res://scripts/game.gd").new()
	game.usb_taken = false
	ok(game._exit_gated(), "USB 未取 → 闸门锁定")
	game.usb_taken = true
	ok(not game._exit_gated(), "USB 入手 → 闸门放行")
	game.free()

	_restore()
	print("\n=== M03 取件关: %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(1 if _fail > 0 else 0)
