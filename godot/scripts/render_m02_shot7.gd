extends SceneTree
## M02 playtest 第四轮修复渲染验收（真实窗口跑）：
##   a 玩家站在核心前厅高台（= r5 c55-59 狙击手位）—— 不再误弹 CLEAR 卡
##   b 玩家走到塔心出口门口 —— 正常弹出 M02 数据塔 CLEAR 卡
##   c 双 S 下穿单向台进行中 —— 人已穿过台面、台面留有提示尘土，底部帮助条可见
## 跑法：godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_m02_shot7.gd
## 输出：user://shot7_*.png（外层拷到 m02_renders/）

var _shot_count := 0


func _init() -> void:
	call_deferred("_run")


func _wait_real(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


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
	player.auto_input = false
	player.hp = 999   ## 摆拍期间挨枪不死

	# 冻结核心前厅 grunt：摘 player 引用让 step 早退，手动摆位 + 站姿贴图
	var ante: Array = []
	var rect6: Rect2i = scene.level.rooms[6]["rect"]
	for m in scene.minions:
		var cell := Vector2i(floori(m.position.x / 32.0), floori(m.position.y / 32.0))
		if rect6.has_point(cell):
			ante.append(m)
	for g in ante:
		g.player = null
		g._set_state("idle")
	# 狙击手让位：从高台挪到楼下地面 c50，面向右（与高台上的玩家对望）
	if not ante.is_empty():
		ante[0].position = Vector2(50 * 32 + 16, 8 * 32 - 0.1)
		ante[0].face = 1
		ante[0]._sync_sprite()

	# ============ 镜头 a：站上核心前厅高台，无 CLEAR 卡 ============
	scene.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 20.0   ## 标题卡/帮助条都淡出
	_pose(scene, Vector2(57 * 32 + 16, 5 * 32 - 0.1))
	_move_cam(scene)
	for i in range(40):
		await process_frame
	print("  镜头a level_cleared = ", scene.level_cleared, "（应为 false）")
	await _shot("shot7_a_platform_no_clear")

	# ============ 镜头 b：走到出口门口，CLEAR 卡弹出 ============
	player.position = scene.level.exit_point
	player.vx = 0.0
	player.vy = 0.0
	for i in range(6):   ## 让 game 的出口判定跑几帧
		await physics_frame
	print("  镜头b level_cleared = ", scene.level_cleared, "（应为 true）")
	_move_cam(scene)
	await _wait_real(500)   ## CLEAR 卡呼吸感 + 相机就位
	await _shot("shot7_b_exit_door_clear")

	# ============ 镜头 c：双 S 下穿高台进行中 ============
	scene._unhandled_input(_make_key(KEY_BACKSPACE))   ## 复位过关态
	await physics_frame
	# 帮助条重新亮起（含「双S 下穿平台」），标题卡保持跳过
	scene.hud.level_start_t = Time.get_ticks_msec() / 1000.0 - 5.0
	_pose(scene, Vector2(57 * 32 + 16, 5 * 32 - 0.1))
	# 机器人双 S：按下→松 4 帧→再按（0.067s < 0.28s 窗口）→ 触发下穿
	player.keys[KEY_S] = true
	player.step(1.0 / 60.0)
	player.keys.clear()
	for i in range(4):
		player.step(1.0 / 60.0)
	player.keys[KEY_S] = true
	player.step(1.0 / 60.0)
	player.keys.clear()
	# 下穿后再走 4 帧：脚已穿过台面（y > 160），尘土播到第 1 帧
	for i in range(4):
		player.step(1.0 / 60.0)
	print("  镜头c 下穿越位 y = %.1f（台面 160，楼下地面 255.9）" % player.position.y)
	_move_cam(scene)
	for i in range(3):
		await process_frame
	await _shot("shot7_c_drop_through")

	print("RENDER_RESULT: PASS")
	quit(0)


func _make_key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


## 传送 + 手动空步 settle：清按键、落地/站台、贴图回 idle
func _pose(scene: Node2D, pos: Vector2) -> void:
	var player: KairullPlayer = scene.player
	player.position = pos
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	for i in range(20):
		player.step(1.0 / 60.0)


func _move_cam(scene: Node2D) -> void:
	scene._update_room_state()
	scene.cam_tl = scene._cam_target()
	# auto_input=false 时落地/起跳尘土不自动推进——镜头 a/b 手动摘掉，避免定格残留
	var player: KairullPlayer = scene.player
	if player._drop_t <= 0.0:
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
