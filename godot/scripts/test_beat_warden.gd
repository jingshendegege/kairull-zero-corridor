extends SceneTree
const SESSION := preload("res://scripts/run_session.gd")
const SCENE := "res://scenes/m07_beat_tower.tscn"
var passed := 0
var failed := 0
var clock_time := 0.0
var playback_time := 0.0
var game: Node2D
var arena: BeatArena

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)

func fresh() -> void:
	arena.reset_fight()
	game.player.reset_to_spawn()
	game.player.position = Vector2(1200, 736)
	game.player.auto_input = false
	game.player.invuln_t = 0.0
	game.time_phase = "playing"
	game._set_temporal_nodes_paused(false)
	clock_time = 0.0
	arena.conductor.clock = func() -> float: return clock_time
	arena.conductor.start()
	arena.state = "playing"

func advance(seconds: float) -> void:
	clock_time += seconds
	arena.step(seconds)

func note(kind := "normal", lane := "ground", at_time := 0.0) -> BeatNote:
	return arena.spawn_note({"kind": kind, "lane": lane, "time": at_time})

func hit(n: BeatNote) -> void:
	arena._on_swing_started(0)
	arena.bat_contacts(n.body_rect())

func _run() -> void:
	SESSION.begin_run("easy")
	var boot: Node2D = load(SCENE).instantiate()
	root.add_child(boot)
	current_scene = boot
	game = boot.get_node("Game")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.auto_input = false
	game.action_audio_enabled = false
	game._sfx.clear()
	arena = game.beat_arena
	var c := arena.conductor
	# 正式配乐：用户用 Suno 生成的 Final Stand（谱面由 tools/audio/chart_from_audio.py 自动生成）
	var real_chart: Dictionary = c.chart
	check(arena.config.music == "res://assets/bgm/final_stand.ogg" and ResourceLoader.exists(arena.config.music),
		"boss arena plays Final Stand")
	check(real_chart.notes.size() > 300 and absf(float(real_chart.bpm) - 150.0) < 1.0 and float(real_chart.offset_sec) > 0.0
			and int(real_chart.boss_hp) > 0 and real_chart.sections[-1].name == "finale", "Final Stand chart loads with rising sections")
	# 以下计时/循环/伤害测试使用确定性的旧合成曲谱面作为夹具（数值固定可复现）
	c.chart = JSON.parse_string(FileAccess.get_file_as_string("res://assets/boss/beat_warden_synth_chart.json"))
	arena.boss.max_hp = int(c.chart.boss_hp)
	arena.boss.reset()
	check(c.chart.notes.size() == 258 and int(c.chart.boss_hp) == 160, "chart has 258 notes and 160 HP")
	check(c.chart.sections.map(func(s: Dictionary) -> String: return s.name) == ["intro", "verse", "build", "drop", "finale"], "all five chart sections")
	check(c.chart.bpm == 128 and c.chart.note_speed_px == 520 and c.chart.offset_sec == 0, "chart timing constants")
	fresh()
	var n := note("normal", "ground", c.seconds(8))
	n.advance_incoming(c.seconds(8))
	check(is_equal_approx(n.position.x, 1408) and n.position.y == 700, "beat time arrives exactly at ground judge")
	var air := note("normal", "air", c.seconds(8))
	check(air.position.y == 596 and air.texture.get_width() == 44, "air lane (above the divider) and winged sprite")
	check(not air.body_rect().intersects(Rect2(1391, 654, 34, 82)), "standing hurtbox clears air notes")
	for lane in ["ground", "air"]:
		fresh()
		var horn := arena.boss.anchor("horn_" + lane + "_world").x
		var t := c.seconds(8) - (horn - 1408.0) / 520.0
		var probe := note("normal", lane, c.seconds(8))
		probe.advance_incoming(t)
		check(is_equal_approx(probe.position.x, horn), lane + " exact horn spawn geometry")
	fresh()
	var spawn_time := c.seconds(8) - (arena.boss.anchor("horn_ground_world").x - 1408) / 520.0
	clock_time = spawn_time - 0.001
	arena.step(0.0)
	check(arena.notes.is_empty(), "scheduler does not spawn before horn")
	advance(0.001)
	check(arena.notes.size() == 1 and is_equal_approx(arena.notes[0].position.x, arena.boss.anchor("horn_ground_world").x), "scheduler spawns at horn mouth")
	check(arena.boss.state == "fire_ground", "spawn triggers ground fire")
	fresh()
	n = note()
	hit(n)
	check(n.reflected and arena.rating == "Perfect" and arena.combo == 1, "normal bat contact reflects and rates")
	advance(1.1)
	check(arena.boss.hp == 159 and arena.boss.flash > 0, "reflected normal arrives for one damage and flash")
	fresh()
	game.player.position = Vector2(1350, 736)
	game.player.on_ground = true
	game.player.face = 1
	game.player._start_bat(0)
	n = note()
	arena.step(0)
	check(not n.reflected, "bat windup cannot reflect")
	for tick in 24:
		game.player.keys.clear()
		game.player.step(1.0 / 60)
		if n.reflected:
			break
	check(n.reflected, "actual player bat_swung signal reflects without player modifications")
	fresh()
	game.player.position = Vector2(1350, 736)
	game.player.face = 1
	game.player._start_bat(0)
	var frame_count: int = game.player.db.actions[game.player.BAT_CLIPS[0]].frames
	game.player.frame = ceili((frame_count - 1) * game.player.BAT_HIT_AT)
	game.player.bat_hit_done = true
	n = note()
	arena.step(0)
	check(n.reflected, "note entering bat during active window reflects after signal frame")
	fresh()
	game.player.position = Vector2(1350, 736)
	game.player.face = 1
	game.player._start_bat(0)
	game.player.frame = ceili((frame_count - 1) * 0.8)
	n = note()
	arena.step(0)
	check(not n.reflected, "bat recovery has no active hitbox")
	fresh()
	n = note("heavy")
	hit(n)
	check(n.cracked and not n.reflected and n.speed == 260 and n.texture.resource_path.ends_with("note_heavy_cracked.png"), "heavy first hit cracks and halves speed")
	arena.bat_contacts(n.body_rect())
	check(not n.reflected and arena.combo == 1, "same swing cannot hit heavy twice")
	n.advance_incoming(0.1)
	check(is_equal_approx(n.position.x, 1382), "cracked heavy continues left at half speed")
	hit(n)
	advance(1.2)
	check(arena.boss.hp == 157, "second heavy hit reflects for three damage")
	fresh()
	n = note("bomb")
	hit(n)
	check(game.player.hp == 4 and n.spent and not n.reflected and arena.combo == 0, "bomb bat hit damages player without rating")
	fresh()
	game.player.position = Vector2(1408, 736)
	n = note()
	arena.step(0.0)
	check(game.player.hp == 4 and arena.notes.is_empty(), "untouched note contact damages once and destroys note")
	arena.step(0.0)
	check(game.player.hp == 4, "destroyed note never damages twice")
	fresh()
	game.player.position = Vector2(1408, 736)
	game.player.roll_invuln_t = 0.2
	n = note("bomb")
	arena.step(0.0)
	check(game.player.hp == 5 and arena.notes.is_empty(), "rolling i-frames respect take_damage for bombs")
	fresh()
	game.player.position = Vector2(1408, 736)
	game.player.state = "dash"
	n = note()
	arena.step(0.0)
	check(game.player.hp == 5, "dash invulnerability respected")
	for test in [[0.0,"Perfect"],[0.08,"Perfect"],[-0.08,"Perfect"],[0.0801,"Great"],[0.14,"Great"],[-0.14,"Great"],[0.1401,"Hit"],[0.2,"Hit"]]:
		check(BeatArena.rate(test[0]) == test[1], "rating window %s" % test[0])
	fresh()
	arena.combo = 8
	n = note()
	advance(0.151)
	check(arena.rating == "Miss" and arena.combo == 0 and n.missed, "150ms late unhit note resets combo")
	fresh()
	arena.combo = 8
	n = note("bomb")
	advance(0.151)
	check(arena.combo == 8 and arena.rating.is_empty(), "bomb passing judge keeps combo")
	fresh()
	clock_time = c.seconds(176)
	arena.step(0.0)
	check(arena.boss.exposed and arena.boss.state == "core", "large clock step reaches finale exposed core")
	arena._clear_notes()
	arena.boss.reset()
	arena.boss.expose()
	check(arena.boss.state == "expose", "expose starts once")
	arena.boss.step(0.2, 176)
	check(arena.boss.state == "expose", "expose animation is not skipped during normal ticks")
	arena.boss.step(0.14, 176.75)
	check(arena.boss.state == "core" and arena.boss.frame == 3, "expose transitions to beat-phase core")
	n = note("normal", "ground", c.time)
	hit(n)
	advance(1.1)
	check(arena.boss.hp == 158, "finale reflected normal deals double damage")
	arena._clear_notes()
	n = note("heavy", "ground", c.time)
	hit(n)
	hit(n)
	check(n.reflection_target == arena.boss.anchor("core_world"), "exposed reflections aim straight at atlas core point")
	advance(1.2)
	check(arena.boss.hp == 152, "finale heavy deals six damage")
	fresh()
	clock_time = c.seconds(208) - 0.1
	var events := c.advance()
	check(events.any(func(e: Dictionary) -> bool: return e.cycle == 1 and e.beat == 112), "next cycle lead-in spawned before seek boundary")
	clock_time += 0.2
	c.advance()
	check(c.loop_count == 1 and is_equal_approx(c.song_beat(), 112 + 0.1 / c.seconds(1)), "loop seeks to beat 112 preserving overshoot")
	check(c.finale_started(), "finale damage stays active through loops")
	var continued := c.time
	c.advance()
	check(c.loop_count == 1 and c.time == continued, "loop boundary does not reschedule or advance twice")
	clock_time += c.loop_duration()
	c.advance()
	check(c.loop_count == 2 and c.finale_started(), "repeated loops have no timeout or phase reset")
	var previous := c.time
	clock_time -= 0.05
	c.advance()
	check(c.time == previous, "injected clock clamps backward jitter")
	fresh()
	c.clock = Callable()
	c.playback_clock = func() -> float: return playback_time
	playback_time = c.seconds(208)
	c.advance()
	var seam := c.time
	playback_time += 0.02
	c.advance()
	check(c.loop_count == 1 and c.time == seam, "stale audio sample after asynchronous seek cannot skip another loop")
	playback_time = c.seconds(112) + 0.04
	c.advance()
	check(c.loop_count == 1 and is_equal_approx(c.time, seam + 0.04), "post-seek audio sample resumes monotonic timeline")
	c.playback_clock = Callable()
	fresh()
	n = note("normal", "air", 0.5)
	var frozen_position := n.position
	var frozen_frame := arena.boss.frame
	game.time_charge.active = true
	game._set_temporal_nodes_paused(true)
	advance(3.0)
	check(c.time == 0 and n.position == frozen_position and arena.boss.frame == frozen_frame and c.music.stream_paused, "time-stop freezes clock notes boss and music")
	game.pause_controller.pause_game()
	advance(2.0)
	game.pause_controller.resume_game()
	check(arena.frozen and c.music.stream_paused, "pause over time-stop preserves original freeze")
	game.time_charge.active = false
	game._set_temporal_nodes_paused(false)
	advance(0.1)
	check(is_equal_approx(c.time, 0.1) and not c.music.stream_paused and is_equal_approx(n.position.x, frozen_position.x - 52), "resume excludes paused duration and stays in sync")
	game.pause_controller.pause_game()
	advance(4.0)
	game.pause_controller.resume_game()
	advance(0.1)
	check(is_equal_approx(c.time, 0.2), "ordinary pause also excludes injected wall-clock duration")
	fresh()
	n = note()
	hit(n)
	frozen_position = n.position
	arena.set_frozen(true)
	advance(1.0)
	check(n.position == frozen_position and arena.boss.hp == 160, "reflected note freezes too")
	check(not game._enemies().has(arena.boss), "boss is absent from direct bat bullet and cargo targets")
	arena.set_frozen(false)
	arena.boss.take_reflected_hit(160)
	check(arena.notes.is_empty() and arena.boss.state == "death" and arena.blocks_exit(), "death clears notes and waits for animation")
	arena.step(0.5)
	check(arena.state == "defeated" and not game._exit_gated() and not CorridorLevel.active_exit_requires_boss and not c.music.playing, "death animation releases exit and stops music")
	arena.reset_fight()
	check(arena.boss.hp == 160 and arena.state == "waiting" and arena.notes.is_empty() and c.time == 0 and not c.music.playing and game._exit_gated(), "retry completely resets fight and gate")
	fresh()
	n = note()
	game.player.force_death(0)
	check(arena.state == "waiting" and arena.boss.hp == 160 and arena.notes.is_empty() and not c.running, "real death signal resets arena outside rewind")
	# ---- 2026-09-28 喵斯快跑式双轨操作（用户试玩反馈）
	fresh()
	arena._engage_rhythm()
	check(arena.rhythm_lock and not game.player.auto_input \
			and game.player.position.is_equal_approx(Vector2(1408 + BeatArena.PLAYER_OFFSET, 735.9)),
		"rhythm lock pins player just before the judge line")
	var air_note := note("normal", "air", 0.3)
	var ground_note := note("normal", "ground", 0.2)
	advance(0.37)
	check(arena.rhythm_press("air") == air_note and air_note.reflected and not ground_note.reflected \
			and arena.rating == "Perfect", "up press hits only the air lane (70ms late = Perfect)")
	check(arena.player_lane == "air" and is_equal_approx(game.player.position.y, 736.0 - arena.air_lift() - 0.1) and is_equal_approx(arena.air_lift(), 104.0) \
			and game.player.batting(), "up press teleports into the air lane and swings")
	check(arena.rhythm_press("ground") == ground_note and arena.rating == "Hit" and arena.player_lane == "ground",
		"down press hits the ground lane (170ms late = Hit)")
	fresh()
	arena._engage_rhythm()
	var late := note("normal", "ground", 0.2)
	advance(0.41)
	check(late.missed and arena.rating == "Miss" and arena.rhythm_press("ground") == null and game.player.hp == 5,
		"past the 200ms window: Miss, no late hit, no damage")
	fresh()
	arena._engage_rhythm()
	var bomb := note("bomb", "ground", 0.2)
	advance(0.1)
	check(arena.rhythm_press("ground") == null and not bomb.spent, "bombs cannot be hit")
	arena.rhythm_press("air")
	advance(0.1)
	check(game.player.hp == 5 and bomb.contacted and not bomb.spent, "being in the other lane dodges a bomb")
	advance(0.4)
	check(arena.player_lane == "air", "upper lane persists until the other key is pressed")
	arena.rhythm_press("ground")
	var bomb2 := note("bomb", "ground", 0.8)
	advance(0.2)
	check(game.player.hp == 4 and bomb2.spent, "a bomb reaching the judge line in your lane hurts once")
	fresh()
	arena._engage_rhythm()
	var heavy := note("heavy", "ground", 0.1)
	check(is_equal_approx(heavy.position.y, (596.0 + 700.0) * 0.5), "dual note sits between the two lanes")
	advance(0.1)
	check(arena.rhythm_press("ground") == null and not heavy.reflected, "one lane alone does not hit a dual note")
	check(arena.rhythm_press("air") == heavy and heavy.reflected and heavy.fly_t >= 0.0,
		"pressing up and down together knocks the dual note flying")
	advance(3.0)
	check(arena.boss.hp == 157, "knocked-away dual note deals 3")
	fresh()
	arena._engage_rhythm()
	var late_dual := note("heavy", "ground", 0.1)
	advance(0.05)
	arena.rhythm_press("ground")
	advance(0.15)
	check(arena.rhythm_press("air") == null and not late_dual.reflected,
		"presses more than 120ms apart do not count as a dual hit")
	arena.reset_fight()
	check(not arena.rhythm_lock and game.player.auto_input, "reset releases the player back to free control")
	boot.free()
	current_scene = null
	SESSION.reset_for_tests()
	# AudioServer retires stopped playback objects on its next mix, not the render frame.
	await create_timer(0.25).timeout
	print("BEAT_WARDEN_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
