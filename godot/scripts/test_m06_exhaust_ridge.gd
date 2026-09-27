extends SceneTree
## Actual scene integration; room probes are fixtures, not a traversal claim.
const DATA := preload("res://generated/m06_exhaust_ridge_data.gd")
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
	SESSION.begin_run("easy")
	var boot: Node2D = load("res://scenes/m06_exhaust_ridge.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	var game: Node2D = boot.get_node("Game")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.auto_input = false
	game.action_audio_enabled = false
	game._sfx.clear()
	game.action_audio.stop_all()
	check(game.level.map_w == 330 and game.level.map_h == 37, "map is 330 x 37")
	check(game.level.rooms.size() == 11 and game.minions.size() == 26, "11 rooms and 26 actual enemies")
	# Compiled ENTITIES names encode LDtk IntGrid values 3 and 4.
	var expected := {"MeleeInspector": 0, "Gunner": 0}
	for entity: Dictionary in DATA.ENTITIES:
		if expected.has(entity.kind):
			expected[entity.kind] += 1
	var melee := 0
	var gunners := 0
	for enemy: Node2D in game.minions:
		melee += int(enemy is FreightInspector)
		gunners += int(enemy is GruntGunner)
	check(melee == expected.MeleeInspector and gunners == expected.Gunner and melee + gunners == 26,
		"FreightInspector/GruntGunner counts match ENTITIES kinds 3/4")
	check(game.updraft_fans.size() == 8 and game.glass_panels.size() == 4 and game.dash_nodes.size() == 6,
		"8 fans, 4 glass panels, 6 dash nodes")
	var hazards := {"auto_sniper": 0, "laser_gate": 0, "press": 0}
	for hazard: Node2D in game.tactical_hazards:
		hazards[hazard.hazard_type] += 1
	check(hazards == {"auto_sniper": 1, "laser_gate": 2, "press": 3}
		and game.smoke_tactics.pickups.size() == 3, "1 sniper, 2 lasers, 3 presses, 3 smoke pickups")
	check(CorridorLevel.active_kill_refresh_dash, "M06 enables kill-refresh")
	check(CorridorLevel.active_checkpoints == DATA.CHECKPOINTS
		and game._checkpoint_configs.size() == DATA.CHECKPOINTS.size(), "checkpoint configuration comes from DATA")
	for config: Dictionary in DATA.CHECKPOINTS:
		var index := int(config.room_index)
		check(game._checkpoint_configs[index] == config and game._checkpoint_beacons[index].position
			== Vector2(config.cell[0] * 32 + 16, (config.cell[1] + 1) * 32 - .1), "checkpoint runtime beacon matches DATA")
	check(game._checkpoint_index == -1, "checkpoint is inactive at entry")
	check(CorridorLevel.active_encounter_policy == "linear_flow"
		and game._campaign_boundaries == DATA.ENCOUNTER_BOUNDARIES, "linear boundaries match DATA [4, 6]")
	# Enter and retreat through actual room-state tracking: frontier remains monotonic.
	for probe in [[4, 150, 35, 4], [5, 162, 35, 6], [6, 213, 35, 6], [7, 220, 20, 10], [4, 150, 35, 10]]:
		game.player.position = Vector2(probe[1] * 32 + 16, probe[2] * 32 - .1)
		game._update_room_state()
		check(game.current_room == probe[0], "frontier probe enters room %d" % probe[0])
		var matches := true
		for enemy: Node2D in game.minions:
			var cell: Vector2i = enemy.get_meta("spawn_cell")
			var room: int = game.level.room_at(cell.x * 32 + 16, cell.y * 32 + 16)
			matches = matches and game._campaign_enemy_released(enemy) == (room <= probe[3])
		check(matches, "boundary wake/retreat semantics at room %d" % probe[0])
	check(DATA.MAP_TEXT.strip_edges().split("\n")[34][311] == "D"
		and game.level.door_spawns.size() == 1 and game.doors.size() == 1, "one D at c311/r34 creates one RoomDoor")
	if game.doors.size() == 1:
		var door: RoomDoor = game.doors[0]
		check(door.room_idx == 9 and game.level.rooms[9].room_id == "pump_arena", "door belongs to room 9 pump_arena")
		var defenders: Array[Node2D] = []
		for enemy: Node2D in game.minions:
			var cell: Vector2i = enemy.get_meta("spawn_cell")
			if game.level.room_at(cell.x * 32 + 16, cell.y * 32 + 16) == 9:
				defenders.append(enemy)
		check(defenders.size() == 6, "six pump arena defenders")
		door._physics_process(0.0)
		check(door.locked and game.room_alive_count(9) == 6, "door locks with live arena defenders")
		for index in defenders.size():
			defenders[index].take_hit(defenders[index].position.x - 80.0, 999)
			door._physics_process(0.0)
			check(door.locked == (index + 1 < defenders.size()), "door stays locked until final defender dies (%d)" % index)
		check(not door.locked and game.room_alive_count(9) == 0, "arena clear unlocks door")
	check(not CorridorLevel.active_exit_requires_boss and not game._exit_gated()
		and game.room_alive_count(1) > 0, "earlier surviving enemies do not gate extraction globally")
	check(game.has_node("ExhaustRidgeArt") and game.get_node("ExhaustRidgeArt").get_index() < game.level.get_index(),
		"Claude art layer is set up before terrain")
	await create_timer(.2).timeout
	boot.free()
	current_scene = null
	check(not CorridorLevel.active_kill_refresh_dash and CorridorLevel.active_map.is_empty()
		and CorridorLevel.active_rooms.is_empty() and CorridorLevel.active_checkpoints.is_empty()
		and CorridorLevel.active_stairs.is_empty() and CorridorLevel.active_art_style.is_empty()
		and CorridorLevel.active_semantic_layers.is_empty() and CorridorLevel.active_semantic_ids.is_empty()
		and CorridorLevel.active_tactical_objects.is_empty() and CorridorLevel.active_encounter_boundaries.is_empty()
		and CorridorLevel.active_encounter_policy.is_empty() and CorridorLevel.active_hide_rows_from == -1
		and CorridorLevel.active_minion == "ghost" and CorridorLevel.active_boss == "red"
		and CorridorLevel.active_title.is_empty() and CorridorLevel.active_tile_style.is_empty()
		and CorridorLevel.active_tileset_path.is_empty() and CorridorLevel.active_bgm.is_empty()
		and CorridorLevel.active_bgm_db == -14.0 and not CorridorLevel.active_exit_requires_boss
		and CorridorLevel.active_next_scene.is_empty() and not CorridorLevel.active_campaign_mode
		and CorridorLevel.active_restart_scene.is_empty() and GameBackground.active_cfg.is_empty(), "exit restores every static configured by boot")
	SESSION.reset_for_tests()
	await create_timer(.2).timeout
	print("M06_BOOT_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
