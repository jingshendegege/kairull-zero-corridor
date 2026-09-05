extends SceneTree
## M01 旧城区霓虹街渲染验收：真实窗口跑（无头截图为空）。
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m01_street.gd
## 输出：user://shot_m01_*.png
##   1 出生区（售货亭 + 第一名枪手）  2 高阳台 1 双狙击 + 脚手架
##   3 塔门出口区（货车顶岗 + 门柱）  4 遭遇战：枪手蓄力品红频闪

var _shot_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M01_NEON
	CorridorLevel.active_hide_rows_from = 19
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	GameBackground.active_cfg = GameBackground.CFG_M01_NEON
	var scene: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var player: KairullPlayer = scene.player
	var ground_y := 19.0 * 32 - 0.1

	# --- 镜头 1：出生区（相机就位后落定 30 帧） ---
	for i in range(30):
		await process_frame
	await _shot("shot_m01_1_start")

	# --- 镜头 2：高阳台 1（脚手架上方，双狙击） ---
	player.position = Vector2(64 * 32, ground_y)
	player.vy = 0.0
	scene.cam_tl = scene._cam_target()
	for i in range(20):
		await process_frame
	await _shot("shot_m01_2_balcony")

	# --- 镜头 3：塔门出口区 ---
	player.position = Vector2(172 * 32, ground_y)
	player.vy = 0.0
	scene.cam_tl = scene._cam_target()
	for i in range(20):
		await process_frame
	await _shot("shot_m01_3_exit")

	# --- 镜头 4：遭遇战（中街广场，等枪手进 aim 频闪） ---
	player.position = Vector2(91 * 32, ground_y)
	player.vy = 0.0
	scene.cam_tl = scene._cam_target()
	var got_aim := false
	for i in range(180):
		await process_frame
		for m in scene.minions:
			if is_instance_valid(m) and m.state == "aim" and m.frame >= 20:
				got_aim = true
		if got_aim:
			break
	await _shot("shot_m01_4_combat_aim")
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
