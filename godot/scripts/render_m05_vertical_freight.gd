extends SceneTree
## 第三关真窗口空间巡检：六层双塔/中央桥、贯通井、四部576px长程货梯。
## 镜头摆位冻结其他AI，不宣称完成动态战斗通关；货梯承载画面由生产函数实际推进。

const DATA := preload("res://generated/m05_vertical_freight_data.gd")
const SESSION := preload("res://scripts/run_session.gd")
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/vertical-freight-20260905"
const FLOORS: Array[int] = [15, 33, 51, 69, 87, 105]
var _game: Node2D
var _boot: Node2D
var _failed := false
var _checks := 0
var _shots: Array[String] = []
var _overview: Array[Image] = []


func _init() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	_checks += 1
	_failed = _failed or not value
	print("PASS " if value else "FAIL ", label)


func _sync_view() -> void:
	_game._update_room_state()
	_game.cam_tl = _game._cam_target().round()
	_game.cam.position = _game.cam_tl + Vector2(680.0, 382.5)
	_game.cam.reset_smoothing()
	_game._sync_temporal_projection()


func _place(column: int, floor_row: float) -> void:
	var player: KairullPlayer = _game.player
	player._clear_dash_visual()
	player.set_state("gun_idle")
	player.position = Vector2(column * 32.0 + 16.0, floor_row * 32.0 - .1)
	player.vx = 0.0
	player.vy = 0.0
	player.dead = false
	player.hp = 999
	player.on_ground = true
	player.keys.clear()
	player._sync_sprite()
	_sync_view()
	_game._step_tactics(.001)
	for _i in 8:
		await process_frame


func _camera_top(world_top: float) -> void:
	# 仅供关卡巡检的人工上看/下看，不新增玩家自由摄像机功能。
	_game.cam_tl.y = roundf(world_top)
	_game.cam.position = _game.cam_tl + Vector2(680.0, 382.5)
	_game.cam.reset_smoothing()
	_game._sync_temporal_projection()
	for _i in 8:
		await process_frame


func _shot(stem: String, overview := false) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.get_size() == Vector2i(1360, 765), stem + "输出为1360×765真窗口")
	var path := OUT.path_join(stem + ".png")
	_check(image.save_png(path) == OK, stem + "截图写入成功")
	_shots.append(path)
	if overview:
		_overview.append(image)
	print("M05_SCREENSHOT: ", path)


func _lift_review(index: int) -> void:
	var lift: Node2D = _game.moving_lifts[index]
	# 不改平台相位；等真实循环回到低站，再安放巡检乘客起点。
	for _i in 1000:
		if lift.state == "bottom_wait":
			break
		_game._step_tactics(1.0 / 60.0)
	await _place(floori(lift.position.x / 32.0), lift.bottom_y / 32.0)
	_check(lift.supports_rider(_game.player), "第%d长梯低站获得真实脚底支撑" % (index + 1))
	_check(is_equal_approx(lift.bottom_y - lift.top_y, 576.0), "第%d长梯跨整层576px" % (index + 1))
	await _shot("货梯-%02d-01-底站与真实井口" % (index + 1))
	var mid_saved := false
	var tracked := true
	for _i in 420:
		_game._step_tactics(1.0 / 60.0)
		_game.player.step(1.0 / 60.0)
		tracked = tracked and absf(_game.player.position.y - (lift.position.y - .1)) < 1.1
		if lift.state == "up" and lift.phase_time >= 1.8 and not mid_saved:
			_sync_view()
			_game.player._sync_sprite()
			_check(tracked and not lift.stalled, "第%d长梯在开放井道中实际承载，没有顶板卡住" % (index + 1))
			for _j in 5:
				await process_frame
			await _shot("货梯-%02d-02-576px井道中途承载" % (index + 1))
			mid_saved = true
		if lift.state == "top_wait":
			break
	_check(mid_saved and tracked and lift.state == "top_wait", "第%d货梯乘客实际到达上站，非摆位假装升到顶" % (index + 1))
	_sync_view()
	_game.player._sync_sprite()
	for _i in 5:
		await process_frame
	await _shot("货梯-%02d-03-主要楼层上站" % (index + 1))
	# 再走出井口确认白发人物站到真正楼板上，而不是悬在平台末端。
	var target_x: float = lift.position.x + 96.0
	for _i in 90:
		if _game.player.position.x >= target_x - 7.0:
			break
		_game.player.keys = {KEY_D: true}
		_game._step_tactics(1.0 / 60.0)
		_game.player.step(1.0 / 60.0)
	_game.player.keys.clear()
	_check(_game.level.is_platform(_game.player.position.x, _game.player.position.y + 1.1)
		and absf(_game.player.position.y - (lift.top_y - .1)) < 1.1,
		"第%d货梯上站可直接走出，不穿楼板、不坠回竖井" % (index + 1))
	_sync_view()
	for _i in 5:
		await process_frame
	await _shot("货梯-%02d-04-走出停靠缓冲站" % (index + 1))


func _smoke_review() -> void:
	# 六层取景已通过中枢真实补给自动拾取；抛投仍走游戏生产接入点。
	_check(_game.player.carried_smoke, "视觉巡检从实际地图补给携带烟雾")
	await _place(121, 15)
	var sniper: Node2D = null
	for hazard: Node2D in _game.tactical_hazards:
		if hazard.hazard_type == "auto_sniper" and hazard.room_id == "right_15":
			sniper = hazard
	for _i in 140:
		_game._step_tactics(1.0 / 60.0)
	_check(sniper != null and sniper.state == "warning", "塔冠狙击真实进入跟踪预警")
	await _shot("烟雾-01-塔冠投掷前与狙击预警")
	_game._on_smoke_throw_requested(Vector2(123 * 32.0 + 16.0, 15 * 32.0 - .1))
	for _i in 65:
		_game._step_tactics(1.0 / 60.0)
	_check(_game.smoke_tactics.clouds.size() == 1 and _game.player.smoke_cover_active(),
		"真实抛物线成烟，主角进入横向半径336px烟幕")
	var covered := 0
	for enemy: Node2D in _game.minions:
		if _game.smoke_tactics.contains_actor(enemy):
			covered += 1
	_check(covered > 0 and _game.player._sprite.self_modulate.r < .1,
		"烟内主角深剪影与同区敌人同时实际启用")
	_check(sniper != null and sniper.state not in ["warning", "locked"],
		"烟幕取消塔冠狙击预警和锁定")
	await _shot("烟雾-02-主角浅青边敌人暗剪影与消失锁线")
	_game.smoke_tactics.clear_effects()
	_game._refresh_smoke_cover()
	for _i in 5:
		await process_frame
	await _shot("烟雾-03-消散后原人物与背景恢复")


func _save_gpu_index() -> void:
	# 原图直接作为GPU纹理排入独立画布；不CPU缩图、抠图、补画或编辑游戏截图。
	var sheet := SubViewport.new()
	sheet.size = Vector2i(1360, 1530)
	sheet.disable_3d = true
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var background := ColorRect.new()
	background.color = Color("#05070b")
	background.size = Vector2(1360, 1530)
	sheet.add_child(background)
	for index in _overview.size():
		var tile := TextureRect.new()
		tile.texture = ImageTexture.create_from_image(_overview[index])
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_SCALE
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tile.position = Vector2((index % 3) * 453, (index / 3) * 255)
		tile.size = Vector2(453, 255)
		sheet.add_child(tile)
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	_check(sheet.get_texture().get_image().save_png(OUT.path_join("六层错层双塔-真窗口纵向索引.png")) == OK,
		"六层三列原图GPU纵向索引保存")
	sheet.queue_free()


func _tower_right_review() -> void:
	# 与平台上的原刷点留出视觉距离，避免巡检摆位让主角被冻结枪手遮住。
	await _place(120, 11)
	_check(_game.level.is_platform(_game.player.position.x, _game.player.position.y + 1.1),
		"塔冠右高路摆位同步抬高后的真实脚底支撑")
	await _shot("塔冠-02-右塔高路与下层敌箱")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("第三关美术巡检必须是真窗口，headless不能替代")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = Vector2i(1360, 765)
	root.title = "M05 垂直货运井 - OpenGL 真窗口视觉巡检"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(OUT)
	SESSION.begin_run("hard")
	_boot = load("res://scenes/m05_vertical_freight.tscn").instantiate()
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
	_check(_game.level.map_w == 144 and _game.level.map_h == 114, "真正144×114垂直图装载")
	_check(_game.level.rooms.size() == 20 and _game.minions.size() == 52, "20房和52守军来自当前生成数据")
	_check(_game.moving_lifts.size() == 4 and _game.tactical_hazards.size() == 13, "四长梯及困难模式13机关分开建立")
	_check(_game.quarantine_architecture.stair_semantics_valid and _game.quarantine_architecture.stair_tread_count == 72,
		"六段接梯72踏面视觉/物理匹配")
	_check(_game.has_node("FloorWayfinding") and _game.get_node("FloorWayfinding").sign_count == 6,
		"六层导向色条/文字按ROOM_FLOORS接入，仅第三关显示")
	for _i in 20:
		await process_frame
	if OS.get_cmdline_user_args().has("--tower-only"):
		await _place(74, 51)
		await _tower_right_review()
		_boot.free()
		await create_timer(.20).timeout
		SESSION.reset_for_tests()
		print("M05_TOWER_GUI_RESULT: ", "FAIL" if _failed else "PASS", " checks=", _checks)
		quit(1 if _failed else 0)
		return

	# 纵向索引自塔顶向井底排列，每行左塔/中桥/右塔三图，保留384~576px层高关系。
	for index in FLOORS.size():
		var floor := FLOORS[index]
		await _place(26 if floor == 87 else 32, floor + 6)
		_check(_game.level.rooms[_game.current_room]["role"] == "main", "第%d层左塔是实际战斗室" % (index + 1))
		await _shot("层%02d-1-左塔-row%d" % [index + 1, floor + 6], true)
		await _place(74, floor)
		_check(_game.level.rooms[_game.current_room]["role"] == "connector", "第%d层中央桥是实际独立安全房框" % (index + 1))
		await _shot("层%02d-2-中央桥-row%d" % [index + 1, floor], true)
		await _place(123, floor)
		_check(_game.level.rooms[_game.current_room]["role"] == "main", "第%d层右塔是实际战斗室" % (index + 1))
		await _shot("层%02d-3-右塔-row%d" % [index + 1, floor], true)
	await _place(17, 21)
	_check(_game.level.is_platform(17 * 32.0, 17 * 32.0 + 1.0), "塔冠左上廊真实抬高到128px净空")
	await _shot("塔冠净空-01-左塔低路白发头顶")
	await _place(19, 17)
	await _shot("塔冠净空-02-左塔128px上路与64px踏台")
	await _place(123, 15)
	_check(_game.level.is_platform(123 * 32.0, 11 * 32.0 + 1.0), "塔冠右上廊真实抬高到128px净空")
	await _shot("塔冠净空-03-右塔低路白发头顶")
	await _place(121, 11)
	await _shot("塔冠净空-04-右塔128px上路与侧入口")

	await _place(74, 51)
	await _camera_top(51 * 32.0 - 650.0)
	await _shot("中枢-01-向上观察上联楼层")
	await _camera_top(51 * 32.0 - 130.0)
	await _shot("中枢-02-向下观察下井通路")
	await _place(61, 45)
	_check(_game.level.rooms[_game.current_room]["room_id"] == "maintenance_spine", "维修栈道画面位于贯通井内")
	await _shot("竖井-01-维修跳台与错层接梯")
	await _place(92, 69)
	_check(_game.level.rooms[_game.current_room]["room_id"] == "lift_spine", "长梯画面位于真实贯通货梯井内")
	await _shot("竖井-02-双列导轨与主要站台")
	for index in 4:
		await _lift_review(index)
	for index in DATA.STAIRS.size():
		var stair: Dictionary = DATA.STAIRS[index]
		var bottom: Array = stair["bottom_cell"]
		await _place(int(bottom[0]) + 5, float(bottom[1]) - 3.0)
		_check(_game.player._standing_on_stair(), "第%d钢梯94px人物立于实际中段踏面" % (index + 1))
		await _shot("钢梯-%02d-94px人物与连续踏面" % (index + 1))
	await _place(18, 17)
	_check(_game.level.is_platform(_game.player.position.x, _game.player.position.y + 1.1),
		"塔冠左高路摆位同步抬高后的真实脚底支撑")
	await _shot("塔冠-01-左塔高路与下层敌箱")
	await _tower_right_review()
	await _smoke_review()

	await _place(74, 51)
	for _i in 30:
		await process_frame
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	for _i in 180:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append(float(now - last) / 1000.0)
		last = now
	var total := 0.0
	for value in samples:
		total += value
	samples.sort()
	var timing := "180 frames / avg %.3fms / median %.3fms / p95 %.3fms / max %.3fms" % [
		total / 180.0, samples[90], samples[171], samples[179]]
	print("M05_GUI_PROFILE: ", timing)
	await _save_gpu_index()
	var report := FileAccess.open(OUT.path_join("第三关真窗口验收记录.txt"), FileAccess.WRITE)
	if report != null:
		report.store_string("M05 VerticalFreight true-window review\n" + Engine.get_version_info()["string"]
			+ "\nDisplay: " + DisplayServer.get_name() + "\nGPU: " + RenderingServer.get_video_adapter_name()
			+ "\nWorld:144x114 / 20 rooms / 52 enemies / 26 cargo / 4x576px lifts\nWindow:1360x765\n"
			+ timing + "\n静态180帧采样冻结其他AI/宿主物理，不是动态战斗压力测试或全平台保证。\n"
			+ "层/井/人工上看下看是镜头摆位；四长梯中途、上站和走出站台使用实际承载推进。\n"
			+ "六段钢梯和塔冠高路为摆位检查94px人物视觉净空；烟幕由真实拾取抛投生成。\n"
			+ "\n".join(_shots) + "\n")
		report.close()
	else:
		_failed = true
	await create_timer(.20).timeout
	_boot.free()
	await create_timer(.20).timeout
	SESSION.reset_for_tests()
	print("M05_GUI_RESULT: ", "FAIL" if _failed else "PASS", " checks=", _checks)
	quit(1 if _failed else 0)
