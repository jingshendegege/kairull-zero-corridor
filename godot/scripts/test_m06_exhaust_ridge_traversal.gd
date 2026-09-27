extends SceneTree
## Independent route fixtures; within each route only real Player.step/input and host tactics.
## No position/velocity writes between the route's start and final landing.
const SESSION := preload("res://scripts/run_session.gd")
const DT := 1.0 / 60.0
var game: Node2D
var player: KairullPlayer
var passed := 0
var failed := 0
var fan_launches := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, " feet=", player.position)

func place(c: int, row: int) -> void:
	player.reset_to_spawn()
	player.position = Vector2(c * 32 + 16, row * 32 - .1)
	player.on_ground = true
	player.invuln_t = 1000.0
	player.keys.clear()
	player._prev_keys.clear()
	for fan: Node2D in game.updraft_fans:
		fan.reset_transient()
	fan_launches = 0

func tick(keys: Dictionary) -> void:
	player.keys = keys
	player.step(DT)
	var before: float = player.vy
	game._step_tactics(DT)
	if before >= 0.0 and player.vy < 0.0:
		fan_launches += 1

func go(c: int, row: int, jump := false) -> bool:
	var target := Vector2(c * 32 + 16, row * 32 - .1)
	var jumped := false
	for frame in 240:
		var keys := {}
		var dx := target.x - player.position.x
		if player.on_ground and absf(dx) < 8.0 and absf(player.position.y - target.y) < 1.0:
			return true
		if absf(dx) > 4.0:
			keys[KEY_D if dx > 0 else KEY_A] = true
		if jump and not jumped and player.on_ground and absf(dx) < 175.0:
			keys[KEY_W] = true
			jumped = true
		tick(keys)
	return false

func fan_route(id: String, target_c: int, target_row: int) -> void:
	var fan: Node2D = game.get_node(id)
	place(floori(fan.position.x / 32), floori(fan.position.y / 32))
	tick({})
	check(fan_launches == 1 and player.vy < 0.0, id + " launches from actual floor")
	var apex: float = player.position.y
	var landed := false
	for frame in 150:
		var keys := {}
		# Rise beside the ledges before steering onto the target, avoiding lower landings.
		if player.position.y < target_row * 32.0:
			var dx := target_c * 32 + 16 - player.position.x
			if absf(dx) > 4:
				keys[KEY_D if dx > 0 else KEY_A] = true
		tick(keys)
		apex = minf(apex, player.position.y)
		if player.on_ground:
			landed = absf(player.position.y - (target_row * 32 - .1)) < 1.0 \
				and absf(player.position.x - (target_c * 32 + 16)) < 16.0
			break
	check(apex <= target_row * 32.0 and landed, id + " reaches and lands on row %d ledge" % target_row)
	print("M06_FAN_APEX: ", id, " feet_y=", apex)

func _run() -> void:
	SESSION.begin_run("easy")
	var boot: Node2D = load("res://scenes/m06_exhaust_ridge.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	game = boot.get_node("Game")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.action_audio_enabled = false
	game._sfx.clear()
	game.action_audio.stop_all()
	player = game.player
	player.auto_input = false
	fan_route("fan_tutorial", 13, 29)
	fan_route("fan_shaft", 204, 23)
	place(67, 29)
	var glass: Node2D = game.get_node("glass_gallery_1")
	for frame in 50:
		tick({KEY_D: true})
	check(not glass.broken and player.position.x + player.w * .5 <= glass.body_rect().position.x + .1
		and absf(player.position.y - (29 * 32 - .1)) < 1.0, "upper gallery walking is blocked by intact glass")
	tick({KEY_D: true, KEY_SHIFT: true})
	for frame in 18:
		tick({KEY_D: true})
	check(glass.broken and player.position.x - player.w * .5 > glass.body_rect().end.x,
		"same corridor dash breaks and crosses glass")
	place(4, 35)
	var r1 := go(8, 32, true) and go(13, 29, true)
	check(r1 and fan_launches == 0 and player.dash_cooldown_t == 0.0,
		"R1 floor -> row32 -> row29 continuous plain jumps, no fan/dash")
	place(213, 35)
	var r7 := go(213, 32, true) and go(208, 29, true) and go(211, 26, true) \
		and go(207, 23, true) and go(212, 20, true)
	check(r7 and fan_launches == 0 and player.dash_cooldown_t == 0.0,
		"R7 zig-zag floor -> rows32/29/26/23/20 continuous plain jumps")
	await create_timer(.2).timeout
	boot.free()
	current_scene = null
	SESSION.reset_for_tests()
	await create_timer(.2).timeout
	print("M06_TRAVERSAL_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
