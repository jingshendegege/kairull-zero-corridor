extends SceneTree
## M01 旧城区霓虹街无头单测：地图解析 / 标记提取 / 跳跃物理烟测 /
## grunt 刷怪分支（每个 x 一只 GruntGunner）/ 一击必杀 / Boss "none" 分支。
## 跑法：godot --headless --path godot --script scripts/test_m01_level.gd

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


## 站立格：自身非实心、脚下 1 格实心（与网页版 solidAt 同语义）
func _is_stand(lv: CorridorLevel, c: int, r: int) -> bool:
	return not lv.is_solid_char(lv.tile_at(c, r)) \
		and lv.is_solid_char(lv.tile_at(c, r + 1))


func _run() -> void:
	print("== M01 地图解析 ==")
	CorridorLevel.active_map = CorridorLevel.MAP_M01_NEON
	var level := CorridorLevel.new()
	level.build(false)
	ok(level.map_h == 24, "地图 24 行", str(level.map_h))
	ok(level.map_w == 192, "地图 192 列", str(level.map_w))
	var uniform := true
	for row in level.grid:
		if row.length() != level.map_w:
			uniform = false
	ok(uniform, "各行宽度一致")

	print("== 标记提取 ==")
	ok(level.spawn == Vector2(4 * 32 + 16, 19 * 32 - 0.1), "出生点 @ c4 r18",
		str(level.spawn))
	ok(level.exit_point == Vector2(187 * 32 + 16, 19 * 32 - 0.1), "出口 > c187 r18",
		str(level.exit_point))
	ok(level.enemy_spawns.size() == 12, "12 个敌人刷点", str(level.enemy_spawns.size()))
	var in_bounds := true
	for sp in level.enemy_spawns:
		if sp.x < 32 or sp.x > (level.map_w - 1) * 32 or sp.y < 0 or sp.y > level.world_h:
			in_bounds = false
	ok(in_bounds and level.spawn.x < level.exit_point.x, "标记均在界内且出生在出口左侧")

	print("== 道具标记 B/T 解析 ==")
	var barrels: Array = []
	var crts: Array = []
	for ps in level.prop_spawns:
		if ps["kind"] == "barrel":
			barrels.append(ps["pos"])
		elif ps["kind"] == "crt":
			crts.append(ps["pos"])
	ok(level.prop_spawns.size() == 7, "7 个道具刷点", str(level.prop_spawns.size()))
	ok(barrels.size() == 4, "4 个爆炸桶 B", str(barrels.size()))
	ok(crts.size() == 3, "3 个 CRT T", str(crts.size()))
	var b_cols := []
	for bp in barrels:
		b_cols.append(floori(bp.x / 32.0))
	b_cols.sort()
	ok(b_cols == [24, 99, 101, 165], "桶位于 c24/c99/c101/c165", str(b_cols))
	var c_cols := []
	for cp in crts:
		c_cols.append(floori(cp.x / 32.0))
	c_cols.sort()
	ok(c_cols == [13, 59, 172], "CRT 位于 c13/c59/c172", str(c_cols))
	# 标记已抹成空格（不参与碰撞/渲染）
	var erased := true
	for ps in level.prop_spawns:
		var pc := floori(ps["pos"].x / 32.0)
		var pr := floori((ps["pos"].y + 0.2) / 32.0) - 1
		if level.tile_at(pc, pr) != ".":
			erased = false
			print("    未抹除: c%d r%d -> %s" % [pc, pr, level.tile_at(pc, pr)])
	ok(erased, "B/T 标记解析后从网格抹除")

	print("== 刷点脚下有地面 ==")
	var all_floored := true
	for sp in level.enemy_spawns:
		var c := floori(sp.x / 32.0)
		var r := floori(sp.y / 32.0)
		var found := false
		for dr in range(1, 4):
			if level.is_solid_char(level.tile_at(c, r + dr)):
				found = true
				break
		if not found:
			all_floored = false
			print("    无地面刷点: c%d r%d" % [c, r])
	ok(all_floored, "每个 x 脚下 3 格内有地面")

	print("== 主地面路线缺口 ==")
	var run := 0
	var maxrun := 0
	for c in level.map_w:
		if level.is_solid_char(level.tile_at(c, 19)):
			run = 0
		else:
			run += 1
			maxrun = maxi(maxrun, run)
	ok(maxrun <= 5, "地面缺口 ≤5 格（满速跳 5.8 格可过）", "maxgap=%d" % maxrun)

	print("== 跳跃图可达性烟测（rise≤3）==")
	# BFS：站立格之间按实测跳跃预算连边（rise 3 横移≤3；rise 2 ≤5；rise 1 ≤6；
	# 平走/下落 ≤8）。出生点出发，出口与全部刷点必须可达。
	var start := Vector2i(4, 18)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		for c2 in range(maxi(0, p.x - 8), mini(level.map_w, p.x + 9)):
			for r2 in range(maxi(0, p.y - 3), mini(level.map_h, p.y + 20)):
				var q := Vector2i(c2, r2)
				if seen.has(q) or not _is_stand(level, c2, r2):
					continue
				var rise: int = p.y - r2
				var dc: int = absi(c2 - p.x)
				if rise >= 0:
					var budget: int = {0: 8, 1: 6, 2: 5, 3: 3}.get(rise, -1)
					if dc > budget:
						continue
				elif dc > 8:
					continue
				seen[q] = true
				queue.append(q)
	ok(seen.has(Vector2i(187, 18)), "出口可达")
	var all_reach := true
	for sp in level.enemy_spawns:
		var cell := Vector2i(floori(sp.x / 32.0), floori(sp.y / 32.0))
		if not seen.has(cell):
			all_reach = false
			print("    不可达刷点: ", cell)
	ok(all_reach, "全部 12 个刷点可达")

	print("== grunt 刷怪分支（游戏场景实例化）==")
	CorridorLevel.active_hide_rows_from = 19
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {"name": "neon"}
	GameBackground.active_cfg = GameBackground.CFG_M01_NEON
	var scene: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	ok(scene.minions.size() == level.enemy_spawns.size(),
		"每个 x 刷一只小怪", "%d/%d" % [scene.minions.size(), level.enemy_spawns.size()])
	var all_grunt := true
	var pos_match := true
	for i in scene.minions.size():
		var m: Node2D = scene.minions[i]
		if not m is GruntGunner:
			all_grunt = false
		if m.position != level.enemy_spawns[i]:
			pos_match = false
	ok(all_grunt, "小怪全部是 GruntGunner")
	ok(pos_match, "小怪位置与 x 刷点一一对应")
	ok(scene.red_boss == null, "active_boss=\"none\" 不刷 Boss")

	print("== grunt 一击必杀 ==")
	var g := GruntGunner.new()
	get_root().add_child(g)
	g.position = Vector2(500, 19 * 32 - 0.1)
	ok(not g.dead and g.state == "idle", "出生存活 idle")
	var lethal: bool = g.take_hit(g.position.x, 1)
	ok(lethal and g.dead and g.state == "dead", "单次 take_hit 即死")
	ok(not g.take_hit(g.position.x, 1), "尸体不再响应命中")
	g.queue_free()

	print("== 道具注册进游戏场景 ==")
	ok(scene.props.size() == 7, "游戏场景生成 7 个道具", str(scene.props.size()))
	var n_barrel := 0
	var n_crt := 0
	for pr in scene.props:
		if pr is PropBarrel:
			n_barrel += 1
		elif pr is PropCrt:
			n_crt += 1
	ok(n_barrel == 4 and n_crt == 3, "4 桶 + 3 CRT", "%d/%d" % [n_barrel, n_crt])
	ok(scene.exit_door != null, "出口门节点已生成")

	print("== 爆炸桶：一击引爆 + 半径清怪 + 连锁 ==")
	# 测试专用布置：桶1 与桶2 相距 80px（<110 连锁半径），小怪夹在中间
	var gy := 19.0 * 32 - 0.1
	var tg: Node2D = scene.minions[0]
	tg.position = Vector2(5080, gy)
	var b1: PropBarrel = scene._spawn_prop("barrel", Vector2(5040, gy))
	var b2: PropBarrel = scene._spawn_prop("barrel", Vector2(5120, gy))
	ok(not b1.dead and not b1.fusing, "桶出生存活未引爆")
	ok(b1.take_hit(b1.position.x, 1) and b1.fusing, "桶受击进入引信")
	ok(not b1.take_hit(b1.position.x, 1), "引信中不再响应命中")
	# 推进物理帧：0.35s 引信 + 0.10s 连锁引信 ≈ 27 tick，给足 50
	for i in range(50):
		await physics_frame
	ok(b1.dead, "桶1 引信结束爆炸")
	ok(b2.dead, "桶2 被连锁引爆")
	ok(tg.dead, "半径内小怪被炸死")
	var survivors := 0
	for mn in scene.minions:
		if is_instance_valid(mn) and not mn.dead:
			survivors += 1
	ok(survivors == 11, "半径外小怪不受影响", str(survivors))

	print("== CRT：一击即碎 ==")
	var crt: PropCrt = scene._spawn_prop("crt", Vector2(5200, gy))
	ok(crt.take_hit(crt.position.x, 1) and crt.dead, "CRT 单次 take_hit 即碎")
	ok(not crt.take_hit(crt.position.x, 1), "碎后不再响应命中")
	for i in range(3):
		await physics_frame

	print("== 棍击判定盒覆盖道具 ==")
	var b3: PropBarrel = scene._spawn_prop("barrel", Vector2(5300, gy))
	var hitbox := Rect2(5300 - 38, gy - 60, 76, 56)
	scene._on_player_bat_swung(hitbox, 0)
	ok(b3.fusing, "桶被棍击判定盒点着引信")
	var crt2: PropCrt = scene._spawn_prop("crt", Vector2(5400, gy))
	scene._on_player_bat_swung(Rect2(5400 - 38, gy - 60, 76, 56), 0)
	ok(crt2.dead, "CRT 被棍击判定盒击碎")
	var b_far: PropBarrel = scene._spawn_prop("barrel", Vector2(5600, gy))
	scene._on_player_bat_swung(Rect2(5300 - 38, gy - 60, 76, 56), 1)
	ok(not b_far.fusing and not b_far.dead, "判定盒外的桶不受影响")

	print("== 出口重叠过关 ==")
	ok(not scene.level_cleared, "初始未过关")
	scene.player.position = level.exit_point
	await physics_frame
	await physics_frame
	ok(scene.level_cleared, "玩家触碰出口置过关态")
	scene.player.position = level.spawn

	scene.queue_free()
	await process_frame
	CorridorLevel.active_map = ""
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	GameBackground.active_cfg = []

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
