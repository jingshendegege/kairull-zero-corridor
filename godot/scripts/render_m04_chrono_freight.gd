extends SceneTree
## 真窗口空间/层级验收，不宣称完成机关动态挑战：镜头摆位时冻结宿主物理、保留真实美术。
## Godot --path godot --rendering-driver opengl3 --script scripts/render_m04_chrono_freight.gd

const DATA := preload("res://generated/m04_chrono_freight_data.gd")
const SESSION := preload("res://scripts/run_session.gd")
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/chrono-freight-20260905"
const ROOM_POINTS := [[9, 32], [37, 32], [73, 27], [115, 27], [143, 27],
	[156, 27], [215, 32], [245, 32], [278, 27], [310, 27], [334, 27],
	[382, 32], [432, 27], [451, 27]]
var _failed := false
var _checks := 0
var _files: Array[String] = []
var _room_images: Array[Image] = []
var _game: Node2D
var _boot: Node2D


func _init() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	_checks += 1
	print("PASS " if value else "FAIL ", message)
	_failed = _failed or not value


func _place(column: float, floor_row: float) -> void:
	var player: KairullPlayer = _game.player
	player._clear_dash_visual()
	player.set_state("gun_idle")
	player.position = Vector2(column * 32.0 + 16.0, floor_row * 32.0 - 0.1)
	player.vx = 0.0
	player.vy = 0.0
	player.dead = false
	player.hp = 999
	player.on_ground = true
	player.keys.clear()
	player._sync_sprite()
	_game._update_room_state()
	_game.cam_tl = _game._cam_target().round()
	_game.cam.position = _game.cam_tl + Vector2(680.0, 382.5)
	_game.cam.reset_smoothing()
	_game._sync_temporal_projection()
	_game._step_tactics(0.001)
	for _i in 8:
		await process_frame


func _shot(stem: String, overview := false) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.get_size() == Vector2i(1360, 765), stem + "为1360×765真窗口输出")
	var path := OUT.path_join(stem + ".png")
	_check(image.save_png(path) == OK, stem + "截图成功")
	_files.append(path)
	if overview:
		_room_images.append(image)
	print("M04_SCREENSHOT: ", path)


func _find_sniper(room: String) -> Node2D:
	for hazard: Node2D in _game.tactical_hazards:
		if hazard.hazard_type == "auto_sniper" and hazard.room_id == room:
			return hazard
	return null


func _lift_shots(index: int) -> void:
	var lift: Node2D = _game.moving_lifts[index]
	# 已实例化的真实货梯相位不重置；先等它回低站，再在站台上安排取景起点。
	for _i in 600:
		if lift.state == "bottom_wait":
			break
		_game._step_tactics(1.0 / 60.0)
	await _place(112 if index == 0 else 299, 27)
	_check(lift.supports_rider(_game.player), "第%d货梯截图起点获得真实支撑" % (index + 1))
	var middle_saved := false
	for _i in 360:
		_game._step_tactics(1.0 / 60.0)
		_game.player.step(1.0 / 60.0)
		if lift.state == "up" and lift.phase_time > 1.4 and not middle_saved:
			_check(absf(_game.player.position.y - (lift.position.y - 0.1)) < 1.1,
				"第%d货梯上行中真实承载人物" % (index + 1))
			_game.player._sync_sprite()
			await _shot("货梯-%02d-实际承载上行" % (index + 1))
			middle_saved = true
		if lift.state == "top_wait":
			break
	_check(lift.state == "top_wait" and absf(_game.player.position.y - 671.9) < 1.1,
		"第%d货梯人物实际抵达192px上站" % (index + 1))
	_game.player._sync_sprite()
	await _shot("货梯-%02d-抵达上廊接口" % (index + 1))


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("必须用实际窗口和OpenGL渲染，禁止headless替代美术验收")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = Vector2i(1360, 765)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(OUT)
	SESSION.begin_run("hard")
	_boot = load("res://scenes/m04_chrono_freight.tscn").instantiate()
	root.add_child(_boot)
	current_scene = _boot
	_game = _boot.get_node("Game")
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.player.auto_input = false
	_game.action_audio_enabled = false
	_game._sfx.clear()
	_game.hud.visible = false
	if _game.action_audio != null:
		_game.action_audio.stop_all()
	for voice: AudioStreamPlayer in _game._sfx_pool:
		voice.stop()
	_check(_game.level.map_w == 460 and _game.level.rooms.size() == 14, "真实新关数据/十四房装载")
	_check(_game.tactical_hazards.size() == 7 and _game.smoke_tactics.pickups.size() == 6,
		"困难模式7机关+6烟雾补给实际实例化")
	_check(_game.moving_lifts.size() == 2 and _game.player.moving_platforms.size() == 2,
		"两座真实货梯独立接入，不误生成狙击炮")
	_check(_game.quarantine_architecture.stair_tread_count == 50, "正式50踏面视觉接入")
	for _i in 20:
		await process_frame
	for index in ROOM_POINTS.size():
		var point: Array = ROOM_POINTS[index]
		await _place(float(point[0]), float(point[1]))
		_check(_game.current_room == index, "镜头/角色确实在第%d房" % (index + 1))
		await _shot("%02d-%s" % [index + 1, DATA.ROOMS[index]["display_name"]], true)
	# 两张上廊全景保留上下路同时可见；不只在下路截图中远远露出一条短平台。
	await _place(116, 21)
	_check(_game.level.is_platform(116 * 32.0 + 16.0, 21 * 32.0 + 1.0),
		"分拣上廊脚底是192px高的真实单向平台")
	await _shot("双层-01-分拣上廊与地面货运线")
	await _place(309, 21)
	_check(_game.level.is_platform(309 * 32.0 + 16.0, 21 * 32.0 + 1.0),
		"狙击桥上廊脚底是192px高的真实单向平台")
	await _shot("双层-02-狙击桥上下包抄线")
	for index in 2:
		await _lift_shots(index)
	for index in DATA.STAIRS.size():
		var stair: Dictionary = DATA.STAIRS[index]
		var bottom: Array = stair["bottom_cell"]
		var top: Array = stair["top_cell"]
		var left := mini(int(bottom[0]), int(top[0]))
		var right_up := String(stair["direction"]) == "right_up"
		var rank := 6 if right_up else 5
		await _place(float(left + 5), float(bottom[1]) - float(rank) * 0.5)
		_check(_game.player._standing_on_stair(), "第%d钢梯角色脚底在真实踏面" % (index + 1))
		await _shot("楼梯-%02d-%s" % [index + 1, stair["stair_id"]])

	# 后段狙击捕获真实状态机：不手绘红线、不以任意shader假装已锁定。
	await _place(310, 27)
	var first := _find_sniper("sniper_bridge")
	for _i in 145:
		_game._step_tactics(1.0 / 60.0)
	_check(first != null and first.state == "warning" and first.aim_line_alpha() > 0.5,
		"第一狙击按真实跟踪预警状态显现红线")
	await _shot("狙击-01-三秒预警红线")
	for _i in 65:
		if first.state == "locked":
			break
		_game._step_tactics(1.0 / 60.0)
	_check(first.state == "locked" and first.shot_count == 0, "锁定最后位置后半秒不立即开枪")
	await _shot("狙击-02-半秒锁定弹道")

	# 从地图真实第6补给拾取，再调用同一R事件接入点投掷；摆位只是视觉取景，不是通关bot。
	await _place(405, 27)
	_game.smoke_tactics.try_pickup(_game.player)
	_check(_game.player.carried_smoke, "拾取后携带烟雾图标亮起")
	await _place(406, 27)
	await _shot("烟雾-01-拾取头顶图标")
	await _place(433, 27)
	_game._on_smoke_throw_requested(Vector2(435 * 32.0 + 16.0, 27 * 32.0 - 0.1))
	for _i in 65:
		_game._step_tactics(1.0 / 60.0)
	_check(_game.smoke_tactics.clouds.size() == 1 and not _game.player.carried_smoke,
		"真实抛物线落地成烟，背包只消耗一次")
	_check(_game.player.smoke_cover_active(), "主角进入烟幕后染色反馈已启用")
	var enemy_covered := false
	for enemy: Node2D in _game.minions:
		enemy_covered = enemy_covered or _game.smoke_tactics.contains_actor(enemy)
	_check(enemy_covered, "同一烟雾覆盖邻近敌人，敌人也有外观反馈")
	await _shot("烟雾-02-主角敌人掩护反馈")
	_game.smoke_tactics.clear_effects()
	_game._refresh_smoke_cover()
	await _place(432, 27)
	var last := _find_sniper("terminal_crossfire")
	for _i in 175:
		_game._step_tactics(1.0 / 60.0)
	_check(last != null and last.state == "warning", "末房狙击确实能在烟雾消散后进入预警")
	await _shot("狙击-03-末房火线")
	var room_rect: Rect2i = _game.level.rooms[_game.current_room]["rect"]
	for enemy: Node2D in _game.minions:
		if room_rect.has_point(enemy.get_meta("spawn_cell", Vector2i.ZERO)):
			enemy.dead = true
			enemy.visible = false
	_game._step_tactics(1.0 / 60.0)
	_check(last.cleared_disabled and last.state == "disabled", "清空本房小兵即停机，不要求击毁炮台")
	await _shot("狙击-04-清房停机")

	# 稳定渲染帧间隔：宿主物理冻结，仅考察完整地图/装饰/人物/机关渲染，不代表战斗峰值。
	await _place(244, 32)
	for _i in 30:
		await process_frame
	var intervals: Array[float] = []
	var previous := Time.get_ticks_usec()
	for _i in 180:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
	intervals.sort()
	var total := 0.0
	for value: float in intervals:
		total += value
	var stats := "180 frames / avg %.3fms / median %.3fms / p95 %.3fms / max %.3fms" % [
		total / 180.0, intervals[90], intervals[171], intervals[179]]
	print("M04_GUI_PROFILE: ", stats)
	# 总览仅作为审阅索引；逐房原图全部保留，视觉判断不能只看缩略图。
	var overview := Image.create(1360, 1275, false, Image.FORMAT_RGB8)
	overview.fill(Color("#05070b"))
	for index in _room_images.size():
		var tile := _room_images[index].duplicate()
		tile.convert(Image.FORMAT_RGB8)
		tile.resize(453, 255, Image.INTERPOLATE_NEAREST)
		overview.blit_rect(tile, Rect2i(0, 0, 453, 255), Vector2i((index % 3) * 453, (index / 3) * 255))
	_check(overview.save_png(OUT.path_join("全关十四房-真窗口索引.png")) == OK, "十四房审阅索引保存")
	var report := FileAccess.open(OUT.path_join("地图真窗口验收记录.txt"), FileAccess.WRITE)
	if report != null:
		report.store_string("M04 true-window spatial review\nGodot: " + Engine.get_version_info()["string"]
			+ "\nDisplay: " + DisplayServer.get_name() + "\nAdapter: " + RenderingServer.get_video_adapter_name()
			+ "\nResolution:1360x765\n" + stats
			+ "\n注意：本机稳定渲染采样、宿主物理冻结；不是全平台性能保证或动态机关通关验收。\n"
			+ "十四房和五梯镜头使用摆位；烟雾/狙击画面调用生产状态机，但不冒充全关真实挑战。\n"
			+ "\n".join(_files) + "\n")
		report.close()
	else:
		_failed = true
	await create_timer(0.20).timeout
	_boot.free()
	await create_timer(0.20).timeout
	SESSION.reset_for_tests()
	print("M04_GUI_RESULT: ", "FAIL" if _failed else "PASS", " checks=", _checks)
	quit(1 if _failed else 0)
