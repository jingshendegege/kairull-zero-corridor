extends SceneTree
## HK 竞技场 Boss 战测试：MAP_HK_ARENA + CFG_HK_STREET + HornetBoss（无小怪）。
## 三个距离档位依次验证：投剑（中距）→ 冲撞（近距）→ 丝线（远距），各阶段截图。
## 跑法：godot --path godot --rendering-driver opengl3 --script scripts/render_hk_map.gd
## 输出：user://shot_hk_boss_*.png

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
	CorridorLevel.active_map = CorridorLevel.MAP_HK_ARENA
	CorridorLevel.active_hide_rows_from = 19   # 地面视觉交给背景图街道，只留碰撞
	CorridorLevel.active_minion = "none"       # Boss 单测，不刷小怪
	CorridorLevel.active_boss = "hornet"       # 大黄蜂 Boss（HK 移植）
	GameBackground.active_cfg = GameBackground.CFG_HK_STREET
	var scene = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	# 地图尺寸断言：54×24 格，世界 1728×768
	ok(scene.level.map_w == 54 and scene.level.map_h == 24, "竞技场地图 54×24",
		"%d×%d" % [scene.level.map_w, scene.level.map_h])
	ok(scene.minions.is_empty(), "无小怪")
	ok(scene.red_boss is HornetBoss, "Boss 是大黄蜂")

	var boss: HornetBoss = scene.red_boss
	var player: KairullPlayer = scene.player
	player.auto_input = false
	boss.position = Vector2(40 * 32, 19 * 32)
	var ground_y := 19.0 * 32 - 0.1

	# --- 阶段 1：中距（约 10 格）应触发投剑 ---
	player.position = Vector2(30 * 32, ground_y)
	player.vy = 0.0
	var saw_sword := false
	var saw_aggro := false
	for i in range(240):
		scene._physics_process(1.0 / 60)
		if boss.state != "idle":
			saw_aggro = true
		if boss.state == "throw_sword":
			saw_sword = true
		if i == 150:
			scene._process(1.0 / 60)
			await process_frame
			await _shot("shot_hk_boss_sword")
	ok(saw_aggro, "Boss 索敌进入战斗")
	ok(saw_sword, "中距触发投剑（throw_sword）")

	# --- 阶段 2：近身（约 4 格）应触发 squat→dash 冲撞 ---
	player.position = boss.position + Vector2(-4 * 32, 0)
	player.vy = 0.0
	var saw_squat := false
	var saw_dash := false
	var saw_vfx := false
	for i in range(300):
		scene._physics_process(1.0 / 60)
		if boss.state == "squat":
			saw_squat = true
		if boss.state == "dash":
			saw_dash = true
		for p in boss._projs:
			if p["kind"] == "vfx_dash":
				saw_vfx = true
		if i == 120:
			scene._process(1.0 / 60)
			await process_frame
			await _shot("shot_hk_boss_dash")
	ok(saw_squat, "近距触发蓄力（squat）")
	ok(saw_dash, "蓄力后冲撞（dash）")
	ok(saw_vfx, "冲撞拖出 vfx 残影")

	# --- 阶段 3：远距（约 16 格）应触发丝线 ---
	player.position = boss.position + Vector2(-16 * 32, 0)
	player.vy = 0.0
	var saw_silk := false
	for i in range(400):
		scene._physics_process(1.0 / 60)
		if boss.state == "throw_silk" or boss.state == "throw_barb":
			saw_silk = true
		if i == 250:
			scene._process(1.0 / 60)
			await process_frame
			await _shot("shot_hk_boss_silk")
	ok(saw_silk, "远距触发丝线/棘刺（throw_silk/throw_barb）")

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("RENDER_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
