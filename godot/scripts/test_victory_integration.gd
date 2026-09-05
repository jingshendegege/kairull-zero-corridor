extends SceneTree
## 真实出口接入胜利白字/慢黑幕，完成后Enter必须清存点重新开局，音乐仍连续。
const SESSION := preload("res://scripts/run_session.gd")
const SCENE := "res://scenes/m05_vertical_freight.tscn" # 最终关才保留Enter重玩，前两关另验自动接续。
var passed := 0
var failed := 0
var game: Node2D

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)

func _prepare() -> void:
	game = current_scene.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.set_physics_process(false)
	game._sfx.clear()
	game.action_audio_enabled = false
	game.action_audio.stop_all()
	game.victory_transition.set_process(false)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func _run() -> void:
	SESSION.begin_run("hard")
	var boot: Node2D = load(SCENE).instantiate()
	root.add_child(boot)
	current_scene = boot
	_prepare()
	var config: Dictionary = CorridorLevel.active_checkpoints[0]
	for enemy: Node2D in game.minions:
		var cell: Vector2i = enemy.get_meta("spawn_cell")
		var room: int = game.level.room_at(cell.x*32+16,cell.y*32+16)
		if config.required_clear_rooms.has(room):
			enemy.dead = true
	game.player.position = game._checkpoint_beacons[int(config.room_index)].position
	game.player.on_ground = true
	game._update_room_state()
	game._update_campaign_progress(0.0)
	check(not SESSION.checkpoint.is_empty(), "通关fixture先实际激活中段检查点")
	for enemy: Node2D in game.minions:
		enemy.dead = true
	game.player.position = game.level.exit_point
	game.player.on_ground = true
	await create_timer(.12).timeout
	game.music.play(7.0)
	await create_timer(.12).timeout
	var music_id: int = game.music.get_instance_id()
	var playback_id: int = game.music.get_stream_playback().get_instance_id()
	game._physics_process(0.0)
	check(game.level_cleared and game._victory_started, "真正出口碰撞且全清后才开始胜利结尾")
	check(not game.hud.visible and not game.get_node("TimeSignalOverlay").visible,
			"同帧隐藏原CLEAR与时间HUD，白字不叠旧结算")
	check(game.time_phase == "playing" and not game.time_charge.active,
			"胜利不进入dying/rewinding/interference任何死亡阶段")
	check(not game.player.is_physics_processing() and not game._temporal_paused,
			"停住主角，不遗留时停冻结状态")
	check(game.get_node("VictoryTransition") == game.victory_transition,
			"主线只挂一个生产胜利层")
	game.victory_transition.advance(.2)
	check(game.victory_transition.fade_progress > 0 and game.victory_transition.fade_progress < 1.0 \
			and game.victory_transition.text_opacity > 0.0,
			"0.2秒白字渐显且背景未瞬间全黑")
	var old_id: int = current_scene.get_instance_id()
	_key(KEY_ENTER)
	check(not game._transitioning and current_scene.get_instance_id() == old_id,
			"淡黑未结束前Enter不能跳过整段收束")
	_key(KEY_BACKSPACE)
	check(game.level_cleared and game.time_phase == "playing", "胜利时Backspace不误播死亡花屏")
	var health: int = game.player.hp
	game.enemy_bullets.append({"x":game.player.position.x,"y":game.player.position.y-50,
			"vx":100.0,"vy":0.0,"life":1.0})
	game._physics_process(.5)
	check(game.player.hp == health and not game.player.dead,
			"通关期间危险残弹/机关不会在黑幕下再杀主角")
	game.victory_transition.advance(1.2)
	check(game.victory_transition.fade_progress == 1.0 and game.victory_transition.text_opacity == 1.0,
			"1.4秒背景全黑而白字保留")
	check(not game.victory_transition.is_ready(), "全黑后保留短停顿")
	game.victory_transition.advance(.4)
	check(game.victory_transition.is_ready() and game.victory_transition.prompt_opacity > 0.0,
			"1.8秒显示重玩/返回菜单的小字")
	check(game.music.get_instance_id() == music_id and game.music.playing and game.music.pitch_scale == 1.0,
			"胜利黑屏音乐继续原声播放，不走死亡降调")
	_key(KEY_ENTER)
	for frame in 4:
		await process_frame
	_prepare()
	await create_timer(.12).timeout
	check(current_scene.get_instance_id() != old_id and SESSION.checkpoint.is_empty(),
			"通关确认真正重建并清除上一轮检查点")
	check(game.player.position.distance_to(game.level.spawn) < 1.0 and game._checkpoint_index == -1,
			"明确重新挑战从关卡入口，不从旧半程开始")
	check(game.player.hp == 3 and not game.level_cleared and not game.victory_transition.visible,
			"困难3血和干净胜利状态正确重置")
	check(game.music.get_instance_id() == music_id \
			and game.music.get_stream_playback().get_instance_id() == playback_id \
			and game.music.get_playback_position() >= 7.0,
			"通关重玩保留同一音乐播放器与Playback进度")
	current_scene.free()
	current_scene = null
	SESSION.reset_for_tests()
	await create_timer(.15).timeout
	print("VICTORY_INTEGRATION_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
