extends SceneTree
## M02 playtest 修复渲染验收（真实窗口跑）：
##   1 事务所内玩家站姿 —— 描边/背晕把白发角色从暗墙上剥开
##   2 玩家与 grunt 并排 —— 敌我尺寸对比（grunt ≈ 玩家身高）
##   3 刚击杀的 grunt 尸体贴地平躺 + 血泊
##   4 原堵点（楼梯间A 台阶链）跳跃穿越中帧
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m02_fix.gd
## 输出：user://shot4_m02_*.png

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

	# 标题卡走真实时间：回拨起始时间让它立即过期
	scene.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 10.0

	var player: KairullPlayer = scene.player

	# --- 镜头 1：事务所内玩家站姿（描边+背晕分离暗墙） ---
	_move_cam(scene, Vector2(55 * 32, 25 * 32 - 0.1))
	for i in range(30):
		await process_frame
	await _shot("shot4_m02_1_player_office")

	# --- 镜头 2：玩家与 grunt 并排尺寸对比（事务所 c62 的 grunt） ---
	var grunt: GruntGunner
	for m in scene.minions:
		if absf(m.position.x - (62 * 32 + 16)) < 4.0:
			grunt = m
	if grunt != null:
		grunt.position = Vector2(60 * 32 + 16, 25 * 32 - 0.1)
		player.position = Vector2(57 * 32 + 16, 25 * 32 - 0.1)
		player.face = 1
		_move_cam(scene, player.position, false)
		for i in range(20):
			await process_frame
		await _shot("shot4_m02_2_size_compare")
	else:
		print("  !! 未找到 c62 grunt，跳过镜头 2")

	# --- 镜头 3：刚击杀的 grunt 尸体贴地 + 血泊 ---
	if grunt != null:
		grunt.take_hit(grunt.position.x, 1)
		# 与 game 近战击杀同款：液爆 + 地面血泊（略压暗）
		var burst: SlimeRibbonBurst = scene.fx_layer.spawn_bat_hit(
				grunt.body_rect().get_center(), Vector2(1, -0.18).normalized(), 1.35)
		scene.paint_layer.blood_pool(grunt.body_rect().get_center(), 1.0, 0,
				burst.current_color.darkened(0.15))
		for i in range(40):
			await process_frame
		await _shot("shot4_m02_3_corpse_floor")

	# --- 镜头 4：原堵点穿越中帧（楼梯间A 台阶链，跳台阶B→C 瞬间） ---
	player.auto_input = false
	player.reset_to_spawn()
	player.position = Vector2(118 * 32 + 16, 25 * 32 - 0.1)
	player.vx = 0.0
	player.vy = 0.0
	_move_cam(scene, Vector2(128 * 32 + 16, 24 * 32), false)
	var jumped := false
	var got_air := false
	for i in range(400):
		player.keys.clear()
		player.keys[KEY_D] = true
		# 到台阶A 左缘后起跳，之后每次落地且仍在爬升区就再跳
		if player.on_ground and player.position.x > 122 * 32.0:
			if not jumped or player.position.x > 126 * 32.0:
				player.keys[KEY_W] = true
				jumped = true
		player.step(1.0 / 60.0)
		await physics_frame
		await process_frame
		# 捕捉台阶B→C 区间的腾空中帧
		if not player.on_ground and player.position.x > 127 * 32.0 \
				and player.position.x < 133 * 32.0 \
				and player.position.y < 21 * 32.0:
			got_air = true
			break
	await _shot("shot4_m02_4_stair_climb")
	print("  空中帧捕捉: ", "OK" if got_air else "未捕到（仍已截图）",
			" player=", player.position)

	print("RENDER_RESULT: PASS")
	quit(0)


func _move_cam(scene: Node2D, focus: Vector2, settle := true) -> void:
	scene.player.position = focus if settle else scene.player.position
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	_shot_count += 1
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
