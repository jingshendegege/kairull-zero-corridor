extends SceneTree
## Headless runtime contracts; no production maps/assets are modified.
const HOUND := preload("res://scripts/quarantine_hound.gd")
const TIMELINE := preload("res://scripts/attempt_timeline.gd")
const CHECKPOINT := preload("res://scripts/run_checkpoint.gd")
const SESSION := preload("res://scripts/run_session.gd")
const DT := 1.0 / 60.0
var passed := 0
var failed := 0
var game: Node2D
var hound: QuarantineHound


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _run() -> void:
	_boot()
	_test_atlas()
	_test_ai()
	_test_obstacles()
	_test_damage()
	_test_freeze()
	_test_timeline()
	_test_projectile_kill()
	_test_death_and_checkpoint()
	game.free()
	SESSION.reset_for_tests()
	await create_timer(0.2).timeout
	print("QUARANTINE_HOUND_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))


func _boot() -> void:
	SESSION.reset_for_tests()
	var rows := PackedStringArray()
	for y in 12:
		var row := "#".repeat(48) if y == 10 else ".".repeat(48)
		if y == 9:
			for marker in [[3, "@"], [10, "h"], [30, "h"]]:
				row = row.substr(0, marker[0]) + marker[1] + row.substr(marker[0] + 1)
		rows.append(row)
	CorridorLevel.active_map = "\n".join(rows)
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_stairs = []
	CorridorLevel.active_rooms = [{"name": "Hound fixture", "rect": Rect2i(0, 0, 48, 12)}]
	CorridorLevel.active_checkpoints = [{"id": "hound-checkpoint", "room_index": 0,
		"required_clear_rooms": [], "pos": [112, 319.9]}]
	CorridorLevel.active_tactical_objects = [{"id": "hound-glass", "type": "glass_panel",
		"rect": [1200, 192, 2, 128]}]
	CorridorLevel.active_campaign_mode = false
	CorridorLevel.active_kill_refresh_dash = true
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game.player.set_physics_process(false)
	game._sfx.clear()
	game.action_audio_enabled = false
	check(game.minions.size() == 2 and game.minions[0] is QuarantineHound,
		"MAP_TEXT h creates QuarantineHound through the production factory")
	hound = game.minions[0]
	check(game.level.enemy_spawn_kinds == ["hound", "hound"] and game.level.tile_at(10, 9) == ".",
		"h markers become hound spawn kinds and are stripped from collision grid")
	check(hound.player == game.player and hound.level == game.level and hound.vision_blocker.is_valid()
		and hound.door_blockers.has(game.glass_panels[0]), "factory wires player, level, smoke and glass")
	check(hound.get_meta("spawn_cell") == Vector2i(10, 9) and game.room_alive_count(0) == 2
		and game.room_total_count(0) == 2, "spawn identity and room counts include hounds")
	check(not hound.is_physics_processing(), "hound has no autonomous physics tick")


func _reset(distance := 150.0) -> void:
	game._clear_corpse_impacts()
	hound.dead = false
	hound.hitstop = 0.0
	hound.position = Vector2(336, 319.9)
	hound.velocity = Vector2.ZERO
	hound._set_state("idle")
	hound.frame = 0
	hound._attack_spent = false
	hound._pounce_landed = false
	hound.vision_blocker = Callable(game.smoke_tactics, "blocks_segment")
	hound.door_blockers = game._world_blockers()
	game.player.reset_to_spawn()
	game.player.configure_max_health(20, true)
	game.player.position = hound.position + Vector2(distance, 0)
	game.player.invuln_t = 0
	game.player.roll_invuln_t = 0
	game.player.keys.clear()
	game.time_charge.reset()
	game.timeline_enabled = false
	game.level_cleared = false
	game.time_phase = "playing"


func _ticks(count: int) -> void:
	for i in count:
		hound.step(DT)


func _test_atlas() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HOUND.META_PATH))
	var image := Image.load_from_file(HOUND.ATLAS_PATH)
	check(meta.cell_size == [160.0, 96.0] and meta.baseline_y == 89 and HOUND.SCALE == 1.0,
		"atlas cell 160x96, baseline 89 and scale 1.0")
	var expected := {"idle": 4, "alert": 4, "run": 6, "windup": 4, "pounce": 4, "recover": 4, "death": 6}
	var sizes_ok := true
	var grounded := true
	var record_count := 0
	for animation: String in expected:
		check(int(meta.animations[animation].frames) == expected[animation], animation + " frame count")
		for index in expected[animation]:
			var rect := Rect2i(index * 160, int(meta.animations[animation].row) * 96, 160, 96)
			sizes_ok = sizes_ok and Rect2i(Vector2i.ZERO, image.get_size()).encloses(rect)
			var used := image.get_region(rect).get_used_rect()
			grounded = grounded and used.has_area() and used.end.y == 89
			var matched := false
			for record: Dictionary in meta.frames:
				if record.animation == animation and int(record.frame) == index:
					matched = record.cell_bbox == [float(used.position.x), float(used.position.y),
						float(used.size.x), float(used.size.y)]
					record_count += 1
			grounded = grounded and matched
	check(sizes_ok and record_count == 32, "all 32 JSON frames fit the atlas")
	check(grounded, "real or placeholder frame alpha bounds match JSON and share baseline")
	check(hound._sprite.region_rect.size == Vector2(160, 96)
		and is_equal_approx(hound._sprite.position.y + 89 - 48, 0), "sprite feet anchored using metadata")
	check(hound.body_rect().size == Vector2(56, 48) and hound.standing_height() > 0,
		"short body collision and metadata standing height")
	check(hound._outline.material.shader.code == GruntGunner.OUTLINE_SHADER_CODE
		and hound._rim.material.shader.code == GruntGunner.RIM_SHADER_CODE, "existing outline and rim shaders reused")
	# Exercise a solid-color placeholder through the same loader without replacing real art.
	var placeholder := {"cell_size": [160, 96], "baseline_y": 89, "pivot_x": 80,
		"animations": {}, "frames": []}
	var pixels := Image.create(6 * 160, 7 * 96, false, Image.FORMAT_RGBA8)
	var row := 6 # Deliberately reverse row order to catch hardcoded animation coordinates.
	for animation: String in expected:
		placeholder.animations[animation] = {"row": row, "frames": expected[animation],
			"loop": animation in ["idle", "run"]}
		for index in expected[animation]:
			pixels.fill_rect(Rect2i(index * 160 + 52, row * 96 + 41, 56, 48), Color.MAGENTA)
			placeholder.frames.append({"animation": animation, "frame": index, "row": row,
				"cell_bbox": [52, 41, 56, 48]})
		row -= 1
	var real_texture := hound._atlas
	hound._atlas = ImageTexture.create_from_image(pixels)
	for sprite in [hound._sprite, hound._outline, hound._rim]: sprite.texture = hound._atlas
	hound._load_atlas_metadata(placeholder)
	var placeholder_ok := true
	for animation: String in expected:
		hound.state = "dead" if animation == "death" else animation
		hound.frame = 0
		hound._sync_sprite()
		var rect := Rect2i(hound._sprite.region_rect)
		placeholder_ok = placeholder_ok and rect.position.y == int(placeholder.animations[animation].row) * 96
		placeholder_ok = placeholder_ok and pixels.get_region(rect).get_used_rect().end.y == 89
	check(placeholder_ok and hound.standing_height() == 48 and hound.corpse_extent() == 56,
		"solid-color placeholder uses identical metadata loader, frame bounds and baseline")
	hound._atlas = real_texture
	for sprite in [hound._sprite, hound._outline, hound._rim]: sprite.texture = real_texture
	hound._load_atlas_metadata(meta)
	hound._set_state("idle")
	hound._sync_sprite()


func _test_ai() -> void:
	_reset(430)
	hound.step(DT)
	check(hound.state == "idle", "outside 420px stays idle")
	game.player.position.x = hound.position.x + 350
	hound.step(DT)
	check(hound.state == "alert", "sight within 420px enters alert")
	var facing := hound.face
	game.player.position.x = hound.position.x - 350
	_ticks(13)
	check(hound.state == "alert" and hound.face == facing, "alert locks facing for 14 ticks")
	hound.step(DT)
	check(hound.state == "run", "alert ends on tick 14")
	var x := hound.position.x
	hound.step(DT)
	check(is_equal_approx(hound.position.x, x - 150 * DT), "run chases at exactly 150px/s")
	_reset()
	hound.step(DT)
	_ticks(14)
	check(hound.state == "windup" and not hound.attack_active(), "nearby target starts harmless windup")
	_ticks(23)
	check(hound.state == "windup" and hound._anim_frame(hound._anims.windup) == 3,
		"windup lasts 24 ticks and reaches its last crouch frame")
	game.player.position.x = hound.position.x + 108
	var locked: Vector2 = game.player.position
	hound.step(DT)
	check(hound.state == "pounce" and hound.pounce_target == locked,
		"target sampled at END of windup, including the final player position")
	game.player.position.x = hound.position.x - 200
	hound.vision_blocker = func(_a, _b): return true
	_ticks(6)
	check(hound.position.y < 319.9 and hound.face == 1 and hound.pounce_target == locked,
		"locked parabolic flight ignores subsequent player movement and smoke")
	for i in 22:
		if hound._pounce_landed: break
		hound.step(DT)
	check(hound.position.distance_to(locked) < 0.01, "unobstructed pounce lands at the locked reachable target")
	hound.step(DT)
	check(hound.state == "recover" and not hound.attack_active(), "landing enters harmless recover")
	_ticks(35)
	check(hound.state == "recover", "recover retains all 36 ticks")
	hound.step(DT)
	check(hound.state == "cooldown", "recover then explicit cooldown")
	_ticks(19)
	check(hound.state == "cooldown", "cooldown retains all 20 ticks")
	hound.step(DT)
	check(hound.state == "idle", "cooldown returns idle when vision is blocked")
	_reset(260)
	hound._begin_pounce()
	_ticks(22)
	check(hound._pounce_landed and is_equal_approx(hound.position.x, 336 + 198),
		"540px/s and 22-tick maximum cap travel at 198px")
	_reset(260)
	hound._set_state("windup")
	_ticks(24)
	var active_ticks := 0
	while hound.state == "pounce" and active_ticks < 30:
		active_ticks += 1
		hound.step(DT)
	check(active_ticks == 22, "full pounce has exactly 22 active ticks including launch")
	_reset(108)
	game.player.position.y -= 48
	locked = game.player.position
	hound._begin_pounce()
	game.player.position += Vector2(200, -80)
	_ticks(12)
	check(hound.position.distance_to(locked) < 0.01, "airborne feet target is locked in both axes")
	_ticks(37)
	check(is_equal_approx(hound.position.y, 319.9) and not hound.attack_active(),
		"airborne miss settles to supported floor during harmless recovery")


func _test_obstacles() -> void:
	_reset()
	var old_row: String = game.level.grid[9]
	game.level.grid[9] = old_row.substr(0, 13) + "#" + old_row.substr(14)
	hound.step(DT)
	check(hound.state == "idle", "wall blocks acquisition")
	hound._move_horizontal(200)
	check(hound.body_rect().end.x < 13 * 32, "running sweep stops at wall")
	_reset()
	hound._begin_pounce()
	_ticks(22)
	check(hound.body_rect().end.x < 13 * 32, "pounce stops at wall")
	game.level.grid[9] = old_row
	var door := RoomDoor.new()
	door.position = Vector2(440, 319.9)
	for blocker: Node2D in [door, game.glass_panels[0]]:
		_reset()
		if blocker is GlassPanel:
			blocker.position = Vector2(421, 192)
		hound.door_blockers = [blocker]
		hound.step(DT)
		check(hound.state == "idle", "locked door/intact 2px glass blocks sight")
		hound._begin_pounce()
		_ticks(22)
		check(hound.body_rect().end.x <= blocker.body_rect().position.x,
			"pounce sweep stops at locked door/intact glass")
		if blocker is GlassPanel: blocker.restore_broken(true)
		else: blocker.locked = false
		hound._set_state("idle")
		hound.step(DT)
		check(hound.state == "alert", "unlocked door/broken glass permits sight")
	door.free()
	game.glass_panels[0].position.x = 1200
	game.glass_panels[0].restore_broken(false)
	_reset()
	hound.vision_blocker = func(_a, _b): return true
	hound.step(DT)
	check(hound.state == "idle", "smoke callback blocks new acquisition")
	_reset()
	game.smoke_tactics.deploy_cloud(hound.position)
	game.smoke_tactics.step(0.2)
	hound.step(DT)
	game._refresh_smoke_cover()
	check(hound.state == "idle" and game.smoke_tactics.contains_actor(hound)
		and not hound._rim.visible, "real smoke cloud blocks acquisition and applies hound silhouette")
	hound._begin_pounce()
	_ticks(3)
	var hp: int = game.player.hp
	_contact()
	check(game.player.hp == hp - 1, "real smoke does not cancel an airborne pounce or its melee damage")
	game.smoke_tactics.clear_effects()
	game._refresh_smoke_cover()
	check(hound._rim.visible, "hound rim restores after smoke clears")
	var floor_row: String = game.level.grid[10]
	game.level.grid[10] = "#".repeat(13) + ".".repeat(35)
	_reset()
	hound._move_horizontal(300)
	check(hound.body_rect().end.x < 416, "run stops before platform edge")
	_reset()
	hound._begin_pounce()
	_ticks(22)
	check(hound.body_rect().end.x < 416 and is_equal_approx(hound.position.y, 319.9),
		"pounce cannot leave its supported platform")
	game.level.grid[10] = floor_row


func _contact() -> void:
	game.player.position = hound.position + Vector2(hound.face * 28, 0)
	game.player.invuln_t = 0 # No reliance on hurt i-frames to enforce one hit.
	hound.try_attack(game.player, game.player.hurtbox_rect())


func _test_damage() -> void:
	_reset(108)
	var hp: int = game.player.hp
	for state in ["idle", "alert", "run", "windup", "recover", "cooldown"]:
		hound._set_state(state)
		_contact()
		check(game.player.hp == hp, state + " contact deals no damage")
	hound._begin_pounce()
	check(hound.attack_rect().size == Vector2(60, 40), "pounce attack box is 60x40")
	game.player.roll_invuln_t = 1.0
	_contact()
	check(game.player.hp == hp and not hound._attack_spent, "rolling i-frames avoid damage without consuming a hit")
	game.player.roll_invuln_t = 0
	_contact()
	check(game.player.hp == hp - 1 and not hound.attack_active(), "pounce applies one successful damage")
	for i in 22:
		hound.step(DT)
		_contact()
	check(game.player.hp == hp - 1, "same pounce never repeats damage even with i-frames cleared")
	_reset(108)
	hound._begin_pounce()
	game.player.position = hound.position + Vector2(45, 0)
	hp = game.player.hp
	game._physics_process(DT)
	check(game.player.hp == hp - 1 and hound._attack_spent, "production game damage dispatch consumes hound hit")


func _test_freeze() -> void:
	_reset()
	CorridorLevel.active_campaign_mode = true
	game._campaign_boundaries.append(-1)
	game._campaign_frontier = -1
	var asleep_at := hound.position
	var asleep_clock := hound._anim_clock
	game._physics_process(DT)
	check(hound.position == asleep_at and hound.frame == 0 and hound._anim_clock > asleep_clock,
		"unreleased campaign hound only advances idle presentation")
	CorridorLevel.active_campaign_mode = false
	game._campaign_boundaries.clear()
	_reset()
	hound._begin_pounce()
	hound.step(DT)
	game.timeline_enabled = true
	game.player.keys[MOUSE_BUTTON_RIGHT] = true
	var at := hound.position
	var frame := hound.frame
	var clock := hound._anim_clock
	game._physics_process(DT)
	check(game.time_charge.active and hound.position == at and hound.frame == frame
		and hound._anim_clock == clock, "time-stop freezes movement, attack clock and animation")
	game.player.keys.clear()
	game._physics_process(DT)
	check(not game.time_charge.active and hound.position != at, "time-stop release resumes hound")
	at = hound.position
	frame = hound.frame
	game.pause_controller.pause_game()
	game._physics_process(DT)
	hound.step(DT)
	check(paused and hound.position == at and hound.frame == frame, "main pause freezes hound including direct step")
	game.pause_controller.resume_game()


func _test_timeline() -> void:
	_reset()
	hound._begin_pounce()
	hound.step(DT)
	hound._attack_spent = true
	var timeline := TIMELINE.new()
	var saved := hound.capture_combat_state()
	var at := hound.position
	var frame := hound.frame
	timeline.record(game, DT, true)
	hound.step(DT)
	hound.take_hit(0)
	hound.pounce_target = Vector2.ZERO
	hound._attack_spent = false
	timeline.apply_rewind(game, 0)
	check(hound.state == "pounce" and not hound.dead and hound.frame == frame
		and hound.position == at.round() and hound.capture_combat_state() == saved,
		"timeline round-trip restores pounce target, velocity, progress, consumed hit and pose")


func _test_projectile_kill() -> void:
	_reset()
	hound._begin_pounce()
	hound.step(DT)
	game.player.dash_cooldown_t = 2
	var at := hound.body_rect().get_center()
	game.bullets.append({"x": at.x, "y": at.y, "vx": 0.0, "vy": 0.0, "life": 1.0})
	game._physics_process(DT)
	check(hound.dead and game._corpse_impacts.size() == 1 and game.player.dash_cooldown_t == 0,
		"legacy player projectile also kills airborne hound, retains inertia and refreshes dash")


func _test_death_and_checkpoint() -> void:
	_reset()
	check(hound.take_hit(0) and hound.dead and hound.state == "dead", "one hit kills a grounded hound")
	check(not hound.take_hit(0), "death cannot settle twice")
	_reset()
	hound._begin_pounce()
	hound.step(DT)
	var momentum := hound.velocity
	var at := hound.position
	game.player.face = 1
	game.player.dash_cooldown_t = 2
	game._on_player_bat_swung(hound.body_rect(), 0)
	check(hound.dead and hound.state == "dead" and at.y < 319.9, "production bat kills midair in one hit")
	check(game.player.dash_cooldown_t == 0 and game.room_alive_count(0) == 1,
		"hound kill refreshes dash and updates room clear count")
	check(game._corpse_impacts.size() == 1, "kill registers existing corpse solver")
	if not game._corpse_impacts.is_empty():
		var motion = game._corpse_impacts[0].motion
		check(motion.velocity == Vector2(520, -300) + momentum, "corpse retains full airborne velocity plus hit impulse")
	game._update_enemy_knockbacks(DT)
	check(hound.position != at and hound.corpse_ground_projected, "corpse moves with projected ground shadow")
	hound.set_corpse_lift(12)
	check(hound.wound_anchor_world() == hound.body_rect().get_center() - Vector2(0, 12),
		"blood wound anchor follows corpse lift")
	hound.set_corpse_ground(320, true)
	check(hound.corpse_lift == 0 and hound.wound_anchor_world() == hound.body_rect().get_center(),
		"physical corpse projection avoids double lifting blood/body")
	_ticks(60)
	check(hound._anim_frame(hound._anims.death) == 5 and not hound._rim.visible
		and hound.corpse_used_rect().has_area() and hound.corpse_extent() <= 96,
		"death holds final frame with bounded corpse and no living rim")
	var config: Dictionary = CorridorLevel.active_checkpoints[0]
	var snapshot: Dictionary = CHECKPOINT.capture(game, config, Vector2(112, 319.9))
	check(snapshot.defeated.has(Vector2i(10, 9)), "checkpoint captures hound spawn identity")
	game.free()
	_boot()
	check(CHECKPOINT.restore(game, snapshot), "checkpoint restores into rebuilt game")
	check(hound.dead and not hound.visible and hound.get_meta("checkpoint_cleared", false)
		and not game.minions[1].dead and game.room_alive_count(0) == 1,
		"restore clears defeated hound but preserves future hound")
	var frame := hound.frame
	game._physics_process(DT)
	check(hound.frame == frame and not hound.attack_active(), "checkpoint-cleared hound never steps or damages")
