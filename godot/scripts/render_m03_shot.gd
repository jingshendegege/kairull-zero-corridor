extends SceneTree
## M03 取件关真窗渲染验收：玩家传送巡游，多机位截图。
## 跑法：godot --path godot --rendering-driver opengl3 --script scripts/render_m03_shot.gd
## 输出：%USERPROFILE%/AppData/Local/Temp/m03_shots/*.png

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	CorridorLevel.active_map = CorridorLevel.MAP_M03_BACKROOM
	CorridorLevel.active_rooms = CorridorLevel.MAP_M03_BACKROOM_ROOMS
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {"name": "tower"}
	CorridorLevel.active_stair_material = "stone"
	CorridorLevel.active_exit_requires_usb = true
	CorridorLevel.active_decor = CorridorLevel.MAP_M03_BACKROOM_DECOR
	CorridorLevel.active_tileset_path = "res://assets/clips/tileset_m03.png"
	CorridorLevel.active_enemy_rim = Color(1.0, 0.82, 0.4, 0.75)
	CorridorLevel.active_title = "M03 黑市包间"
	CorridorLevel.active_bgm = ""
	GameBackground.active_cfg = GameBackground.CFG_TOWER_DIM
	var scene: Node2D = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	# 背景墙风格（boot 同款）：西段横板 / 东段 loft
	if scene.wall_backdrop != null:
		scene.wall_backdrop.queue_redraw()   # 风格走 rooms 表 style 字段（生成器分配）
	var player: KairullPlayer = scene.player
	for i in range(10):
		await physics_frame
	player.auto_input = false
	var dir := OS.get_environment("USERPROFILE") + "/AppData/Local/Temp/m03_shots"
	DirAccess.make_dir_recursive_absolute(dir)

	# 机位 [文件名, 列, 站立行] —— 玩家传送到该格站立面上方，落定后截图
	var shots := [
		["s1_spawn", 8, 17],       # 出生全景：CRT / L1 平台 / 地面敌
		["s2_stair_l0l1", 42, 17], # L0→L1 石砌楼梯脚
		["s3_stair_top", 46, 15],  # 楼梯顶小平台（L1 东段）
		["s4_vault", 22, 14],      # 密室：USB + 录音带 #3 + 精英
		["s5_l2_tape", 33, 11],    # L2 平台 B：录音带 #2
		["s6_l3_sniper", 45, 8],   # L3 平台：狙击 + 录音带 #1
		["s7_exit", 53, 17],       # 出口（USB 未取 → 锁定红光）
	]
	for shot in shots:
		var c: int = shot[1]
		var r: int = shot[2]
		player.position = Vector2(c * 32 + 16, r * 32 - 2)
		player.vy = 0.0
		player.vx = 0.0
		# 等 lerp 相机收敛 + 玩家落定
		for i in range(40):
			await physics_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png(dir + "/" + shot[0] + ".png")
		print("SHOT: " + shot[0])
	# 机位 8：取件后警报态（灯光切红）
	if scene.room_lights != null:
		scene.room_lights.alarm = true
	player.position = Vector2(30 * 32 + 16, 17 * 32 - 2)
	player.vy = 0.0
	for i in range(40):
		await physics_frame
	await RenderingServer.frame_post_draw
	get_root().get_viewport().get_texture().get_image().save_png(dir + "/s8_alarm.png")
	print("SHOT: s8_alarm")
	print("SAVED: " + dir)
	quit(0)
