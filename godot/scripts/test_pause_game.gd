extends SceneTree
## 主暂停真实输入/场景身份/死亡及胜利时钟/确认重试合同，不用reload伪装“继续”。
const SESSION := preload("res://scripts/run_session.gd")
const SCENE := "res://scenes/m04_chrono_freight.tscn"
var game: Node2D
var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)

func key(code: Key, pressed := true, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events() # 测试即时投递累积输入；否则按下/释放会滞留到下帧污染下个用例。

func mouse(button: MouseButton, pressed: bool, at := Vector2(400,300)) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release_all() -> void:
	for code in [KEY_ESCAPE,KEY_ENTER,KEY_R,KEY_W,KEY_S,KEY_SHIFT,KEY_CTRL,KEY_F,KEY_K]:
		key(code,false)
	mouse(MOUSE_BUTTON_LEFT,false)
	mouse(MOUSE_BUTTON_RIGHT,false)

func _prepare() -> void:
	game = current_scene.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.set_physics_process(false)
	game.player.keys.clear()
	game.player._prev_keys.clear()
	game._sfx.clear()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	game.action_audio_enabled = false
	game.action_audio.stop_all()
	game.victory_transition.set_process(false)

func _boot() -> void:
	SESSION.begin_run("hard")
	SESSION.start_level = 1
	var scene: Node2D = load(SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene
	_prepare()

func _run() -> void:
	release_all()
	_boot()
	await _test_toggle()
	await _test_pointer_and_actions()
	await _test_death_phases()
	await _cleanup()
	_boot()
	await _test_victory_clock()
	await _test_confirmed_retry()
	await _cleanup()
	_boot()
	await _test_exit_while_paused()
	SESSION.reset_for_tests()
	print("PAUSE_GAME_RESULT: %d PASS / %d FAIL" % [passed,failed])
	quit(int(failed > 0))

func _test_toggle() -> void:
	var controller: Node = game.pause_controller
	var scene_id: int = current_scene.get_instance_id()
	var at: Vector2 = game.player.position
	var hp: int = game.player.hp
	var attempt: int = SESSION.attempt
	check(not game.debug_hotkeys_enabled and not game.player.debug_hotkeys_enabled, "F/K开发快捷键默认关闭")
	key(KEY_F)
	key(KEY_F,false)
	game.player.keys = {KEY_K:true}
	game.player.step(1.0/60.0)
	game.player.keys.clear()
	check(not game.debug and not game.player.dead and game.player.hp == hp, "F不打开调试，K不触发测试自杀")
	game.player.position = at
	game.hud.show_msg("暂停前提示")
	game.hud._overlay.show_room_card("暂停前房间",1,3)
	game._next_original_kill_pitch(Time.get_ticks_usec()/1000000.0)
	var message_remaining: float = game.hud._msg_until - Time.get_ticks_usec()/1000000.0
	var kill_elapsed: float = Time.get_ticks_usec()/1000000.0 - game._last_original_kill_at
	key(KEY_ESCAPE)
	await process_frame
	check(controller.active and paused and controller.ui.menu_open, "真实Esc按下只打开一次暂停菜单")
	check(controller.ui.difficulty() == "hard", "暂停菜单保留困难3血而非回退简单")
	check(controller.process_mode == Node.PROCESS_MODE_ALWAYS \
			and game.get_node("TimeSignalOverlay").process_mode == Node.PROCESS_MODE_DISABLED,
			"控制器可在暂停中接输入，原ALWAYS时间层停止")
	key(KEY_ESCAPE,true,true)
	key(KEY_ESCAPE,false)
	check(controller.active and paused, "Esc键盘回声/抬起不会重复切换")
	await create_timer(.20,true).timeout
	game._process(2.0)
	game._physics_process(2.0)
	game.player.step(2.0)
	check(current_scene.get_instance_id() == scene_id and game.player.position == at \
			and game.player.hp == hp and SESSION.attempt == attempt, "暂停不移动/扣血/重建或增加轮次")
	key(KEY_ESCAPE)
	key(KEY_ESCAPE,false)
	await process_frame
	check(not controller.active and not paused and not controller.ui.visible,
			"第二次真实Esc直接原地继续，不回主菜单")
	check(current_scene.get_instance_id() == scene_id and game.player.position == at,
			"继续后仍是原场景、原位置")
	check(absf((game.hud._msg_until-Time.get_ticks_usec()/1000000.0)-message_remaining) < .10,
			"HUD提示剩余墙钟时间冻结，不在暂停中消失")
	check(absf((Time.get_ticks_usec()/1000000.0-game._last_original_kill_at)-kill_elapsed) < .10,
			"原击杀连杀窗口不把暂停时间算入断连")
	controller.pause_game()
	controller.ui.handle_input(_press(KEY_DOWN))
	controller.ui.handle_input(_press(KEY_ENTER))
	check(controller.ui.confirmation_action == "retry" and controller.ui.confirmation_choice == 0,
			"重试先弹确认且默认取消")
	key(KEY_ESCAPE)
	key(KEY_ESCAPE,false)
	check(not paused and not controller.active and not game._transitioning,
			"确认页Esc也直接继续，不是返回上级或自动重试")

func _press(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func _test_pointer_and_actions() -> void:
	var player: KairullPlayer = game.player
	player.auto_input = true
	player.set_carried_smoke(true)
	key(KEY_R)
	player._collect_input()
	player._prev_keys = player.keys.duplicate()
	game.pause_controller.pause_game()
	var button: Rect2 = game.pause_controller.ui.button_rect(0)
	mouse(MOUSE_BUTTON_LEFT,true,button.get_center())
	check(paused, "继续按钮按下先保持暂停，抬起才确认")
	mouse(MOUSE_BUTTON_LEFT,false,button.get_center())
	await process_frame
	player._collect_input()
	player.step(1.0/60.0)
	check(not paused and player.carried_smoke and game.smoke_tactics.grenades.is_empty() \
			and not player.batting(), "R按住时点击继续不会投烟或挥棒")
	mouse(MOUSE_BUTTON_LEFT,true,Vector2(900,430))
	player._collect_input()
	player.step(1.0/60.0)
	check(not player.carried_smoke and game.smoke_tactics.grenades.size()==1,
			"恢复后的新左键仍可正常投烟，不永久吃掉输入")
	release_all()
	player._collect_input()
	game.smoke_tactics.clear_effects()
	game.time_charge.reset()
	game.pause_controller.pause_game()
	mouse(MOUSE_BUTTON_RIGHT,true)
	key(KEY_ESCAPE)
	key(KEY_ESCAPE,false)
	game._advance_time_charge(.01)
	check(not game.time_charge.active, "暂停菜单里新按的右键不能在继续时偷启动时停")
	mouse(MOUSE_BUTTON_RIGHT,false)
	game._advance_time_charge(0.0)
	mouse(MOUSE_BUTTON_RIGHT,true)
	game._advance_time_charge(.01)
	check(game.time_charge.active, "右键释放后重新按下正常启动时停")
	mouse(MOUSE_BUTTON_RIGHT,false)
	game._advance_time_charge(0.0)
	player.auto_input = false
	player.keys.clear()

func _test_death_phases() -> void:
	game.player.force_death(game.player.position.x-40)
	game._death_prompt_ready = true
	game.pause_controller.pause_game()
	var button: Rect2 = game.pause_controller.ui.button_rect(0)
	mouse(MOUSE_BUTTON_LEFT,true,button.get_center())
	mouse(MOUSE_BUTTON_LEFT,false,button.get_center())
	check(game.time_phase == "dying" and not paused, "死亡提示时点击继续不穿透成任意键倒带")
	for phase in ["dying","rewinding","interference"]:
		if phase == "rewinding":
			game._begin_rewind()
			game._advance_rewind(.10)
		elif phase == "interference":
			game._advance_rewind(.60)
		check(game.time_phase == phase, "暂停阶段fixture确实进入"+phase)
		var progress: float = game.rewind_progress
		var elapsed: float = game._rewind_elapsed
		var mode: int = game.bg.process_mode
		var music_pitch: float = game.music.pitch_scale
		game.pause_controller.pause_game()
		await create_timer(.12,true).timeout
		game._advance_rewind(3.0)
		game._process(3.0)
		check(game.time_phase == phase and game._rewind_elapsed == elapsed \
				and game.rewind_progress == progress and not game._transitioning,
				phase+"暂停期间不跳过回放/花屏或自行切关")
		game.pause_controller.resume_game()
		check(game.bg.process_mode == mode and game._temporal_paused and game.music.pitch_scale == music_pitch,
				phase+"恢复保留原死亡冻结模式和音乐音高")

func _test_victory_clock() -> void:
	game.level_cleared = true
	game._begin_victory()
	game.victory_transition.advance(.2)
	var elapsed: float = game.victory_transition.elapsed
	game.pause_controller.pause_game()
	check(game.pause_controller.ui.layer > game.victory_transition.layer, "暂停菜单位于胜利黑幕上方")
	await create_timer(.20,true).timeout
	check(game.victory_transition.elapsed == elapsed, "胜利淡黑在暂停期间不继续")
	game.pause_controller.resume_game()
	game.victory_transition._process(.01)
	check(game.victory_transition.elapsed - elapsed < .1, "恢复胜利墙钟不一次补算整段暂停时长")
	check(not game.hud.visible and not game.player.is_physics_processing(),
			"暂停恢复不误开启已由胜利隐藏的HUD或角色物理")
	await _cleanup()
	_boot()

func _test_confirmed_retry() -> void:
	var config: Dictionary = CorridorLevel.active_checkpoints[0]
	for enemy: Node2D in game.minions:
		var cell: Vector2i = enemy.get_meta("spawn_cell")
		if config.required_clear_rooms.has(game.level.room_at(cell.x*32+16,cell.y*32+16)):
			enemy.dead = true
	game.player.position = game._checkpoint_beacons[int(config.room_index)].position
	game.player.on_ground = true
	game._update_room_state()
	game._update_campaign_progress(0.0)
	var saved: Dictionary = SESSION.checkpoint.duplicate(true)
	var point: Vector2 = game.player.position
	var scene_id: int = current_scene.get_instance_id()
	game.player.position.x += 50.0
	game.pause_controller.pause_game()
	var ui: CanvasLayer = game.pause_controller.ui
	check(ui.has_checkpoint() and ui.button_label(1) == "从检查点重试", "暂停菜单读取已激活的当前检查点")
	ui.handle_input(_press(KEY_DOWN))
	ui.handle_input(_press(KEY_ENTER))
	check(game.time_phase == "playing" and SESSION.checkpoint == saved, "只选重试不立即重开或更改存档")
	ui.handle_input(_press(KEY_RIGHT))
	ui.handle_input(_press(KEY_ENTER))
	check(not paused and game.time_phase == "rewinding", "明确确认才解除暂停并走原短倒带重试")
	game._advance_rewind(game.REWIND_DURATION+game.INTERFERENCE_DURATION+.01)
	for frame in 4:
		await process_frame
	_prepare()
	check(current_scene.get_instance_id()!=scene_id and game.player.position.distance_to(point)<1.0 \
			and SESSION.checkpoint == saved and game.player.hp==3,
			"确认重试实际重建到检查点，保留困难3血与原存点")

func _test_exit_while_paused() -> void:
	game.pause_controller.pause_game()
	check(paused, "直接卸载测试先进入主暂停")
	current_scene.free()
	current_scene = null
	await create_timer(.25,true).timeout # 给真实音频线程完成销毁，避免测试进程瞬退的异步资源告警。
	check(not paused, "外部卸载暂停场景也释放SceneTree.paused，不锁住下个场景")

func _cleanup() -> void:
	release_all()
	if is_instance_valid(current_scene):
		current_scene.free()
	current_scene = null
	await create_timer(.20,true).timeout
	SESSION.reset_for_tests()
