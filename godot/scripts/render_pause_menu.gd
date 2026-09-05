extends SceneTree
## 真窗口只使用生产game.pause_controller.ui；真实parse+flush Esc/鼠标，不另挂暂停UI。
## M05存点前段清除是明确视觉fixture，激活仍走生产_update_campaign_progress。
const SESSION := preload("res://scripts/run_session.gd")
const OUT := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/pause-menu-20260906"
var checks := 0
var failed := false
var _game: Node2D
var _files: Array[String] = []
var _freeze_changes: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	checks += 1
	failed = failed or not value
	print("PASS " if value else "FAIL ", label)


func _key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events() # 明确投递一次累积事件，不再调用controller方法补投第二遍。


func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(point: Vector2) -> void:
	_mouse(point, true)
	await process_frame
	_mouse(point, false)
	for _i in 2:
		await process_frame


func _escape(want_active: bool) -> bool:
	_key(KEY_ESCAPE, true)
	for _i in 3:
		await process_frame
	var value: bool = _game.pause_controller.active == want_active and paused == want_active \
		and _game.pause_controller.ui.menu_open == want_active
	_key(KEY_ESCAPE, false)
	for _i in 2:
		await process_frame
	check(value and _game.pause_controller.active == want_active,
		"真实Esc按下/抬起只切换一次：" + ("打开暂停" if want_active else "原地继续"))
	return value


func _place(at: Vector2) -> void:
	_game.player.position = at
	_game.player.vx = 0.0
	_game.player.vy = 0.0
	_game.player.on_ground = true
	_game.player.keys.clear()
	_game.player._sync_sprite()
	_game._update_room_state()
	_game.cam_tl = _game._cam_target().round()
	_game.cam.position = _game.cam_tl + Vector2(680, 382.5)
	_game.cam.reset_smoothing()
	_game.cam.force_update_scroll()
	_game._sync_temporal_projection()


func _shot(stem: String) -> Image:
	for _i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == Vector2i(1360, 765), stem + "为1360×765真窗口")
	var path := OUT.path_join(stem + ".png")
	check(image.save_png(path) == OK, stem + "写盘成功")
	_files.append(path)
	print("PAUSE_SCREENSHOT: ", path)
	return image


func _review(scene_path: String, prefix: String, checkpoint: bool) -> void:
	SESSION.begin_run("zero" if checkpoint else "easy")
	var boot: Node2D = load(scene_path).instantiate()
	root.add_child(boot)
	current_scene = boot
	_game = boot.get_node("Game")
	# 只停住宿主用于稳定选取画面；背景/墙灯仍正常process，下面由真正暂停冻结它们。
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.player.auto_input = false
	_game.player.keys.clear()
	_game.action_audio_enabled = false
	_game._sfx.clear()
	if _game.action_audio != null:
		_game.action_audio.stop_all()
	_place(_game.level.spawn + Vector2(64, 0))
	if checkpoint:
		var config: Dictionary = CorridorLevel.active_checkpoints[0]
		for enemy: Node2D in _game.minions:
			var cell: Vector2i = enemy.get_meta("spawn_cell", Vector2i(-1, -1))
			var room: int = _game.level.room_at(cell.x * 32 + 16, cell.y * 32 + 16)
			if room in config.required_clear_rooms:
				enemy.dead = true
				enemy.visible = false
		var beacon: Node2D = _game._checkpoint_beacons[int(config.room_index)]
		_place(beacon.position)
		_game._update_campaign_progress(0.0)
		check(_game._checkpoint_index == int(config.room_index) and not SESSION.checkpoint.is_empty(),
			prefix + "通过生产逻辑激活存点，暂停信息不是虚构context")
		_place(beacon.position + Vector2(48, 0))
	for _i in 15:
		await process_frame
	var scene_id: int = boot.get_instance_id()
	var player_id: int = _game.player.get_instance_id()
	var at: Vector2 = _game.player.position
	var attempt: int = SESSION.attempt
	var music_id: int = _game.music.get_instance_id()
	await _shot(prefix + "-01-暂停前现场")
	if not await _escape(true):
		boot.free()
		await create_timer(.15, true).timeout
		return
	var ui: CanvasLayer = _game.pause_controller.ui
	check(ui.get_parent() == _game.pause_controller and ui.selected_index == 0,
		prefix + "使用生产唯一UI且默认继续")
	check(ui.has_checkpoint() == checkpoint, prefix + "显示真实检查点/入口重试分支")
	var first := await _shot(prefix + "-02-暂停菜单默认继续")
	var phase: float = _game.quarantine_architecture._phase
	var audio_position: float = _game.music.get_playback_position()
	await create_timer(.25, true).timeout
	var held := await _shot(prefix + "-03-暂停现场保持静止")
	var changed := 0
	var panel: Rect2 = ui.panel_rect().grow(4)
	for y in range(0, 765, 4):
		for x in range(0, 1360, 4):
			if not panel.has_point(Vector2(x, y)) and first.get_pixel(x, y) != held.get_pixel(x, y):
				changed += 1
	_freeze_changes.append(changed)
	check(changed == 0 and _game.quarantine_architecture._phase == phase,
		prefix + "暂停后底图采样零变化，背景动画真正停住")
	check(_game.music.stream_paused and absf(_game.music.get_playback_position() - audio_position) < .04,
		prefix + "同一个音乐播放器进度暂停，不stop/replay")
	await _click(ui.button_rect(1).get_center())
	check(ui.confirmation_action == "retry" and ui.confirmation_choice == 0 and paused,
		prefix + "重试二次确认默认取消，未直接重开")
	await _shot(prefix + "-04-重试二次确认")
	await _click(ui.confirm_button_rect(0).get_center())
	check(ui.confirmation_action.is_empty() and boot.get_instance_id() == scene_id,
		prefix + "取消确认保留当前现场")
	await _click(ui.button_rect(2).get_center())
	check(ui.confirmation_action == "menu", prefix + "返回菜单显示清除检查点警告")
	await _shot(prefix + "-05-返回菜单确认警告")
	if not await _escape(false):
		boot.free()
		await create_timer(.15, true).timeout
		return
	check(boot.get_instance_id() == scene_id and _game.player.get_instance_id() == player_id \
		and _game.player.position == at and SESSION.attempt == attempt,
		prefix + "确认页Esc也原地继续，未重载场景/人物/轮次")
	check(_game.music.get_instance_id() == music_id and not _game.music.stream_paused,
		prefix + "恢复原音乐实例")
	await _shot(prefix + "-06-Esc原地继续")
	if not await _escape(true):
		boot.free()
		await create_timer(.15, true).timeout
		return
	await _click(ui.button_rect(0).get_center())
	check(not paused and not ui.menu_open and boot.get_instance_id() == scene_id,
		prefix + "生产鼠标抬起继续按钮正常恢复同一现场")
	if checkpoint:
		# 胜利黑幕上也能用同一个暂停UI，layer100压住Victory80，不另造菜单。
		_game.level_cleared = true
		_game._begin_victory()
		_game.victory_transition.advance(1.8)
		if await _escape(true):
			check(ui.layer > _game.victory_transition.layer, "暂停层盖住胜利黑幕")
			await _shot("M05-07-胜利黑幕上的暂停菜单")
			await _escape(false)
	await create_timer(.20, true).timeout
	boot.free()
	await create_timer(.20, true).timeout


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("暂停菜单观感必须用真实窗口")
		quit(1)
		return
	root.size = Vector2i(1360, 765)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(OUT)
	await _review("res://scenes/m01_protocol_quarantine.tscn", "M01", false)
	await _review("res://scenes/m05_vertical_freight.tscn", "M05", true)
	SESSION.reset_for_tests()
	var report := FileAccess.open(OUT.path_join("暂停真窗口验收记录.txt"), FileAccess.WRITE)
	if report:
		report.store_string("Production pause-controller UI review\n" + Engine.get_version_info()["string"]
			+ "\nGPU: " + RenderingServer.get_video_adapter_name()
			+ "\n1360x765 / Input.parse_input_event + flush_buffered_events\n"
			+ "Background changed sample counts: " + str(_freeze_changes)
			+ "\nM05存点前段清敌是视觉fixture，保存和暂停均走生产方法；不冒称完整战斗通关。\n"
			+ "\n".join(_files) + "\n")
		report.close()
	print("PAUSE_UI_RENDER_RESULT: ", "FAIL" if failed else "PASS", " checks=", checks)
	quit(int(failed))
