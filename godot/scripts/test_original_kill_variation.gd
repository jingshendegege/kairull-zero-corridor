extends SceneTree
## 原09重击+液爆仅加微小音高差：独立随机、双层同步、旧连杀基准/增益/音乐不变。
const GAME := preload("res://scripts/game.gd")
const SESSION := preload("res://scripts/run_session.gd")
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _run() -> void:
	_test_pitch_math()
	_test_global_rng_isolation()
	await _test_real_voice_pair()
	print("ORIGINAL_KILL_VARIATION_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_pitch_math() -> void:
	var first := GAME.new()
	var second := GAME.new()
	check(is_equal_approx(first.original_kill_pitch_variation, .015), "默认击杀随机变化幅度仅±1.5%")
	check(is_equal_approx(first.original_kill_pitch_step, .02), "原每次连杀+2%基准保留")
	first.set_original_kill_variation_seed(19451)
	second.set_original_kill_variation_seed(19451)
	var deterministic := true
	var bounded := true
	var base_preserved := true
	var neighbors_different := true
	var distinct: Dictionary = {}
	var previous := -INF
	for index in 160:
		var pitch: float = first._next_original_kill_pitch(10.0 + index * .1)
		var twin: float = second._next_original_kill_pitch(10.0 + index * .1)
		var base := minf(1.08, 1.0 + .02 * index)
		deterministic = deterministic and pitch == twin
		bounded = bounded and pitch >= .985 - .000001 and pitch <= 1.095 + .000001
		base_preserved = base_preserved and absf(pitch - base) <= .015001
		neighbors_different = neighbors_different and absf(pitch - previous) >= .002999
		distinct[roundi(pitch * 1000000)] = true
		previous = pitch
	check(deterministic, "同专用seed可复现160次击杀序列")
	check(bounded, "大量连杀总音高始终限定.985至1.095，不越来越尖")
	check(base_preserved, "变化叠在原1.00/1.02/…/1.08基准内，偏差最多1.5%")
	check(neighbors_different, "相邻击杀至少轻错开0.3%，不会紧邻原样重复")
	check(distinct.size() > 80, "默认变化实际产生多种轻音色，不是固定循环两音")
	check(first._original_kill_streak == 32, "连杀计数仍有32上限")
	var broken: float = first._next_original_kill_pitch(99.0)
	check(first._original_kill_streak == 1 and broken >= .985 and broken <= 1.015,
		"超过2.4秒断连恢复原声附近，而非保留8%高调")
	first._reset_original_kill_chain()
	check(first._original_kill_streak == 0 and first._last_original_kill_at == -INF \
		and first._last_original_kill_pitch == -INF and first._last_original_kill_variation == 0.0,
		"复位清连杀和防重复记录，不残留高音状态")
	first.original_kill_pitch_variation = 0.0
	var old_baseline := true
	for index in 15:
		old_baseline = old_baseline and is_equal_approx(first._next_original_kill_pitch(100 + index * .1),
			minf(1.08, 1.0 + index * .02))
	check(old_baseline, "variation=0精确返回旧连杀升调序列")
	first.original_kill_pitch_step = 0.0
	check(first._next_original_kill_pitch(101.6) == 1.0, "两项都关闭完全恢复原速原声")
	first.original_kill_pitch_variation = .015
	var unchained: Dictionary = {}
	var unchained_in_range := true
	for index in 48:
		var pitch: float = first._next_original_kill_pitch(200 + index * 3)
		unchained[roundi(pitch * 1000000)] = true
		unchained_in_range = unchained_in_range and pitch >= .985 and pitch <= 1.015
	check(unchained.size() > 30 and unchained_in_range, "单杀也有轻变化；关闭连杀升调不关闭微变调")
	first.original_kill_pitch_variation = 99.0
	check(absf(first._next_original_kill_pitch(400.0) - 1.0) <= .015001, "越界Inspector/代码参数仍安全限至1.5%")
	first.original_kill_pitch_variation = -1.0
	check(first._next_original_kill_pitch(400.1) == 1.0, "负幅度安全视作关闭")
	first.free()
	second.free()


func _test_global_rng_isolation() -> void:
	# 仅测试进程设置全局seed，证明生产专用RNG连初始化都不消费玩法randi序列。
	seed(462913)
	var expected_first := randi()
	var expected_second := randi()
	seed(462913)
	check(randi() == expected_first, "全局随机隔离用例基线正确")
	var game := GAME.new()
	for index in 64:
		game._next_original_kill_pitch(10 + index * .2)
	check(randi() == expected_second, "专用音色RNG及首次randomize不改变全局玩法随机序列")
	game.free()
	var disabled := GAME.new()
	disabled.original_kill_pitch_variation = 0.0
	disabled._next_original_kill_pitch(10.0)
	check(not disabled._original_kill_rng_initialized, "关闭变化时不初始化或消费随机音色序列")
	disabled.free()


func _voice(game: Node2D, offset: int) -> AudioStreamPlayer:
	return game._sfx_pool[posmod(game._sfx_idx - offset, game._sfx_pool.size())]


func _test_real_voice_pair() -> void:
	SESSION.begin_run("easy")
	var boot := load("res://scenes/m01_protocol_quarantine.tscn").instantiate() as Node2D
	root.add_child(boot)
	var game := boot.get_node("Game") as Node2D
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.set_original_kill_variation_seed(568911)
	game._reset_original_kill_chain()
	var gain_before: Dictionary = game._sfx_gain.duplicate(true)
	var player_count_before: int = game._sfx_pool.size()
	var music_id: int = game.music.get_instance_id()
	var music_stream: String = game.music.stream.resource_path
	var music_gain: float = game.music.volume_db
	var music_time: float = game.music.get_playback_position()
	var pairs_synced := true
	var original_sources := true
	var original_gains := true
	var distinct: Dictionary = {}
	for _index in 12:
		var result: Dictionary = game.play_action(&"enemy_kill")
		var strike := _voice(game, 2)
		var wet := _voice(game, 1)
		pairs_synced = pairs_synced and strike.pitch_scale == wet.pitch_scale \
			and is_equal_approx(strike.pitch_scale, result.pitch)
		original_sources = original_sources and strike.stream.resource_path == "res://assets/sfx/09_bat_hit_kill.wav" \
			and wet.stream.resource_path == "res://assets/sfx/slime/slime_death_burst.wav"
		original_gains = original_gains and strike.volume_db == 4.5 and wet.volume_db == -3.5
		distinct[roundi(strike.pitch_scale * 1000000)] = true
	check(pairs_synced, "真实12次击杀重击与液爆两层始终同一音高")
	check(original_sources, "每次仍是原09_bat_hit_kill和slime_death双层素材")
	check(original_gains and game._sfx_gain == gain_before, "双层+4.5/-3.5dB及全部原增益完全未改")
	check(distinct.size() > 8, "真实播放器收到默认轻变化，不只是返回调试数据")
	game.play_action(&"player_dash")
	check(_voice(game, 1).stream.resource_path == "res://assets/sfx/hk/enemy_dash.mp3" \
		and _voice(game, 1).pitch_scale == 1.0 and _voice(game, 1).volume_db == 0.0,
		"连杀之后冲刺仍保持原MP3音高和力度")
	game.play_action(&"body_hit")
	check(_voice(game, 1).stream.resource_path.contains("_bat_hit_normal.wav") \
		and _voice(game, 1).pitch_scale == 1.0 and _voice(game, 1).volume_db == 3.5,
		"普通击打仍是原06~08素材，音高增益不受随机击杀影响")
	check(game._sfx_pool.size() == player_count_before and player_count_before == 12 \
		and game.action_audio.debug_stats().voices == 8, "不增加12+8声部池，不生成新音频资源")
	await create_timer(.2).timeout
	check(game.music.get_instance_id() == music_id and game.music.stream.resource_path == music_stream \
		and game.music.pitch_scale == 1.0 and game.music.volume_db == music_gain \
		and game.music.get_playback_position() >= music_time, "音乐同一播放器继续播放，音高音量和位置未重置")
	game.player.force_death(game.player.position.x - 40.0)
	check(game._original_kill_streak == 0 and game._last_original_kill_pitch == -INF \
		and game._last_original_kill_variation == 0.0, "真实死亡事件同时清连杀和防重复状态")
	var after_death: float = game._next_original_kill_pitch(800.0)
	check(after_death >= .985 and after_death <= 1.015, "死亡后首杀恢复原调附近，不延续连杀高调")
	await create_timer(.2).timeout
	boot.free()
	SESSION.reset_for_tests()
	await create_timer(.15).timeout
