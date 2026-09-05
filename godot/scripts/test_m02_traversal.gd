extends SceneTree
## M02 数据塔真实走位验收：脚本机器人驱动真实游戏场景（game.tscn）里的玩家，
## 用与玩家脚本相同的 keys 输入走/跳/冲，从 @ 出生点逐路点走到 > 出口。
## BFS 只验证格子图可达；本测试验证"真实物理走位可过"（头顶碰撞/台阶链/门洞）。
##
## 跑法：godot --headless --path godot --script scripts/test_m02_traversal.gd
##
## 附带验收（本次 playtest 修复）：
##   - grunt 站立视觉高度 = 玩家视觉高度的 0.9~1.1 倍
##   - grunt 尸体最低像素贴地（与脚下地面顶面偏差 ≤4px）
##   - 玩家可读性层存在（Outline 描边 + Halo 背晕节点）

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
	CorridorLevel.active_map = CorridorLevel.MAP_M02_TOWER
	CorridorLevel.active_rooms = CorridorLevel.MAP_M02_TOWER_ROOMS
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {"name": "tower"}
	CorridorLevel.active_title = "M02 数据塔"
	GameBackground.active_cfg = GameBackground.CFG_TOWER_DIM
	var scene: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var level: CorridorLevel = scene.level
	var player: KairullPlayer = scene.player
	for i in range(3):
		await physics_frame

	print("== 敌我比例 / 尸体贴地 / 可读性层 ==")
	var g0: GruntGunner = scene.minions[0]
	var ratio: float = g0.standing_height() / player.visual_height()
	ok(ratio >= 0.9 and ratio <= 1.1,
		"grunt 站立高度为玩家的 0.9~1.1 倍",
		"grunt=%.1f player=%.1f ratio=%.3f" % [g0.standing_height(),
			player.visual_height(), ratio])

	# 尸体贴地：杀一只 grunt，尸体内容最低像素应落在脚下地面顶面 ±4px
	var g_corpse: GruntGunner = scene.minions[1]
	g_corpse.take_hit(g_corpse.position.x, 1)
	var floor_top := -1.0
	for dy in range(0, 96):
		if level.solid_at(g_corpse.position.x, g_corpse.position.y + dy + 1.0):
			floor_top = floori((g_corpse.position.y + dy + 1.0) / 32.0) * 32.0
			break
	ok(floor_top > 0.0, "尸体脚下找到地面", str(g_corpse.position))
	# 内容锚定后尸体最低像素世界 y = position.y（脚底）；与地面顶面比
	var corpse_bottom := g_corpse.position.y
	ok(absf(corpse_bottom - floor_top) <= 4.0,
		"尸体最低像素贴地（≤4px）",
		"corpse_bottom=%.1f floor_top=%.1f" % [corpse_bottom, floor_top])
	# 尸体归一化（round3）：横躺 sprawl 独立缩放，最长边 ≈ 站立身高、≤105px，
	# 不得比活体更占画面；亮青轮廓光是活体可读性辅助，尸体摘掉
	ok(g_corpse.corpse_extent() <= 105.0,
		"尸体最长边 ≤105px（≈站立身高 96px）",
		"extent=%.1f" % g_corpse.corpse_extent())
	ok(g_corpse.corpse_extent() >= 80.0,
		"尸体最长边 ≥80px（不缩没）", "extent=%.1f" % g_corpse.corpse_extent())
	ok(not g_corpse._rim.visible, "尸体摘掉亮青轮廓光（rim 只给活体威胁）")
	ok(g_corpse._shadow.scale == GruntGunner.CORPSE_SHADOW_SCALE,
		"尸体接触阴影跟随横躺宽度", str(g_corpse._shadow.scale))
	ok(g_corpse._sprite.scale.x < GruntGunner.SCALE,
		"尸体缩放独立于站姿 SCALE 且更小", str(g_corpse._sprite.scale))

	ok(player._outline != null and player._halo != null,
		"玩家可读性层存在（Outline 描边 + Halo 背晕）")
	ok(player._shadow != null and player._shadow.texture != null,
		"玩家接触阴影存在（ContactShadow）")
	ok(g0._rim != null and (g0._rim.material as ShaderMaterial) != null,
		"grunt 轮廓光存在（Rim shader 亮青边环）")
	ok(g0._shadow != null and g0._shadow.texture != null,
		"grunt 接触阴影存在（ContactShadow）")
	ok(g0._shadow.get_index() < g0._outline.get_index()
			and g0._outline.get_index() < g0._sprite.get_index()
			and g0._sprite.get_index() < g0._rim.get_index(),
		"grunt 图层序：阴影 < 描边 < 本体 < 轮廓光")
	player.step(1.0 / 60.0)
	ok(player._outline.visible and player._outline.texture != null,
		"描边剪影跟随本体帧")
	ok(player._halo.visible, "背晕存活时可见")
	ok(player._outline.get_index() < player._sprite.get_index(),
		"描边绘制在本体之下")

	print("== 机器人走位：@ → > 全图穿越 ==")
	# 清场：本测试只验地形可达性，不验战斗；杀光 grunt 门全部解锁
	for m in scene.minions:
		if is_instance_valid(m) and not m.dead:
			m.take_hit(m.position.x, 1)
	for i in range(3):
		await physics_frame
	var all_unlocked := true
	for d in scene.doors:
		if d.locked:
			all_unlocked = false
	ok(all_unlocked, "清场后 5 门全部解锁")

	# 路点（脚底世界坐标）：大堂→事务所→楼梯间A→竖井→F2→楼梯间B→竖井→F3→塔心
	var route: Array[Vector2] = [
		Vector2(30 * 32 + 16, 25 * 32 - 0.1),    # 大堂中段
		Vector2(40 * 32 + 16, 25 * 32 - 0.1),    # 大堂门 D c40
		Vector2(55 * 32 + 16, 25 * 32 - 0.1),    # 事务所中段
		Vector2(80 * 32 + 16, 25 * 32 - 0.1),    # 事务所门 D c80
		Vector2(120 * 32 + 16, 25 * 32 - 0.1),   # 楼梯间A 地面
		Vector2(125 * 32 + 16, 23 * 32 - 0.1),   # 台阶A顶（feet r22）
		Vector2(129 * 32 + 16, 21 * 32 - 0.1),   # 台阶B顶（feet r20）
		Vector2(132 * 32 + 16, 19 * 32 - 0.1),   # 台阶C顶（feet r18，井口下）
		Vector2(132 * 32 + 16, 16 * 32 - 0.1),   # 竖井 = 台（feet r15）
		Vector2(100 * 32 + 16, 16 * 32 - 0.1),   # F2 服务器厅
		Vector2(72 * 32 + 16, 16 * 32 - 0.1),    # 服务器厅门 D c72
		Vector2(50 * 32 + 16, 16 * 32 - 0.1),    # 休息室
		Vector2(31 * 32 + 16, 16 * 32 - 0.1),    # 休息室门 D c31
		Vector2(29 * 32 + 16, 16 * 32 - 0.1),    # 楼梯间B 地面
		Vector2(26 * 32 + 16, 14 * 32 - 0.1),    # 台阶A顶（feet r13）
		Vector2(23 * 32 + 16, 12 * 32 - 0.1),    # 台阶B顶（feet r11）
		Vector2(20 * 32 + 16, 10 * 32 - 0.1),    # 台阶C顶（feet r9，井口下）
		Vector2(21 * 32 + 16, 8 * 32 - 0.1),     # 竖井 = 台（feet r7，F3）
		Vector2(50 * 32 + 16, 8 * 32 - 0.1),     # 核心前厅
		Vector2(70 * 32 + 16, 8 * 32 - 0.1),     # 前厅门 D c70
		Vector2(120 * 32 + 16, 8 * 32 - 0.1),    # 塔心
		Vector2(135 * 32 + 16, 8 * 32 - 0.1),    # 出口 >
	]

	player.auto_input = false   ## 输入由机器人注入 keys，步进手动调
	player.reset_to_spawn()
	var stuck_report := ""
	var total_frames := 0
	for wi in route.size():
		var target: Vector2 = route[wi]
		var reached := false
		var last_x: float = player.position.x
		var stall := 0
		var jumps := 0
		var jump_cd := 0
		for f in range(900):   ## 单路点预算 15s@60fps
			total_frames += 1
			var pos: Vector2 = player.position
			var dx: float = target.x - pos.x
			var dy: float = target.y - pos.y
			# 路点全在爬升方向上：水平到位且不矮于目标即算到达
			# （上升跳可能一鼓作气穿过井口直接落到上一层，dy 会冲过目标）
			if absf(dx) <= 10.0 and pos.y <= target.y + 18.0:
				reached = true
				break
			player.keys.clear()
			if dx > 6.0:
				player.keys[KEY_D] = true
			elif dx < -6.0:
				player.keys[KEY_A] = true
			jump_cd = maxi(0, jump_cd - 1)
			# 跳：目标在上方且已贴近 / 水平被卡住
			var want_up: bool = dy < -24.0 and absf(dx) < 56.0
			if absf(pos.x - last_x) < 2.0 and absf(dx) > 6.0 and player.on_ground:
				stall += 1
			else:
				stall = 0
			last_x = pos.x
			if player.on_ground and jump_cd == 0 \
					and (want_up or stall >= 22):
				player.keys[KEY_W] = true
				jump_cd = 22
				jumps += 1
				stall = 0
			elif jumps >= 3 and stall >= 30 and player.on_ground \
					and player.dash_cooldown_t <= 0.0:
				player.keys[KEY_SHIFT] = true   ## 跳不过就试冲刺
				stall = 0
			player.step(1.0 / 60.0)
			await physics_frame
		var cell := Vector2i(floori(player.position.x / 32.0),
				floori(player.position.y / 32.0))
		if reached:
			print("  PASS  路点 %2d -> c%d r%d（%d 帧累计）" % [wi,
					cell.x, cell.y, total_frames])
			_pass += 1
		else:
			_fail += 1
			var msg := "路点 %d 卡住：目标(%.0f,%.0f) 实到(%.0f,%.0f) c%d r%d" % [
					wi, target.x, target.y, player.position.x,
					player.position.y, cell.x, cell.y]
			print("  FAIL  ", msg)
			stuck_report = msg
			break   ## 第一处卡点就是 playtest 报告的堵点，停在这里便于诊断

	if stuck_report.is_empty():
		for i in range(30):   ## 让 game 的出口判定跑几帧
			await physics_frame
		ok(scene.level_cleared, "触碰出口过关（level_cleared）")
	else:
		ok(false, "全程走完", stuck_report)

	# 清理静态配置（与其他测试一致）
	scene.queue_free()
	await process_frame
	CorridorLevel.active_map = ""
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_title = ""
	GameBackground.active_cfg = []

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
