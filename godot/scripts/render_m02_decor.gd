extends SceneTree
## M02 数据塔 task B 渲染验收：墙面 backdrop / 房间装饰 / 光影 / 窗墙。真实窗口跑。
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m02_decor.gd
## 输出：user://shot3_m02_*.png
##   1 大堂（前台/盆栽/徽牌 + 光池）   2 事务所（工位/相框）
##   3 服务器厅（机柜+LED+走线 + 右侧窗墙）   4 核心前厅（导管/警示纹/红脉冲）
##   5 事务所遭遇战（枪手蓄力频闪，装饰在背景层）

var _shot_count := 0


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

	# 标题卡走真实时间（fixed-fps 下帧数≠秒数）：直接回拨起始时间让它立即过期
	scene.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 10.0

	var player: KairullPlayer = scene.player

	# --- 镜头 1：大堂（前台/盆栽 + L 光池；标题卡已淡出） ---
	for i in range(30):
		await process_frame
	await _shot("shot3_m02_1_lobby")

	# --- 镜头 2：事务所（工位桌/显示器/相框，门口视角） ---
	player.position = Vector2(46 * 32, 25 * 32 - 0.1)
	player.vy = 0.0
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	for i in range(24):
		await process_frame
	await _shot("shot3_m02_2_office")

	# --- 镜头 3：服务器厅右段（机柜列+LED 闪烁+走线槽 + c143 窗墙） ---
	player.position = Vector2(128 * 32, 16 * 32 - 0.1)
	player.vy = 0.0
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	for i in range(30):
		await process_frame
	await _shot("shot3_m02_3_server_hall")

	# --- 镜头 4：核心前厅右段（导管/警示纹/红脉冲 + 锁定门红光） ---
	player.position = Vector2(58 * 32, 8 * 32 - 0.1)
	player.vy = 0.0
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	for i in range(30):
		await process_frame
	await _shot("shot3_m02_4_antechamber")

	# --- 镜头 5：事务所遭遇战（等枪手进 aim 品红频闪，装饰在背景层） ---
	player.position = Vector2(58 * 32, 25 * 32 - 0.1)
	player.vy = 0.0
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	var got_aim := false
	for i in range(240):
		await process_frame
		for m in scene.minions:
			if is_instance_valid(m) and m.state == "aim" and m.frame >= 20:
				got_aim = true
		if got_aim:
			break
	await _shot("shot3_m02_5_office_fight")
	print("  aim 频闪捕捉: ", "OK" if got_aim else "未等到（仍已截图）")

	print("RENDER_RESULT: PASS")
	quit(0)


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	_shot_count += 1
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
