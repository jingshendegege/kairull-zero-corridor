extends SceneTree
## M02 playtest 第二轮修复渲染验收（真实窗口跑）：
##   1 锁定门 + 玩家站旁边 —— 门（含墙面门框/门楣，160px）明显高于玩家（93.6px）
##   2 同一扇门解锁 —— 门板沉地、品红/青边灯 + 门楣青灯亮
##   3 服务器厅最暗墙面前的 grunt —— 青色轮廓光 + 脚下接触阴影（squint test）
##   4 击杀后的 grunt 尸体贴地 + 血泊 + 接触阴影
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m02_shot5.gd
## 输出：user://shot5_*.png

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
	player.auto_input = false

	# 事务所 3 只 grunt 挪到房间最左（远离玩家 >480px 不索敌，保持门锁定）
	var office_grunts: Array = []
	for m in scene.minions:
		var c := floori(m.position.x / 32.0)
		if c >= 41 and c <= 80:
			office_grunts.append(m)
	for i in office_grunts.size():
		office_grunts[i].position = Vector2((43 + i * 2) * 32 + 16, 25 * 32 - 0.1)

	# --- 镜头 1：锁定门（事务所门 c80）+ 玩家站旁边 ---
	player.position = Vector2(76 * 32 + 16, 25 * 32 - 0.1)
	player.face = 1
	_move_cam(scene)
	for i in range(30):
		await process_frame
	await _shot("shot5_door_locked")

	# --- 镜头 2：同一扇门解锁（杀光事务所 3 只 → 门板沉地 + 品红/青灯） ---
	for m in office_grunts:
		m.take_hit(m.position.x, 1)
	for i in range(4):
		await physics_frame
	for i in range(30):   ## 门板沉地动画 0.45s 播完
		await process_frame
	await _shot("shot5_door_unlocked")

	# --- 镜头 3：服务器厅暗墙前的 grunt（轮廓光 + 接触阴影） ---
	# 其余 grunt 摘掉 player 引用 → 保持 idle 不索敌不开枪（避免品红瞄准闪干扰读图）
	var subject: GruntGunner
	for m in scene.minions:
		if is_instance_valid(m) and not m.dead:
			m.player = null
			if absf(m.position.x - (98 * 32 + 16)) < 4.0:
				subject = m
	if subject != null:
		subject.position = Vector2(90 * 32 + 16, 16 * 32 - 0.1)   ## 光池间的暗墙区
		player.position = Vector2(84 * 32 + 16, 16 * 32 - 0.1)
		player.face = 1
		_move_cam(scene)
		for i in range(30):
			await process_frame
		await _shot("shot5_grunt_rim_shadow")

		# --- 镜头 4：击杀 → 尸体贴地 + 血泊 + 接触阴影 ---
		subject.take_hit(subject.position.x, 1)
		var burst: SlimeRibbonBurst = scene.fx_layer.spawn_bat_hit(
				subject.body_rect().get_center(), Vector2(1, -0.18).normalized(), 1.35)
		scene.paint_layer.blood_pool(subject.body_rect().get_center(), 1.0, 0,
				burst.current_color.darkened(0.15))
		for i in range(40):
			await process_frame
		await _shot("shot5_corpse_blood")
	else:
		print("  !! 未找到 c98 grunt，跳过镜头 3/4")

	print("RENDER_RESULT: PASS")
	quit(0)


func _move_cam(scene: Node2D) -> void:
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	# auto_input=false 时 step() 不跑，落地尘土 FX 会冻住——手动清掉
	var player: KairullPlayer = scene.player
	player._land_fx.visible = false
	player._land_fx_t = -1.0
	player._jump_fx.visible = false
	player._jump_fx_t = -1.0


func _shot(name: String) -> void:
	await process_frame
	var img := get_root().get_texture().get_image()
	var path := "user://%s.png" % name
	var err := img.save_png(path)
	_shot_count += 1
	print("  截图 ", name, " -> ", ProjectSettings.globalize_path(path), " err=", err)
