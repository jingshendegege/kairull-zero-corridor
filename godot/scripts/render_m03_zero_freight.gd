extends SceneTree
## M03 真窗口构图验收；headless 截图无效。
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m03_zero_freight.gd
## 输出：user://shot_m03_zero_freight_*.png


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var boot: Node2D = load("res://scenes/m03_zero_freight.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	var player: KairullPlayer = game.player
	player.auto_input = false
	for i in range(32):
		await process_frame

	# 1：出生点即看到锁定出口，先建立“绕一圈再回来”的目标。
	await _place_and_shot(game, player, Vector2(7 * 32 + 16, 25 * 32 - 0.1),
		"shot_m03_zero_freight_1_arrival")
	# 标题卡按真实时钟计时；真窗口脚本跑得比实时快，需等到 2.8s 后再取后续镜头。
	while Time.get_ticks_msec() / 1000.0 - game.hud.level_start_t < 3.0:
		await process_frame
	# 2：中央候车厅是下层主战斗空间，短高台和桶形成近战动线。
	await _place_and_shot(game, player, Vector2(56 * 32 + 16, 25 * 32 - 0.1),
		"shot_m03_zero_freight_2_concourse")
	# 3：东楼梯井承担下层到上层的清晰换层节奏。
	await _place_and_shot(game, player, Vector2(88 * 32 + 16, 23 * 32 - 0.1),
		"shot_m03_zero_freight_3_east_stairs")
	# 4：西井的单向台正落回到达台，读出 U 形回环的捷径。
	await _place_and_shot(game, player, Vector2(23 * 32 + 16, 16 * 32 - 0.1),
		"shot_m03_zero_freight_4_west_drop")
	# 5：上层信号室与锁定西门。
	await _place_and_shot(game, player, Vector2(54 * 32 + 16, 16 * 32 - 0.1),
		"shot_m03_zero_freight_5_signal")
	# 6：调度室/维修库上下叠置，展示 U 形回环的远端折返点。
	await _place_and_shot(game, player, Vector2(111 * 32 + 16, 16 * 32 - 0.1),
		"shot_m03_zero_freight_6_control")
	print("RENDER_RESULT: PASS")
	quit(0)


func _place_and_shot(game: Node2D, player: KairullPlayer, pos: Vector2,
		name: String) -> void:
	player.position = pos
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	game._update_room_state()
	game.cam_tl = game._cam_target()
	for i in range(20):
		await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
