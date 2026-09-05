extends SceneTree
## M02 playtest 第四轮修复验收（无头）：
##   1) 出口判定收紧：CLEAR 只在玩家真的站在塔门口（门口地面层紧矩形）触发——
##      核心前厅高台 / 楼梯间 / 各房间 / 门口上空（楼板台面上方）均不得触发；
##      走到门口才触发。
##   2) 双 S 下穿单向台：站在 = 台上 0.28s 内连按两次 S → 穿过台板落到下层；
##      站在 # 实地上双 S 不下穿；单按 S 无效果；慢速两按（>0.28s）不下穿。
## 跑法：godot --headless --path godot --script scripts/test_m02_round4.gd

var _pass := 0
var _fail := 0

const DT := 1.0 / 60.0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _make_key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


## 机器人注入一次 S 点按（按下 1 帧 → 松开 gap 帧）
func _tap_s(p: KairullPlayer, gap_frames: int) -> void:
	p.keys.clear()
	p.keys[KEY_S] = true
	p.step(DT)
	p.keys.clear()
	for i in range(gap_frames):
		p.step(DT)


## 机器人双 S（间隔 gap 帧）
func _double_tap_s(p: KairullPlayer, gap_frames := 4) -> void:
	_tap_s(p, gap_frames)
	p.keys[KEY_S] = true
	p.step(DT)
	p.keys.clear()


## 传送玩家到指定脚底坐标并手动步进 settle 帧（不 await，纯玩家物理）
func _pose(p: KairullPlayer, pos: Vector2, settle := 20) -> void:
	p.position = pos
	p.vx = 0.0
	p.vy = 0.0
	p.keys.clear()
	for i in range(settle):
		p.step(DT)


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
	for i in range(3):
		await physics_frame

	var level: CorridorLevel = scene.level
	var player: KairullPlayer = scene.player
	player.auto_input = false
	player.hp = 999
	# 清场：门全解锁、无人干扰走位与截图语义（本测试不验战斗）
	for m in scene.minions:
		if is_instance_valid(m) and not m.dead:
			m.take_hit(m.position.x, 1)
	for i in range(3):
		await physics_frame

	print("== 出口触发区几何 ==")
	var exit_feet: Vector2 = level.exit_point
	var trig: Rect2 = scene.exit_door.trigger_rect()
	ok(absf(trig.get_center().x - exit_feet.x) < 1.0, "触发区水平居中于门口",
		"center=%.1f exit=%.1f" % [trig.get_center().x, exit_feet.x])
	ok(absf(trig.end.y - exit_feet.y) < 1.0, "触发区底边贴在门口地面层",
		"bottom=%.1f floor=%.1f" % [trig.end.y, exit_feet.y])
	ok(trig.size.y <= 66.0, "触发区高 ≤66px（≈2 格门洞脚高，不向上探 3 格）",
		"h=%.1f" % trig.size.y)
	ok(trig.size.x <= 48.0, "触发区宽 ≤48px（≈门宽）", "w=%.1f" % trig.size.x)
	# 触发区顶沿必须低于单向台面平面（r5 顶 y=160），隔空高台永不相交
	ok(trig.position.y > 160.0, "触发区顶沿低于 = 台面平面（不会隔空扫到高台）",
		"top=%.1f" % trig.position.y)

	print("== 远程/提前不误触（playtest round4 回归）==")
	# 关键回归：核心前厅高台（= 台 r5 c55-59，狙击手位）——owner 截图姿势
	_pose(player, Vector2(57 * 32 + 16, 5 * 32 - 0.1), 40)
	ok(player.on_ground, "前置：玩家站上核心前厅高台", str(player.position))
	for i in range(10):
		await physics_frame
	ok(not scene.level_cleared, "站在核心前厅高台不触发 CLEAR")
	# 门口正上方、= 台面所在高度（旧 92px 高判定区会在这里隔空触发）
	_pose(player, Vector2(135 * 32 + 16, 5 * 32 - 0.1), 2)
	await physics_frame
	ok(not scene.level_cleared, "门口正上方台面高度（脚离地面 96px）不触发 CLEAR")
	# 各房间代表点（含与出口同层同房的远处）均不触发
	var spots := {
		"大堂地面 c20": Vector2(20 * 32 + 16, 25 * 32 - 0.1),
		"事务所地面 c60": Vector2(60 * 32 + 16, 25 * 32 - 0.1),
		"楼梯间A 地面 c100": Vector2(100 * 32 + 16, 25 * 32 - 0.1),
		"楼梯间B 地面 c15": Vector2(15 * 32 + 16, 16 * 32 - 0.1),
		"休息室地面 c50": Vector2(50 * 32 + 16, 16 * 32 - 0.1),
		"服务器厅地面 c100": Vector2(100 * 32 + 16, 16 * 32 - 0.1),
		"核心前厅地面 c30（同层）": Vector2(30 * 32 + 16, 8 * 32 - 0.1),
		"塔心地面 c100（同房远处）": Vector2(100 * 32 + 16, 8 * 32 - 0.1),
		"塔心门口旁 c133（同层未到门）": Vector2(133 * 32 + 16, 8 * 32 - 0.1),
	}
	for label in spots:
		_pose(player, spots[label], 10)
		await physics_frame
		ok(not scene.level_cleared, "%s 不触发 CLEAR" % label, str(player.position))

	print("== 走到门口才触发 ==")
	_pose(player, Vector2(75 * 32 + 16, 8 * 32 - 0.1), 20)
	var walked := false
	for f in range(900):
		player.keys.clear()
		player.keys[KEY_D] = true
		player.step(DT)
		await physics_frame
		if scene.level_cleared:
			walked = true
			break
	ok(walked, "塔心地面向右走到门口触发 CLEAR")
	ok(absf(player.position.y - (8 * 32 - 0.1)) < 2.0,
		"触发时玩家脚踩门口地面层（同一 floor level）",
		"y=%.1f" % player.position.y)
	ok(player.position.x > 135 * 32 - 32.0 and player.position.x < 135 * 32 + 48.0,
		"触发点就在门口（c134~c136.5）", "x=%.1f" % player.position.x)
	# Backspace 复位，进入下穿测试段
	scene._unhandled_input(_make_key(KEY_BACKSPACE))
	await physics_frame
	ok(not scene.level_cleared, "Backspace 复位过关态")

	print("== 双 S 下穿单向台 ==")
	# --- 事务所高台（= r22 c66-70，脚下 F1 地面 799.9）---
	_pose(player, Vector2(68 * 32 + 16, 22 * 32 - 0.1), 40)
	ok(player.on_ground and absf(player.position.y - (22 * 32 - 0.1)) < 1.0,
		"前置：站上事务所高台", str(player.position))
	_double_tap_s(player)
	ok(player._jump_fx.visible, "下穿触发提示尘土（复用起跳尘）")
	var y0 := 22 * 32 - 0.1
	var fell := false
	for i in range(8):
		player.step(DT)
		if player.position.y > y0 + 10.0:
			fell = true
			break
	ok(fell, "双 S 后开始下落（脚穿过台面）", "y=%.1f y0=%.1f" % [player.position.y, y0])
	for i in range(60):
		player.step(DT)
	ok(player.on_ground and absf(player.position.y - (25 * 32 - 0.1)) < 1.0,
		"下穿后落到下层地面（F1 799.9）", str(player.position))

	# --- 核心前厅高台（= r5 c55-59 → F3 地面 255.9）---
	_pose(player, Vector2(57 * 32 + 16, 5 * 32 - 0.1), 40)
	ok(player.on_ground, "前置：站上核心前厅高台", str(player.position))
	_double_tap_s(player)
	for i in range(60):
		player.step(DT)
	ok(player.on_ground and absf(player.position.y - (8 * 32 - 0.1)) < 1.0,
		"核心前厅高台下穿落到 F3 地面（255.9）", str(player.position))

	# --- 竖井 = 台（r16 c129-134 → 下穿落到井口正下方的台阶C顶 feet r18）---
	_pose(player, Vector2(131 * 32 + 16, 16 * 32 - 0.1), 40)
	ok(player.on_ground, "前置：站上竖井封口台", str(player.position))
	_double_tap_s(player)
	for i in range(80):
		player.step(DT)
	ok(player.on_ground and absf(player.position.y - (19 * 32 - 0.1)) < 1.0,
		"竖井台下穿落到台阶C顶（607.9，原路可下不再困人）", str(player.position))

	print("== 不误触发 ==")
	# 站在 # 实地上双 S：不得下穿
	_pose(player, Vector2(30 * 32 + 16, 25 * 32 - 0.1), 40)
	ok(player.on_ground, "前置：站上大堂 # 实地")
	_double_tap_s(player)
	for i in range(30):
		player.step(DT)
	ok(player.on_ground and absf(player.position.y - (25 * 32 - 0.1)) < 1.0,
		"# 实地上双 S 不下穿", str(player.position))
	# 单按 S：无效果
	_pose(player, Vector2(68 * 32 + 16, 22 * 32 - 0.1), 40)
	_tap_s(player, 10)
	for i in range(20):
		player.step(DT)
	ok(player.on_ground and absf(player.position.y - (22 * 32 - 0.1)) < 1.0,
		"单按 S 留在台上", str(player.position))
	# 慢速两按（>0.28s 窗口）：不下穿
	_tap_s(player, 30)   ## 30 帧 = 0.5s
	player.keys[KEY_S] = true
	player.step(DT)
	player.keys.clear()
	for i in range(30):
		player.step(DT)
	ok(player.on_ground and absf(player.position.y - (22 * 32 - 0.1)) < 1.0,
		"慢速两按（间隔 0.5s）不下穿", str(player.position))
	# 倒地（K）时双 S 不下穿
	_pose(player, Vector2(68 * 32 + 16, 22 * 32 - 0.1), 40)
	player.take_damage(999, player.position.x - 10.0)
	_double_tap_s(player)
	for i in range(20):
		player.step(DT)
	ok(absf(player.position.y - (22 * 32 - 0.1)) < 1.0,
		"倒地状态双 S 不下穿", str(player.position))

	print("== HUD 操作说明包含双 S ==")
	ok(scene.hud._help_label.text.contains("双S 下穿平台"),
		"底部操作说明含「双S 下穿平台」", scene.hud._help_label.text)

	# 清理静态配置
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
