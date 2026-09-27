extends SceneTree
## Real game/player integration in a small arena; no generated map or art mutations.
const SESSION := preload("res://scripts/run_session.gd")
const CHECKPOINT := preload("res://scripts/run_checkpoint.gd")
const TIMELINE := preload("res://scripts/attempt_timeline.gd")
const DT := 1.0 / 60.0
const FLOOR_Y := 608.0
var passed := 0
var failed := 0
var game: Node2D
var player: KairullPlayer
var fan: Node2D
var glass: Node2D
var node: Node2D
var sniper: Node2D


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String, detail := "") -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label, " " + detail if not value else "")


func _build_arena() -> void:
	SESSION.reset_for_tests()
	var rows := PackedStringArray()
	for y in 20:
		var row := ".".repeat(64)
		if y == 19:
			row = "#".repeat(64)
		elif y == 18:
			for pair in [[3, "@"], [42, "C"], [44, "m"], [47, "x"]]:
				row = row.substr(0, pair[0]) + pair[1] + row.substr(pair[0] + 1)
		rows.append(row)
	CorridorLevel.active_map = "\n".join(rows)
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_rooms = [{"name": "M06 test arena", "room_id": "arena", "rect": Rect2i(0, 0, 64, 20)}]
	CorridorLevel.active_checkpoints = [{"id": "fixture", "room_index": 0, "cell": [3, 18], "required_clear_rooms": []}]
	CorridorLevel.active_tactical_objects = [
		{"id": "fan", "type": "updraft_fan", "pos": [160, 608], "width": 64, "launch_height": 288},
		{"id": "glass", "type": "glass_panel", "rect": [512, 480, 32, 128]},
		{"id": "glass_saved", "type": "glass_panel", "rect": [1088, 480, 32, 128]},
		{"id": "node", "type": "dash_node", "pos": [900, 580], "respawn": 2.0},
		{"id": "sniper", "type": "auto_sniper", "pos": [360, 608], "direction": [1, 0], "room_id": "arena"}]
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.set_process(false)
	game.set_physics_process(false)
	game.timeline_enabled = true
	game.action_audio_enabled = false
	game._sfx.clear()
	game.action_audio.stop_all()
	player = game.player
	player.auto_input = false
	player.set_physics_process(false)
	fan = game.updraft_fans[0]
	glass = game.glass_panels[0]
	node = game.dash_nodes[0]
	sniper = game.tactical_hazards[0]
	check(game.updraft_fans.size() == 1 and game.glass_panels.size() == 2 and game.dash_nodes.size() == 1,
			"setup dispatches all three new tactical types separately from hazards")
	check(player.glass_panels.has(glass) and player.death_obstacles.has(glass)
			and game._world_blockers().has(glass) and not game.doors.has(glass),
			"glass shares the world blocker interface without joining clear-room doors")
	check(not CorridorLevel.active_kill_refresh_dash, "kill refresh defaults off")


func _place(x: float, y := FLOOR_Y - 0.1) -> void:
	game._set_player_time_focus(false)
	game._set_temporal_nodes_paused(false)
	game.time_phase = "playing"
	game.time_charge.reset()
	game.level_cleared = false
	player.reset_to_spawn()
	player.position = Vector2(x, y)
	player.configure_max_health(5)
	player.invuln_t = 100.0
	player.on_ground = true
	player.keys.clear()
	player._prev_keys.clear()
	player._sync_sprite()
	game._update_room_state()
	game.cam_tl = Vector2.ZERO
	game.enemy_bullets.clear()


func _run() -> void:
	_build_arena()
	_test_fan()
	_test_dash_node()
	_test_frozen_world()
	_test_glass_blocking()
	_test_glass_breaks()
	_test_projectile_breaks()
	_test_kill_refresh()
	_test_barrel_attribution()
	_test_restore_and_rewind()
	_test_scene_rebuild()
	CorridorLevel.active_kill_refresh_dash = true
	game.free()
	check(not CorridorLevel.active_kill_refresh_dash, "scene exit resets kill-refresh rule")
	CorridorLevel.active_map = ""
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_rooms = []
	CorridorLevel.active_checkpoints = []
	CorridorLevel.active_tactical_objects = []
	SESSION.reset_for_tests()
	await process_frame
	print("M06_MECHANICS_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))


func _test_fan() -> void:
	_place(fan.position.x)
	fan.reset_transient()
	player.dash_cooldown_t = 0.8
	game._step_tactics(DT)
	check(player.vy < 0.0 and not player.on_ground, "fan launches grounded player")
	check(is_equal_approx(player.dash_cooldown_t, 0.8), "fan neither consumes nor refreshes dash")
	var minimum_y := player.position.y
	for tick in 100:
		player.step(DT)
		minimum_y = minf(minimum_y, player.position.y)
		if player.vy >= 0.0:
			break
	var height: float = FLOOR_Y - 0.1 - minimum_y
	print("FAN_APEX: measured=%.3fpx configured=%.3fpx tolerance=8px" % [height, fan.launch_height])
	check(absf(height - fan.launch_height) <= 8.0, "real player gravity reaches configured fan apex within 8px", "height=%.3f" % height)
	_place(fan.position.x)
	fan.reset_transient()
	game._step_tactics(DT)
	player.on_ground = true
	player.vy = 0.0
	game._step_tactics(0.24)
	check(player.vy == 0.0 and player.on_ground, "same fan cannot retrigger within 0.25 seconds")
	game._step_tactics(0.011)
	check(player.vy < 0.0 and not player.on_ground, "fan becomes reusable after 0.25 seconds")
	_place(fan.position.x + fan.width * 0.5 + 1.0)
	fan.reset_transient()
	game._step_tactics(DT)
	check(player.vy == 0.0, "fan uses feet center and configured width")
	_place(fan.position.x, FLOOR_Y - 100.0)
	player.on_ground = false
	game._step_tactics(DT)
	check(player.vy == 0.0, "fan does not launch a player merely above it")
	for tick in 120:
		player.step(DT)
		game._step_tactics(DT)
		if fan.cooldown_t > 0.0:
			break
	check(fan.cooldown_t > 0.0 and player.vy < 0.0, "landing from the air activates the fan")


func _test_dash_node() -> void:
	_place(node.position.x)
	node.reset_transient()
	game._step_tactics(DT)
	check(node.lit and player.dash_cooldown_t == 0.0, "available dash does not consume node")
	player.dash_cooldown_t = 1.2
	game._step_tactics(DT)
	check(not node.lit and player.dash_cooldown_t == 0.0, "node contact clears active dash cooldown")
	player.dash_cooldown_t = 0.9
	game._step_tactics(node.respawn - 0.01)
	check(not node.lit and is_equal_approx(player.dash_cooldown_t, 0.9), "dark node cannot refresh before respawn threshold")
	player.position.x += 100.0
	game._step_tactics(0.011)
	check(node.lit, "node relights after configured respawn seconds")
	player.position.x = node.position.x
	game._step_tactics(DT)
	check(not node.lit and player.dash_cooldown_t == 0.0, "relit node can be consumed again")


func _test_frozen_world() -> void:
	_place(fan.position.x)
	fan.reset_transient()
	node.lit = false
	node.respawn_remaining = 1.5
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	var phase: float = fan.spin_phase
	for tick in 20:
		game._physics_process(DT)
		game._step_tactics(DT) # Host guard must also protect direct tactical stepping.
	check(game.time_charge.active and player.vy == 0.0 and fan.spin_phase == phase,
			"time-stop freezes fan visual clock and launch")
	check(not node.lit and is_equal_approx(node.respawn_remaining, 1.5), "time-stop freezes node respawn")
	player.keys.clear()
	game._physics_process(DT)
	check(not game.time_charge.active and player.vy < 0.0 and node.respawn_remaining < 1.5,
			"release time-stop resumes fan and node simulation")
	_place(fan.position.x)
	fan.reset_transient()
	phase = fan.spin_phase
	var remaining: float = node.respawn_remaining
	game.pause_controller.pause_game()
	for tick in 20:
		game._physics_process(DT)
		game._step_tactics(DT)
	check(game.pause_controller.active and fan.spin_phase == phase and player.vy == 0.0
			and node.respawn_remaining == remaining, "pause freezes launch, fan visuals, and node clock")
	game.pause_controller.resume_game()
	player.force_death(player.position.x - 60.0)
	for tick in 20:
		game._physics_process(DT)
		game._step_tactics(DT)
	check(player.dead and game.time_phase == "dying" and fan.spin_phase == phase
			and node.respawn_remaining == remaining, "death freezes traversal clocks")
	_place(440.0)
	glass.restore_broken(false)
	var shard_panel: Node2D = game.glass_panels[1]
	shard_panel.take_hit(player.position.x)
	player.hitstop = 0.0
	var frozen_shards: Array = shard_panel.shards.duplicate(true)
	player.keys = {MOUSE_BUTTON_RIGHT: true}
	game._physics_process(DT)
	player.keys[KEY_SHIFT] = true
	var dash_started := false
	for tick in 20:
		game._physics_process(DT)
		player.step(DT)
		dash_started = dash_started or player.dashing()
		player.keys.erase(KEY_SHIFT)
	check(dash_started and game.time_charge.active and not glass.broken
			and player.position.x + player.w * 0.5 <= glass.position.x + 0.1,
			"real dash during host time-stop cannot break or cross intact glass")
	check(shard_panel.shards == frozen_shards, "host time-stop freezes existing glass shards")
	player.keys.clear()
	game._physics_process(DT)
	check(not game.time_charge.active and shard_panel.shards != frozen_shards, "thaw resumes shard particles")
	_place(440.0)
	player.face = 1
	player.keys = {KEY_SHIFT: true}
	for tick in 15:
		player.step(DT)
		player.keys.clear()
	check(glass.broken and player.position.x > glass.body_rect().end.x, "fresh dash after thaw breaks and crosses glass")
	shard_panel.restore_broken(false)
	_place(430.0)


func _test_glass_blocking() -> void:
	glass.restore_broken(false)
	_place(450.0)
	player.keys = {KEY_D: true}
	for tick in 40:
		player.step(DT)
	check(not glass.broken and player.position.x + player.w * 0.5 <= glass.position.x + 0.1,
			"walking into glass blocks movement and leaves it intact", str(player.position))
	_place(640.0)
	player.invuln_t = 0.0
	var hp := player.hp
	var bullet := {"x": 450.0, "y": 570.0, "vx": 2700.0, "vy": 0.0, "life": 2.0}
	game.enemy_bullets.append(bullet)
	game._advance_enemy_bullets(0.1)
	check(game.enemy_bullets.is_empty() and player.hp == hp and not glass.broken
			and float(bullet.x) <= glass.body_rect().end.x,
			"intact glass absorbs a high-speed enemy bullet before player")
	sniper.set_armed(true)
	sniper._change_state("idle")
	sniper.advance(DT, player)
	check(sniper.state == "idle" and not sniper._can_acquire(player, false), "glass blocks sniper acquisition ray")
	for enemy: Node2D in game.minions:
		enemy.position = Vector2(460.0, FLOOR_Y - 0.1)
		check(enemy.door_blockers.has(glass) and not enemy._has_los(), "glass blocks %s enemy vision" % enemy.get_class())
		var before: Vector2 = enemy.position
		# Feed the normal enemy movement solver and host collision correction together.
		for tick in 40:
			before = enemy.position
			enemy._move_horizontal(5.0)
			game._resolve_glass_enemy_movement(enemy, before)
		check(enemy.body_rect().end.x <= glass.position.x + 0.1, "glass blocks %s enemy walking" % enemy.get_script().resource_path)
		var falling_start := Vector2(460.0, FLOOR_Y - 50.0)
		enemy.position = falling_start + Vector2(100.0, 10.0)
		game._resolve_glass_enemy_movement(enemy, falling_start)
		check(enemy.body_rect().end.x <= glass.position.x + 0.1
				and is_equal_approx(enemy.position.y, falling_start.y + 10.0),
				"glass side collision preserves enemy vertical fall")
		enemy.position.y = FLOOR_Y - 0.1
		glass.restore_broken(true)
		check(enemy._has_los(), "broken glass restores enemy vision")
		glass.restore_broken(false)
		enemy.position = Vector2(1450.0 + game.minions.find(enemy) * 160.0, FLOOR_Y - 0.1)
	glass.restore_broken(true)
	sniper._change_state("idle")
	sniper.advance(DT, player)
	check(sniper.state == "warning", "broken glass allows sniper acquisition")
	sniper.set_armed(false)


func _test_glass_breaks() -> void:
	for action in [KEY_SHIFT, KEY_CTRL]:
		glass.restore_broken(false)
		_place(440.0)
		player.face = 1
		var start_x := player.position.x
		if action == KEY_SHIFT:
			player._try_dash()
		else:
			player._try_roll()
		check(not glass.broken, "burst destination preview does not break glass before contact")
		for tick in 45:
			player.step(DT)
		check(glass.broken, "actual %s contact breaks glass" % ("dash" if action == KEY_SHIFT else "roll"))
		var expected := KairullPlayer.DASH_DISTANCE if action == KEY_SHIFT else KairullPlayer.ROLL_DISTANCE
		check(player.position.x >= start_x + expected - 2.0, "glass break preserves full burst travel")
	glass.restore_broken(false)
	_place(462.0)
	player.face = 1
	player.keys = {MOUSE_BUTTON_LEFT: true}
	player.step(DT)
	check(player.batting() and not glass.broken, "bat windup starts without premature glass break")
	player.keys.clear()
	for tick in 45:
		player.step(DT)
		if glass.broken:
			break
	check(glass.broken, "real bat active hitbox breaks glass")
	check(is_equal_approx(player.hitstop, 0.05) and game.camera_trauma > 0.0,
			"glass break adds approximately 0.05s hitstop and camera shake", str(player.hitstop))
	check(glass.shards.size() > 0 and glass.shards.size() <= glass.MAX_SHARDS, "glass shard count is bounded")
	var count: int = glass.shards.size()
	check(not glass.take_hit(player.position.x) and glass.shards.size() == count, "broken glass cannot duplicate shatter particles")
	glass.advance(glass.SHARD_LIFETIME + 0.01)
	check(glass.shards.is_empty(), "glass shards expire and release their bounded pool")


func _test_projectile_breaks() -> void:
	_place(350.0)
	glass.restore_broken(false)
	var cargo: PropBatCargo = game.props[0]
	cargo.reset_to_spawn()
	cargo.position = Vector2(430.0, FLOOR_Y - 0.1)
	game._on_player_bat_swung(cargo.body_rect(), 0)
	check(cargo.flying and not glass.broken, "bat launches cargo before glass contact")
	for tick in 20:
		game._physics_process(DT)
		if cargo.dead:
			break
	check(glass.broken and cargo.dead, "host-stepped flying cargo breaks glass on impact")
	glass.restore_broken(false)
	var enemy: Node2D = game.minions[0]
	enemy.position = Vector2(415.0, FLOOR_Y - 0.1)
	enemy.take_hit(350.0, 1)
	check(enemy.dead and game._start_corpse_impact(enemy, 2, 1.0), "real enemy corpse starts inertial flight")
	for tick in 45:
		game._update_corpse_impacts(DT)
		if glass.broken:
			break
	check(glass.broken, "flying corpse breaks glass through host motion callback")
	game._clear_corpse_impacts()
	enemy.position.x = 1450.0


func _revive(enemy: Node2D, at: Vector2) -> void:
	enemy.dead = false
	enemy.visible = true
	enemy.position = at
	enemy._set_state("idle")
	enemy.set_corpse_lift(0.0)


func _test_kill_refresh() -> void:
	_place(1200.0)
	var enemy: Node2D = game.minions[0]
	for enabled in [false, true]:
		CorridorLevel.active_kill_refresh_dash = enabled
		_revive(enemy, Vector2(1250.0, FLOOR_Y - 0.1))
		player.dash_cooldown_t = 1.0
		game._on_player_bat_swung(enemy.body_rect(), 0)
		check(enemy.dead and player.dash_cooldown_t == (0.0 if enabled else 1.0),
				"player bat kill refresh rule %s" % enabled)
		_revive(enemy, Vector2(1250.0, FLOOR_Y - 0.1))
		player.dash_cooldown_t = 1.0
		var cargo: PropBatCargo = game.props[0]
		cargo.reset_to_spawn()
		cargo.position = Vector2(1160.0, FLOOR_Y - 0.1)
		cargo.launch(1)
		cargo.advance(0.15, game.level, game._cargo_targets(), game.doors + game.moving_lifts)
		check(enemy.dead and player.dash_cooldown_t == (0.0 if enabled else 1.0),
				"player cargo kill refresh rule %s" % enabled)
		game._clear_corpse_impacts()
	CorridorLevel.active_kill_refresh_dash = true
	_revive(enemy, Vector2(1400.0, FLOOR_Y - 0.1))
	player.dash_cooldown_t = 0.8
	game._on_player_enemy_killed(enemy)
	check(is_equal_approx(player.dash_cooldown_t, 0.8), "live enemy does not qualify for kill refresh")
	CorridorLevel.active_kill_refresh_dash = false


func _test_barrel_attribution() -> void:
	_place(1140.0)
	CorridorLevel.active_kill_refresh_dash = true
	var enemy: Node2D = game.minions[0]
	for player_ignited in [false, true]:
		_revive(enemy, Vector2(1370.0, FLOOR_Y - 0.1))
		var first: PropBarrel = game._spawn_prop("barrel", Vector2(1200.0, FLOOR_Y - 0.1))
		var chained: PropBarrel = game._spawn_prop("barrel", Vector2(1280.0, FLOOR_Y - 0.1))
		player.dash_cooldown_t = 1.0
		if player_ignited:
			game._on_player_bat_swung(first.body_rect(), 0)
		else:
			game.enemy_bullets.append({"x": 1170.0, "y": 594.0, "vx": 600.0, "vy": 0.0, "life": 2.0})
			game._advance_enemy_bullets(0.1)
			# Hitting an already enemy-ignited fuse must not steal kill attribution.
			game._on_player_bat_swung(first.body_rect(), 0)
		check(first.fusing and bool(first.get_meta("player_ignited", false)) == player_ignited,
				"barrel ignition preserves player-source attribution %s" % player_ignited)
		first.step(PropBarrel.FUSE_TIME + 0.01)
		check(chained.fusing and not enemy.dead, "first barrel transfers fuse before distant target dies")
		chained.step(PropBarrel.CHAIN_FUSE + 0.01)
		check(enemy.dead and player.dash_cooldown_t == (0.0 if player_ignited else 1.0),
				"chain explosion refreshes only for player-originated kill %s" % player_ignited)
		game._clear_corpse_impacts()
		game.props.erase(first)
		game.props.erase(chained)
		first.free()
		chained.free()
	CorridorLevel.active_kill_refresh_dash = false


func _test_restore_and_rewind() -> void:
	_place(112.0)
	var saved_glass: Node2D = game.glass_panels[1]
	glass.restore_broken(false)
	saved_glass.restore_broken(true)
	var snapshot := CHECKPOINT.capture(game, CorridorLevel.active_checkpoints[0], player.position)
	glass.take_hit(player.position.x)
	saved_glass.restore_broken(false)
	fan.cooldown_t = 0.2
	node.lit = false
	node.respawn_remaining = 1.2
	check(CHECKPOINT.restore(game, snapshot), "checkpoint restores real game with all new tactical types")
	check(not glass.broken and saved_glass.broken, "checkpoint preserves pre-snapshot break and undoes post-snapshot break")
	check(node.lit and node.respawn_remaining == 0.0 and fan.cooldown_t == 0.0,
			"checkpoint relights nodes and clears fan cooldowns")
	var timeline := TIMELINE.new()
	fan.spin_phase = 0.25
	timeline.record(game, 0.0, true)
	glass.take_hit(player.position.x)
	fan.spin_phase = 1.0
	fan.cooldown_t = 0.18
	node.lit = false
	node.respawn_remaining = 1.4
	timeline.record(game, 0.5, true)
	player.hitstop = 0.0
	timeline.apply_rewind(game, 1.0)
	check(not glass.broken and saved_glass.broken and node.lit and is_equal_approx(fan.spin_phase, 0.25),
			"timeline safely restores oldest new-object poses")
	timeline.apply_rewind(game, 0.0)
	check(glass.broken and not node.lit and is_equal_approx(node.respawn_remaining, 1.4)
			and is_equal_approx(fan.cooldown_t, 0.18) and is_equal_approx(fan.spin_phase, 1.0),
			"timeline safely restores newest new-object poses")
	check(player.hitstop == 0.0 and glass.shards.size() <= glass.MAX_SHARDS,
			"timeline restore does not replay shatter feedback or grow particles")


func _test_scene_rebuild() -> void:
	# Death uses a fresh scene; verify construction itself resets transient traversal resources.
	_place(112.0)
	fan.cooldown_t = 0.2
	node.lit = false
	node.respawn_remaining = 1.2
	glass.restore_broken(true)
	player.force_death(player.position.x - 60.0)
	check(player.dead and game.time_phase == "dying", "death enters the real host restore lifecycle")
	game.free()
	_build_arena()
	check(not player.dead and node.lit and node.respawn_remaining == 0.0 and fan.cooldown_t == 0.0
			and not glass.broken, "fresh scene after death relights nodes, clears fans, and restores intact glass")
