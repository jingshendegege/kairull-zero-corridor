extends Node
## Esc是独立主暂停，不取消时停、不重载场景；只由明确菜单确认才重试/退出。

const SESSION := preload("res://scripts/run_session.gd")
var host: Node2D
var ui: CanvasLayer
var active := false
var _started_usec := 0
var _mode_snapshot: Array[Dictionary] = []
var _audio_snapshot: Array[Dictionary] = []
var _before_keys: Dictionary = {}
var _mouse_mode := Input.MOUSE_MODE_HIDDEN


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui = load("res://scripts/pause_menu.gd").new()
	ui.name = "PauseMenu"
	ui.host = host
	add_child(ui)
	ui.resume_requested.connect(resume_game)
	ui.retry_requested.connect(retry_from_pause)
	ui.menu_requested.connect(return_to_main_menu)
	ui.difficulty_requested.connect(change_difficulty)


func change_difficulty(mode: String) -> void:
	if not active or not is_instance_valid(host) or mode not in SESSION.DIFFICULTIES:
		return
	SESSION.difficulty = mode
	host.player.configure_max_health(SESSION.health_for_difficulty(mode), false)
	# 用户主动改难度允许沿用本轮存点；不增轮次、不复活尸体，也不能通过反复切换刷血。
	if SESSION.checkpoint.get("scene", "") == CorridorLevel.active_restart_scene:
		SESSION.checkpoint["difficulty"] = mode
	ui.set_difficulty(mode)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(host) or host._transitioning:
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		var viewport := get_viewport()
		viewport.set_input_as_handled() # 在死亡“任意键”和角色轮询前消费，不在同帧开又关。
		if event.pressed and not event.echo:
			toggle_pause()
		viewport.set_input_as_handled() # 鼠标显隐若触发嵌套事件，返回时仍保证原Esc已消费。
		return
	if active:
		var viewport := get_viewport()
		viewport.set_input_as_handled() # 先消费再回调，继续按钮的左键不能穿透成挥棒/投烟。
		ui.handle_input(event)
		viewport.set_input_as_handled()


func toggle_pause() -> void:
	if active:
		resume_game()
	else:
		pause_game()


func pause_game() -> void:
	if active or not is_instance_valid(host) or host._transitioning or get_tree().paused:
		return
	_started_usec = Time.get_ticks_usec()
	_mouse_mode = Input.mouse_mode
	_before_keys = host.player.pause_input_snapshot()
	_mode_snapshot.clear()
	_audio_snapshot.clear()
	var seen_audio: Dictionary = {}
	_capture_audio(host.music, seen_audio)
	for node: Node in host.find_children("*", "", true, false):
		if node == self or is_ancestor_of(node):
			continue
		_capture_audio(node, seen_audio)
		# 普通节点由SceneTree暂停；原ALWAYS必须显式停，恢复精确模式而不是一律INHERIT。
		if node.process_mode in [Node.PROCESS_MODE_ALWAYS, Node.PROCESS_MODE_WHEN_PAUSED]:
			_mode_snapshot.append({"ref": weakref(node), "mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED
	active = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var progress: Dictionary = host.run_progress()
	ui.show_menu({"difficulty": SESSION.difficulty,
		"checkpoint": progress.checkpoint, "has_checkpoint": host._checkpoint_index >= 0 and not host.level_cleared,
		"level_title": CorridorLevel.active_title})


func _capture_audio(node: Node, seen: Dictionary) -> void:
	if not is_instance_valid(node) or seen.has(node.get_instance_id()):
		return
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		seen[node.get_instance_id()] = true
		_audio_snapshot.append({"ref": weakref(node), "paused": node.stream_paused})
		node.stream_paused = true # 同一个播放器和Playback，不stop/play/seek，音量与音高都不改。


func resume_game() -> void:
	_finish_pause(true)


func _finish_pause(sync_input: bool) -> void:
	if not active:
		return
	var duration_usec := maxi(0, Time.get_ticks_usec() - _started_usec)
	_compensate_wall_clocks(duration_usec)
	for entry: Dictionary in _mode_snapshot:
		var node: Node = entry.ref.get_ref()
		if is_instance_valid(node):
			node.process_mode = entry.mode
	_mode_snapshot.clear()
	# 先让引擎恢复Pausable，再还原显式stream_paused，保留本来就暂停的声部。
	get_tree().paused = false
	for entry: Dictionary in _audio_snapshot:
		var node: Node = entry.ref.get_ref()
		if is_instance_valid(node):
			node.stream_paused = bool(entry.paused)
	_audio_snapshot.clear()
	active = false
	if is_instance_valid(ui):
		ui.hide_menu()
	Input.set_mouse_mode(_mouse_mode)
	if sync_input and is_instance_valid(host) and is_instance_valid(host.player):
		host.player.sync_input_after_pause(_before_keys)
	_before_keys.clear()


func _compensate_wall_clocks(duration_usec: int) -> void:
	if not is_instance_valid(host):
		return
	var seconds := float(duration_usec) / 1000000.0
	# 逻辑dt自然冻结；只有墙钟截止点顺延，恢复不能跳完胜利淡黑或悄悄断连杀。
	if is_finite(host._last_original_kill_at):
		host._last_original_kill_at += seconds
	if is_instance_valid(host.hud):
		host.hud.level_start_t += seconds
		host.hud._msg_until += seconds
		if is_instance_valid(host.hud._overlay):
			host.hud._overlay._room_card_until += seconds
	if is_instance_valid(host.victory_transition):
		host.victory_transition._last_usec += duration_usec
	if is_instance_valid(host.action_audio) and host.action_audio.clock_override < 0.0:
		if is_finite(host.action_audio._last_kill_at):
			host.action_audio._last_kill_at += seconds
		for index in host.action_audio._voice_until.size():
			host.action_audio._voice_until[index] += seconds


func retry_from_pause() -> void:
	if not active or host._transitioning:
		return
	resume_game()
	host.retry_from_pause_menu()


func return_to_main_menu() -> void:
	if not active or host._transitioning:
		return
	resume_game()
	host.return_to_main_menu()


func _exit_tree() -> void:
	# 关闭窗口/外部卸载也释放主暂停，不能把下一场景或测试树永久留在paused。
	_finish_pause(false)
