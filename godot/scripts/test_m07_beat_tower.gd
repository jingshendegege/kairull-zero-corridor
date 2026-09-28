extends SceneTree
const SESSION := preload("res://scripts/run_session.gd")
const DATA := preload("res://generated/m07_beat_tower_data.gd")
const SNAPSHOT := preload("res://scripts/run_checkpoint.gd")
const SCENE := "res://scenes/m07_beat_tower.tscn"
var passed := 0
var failed := 0
var clock_time := 0.0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)

func prepare(game: Node2D) -> void:
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.auto_input = false
	game.action_audio_enabled = false
	game._sfx.clear()
	game.beat_arena.conductor.clock = func() -> float: return clock_time

func _run() -> void:
	SESSION.begin_run("hard")
	var boot: Node2D = load(SCENE).instantiate()
	root.add_child(boot)
	current_scene = boot
	var game: Node2D = boot.get_node("Game")
	prepare(game)
	var arena: BeatArena = game.beat_arena
	check(game.level.map_w == 80 and game.level.map_h == 25, "scene boots 80 x 25 compiled map")
	check(game.level.rooms.size() == 3 and game.minions.size() == 2, "three rooms and two minions")
	check(game.minions.any(func(e: Node2D) -> bool: return e is FreightInspector) and game.minions.any(func(e: Node2D) -> bool: return e is GruntGunner), "one melee and one gunner")
	check(CorridorLevel.active_checkpoints == DATA.CHECKPOINTS and game._checkpoint_beacons.size() == 1, "single green-room checkpoint")
	check(DATA.BOSS_ARENA.floor_y == 736 and arena.config == DATA.BOSS_ARENA, "BOSS_ARENA delivered geometry used unchanged")
	check(GameBackground.active_cfg == GameBackground.CFG_M07 and QuarantineArchitecture.open_sky_profiles == ["beat_stage"], "stage backdrop and open sky profile enabled")
	check(CorridorLevel.active_title == "05 节拍广播塔" and game.timeline_enabled and game.red_boss == null, "campaign title and independent rhythm boss")
	check(game.music.stream.resource_path.ends_with("m02_oldtown.mp3") and game.music.volume_db == -18, "backstage music at -18 dB")
	arena.step(10)
	check(arena.state == "waiting" and not arena.conductor.running and game._exit_gated(), "backstage cannot start fight or bypass exit")
	var point: Vector2 = game._checkpoint_beacons[1].position
	game.player.position = point
	game.player.on_ground = true
	game._update_room_state()
	game._update_campaign_progress(0)
	check(SESSION.checkpoint.is_empty(), "checkpoint locked before backstage clear")
	for enemy: Node2D in game.minions:
		enemy.dead = true
	game._update_campaign_progress(0)
	check(SESSION.checkpoint.get("id") == "m07_green_room", "backstage clear activates real checkpoint")
	var saved := SESSION.checkpoint.duplicate(true)
	game.player.position = Vector2(1183, 736)
	arena.step(0)
	check(arena.state == "waiting", "entry threshold excludes x 1183")
	game.player.position.x = 1184
	arena.step(0)
	check(arena.state == "count_in" and arena.judge_label.text == "3" and not arena.conductor.running, "stage entry begins count-in")
	for label in ["2", "1", "GO"]:
		arena.step(arena.conductor.seconds(1))
		check(arena.judge_label.text == label, "count-in " + label)
	check(not arena.conductor.running, "GO still occupies fourth beat")
	arena.step(arena.conductor.seconds(1))
	check(arena.state == "playing" and arena.conductor.time == 0 and not game.music.playing, "one bar starts boss song from zero and stops ambience")
	arena.boss.take_reflected_hit(20)
	arena.spawn_note({"kind":"normal","lane":"ground","time":2.0})
	game.attempt_timeline.record(game, 0, true)
	game.player.force_death(2000)
	check(arena.state == "waiting" and arena.boss.hp == 160 and arena.notes.is_empty() and not arena.conductor.music.playing, "real campaign death resets full fight")
	game._begin_rewind()
	game.attempt_timeline.apply_rewind(game, 0.5)
	check(arena.boss.hp == 160 and arena.notes.is_empty(), "timeline does not restore partial encounter")
	game._advance_rewind(game.REWIND_DURATION + game.INTERFERENCE_DURATION + 0.01)
	for frame in 4:
		await process_frame
	game = current_scene.get_node("Game")
	prepare(game)
	arena = game.beat_arena
	check(game._checkpoint_index == 1 and game.player.position.distance_to(point) < 1 and game.player.hp == 3, "retry truly rebuilds at green-room checkpoint with difficulty health")
	check(arena.state == "waiting" and arena.boss.hp == 160 and arena.conductor.time == 0 and arena.notes.is_empty(), "new encounter remains idle after checkpoint restore")
	check(game.music.playing and not arena.conductor.music.playing, "retry restores backstage music without overlapping boss song")
	check(SESSION.checkpoint.id == saved.id and SNAPSHOT.signature() == saved.signature, "checkpoint remains compatible and carries no boss snapshot")
	game.player.position = Vector2(1200, 736)
	arena.step(0)
	check(arena.state == "count_in" and arena.judge_label.text == "3", "re-enter stage counts in again")
	arena.step(arena.conductor.seconds(4))
	arena.boss.take_reflected_hit(160)
	arena.step(0.5)
	game.player.position = game.level.exit_point
	game._physics_process(0)
	check(game.level_cleared and game._victory_started and game.victory_next_scene().is_empty(), "boss death leads to normal final victory via actual exit")
	current_scene.free()
	current_scene = null
	check(GameBackground.active_cfg.is_empty() and QuarantineArchitecture.open_sky_profiles.is_empty() and not CorridorLevel.active_exit_requires_boss, "boot cleans backdrop and gate statics")
	check(SESSION.LEVEL_SCENES.size() == 5 and SESSION.LEVEL_NAMES[4] == "05 节拍广播塔", "session contains five menu levels")
	check(SESSION.next_scene_after("res://scenes/m06_exhaust_ridge.tscn") == SCENE and SESSION.next_scene_after(SCENE).is_empty(), "M06 advances to M07 and M07 is final")
	SESSION.reset_for_tests()
	var menu: Node3D = load("res://scenes/surveillance_menu.tscn").instantiate()
	menu.suppress_external_actions = true
	root.add_child(menu)
	current_scene = menu
	await process_frame
	for index in 4:
		menu._handle_keycode(KEY_DOWN)
	check(menu.selected_level == 4 and SESSION.selected_scene() == SCENE, "menu keyboard selects fifth level")
	var card: Rect2 = menu.level_card_rect(4)
	check(card.end.x <= 602 and card.position.x > menu.level_card_rect(3).end.x, "five menu cards fit without overlap")
	menu._handle_keycode(KEY_DOWN)
	check(menu.selected_level == 0, "fifth menu entry wraps to first")
	menu.free()
	current_scene = null
	SESSION.reset_for_tests()
	await process_frame
	print("M07_BEAT_TOWER_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
