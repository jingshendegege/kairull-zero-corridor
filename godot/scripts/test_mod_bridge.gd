extends SceneTree
## 创意工坊桥接：注册表应用到真实游戏钩子（限幅、默认值不变）与事件发出。
const SESSION := preload("res://scripts/run_session.gd")
const CHRONO := preload("res://scripts/chrono_charge.gd")
const BEAT_ARENA := preload("res://scripts/beat_arena.gd")
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _run() -> void:
	var bridge: Node = root.get_node("ModBridge")
	check(bridge != null and not bridge.web_enabled, "autoload present; desktop/headless has no JS bridge")
	check(SESSION.health_for_difficulty("easy") == 5 and SESSION.health_for_difficulty("zero") == 1
		and CHRONO.max_duration() == 2.0 and BEAT_ARENA.mod_boss_hp_scale == 1.0, "defaults unchanged without mods")
	bridge.apply({"difficultyHealth": {"easy": 7, "zero": 99}, "timeStop": {"durationScale": 1.5, "rechargeScale": 0.01},
		"boss": {"hpScale": 0.5}, "playerTint": {"color": "#ff0000", "strength": 0.5}})
	check(SESSION.health_for_difficulty("easy") == 7 and SESSION.health_for_difficulty("hard") == 3
		and SESSION.health_for_difficulty("zero") == 9, "difficulty health override is clamped to 1-9, unset modes keep defaults")
	check(is_equal_approx(CHRONO.max_duration(), 3.0) and is_equal_approx(CHRONO.recharge_scale, 0.25),
		"time-stop scales apply and are clamped to 0.25-4")
	var charge := CHRONO.new()
	check(is_equal_approx(charge.energy, 3.0) and is_equal_approx(charge.ratio(), 1.0), "new time-stop charge starts full at the modded duration")
	SESSION.begin_run("easy")
	var boot: Node = load("res://scenes/m07_beat_tower.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	for i in 3:
		await process_frame
	var game: Node2D = boot.get_node("Game")
	check(game.player.max_hp == 7, "modded difficulty health reaches the real player")
	check(game.beat_arena.boss.max_hp == int(round(float(game.beat_arena.conductor.chart.boss_hp) * 0.5)), "boss HP scale reaches the rhythm boss")
	var names: Array = bridge.events_log.map(func(e: Dictionary) -> String: return e.name)
	check(names.has("game:ready") and names.has("level:start"), "game:ready and level:start events emitted")
	var start: Dictionary = bridge.events_log.filter(func(e: Dictionary) -> bool: return e.name == "level:start")[-1].payload
	check(start.scene == "m07_beat_tower" and start.maxHealth == 7, "level:start carries scene and max health")
	var sprite: Sprite2D = game.player._sprite
	check(is_equal_approx(sprite.modulate.r, 1.0) and is_equal_approx(sprite.modulate.g, 0.5), "player tint applied (strength 0.5 toward red)")
	game.beat_arena.rated.emit("Perfect", "air")
	game.player.hurt.emit()
	names = bridge.events_log.map(func(e: Dictionary) -> String: return e.name)
	check(names.has("rhythm:judge") and names.has("player:hurt"), "rhythm judge and hurt events forwarded")
	var judge: Dictionary = bridge.events_log.filter(func(e: Dictionary) -> bool: return e.name == "rhythm:judge")[-1].payload
	check(judge.rating == "perfect" and judge.lane == "air", "rhythm ratings are normalized to lowercase API values")
	var music := root.get_node_or_null("ContinuousLevelMusic")
	boot.queue_free()
	current_scene = null
	await process_frame
	if music != null:
		music.stop()
	bridge.reset()
	check(SESSION.health_for_difficulty("easy") == 5 and CHRONO.max_duration() == 2.0
		and BEAT_ARENA.mod_boss_hp_scale == 1.0 and not bridge.has_player_tint, "reset restores all defaults")
	SESSION.reset_for_tests()
	print("MOD_BRIDGE_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
