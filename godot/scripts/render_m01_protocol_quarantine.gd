extends SceneTree
## 正式第一关真窗口分房验收；headless 截图不能替代本脚本。
## 跑法：Godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m01_protocol_quarantine.gd
## 输出：user://shot_m01_protocol_*.png

var _render_failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("地图美术验收必须使用真窗口")
		quit(1)
		return
	var boot: Node2D = load("res://scenes/m01_protocol_quarantine.tscn").instantiate()
	get_root().add_child(boot)
	await process_frame
	await process_frame
	var game: Node2D = boot.get_node("Game")
	var player: KairullPlayer = game.player
	var art: QuarantineArchitecture = game.quarantine_architecture
	# 真窗口前先核对本轮货运扫描切片已接入，不让旧三窗占位图误报 PASS。
	if art == null or art.cargo_scanner_dynamic_channel_count != 3 \
			or art.cargo_gantry_span_px < 800.0 or art.cargo_conveyor_span_px < 740.0 \
			or art.large_wall_panel_count < 20 or art.wall_wear_cluster_count < 5:
		_render_failed = true
		push_error("检疫厅扫描门架/大墙板结构预算未满足")
	player.auto_input = false
	player.hp = 999
	# 地图美术验收隐藏 HUD；角色与两类敌人仍保留真实大小和层级作可读性参照。
	game.hud.visible = false
	for minion: Node2D in game.minions:
		minion.process_mode = Node.PROCESS_MODE_DISABLED
	# Game 会在自身 physics 中直接调用 minion.step；只禁用敌节点仍会漂离 LDtk 刷点。
	# 冻结宿主物理，但保留建筑层 _process，让扫描线/状态屏继续动态刷新。
	game.set_physics_process(false)

	for i in range(20):
		await process_frame
	await _place_and_shot(game, player, game.level.spawn,
			"shot_m01_protocol_1_entry")
	# 在检疫厅墙面放三种正式彩色血迹，专门核对中亮墙材是否仍有可读对比。
	game.paint_layer.spawn_wall_snapshot(Vector2(720, 600), Vector2(1.0, -0.08),
			0.72, 2, false, 0.62, Color("#ff4fa3"))
	game.paint_layer.spawn_wall_snapshot(Vector2(1248, 560), Vector2(-1.0, 0.06),
			0.68, 4, false, 0.58, Color("#43e8ff"))
	game.paint_layer.spawn_wall_snapshot(Vector2(1480, 640), Vector2(-1.0, -0.12),
			0.64, 1, false, 0.55, Color("#ffb347"))
	# c36 是枪手刷点；比例尺放到 c33，避免白发角色与敌人叠成一团。
	await _place_and_shot(game, player, Vector2(33 * 32 + 16, 28 * 32 - 0.1),
			"shot_m01_protocol_2_quarantine_hall")
	await _place_and_shot(game, player, Vector2(43 * 32 + 16, 28 * 32 - 0.1),
			"shot_m01_protocol_2b_walkway_clearance")
	await _place_and_shot(game, player, Vector2(58 * 32 + 16, 24 * 32 - 0.1),
			"shot_m01_protocol_3_maintenance_stair")
	# 在正式十级楼梯底部启动冲刺，额外验收贴阶位移与头顶 CD 在正式墙材上的可读性。
	player.position = Vector2(52 * 32 - 20, 28 * 32 - 0.1)
	player.vy = 0.0
	player.on_ground = true
	player.set_state("gun_idle")
	player.keys = {KEY_D: true, KEY_SHIFT: true}
	player._prev_keys.clear()
	for i in range(3):
		player.step(1.0 / 60.0)
	if not player.dashing() or not player.dash_cooldown_ui_visible() \
			or not player._standing_on_stair():
		_render_failed = true
		push_error("正式楼梯冲刺/CD UI 状态未达到截图验收点")
	await _place_and_shot(game, player, player.position,
			"shot_m01_protocol_3b_dash_stair_cd", true)
	await _place_and_shot(game, player, Vector2(80 * 32 + 16, 21 * 32 - 0.1),
			"shot_m01_protocol_4_archive_sorting")
	await _place_and_shot(game, player, Vector2(108 * 32 + 16, 23 * 32 - 0.1),
			"shot_m01_protocol_5_checkpoint")
	# 扩展后出口在 c274；后半程逐房构图另见 render_extended_campaign.gd。
	await _place_and_shot(game, player, Vector2(270 * 32 + 16, 23 * 32 - 0.1),
			"shot_m01_protocol_10_exit")
	if game.music != null:
		game.music.stop()
		game.music.stream = null
	# 渲染脚本会立即退出，先断开短音效资源，避免把测试清理警告误判成关卡泄漏。
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
		voice.stream = null
	game._sfx.clear()
	boot.free()
	await process_frame
	print("RENDER_RESULT: ", "FAIL" if _render_failed else "PASS")
	quit(1 if _render_failed else 0)


func _place_and_shot(game: Node2D, player: KairullPlayer, pos: Vector2,
		file_stem: String, preserve_dash := false) -> void:
	# 分房截图不可把上一张冲刺的白化/CD冻结带到后续房间。
	if not preserve_dash:
		player._clear_dash_visual()
		player.set_state("gun_idle")
	player.position = pos
	if not preserve_dash:
		var surface: float = game.level.stair_surface_near(pos.x, pos.y, 20.0, 20.0)
		if is_finite(surface):
			player.position.y = surface - 0.1
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	player._sync_sprite()
	game._update_room_state()
	game.cam_tl = game._cam_target().round()
	game.cam.position = game.cam_tl + Vector2(680, 382.5)
	for i in range(12):
		await process_frame
	var image := get_root().get_texture().get_image()
	var path := "user://%s.png" % file_stem
	var err := image.save_png(path)
	# 真窗口验收必须把写盘失败传到退出码，不能只打印一个无条件 PASS。
	if err != OK:
		_render_failed = true
	print("  截图 ", file_stem, " -> ", ProjectSettings.globalize_path(path),
			" err=", err)
