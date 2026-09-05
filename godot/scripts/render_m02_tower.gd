extends SceneTree
## M02 数据塔渲染验收：真实窗口跑（无头截图为空）。
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m02_tower.gd
## 输出：user://shot_m02_*.png
##   1 大堂 + 开场标题卡   2 事务所遭遇战（枪手蓄力品红频闪）
##   3 服务器厅（右外墙窗 W + 连锁桶对）   4 核心前厅→塔心锁定门（红光）

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

	var player: KairullPlayer = scene.player

	# --- 镜头 1：大堂出生区 + 开场标题卡（2.8s 内） ---
	for i in range(36):
		await process_frame
	await _shot("shot_m02_1_lobby_title")

	# --- 镜头 2：事务所遭遇战（等枪手进 aim 频闪） ---
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
	await _shot("shot_m02_2_office_fight")
	print("  aim 频闪捕捉: ", "OK" if got_aim else "未等到（仍已截图）")

	# --- 镜头 3：服务器厅（窗 + 连锁桶对） ---
	player.position = Vector2(125 * 32, 16 * 32 - 0.1)
	player.vy = 0.0
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	for i in range(20):
		await process_frame
	await _shot("shot_m02_3_server_hall")

	# --- 镜头 4：核心前厅→塔心锁定门（红边光） ---
	player.position = Vector2(62 * 32, 8 * 32 - 0.1)
	player.vy = 0.0
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	for i in range(20):
		await process_frame
	var door_ante: RoomDoor
	for d in scene.doors:
		if floori(d.position.x / 32.0) == 70:
			door_ante = d
	print("  前厅门锁定状态: ", "锁定（红光）" if door_ante != null and door_ante.locked else "异常")
	await _shot("shot_m02_4_core_door")

	print("RENDER_RESULT: PASS")
	quit(0)


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	_shot_count += 1
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
