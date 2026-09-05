extends SceneTree
## 原版战斗声优先，新技能独立；直接检查真实播放器的资源、音量与叠层，防止再次换掉爽感。
const SESSION := preload("res://scripts/run_session.gd")
var passed := 0
var failed := 0

class DurableTarget extends Node2D:
	var dead := false
	var hitstop := 0.0
	var health := 2
	func body_rect() -> Rect2:
		return Rect2(position - Vector2(16, 80), Vector2(32, 80))
	func take_hit(_from_x: float, damage := 1) -> bool:
		health -= damage
		dead = health <= 0
		return true

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)

func _run() -> void:
	SESSION.begin_run("easy")
	var boot := load("res://scenes/m01_protocol_quarantine.tscn").instantiate() as Node2D
	root.add_child(boot)
	var game: Node2D = boot.get_node("Game")
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.music.stop()
	var router: Node = game.action_audio
	router.clock_override = 10.0
	check(game.original_combat_audio_enabled, "正式关卡默认保留原版战斗声")
	check(is_equal_approx(game.original_kill_pitch_variation, 0.015), "正式关卡默认开启最多±1.5%轻微击杀变调")
	game.original_kill_pitch_variation = 0.0 # 以下旧合同精确验证原连杀基准；默认随机分支由独立专项覆盖。
	for stage in 3:
		game._on_bat_swing_started(stage)
		check(_last_original_voice(game).stream.resource_path.contains("_bat_swing.wav") \
				and is_equal_approx(_last_original_voice(game).volume_db, 0.0) \
				and is_equal_approx(_last_original_voice(game).pitch_scale, 1.0),
				"第%d段挥棒恢复原破风与原音高/音量" % (stage + 1))
	var hit_result: Dictionary = game.play_action("body_hit")
	check(hit_result.get("bank") == "original" and _last_original_voice(game).stream.resource_path.contains("_bat_hit_normal.wav"),
			"非致命击打使用原06至08命中素材")
	check(is_equal_approx(_last_original_voice(game).volume_db, 3.5) \
			and is_equal_approx(_last_original_voice(game).pitch_scale, 1.0), "原命中+3.5dB、不改变音高")
	var durable := DurableTarget.new()
	durable.position = Vector2(-1000, 700)
	game.add_child(durable)
	game.minions.append(durable)
	game._on_player_bat_swung(durable.body_rect(), 0)
	check(durable.health == 1 and not durable.dead \
			and _last_original_voice(game).stream.resource_path.contains("_bat_hit_normal.wav"),
			"真实挥棒非致命分支也播放原命中声")
	game.minions.erase(durable)
	durable.queue_free()
	var target: Node2D = game.minions[0]
	game._on_player_bat_swung(target.body_rect(), 2)
	check(target.dead and _original_kill_pair(game), "真实球棒击杀恢复09重击+液爆双层及原增益")
	game._on_player_bat_swung(game.minions[1].body_rect(), 2)
	check(_original_kill_pair(game, 1.02), "第二次连续击杀两层同步升调2%，原增益不变")
	game._reset_original_kill_chain()
	check(is_equal_approx(game._next_original_kill_pitch(100.0), 1.0), "新连杀第一杀保持原速")
	check(is_equal_approx(game._next_original_kill_pitch(100.3), 1.02) \
			and is_equal_approx(game._next_original_kill_pitch(100.6), 1.04), "连续击杀音高逐级轻升")
	for index in 20:
		game._next_original_kill_pitch(100.9 + index * 0.1)
	check(is_equal_approx(game._next_original_kill_pitch(103.0), 1.08), "大量连杀音高封顶8%")
	check(is_equal_approx(game._next_original_kill_pitch(106.0), 1.0), "超过2.4秒断连恢复原音高")
	game.original_kill_pitch_step = 0.0
	check(is_equal_approx(game._next_original_kill_pitch(106.2), 1.0), "单独关闭升调仍保留原声")
	game.original_kill_pitch_step = 0.02
	game._reset_original_kill_chain()
	game.player.dashed.emit()
	check(_last_original_voice(game).stream.resource_path == "res://assets/sfx/hk/enemy_dash.mp3" \
			and is_equal_approx(_last_original_voice(game).volume_db, 0.0) \
			and is_equal_approx(_last_original_voice(game).pitch_scale, 1.0), "冲刺恢复用户认可的原MP3及音量/音高")
	check(router.last_event.is_empty() and router.debug_stats().active == 0, "原战斗声不额外叠放合成版")
	# 原声与新库分开开关：可以A/B，但默认不能静默回到新合成音。
	game.original_combat_audio_enabled = false
	var original_index: int = game._sfx_idx
	game.play_action("enemy_kill")
	check(router.last_event.event == "enemy_kill" and game._sfx_idx == original_index, "关闭原声开关才对照合成版，且不双播")
	game.original_combat_audio_enabled = true
	game.player.take_damage(1, game.player.position.x - 60)
	check(router.last_event.event == "player_hurt", "非致命主角受击独立音色")
	game._on_boss_shoot_orb(game.player.position + Vector2(120, -30), Vector2.LEFT * 180)
	check(router.last_event.event == "enemy_shot", "枪手发射不再使用肉体命中声")
	game.player.keys[MOUSE_BUTTON_RIGHT] = true
	game._advance_time_charge(0.01)
	check(router.last_event.event == "time_stop_start", "时停开始使用吸入锁定声")
	game.player.keys.clear()
	game._advance_time_charge(0.01)
	check(router.last_event.event == "time_stop_end", "时停结束使用独立释放声")
	game.player.force_death(game.player.position.x - 60)
	check(router.last_event.event == "player_death", "主角倒地不用敌人击杀声")
	check(game._original_kill_streak == 0, "死亡清除连杀音高状态")
	game._begin_rewind()
	check(router.last_event.event == "rewind" and router.debug_stats().active == 1, "倒带先清旧尾音再播独立磁带声")
	var originals_stopped := true
	for voice: AudioStreamPlayer in game._sfx_pool:
		originals_stopped = originals_stopped and not voice.playing
	check(originals_stopped, "倒带开始也清除恢复后的原战斗尾音")
	game._advance_rewind(game.REWIND_DURATION + 0.001)
	check(router.last_event.event == "tv_fault", "进入电视故障时单独播放短电路杂音")
	var fault_variant: int = router.last_event.variant
	game._advance_rewind(0.01)
	check(router.last_event.variant == fault_variant, "故障持续帧不重复播放杂音")
	game.action_audio_enabled = false
	check(not game.play_action("cargo_impact").played, "新技能/环境声可单独停用对照")
	check(game.play_action("player_dash").played, "静音新库不影响原版冲刺声")
	check(game._sfx_pool.size() == 12 and router.debug_stats().voices == 8, "复用现有12+8路池，不增加播放器")
	var audio_refs := _audio_refs(game)
	# 给音频线程真实消费时间，不能在同帧十连play/stop后立即销毁整场。
	await create_timer(0.20).timeout
	boot.free()
	SESSION.reset_for_tests()
	await create_timer(0.15).timeout
	check(AudioServer.get_bus_index("KairullActionSfx") < 0, "整场卸载不遗留动作音效总线")
	check(_live_refs(audio_refs) == 0, "整场卸载后音频流与playback弱引用全部失效")
	# 真实重开保留跨帧播放期；在同一进程反复切场，检查不是把泄漏推迟到下次退出。
	for cycle in range(3):
		SESSION.begin_run("easy")
		var next_boot := load("res://scenes/m01_protocol_quarantine.tscn").instantiate() as Node2D
		root.add_child(next_boot)
		var next_game: Node2D = next_boot.get_node("Game")
		next_game.set_process(false)
		next_game.set_physics_process(false)
		next_game.player.auto_input = false
		next_game._on_bat_swing_started(0)
		next_game.play_action("body_hit")
		next_game.play_action("player_dash")
		await create_timer(0.20).timeout
		next_game._begin_rewind()
		audio_refs = _audio_refs(next_game)
		await create_timer(0.20).timeout
		next_boot.free()
		SESSION.reset_for_tests()
		await create_timer(0.15).timeout
		check(_live_refs(audio_refs) == 0, "连续重开第%d轮音频引用全部回收" % (cycle + 1))
		check(AudioServer.get_bus_index("KairullActionSfx") < 0,
				"连续重开第%d轮无额外AudioBus" % (cycle + 1))
	print("ACTION_AUDIO_INTEGRATION: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))


func _last_original_voice(game: Node2D, offset := 1) -> AudioStreamPlayer:
	return game._sfx_pool[posmod(game._sfx_idx - offset, game._sfx_pool.size())]


func _original_kill_pair(game: Node2D, expected_pitch := 1.0) -> bool:
	var wet := _last_original_voice(game)
	var strike := _last_original_voice(game, 2)
	return strike.stream.resource_path == "res://assets/sfx/09_bat_hit_kill.wav" \
			and wet.stream.resource_path == "res://assets/sfx/slime/slime_death_burst.wav" \
			and is_equal_approx(strike.volume_db, 4.5) and is_equal_approx(wet.volume_db, -3.5) \
			and is_equal_approx(strike.pitch_scale, expected_pitch) and is_equal_approx(wet.pitch_scale, expected_pitch)


## 只保存WeakRef，测试自身不能持有AudioStream/Playback从而制造假泄漏。
func _audio_refs(game: Node2D) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for clips: Array in game.action_audio._streams.values():
		for stream: AudioStream in clips:
			refs.append(weakref(stream))
	for voice: AudioStreamPlayer in game.action_audio._voices:
		if voice.has_stream_playback():
			refs.append(weakref(voice.get_stream_playback()))
	# 原素材可能被资源缓存共享，不要求流卸载；检查恢复后的旧池playback不泄漏。
	for voice: AudioStreamPlayer in game._sfx_pool:
		if voice.has_stream_playback():
			refs.append(weakref(voice.get_stream_playback()))
	if game.music != null:
		refs.append(weakref(game.music.stream))
		if game.music.has_stream_playback():
			refs.append(weakref(game.music.get_stream_playback()))
	return refs


func _live_refs(refs: Array[WeakRef]) -> int:
	var live := 0
	for reference: WeakRef in refs:
		live += int(reference.get_ref() != null)
	return live
