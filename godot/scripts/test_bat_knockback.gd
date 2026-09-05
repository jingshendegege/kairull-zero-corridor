extends SceneTree
## 球棒击退无头验收：正式命中链、真实死亡惯性、连段力度、挡墙与飞出平台后自然下落。
## 跑法：godot --headless --path godot --script scripts/test_bat_knockback.gd

const DT := 1.0 / 60.0
const MAP_W := 48
const MAP_H := 8
const FEET_Y := 7.0 * CorridorLevel.TS - 0.1
const BOOT_MAP := """
################################################
#..............................................#
#..............................................#
#..............................................#
#..............................................#
#..............................................#
#..@....m......................................#
################################################
"""

var _pass := 0
var _fail := 0


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func between(value: float, minimum: float, maximum: float) -> bool:
	return value >= minimum and value <= maximum


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_configure_statics()
	var packed := load("res://scenes/game.tscn") as PackedScene
	ok(packed != null, "正式 game.tscn 可加载")
	if packed == null:
		_reset_statics()
		_finish()
		return

	var game = packed.instantiate()
	get_root().add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.player.auto_input = false
	game._sfx.clear()
	game.action_audio_enabled = false

	ok(game.minions.size() == 1 and game.minions[0] is FreightInspector,
			"测试图只生成一个真实货运巡检员", str(game.minions.size()))
	if game.minions.size() != 1 or not (game.minions[0] is FreightInspector):
		await _free_game(game)
		_reset_statics()
		_finish()
		return

	var enemy = game.minions[0]
	_set_logic_arena(game.level)
	ok(game.debug_enemy_knockback_count() == 0, "新场景没有残留击退任务")

	print("== 正式球棒链：死亡后持续位移与方向 ==")
	_prepare_enemy(enemy, Vector2(600.0, FEET_Y))
	game.player.position = Vector2(530.0, FEET_Y)
	game.player.face = 1
	var right_start: float = enemy.position.x
	game._on_player_bat_swung(enemy.body_rect().grow(1.0), 0)
	ok(enemy.dead and game.debug_enemy_knockback_count() == 1,
			"球棒命中一击死亡后仍登记一个击退任务",
			"dead=%s count=%d" % [enemy.dead, game.debug_enemy_knockback_count()])
	game._update_enemy_knockbacks(DT)
	ok(enemy.dead and enemy.position.x > right_start + 1.0,
			"死亡敌人不受 dead 早退影响，首个击退 tick 向右移动",
			"%.2f -> %.2f" % [right_start, enemy.position.x])
	ok(enemy.position.y < FEET_Y - 3.0 and enemy.corpse_lift == 0.0,
			"首帧真实脚底离地形成小抛物线，不是只抬高精灵")
	_drain_knockback(game)
	var stage0_distance: float = enemy.position.x - right_start
	ok(between(stage0_distance, 206.0, 216.0),
			"第一段致命惯性约 211px", "distance=%.3f" % stage0_distance)
	ok(absf(enemy.position.y - FEET_Y) < 0.3 and enemy.corpse_ground_valid,
			"抛物线、轻弹和滑移收尾后脚底回到真实地面")
	var stopped_x: float = enemy.position.x
	for _i in 20:
		game._update_enemy_knockbacks(DT)
	ok(game.debug_enemy_knockback_count() == 0
			and absf(enemy.position.x - stopped_x) <= 0.01,
			"击退结束后任务清零且尸体不再漂移",
			"count=%d drift=%.4f" % [game.debug_enemy_knockback_count(),
					absf(enemy.position.x - stopped_x)])
	# 最后一名敌人倒下即可触发 CLEAR；活体 AI 冻结时，尸体动画仍须播完。
	enemy.hitstop = 0.0
	enemy.frame = 0
	game.level_cleared = true
	game._physics_process(DT)
	ok(enemy.frame == 1, "CLEAR 后仍推进死亡敌人的倒地收尾", "frame=%d" % enemy.frame)
	game.level_cleared = false

	game.fx_layer.clear_explosions()
	_prepare_enemy(enemy, Vector2(820.0, FEET_Y))
	game.player.position = Vector2(890.0, FEET_Y)
	game.player.face = -1
	var left_start: float = enemy.position.x
	game._on_player_bat_swung(enemy.body_rect().grow(1.0), 0)
	_drain_knockback(game)
	var left_distance: float = left_start - enemy.position.x
	ok(enemy.dead and left_distance > 0.0,
			"玩家朝左挥棍时尸体沿受力方向向左移动",
			"distance=%.3f" % left_distance)
	ok(absf(left_distance - stage0_distance) <= 0.5,
			"左右击退距离对称", "right=%.3f left=%.3f" % [stage0_distance, left_distance])

	print("== 三连段力度 ==")
	game.fx_layer.clear_explosions()
	_prepare_enemy(enemy, Vector2(600.0, FEET_Y))
	game.player.position = Vector2(530.0, FEET_Y)
	game.player.face = 1
	var stage2_start: float = enemy.position.x
	game._on_player_bat_swung(enemy.body_rect().grow(1.0), 2)
	_drain_knockback(game)
	var stage2_distance: float = enemy.position.x - stage2_start
	ok(between(stage2_distance, 263.0, 273.0),
			"第三段致命惯性约 268px", "distance=%.3f" % stage2_distance)
	ok(stage2_distance > stage0_distance + 48.0,
			"第三段明显强于第一段",
			"stage0=%.3f stage2=%.3f" % [stage0_distance, stage2_distance])

	print("== 墙体阻挡与越出平台自然下落 ==")
	game.fx_layer.clear_explosions()
	_set_logic_arena(game.level, 20)
	_prepare_enemy(enemy, Vector2(570.0, FEET_Y), true)
	var wall_start: float = enemy.position.x
	game._start_enemy_knockback(enemy, Vector2.RIGHT, 2, true)
	_drain_knockback(game)
	var wall_left: float = 20.0 * CorridorLevel.TS
	var corpse_right: float = enemy.body_rect().end.x + 26.0
	ok(enemy.position.x > wall_start + 1.0 and corpse_right <= wall_left + 0.5,
			"尸体可滑向墙面但含倒地留边后不穿墙",
			"moved=%.3f corpse_right=%.3f wall=%.3f" % [
				enemy.position.x - wall_start, corpse_right, wall_left])
	stopped_x = enemy.position.x
	for _i in 10:
		game._update_enemy_knockbacks(DT)
	ok(absf(enemy.position.x - stopped_x) <= 0.01,
			"撞墙会吞掉剩余冲量，不在后续 tick 穿入")

	# 地面只保留到第20列，惯性可以带尸体飞出；无支撑后自然掉落，禁止旧防坠钳制。
	_set_logic_arena(game.level, -1, 20, true)
	_prepare_enemy(enemy, Vector2(580.0, FEET_Y), true)
	var cliff_start: float = enemy.position.x
	game._start_enemy_knockback(enemy, Vector2.RIGHT, 2, true)
	var platform_end: float = 21.0 * CorridorLevel.TS
	var dust_before: int = game.fx_layer.corpse_dust_stats().total
	for _i in 36:
		game._update_enemy_knockbacks(DT)
	ok(enemy.position.x > cliff_start + 180.0 \
			and enemy.body_rect().position.x - 26.0 > platform_end,
			"真实惯性把整个尸体带出平台，不在悬崖前急刹", str(enemy.position))
	ok(enemy.position.y > FEET_Y + 100.0 and not enemy.corpse_ground_valid,
			"脚下无承接面则受重力下落，不在平台高度悬空滑行", str(enemy.position))
	ok(game.fx_layer.corpse_dust_stats().total == dust_before,
			"平台外未接地，不伪造落地尘")
	_drain_knockback(game, 240)
	stopped_x = enemy.position.x
	for _i in 10:
		game._update_enemy_knockbacks(DT)
	ok(game.debug_enemy_knockback_count() == 0
			and absf(enemy.position.x - stopped_x) <= 0.01,
			"无底深渊最多3秒回收任务，后续不遗留无限更新")

	await _free_game(game)
	_reset_statics()
	_finish()


func _prepare_enemy(enemy, world_position: Vector2, keep_dead := false) -> void:
	enemy.dead = keep_dead
	enemy.hitstop = 0.0
	enemy.cooldown = 0
	enemy.position = world_position
	enemy._set_state("dead" if keep_dead else "idle")
	enemy._sync_sprite()


func _drain_knockback(game, max_ticks := 180) -> void:
	var ticks := 0
	while game.debug_enemy_knockback_count() > 0 and ticks < max_ticks:
		game._update_enemy_knockbacks(DT)
		ticks += 1
	ok(ticks < max_ticks, "击退任务在有限时间内结束", "ticks=%d" % ticks)


## 只替换无头碰撞网格；真实 game.tscn 及其生产命中链保持原样。
func _set_logic_arena(level: CorridorLevel, wall_col := -1,
		floor_end_col := -1, platform_floor := false) -> void:
	var rows := PackedStringArray()
	for y in MAP_H:
		var row := ".".repeat(MAP_W)
		row = _replace_cell(row, 0, "#")
		row = _replace_cell(row, MAP_W - 1, "#")
		if wall_col >= 0 and y >= 1 and y < MAP_H - 1:
			row = _replace_cell(row, wall_col, "#")
		if y == MAP_H - 1:
			if floor_end_col < 0:
				row = "#".repeat(MAP_W)
			else:
				var floor_tile := "=" if platform_floor else "#"
				for x in range(1, floor_end_col + 1):
					row = _replace_cell(row, x, floor_tile)
		rows.append(row)
	level.grid = rows
	level.map_w = MAP_W
	level.map_h = MAP_H
	level.world_w = MAP_W * CorridorLevel.TS
	level.world_h = MAP_H * CorridorLevel.TS
	level.stairs.clear()


func _replace_cell(row: String, column: int, value: String) -> String:
	return row.substr(0, column) + value + row.substr(column + 1)


func _configure_statics() -> void:
	CorridorLevel.active_map = BOOT_MAP
	CorridorLevel.active_stairs = []
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "melee"
	CorridorLevel.active_boss = "none"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_title = "击退测试"
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_exit_requires_boss = false
	GameBackground.active_cfg = []


func _reset_statics() -> void:
	CorridorLevel.active_map = ""
	CorridorLevel.active_stairs = []
	CorridorLevel.active_rooms = []
	CorridorLevel.active_hide_rows_from = -1
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	CorridorLevel.active_tile_style = {}
	CorridorLevel.active_tileset_path = ""
	CorridorLevel.active_title = ""
	CorridorLevel.active_bgm = ""
	CorridorLevel.active_bgm_db = -14.0
	CorridorLevel.active_next_scene = ""
	CorridorLevel.active_exit_requires_boss = false
	GameBackground.active_cfg = []


func _free_game(game) -> void:
	game.fx_layer.clear_explosions()
	for audio in game._sfx_pool:
		audio.stop()
		audio.stream = null
	game._sfx.clear()
	game.queue_free()
	await process_frame


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
