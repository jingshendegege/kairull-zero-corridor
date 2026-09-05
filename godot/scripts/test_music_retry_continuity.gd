extends SceneTree
## 用真实整关重载和音频线程时间验收：死亡回溯不重新播放BGM，退出则释放，不能靠记录秒数伪造续播。
const SESSION := preload("res://scripts/run_session.gd")
const LEVEL_SCENE := "res://scenes/m01_protocol_quarantine.tscn"
const ROOT_MUSIC_NAME := "ContinuousLevelMusic"
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, " ", detail if not value else "")


func _prepare(game: Node2D) -> void:
	# 停住游戏驱动，不暂停音频节点或SceneTree；禁止测试辅助函数顺手stop BGM。
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.keys.clear()
	game.player.set_physics_process(false)
	game.action_audio_enabled = false
	game._sfx.clear()
	for voice: AudioStreamPlayer in game._sfx_pool:
		voice.stop()
	if game.action_audio != null:
		game.action_audio.stop_all()


func _root_music_count() -> int:
	var count := 0
	for child: Node in root.get_children():
		if child is AudioStreamPlayer and String(child.name).begins_with(ROOT_MUSIC_NAME):
			count += 1
	return count


func _boot(selected_difficulty := "easy") -> Node2D:
	SESSION.begin_run(selected_difficulty)
	var boot := load(LEVEL_SCENE).instantiate() as Node2D
	root.add_child(boot)
	current_scene = boot
	var game: Node2D = boot.get_node("Game")
	_prepare(game)
	return game


func _run() -> void:
	print("== 真实死亡回溯整场重载仍使用同一音频播放实例 ==")
	var game := _boot()
	check(is_instance_valid(game.music) and game.music.playing,
			"新开局仍正常播放原关卡BGM")
	if not is_instance_valid(game.music):
		_fail_cleanup()
		return
	check(game.music.get_parent() == root and game.music.name == ROOT_MUSIC_NAME,
			"时间循环模式BGM位于SceneTree根，不随关卡销毁")
	check(_root_music_count() == 1, "首轮只创建一个跨轮BGM播放器")
	var original_player_id: int = game.music.get_instance_id()
	var original_stream_id: int = game.music.stream.get_instance_id()
	var original_music_ref: WeakRef = weakref(game.music)
	var expected_volume: float = CorridorLevel.active_bgm_db
	check(game.music.stream.get_length() > 15.0, "测试曲目足够长，12秒起播不会触发正常曲终循环")
	# 真正让音频线程播放到非零位置，避免只断言playing而漏掉归零重播。
	await create_timer(0.15).timeout
	game.music.play(12.0)
	await create_timer(0.18).timeout
	var start_position: float = game.music.get_playback_position()
	check(game.music.playing and start_position >= 12.0,
			"音频线程已从12秒处实际播放", str(start_position))
	var original_playback_id := 0
	if game.music.has_stream_playback():
		original_playback_id = game.music.get_stream_playback().get_instance_id()
	check(original_playback_id != 0, "播放器持有真实AudioStreamPlayback")
	for cycle in 3:
		var old_scene_id: int = current_scene.get_instance_id()
		var before_death: float = game.music.get_playback_position()
		game.player.force_death(game.player.position.x - 60.0)
		check(game.time_phase == "dying" and game.music.playing \
				and is_equal_approx(game.music.pitch_scale, 0.68),
				"第%d次死亡仅降BGM音高，继续播放" % (cycle + 1))
		await create_timer(0.15).timeout
		game._begin_rewind()
		check(game.time_phase == "rewinding" and game.music.playing \
				and is_equal_approx(game.music.pitch_scale, 0.48),
				"第%d次短倒带继续原音轨，仅改变音高" % (cycle + 1))
		await create_timer(0.15).timeout
		var before_reload: float = game.music.get_playback_position()
		check(before_reload > before_death,
				"第%d次死亡与倒带期间音频播放进度持续前进" % (cycle + 1),
				"%.3f -> %.3f" % [before_death, before_reload])
		# 故障收尾仍走生产change_scene_to_file，不手工实例化替代真正的整关重载。
		game._advance_rewind(game.REWIND_DURATION + game.INTERFERENCE_DURATION + 0.01)
		for _i in 4:
			await process_frame
		check(is_instance_valid(current_scene) and current_scene.get_instance_id() != old_scene_id,
				"第%d次回溯确实重载整关节点" % (cycle + 1))
		if not is_instance_valid(current_scene) or not current_scene.has_node("Game"):
			_fail_cleanup()
			return
		game = current_scene.get_node("Game")
		_prepare(game)
		await create_timer(0.15).timeout
		check(is_instance_valid(game.music) and game.music.get_instance_id() == original_player_id,
				"第%d次重开沿用同一个AudioStreamPlayer" % (cycle + 1))
		check(game.music.stream.get_instance_id() == original_stream_id,
				"第%d次重开沿用同一个AudioStream资源" % (cycle + 1))
		check(game.music.has_stream_playback() \
				and game.music.get_stream_playback().get_instance_id() == original_playback_id,
				"第%d次重开不重新play或seek，不替换底层Playback" % (cycle + 1))
		var after_reload: float = game.music.get_playback_position()
		check(after_reload >= 12.0 and after_reload >= before_reload - 0.05,
				"第%d次重开音乐进度不归零或倒退" % (cycle + 1),
				"%.3f -> %.3f" % [before_reload, after_reload])
		check(game.music.playing and is_equal_approx(game.music.pitch_scale, 1.0) \
				and is_equal_approx(game.music.volume_db, expected_volume),
				"第%d次新场恢复正常BGM音高及原音量" % (cycle + 1))
		check(_root_music_count() == 1 and game.music.get_parent() == root,
				"第%d次重开无重复BGM播放器叠音" % (cycle + 1))
		check(SESSION.attempt == cycle + 2 and not game.player.dead and game.player.hp == 5,
				"第%d次只有音乐持续，死亡状态和生命正常重置" % (cycle + 1))
		print("MUSIC_CONTINUITY_PROFILE cycle=%d position=%.3fs player=%d playback=%d" \
				% [cycle + 1, after_reload, original_player_id, original_playback_id])
	print("== 返回菜单与普通卸载必须回收跨轮音乐 ==")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	var escape_release := InputEventKey.new()
	escape_release.keycode = KEY_ESCAPE
	escape_release.pressed = false
	var original_voice_pauses: Array[bool] = []
	for voice: AudioStreamPlayer in game.action_audio._voices:
		original_voice_pauses.append(voice.stream_paused)
	var paused_scene_id: int = current_scene.get_instance_id()
	game.pause_controller._input(escape)
	game.pause_controller._input(escape_release)
	check(game.pause_controller.active and paused and current_scene.get_instance_id() == paused_scene_id,
			"Esc只暂停原场景，不以重载替代暂停")
	check(game.music.get_instance_id() == original_player_id and game.music.stream_paused \
			and game.music.get_stream_playback().get_instance_id() == original_playback_id,
			"暂停只冻结原音乐流，保留同一BGM和Playback")
	game.pause_controller._input(escape)
	game.pause_controller._input(escape_release)
	check(not paused and not game.pause_controller.active and game.music.playing \
			and not game.music.stream_paused and game.music.get_instance_id() == original_player_id \
			and game.music.get_stream_playback().get_instance_id() == original_playback_id,
			"再按Esc恢复同一音乐播放，不stop/play/seek或重建")
	var voice_pauses_restored := true
	for index in game.action_audio._voices.size():
		voice_pauses_restored = voice_pauses_restored \
				and game.action_audio._voices[index].stream_paused == original_voice_pauses[index]
	check(voice_pauses_restored, "ALWAYS音效父节点下各声部的暂停标志也逐项恢复，不永远静音")
	game.pause_controller._input(escape)
	game.pause_controller._input(escape_release)
	game.pause_controller.return_to_main_menu()
	for _i in 4:
		await process_frame
	await create_timer(0.15).timeout
	check(is_instance_valid(current_scene) \
			and current_scene.get_script() == load("res://scripts/surveillance_menu.gd") \
			and not SESSION.timeline_enabled and not paused, "暂停菜单明确返回主菜单才结束挑战并解除全局暂停")
	check(original_music_ref.get_ref() == null and _root_music_count() == 0,
			"明确返回主菜单后释放原BGM，不在菜单继续留关卡音乐")
	current_scene.free()
	await process_frame
	game = _boot("zero")
	var normal_free_ref: WeakRef = weakref(game.music)
	check(game.music.playing and game.music.get_instance_id() != original_player_id \
			and game.player.hp == 1, "重新开局创建新音乐，武士零模式仍为一血")
	await create_timer(0.15).timeout
	current_scene.free()
	await create_timer(0.15).timeout
	check(normal_free_ref.get_ref() == null and _root_music_count() == 0,
			"直接free场景也释放跨轮BGM，不依赖一定经Esc退出")
	# 旧地图/旧测试未启用Session，继续局部节点生命周期，不扩散跨场音乐规则。
	SESSION.reset_for_tests()
	var legacy_boot := load(LEVEL_SCENE).instantiate() as Node2D
	root.add_child(legacy_boot)
	current_scene = legacy_boot
	game = legacy_boot.get_node("Game")
	_prepare(game)
	var legacy_music_ref: WeakRef = weakref(game.music)
	check(not game.timeline_enabled and game.music.get_parent() == game \
			and _root_music_count() == 0, "非时间循环旧模式继续使用局部Music节点")
	await create_timer(0.15).timeout
	legacy_boot.free()
	await create_timer(0.15).timeout
	check(legacy_music_ref.get_ref() == null, "旧模式场景卸载一并释放音乐")
	SESSION.reset_for_tests()
	print("MUSIC_RETRY_CONTINUITY_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))


func _fail_cleanup() -> void:
	if is_instance_valid(current_scene):
		current_scene.free()
	SESSION.reset_for_tests()
	print("MUSIC_RETRY_CONTINUITY_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(1)
