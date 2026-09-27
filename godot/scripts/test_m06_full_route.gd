extends SceneTree
## 04 排风脊线全关连通验收（Claude）：只用真实按键 + Player.step，从出生点沿"普通路线"走到出口。
## 不靠弹射扇、冲刺节点、冲刺连杀；唯一的特殊动作是翻滚撞碎挡路的检疫玻璃（翻滚是基础动作）。
## 机关伤害用无敌屏蔽，敌人 AI 不推进（只验证几何连通）；终局泵站把守敌判死后房门解锁放行。
## 跑法：godot --headless --path godot --script scripts/test_m06_full_route.gd
const SESSION := preload("res://scripts/run_session.gd")
const DT := 1.0 / 60.0
var game: Node2D
var player: KairullPlayer
var passed := 0
var failed := 0
var frames_used := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, "  feet=", player.position)


func tick(keys: Dictionary) -> void:
	player.keys = keys
	player.invuln_t = 1000.0
	player.step(DT)
	game._step_tactics(DT)
	for door: Node2D in game.doors:
		door._physics_process(DT)
	frames_used += 1


## 走到 (c, 地表行)；jump=true 时接近目标后起跳一次。返回是否稳定站到目标附近。
func go(c: int, row: int, jump := false, budget := 420) -> bool:
	var target := Vector2(c * 32 + 16, row * 32 - .1)
	var jumped := false
	for frame in budget:
		var keys := {}
		var dx := target.x - player.position.x
		if player.on_ground and absf(dx) < 10.0 and absf(player.position.y - target.y) < 1.0:
			return true
		if absf(dx) > 4.0:
			keys[KEY_D if dx > 0 else KEY_A] = true
		if jump and not jumped and player.on_ground and absf(dx) < 120.0:
			keys[KEY_W] = true
			jumped = true
		tick(keys)
	return false


func roll_right() -> void:
	tick({KEY_D: true, KEY_CTRL: true})
	for frame in 24:
		tick({KEY_D: true})


func _run() -> void:
	SESSION.begin_run("easy")
	var boot: Node2D = load("res://scenes/m06_exhaust_ridge.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	game = boot.get_node("Game")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.action_audio_enabled = false
	game._sfx.clear()
	game.action_audio.stop_all()
	player = game.player
	player.auto_input = false
	player.keys.clear()
	player._prev_keys.clear()
	check(player.position.distance_to(game.level.spawn) < 1.0, "从关卡出生点开始")

	# 地面贯穿：检修口 → 扇阵 → 天窗廊（光栅）→ 冷却塔（压机）→ 中继站
	var ground_ok := true
	for c in [16, 40, 58, 80, 100, 120, 142, 157, 165]:
		ground_ok = ground_ok and go(c, 35)
	check(ground_ok, "地面主路线连通出生 → 狙击桅杆房入口")

	# 掩体箱顶 → 翻滚撞碎挡路玻璃 → 落回地面
	check(go(168, 33, true), "跳上掩体箱")
	var glass: Node2D = game.get_node("glass_mast_cover")
	roll_right()
	check(glass.broken, "翻滚撞碎桅杆前的检疫玻璃")
	check(go(174, 35), "玻璃后落回地面")

	# 10 级钢梯 → 梯顶平台 → 桅杆顶
	check(go(186, 30, false, 600), "爬 10 级钢梯到梯顶平台")
	check(go(189, 30) and go(192, 27, true) and go(199, 27), "跳上桅杆顶并走到竖井边")

	# 排气竖井：从桅杆顶落到井底，再沿之字单向台阶普通攀爬到 L5（井口 = 索桥基座高度）
	var shaft_ok := go(207, 35) and go(213, 32, true) and go(208, 29, true) and go(211, 26, true) 			and go(207, 23, true) and go(212, 20, true)
	check(shaft_ok, "排气竖井之字台阶普通攀爬到井口")

	# 高空索桥基座（光栅）→ 坠落通道两级缓降台 → 井底
	check(go(236, 20) and go(256, 20), "走过索桥基座")
	check(go(262, 26) and go(268, 31) and go(271, 35), "坠落通道逐级落到井底")

	# 终局泵站：守敌存活时房门锁住挡路；全清后放行
	check(go(300, 35), "进入封锁泵站")
	var door: Node2D = game.doors[0] if not game.doors.is_empty() else null
	check(door != null and door.locked, "泵站守敌存活时出口侧房门锁定")
	go(318, 35, false, 180)
	check(player.position.x < 311 * 32, "锁定房门挡住去路")
	for enemy: Node2D in game.minions:
		if game.level.room_at(enemy.position.x, enemy.position.y - 1.0) == 9:
			enemy.dead = true
	tick({})
	check(door != null and not door.locked, "泵站全清后房门解锁")

	# 撤离塔吊：到出口
	check(go(325, 35, false, 600), "穿过房门到达撤离出口")
	check(player.position.distance_to(game.level.exit_point) < 40.0, "脚底位于出口标记处")
	print("M06_FULL_ROUTE_FRAMES: ", frames_used, " (≈", snappedf(frames_used / 60.0, 0.1), "s 纯移动)")

	await create_timer(.2).timeout
	boot.free()
	current_scene = null
	SESSION.reset_for_tests()
	await create_timer(.2).timeout
	print("M06_FULL_ROUTE_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
