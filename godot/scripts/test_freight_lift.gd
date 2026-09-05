extends SceneTree
## 真实player.step承载回归：帧率、跳离、相对落点、时停、净空、边缘以及幂等承载。
const LIFT := preload("res://scripts/freight_lift.gd")
const CONFIG := {"type": "freight_lift", "pos": [320.0, 384.0], "top_y": 192.0, "width": 96.0,
	"height": 12.0, "travel_time": 2.8, "dwell": 1.2, "room_id": "lift_test"}
var passed := 0
var failed := 0
var level: CorridorLevel
var player: KairullPlayer
var lift: Node2D
var atlas: AtlasDB

class TestDoor extends Node2D:
	var locked := true
	func body_rect() -> Rect2:
		return Rect2(300, 210, 40, 50)


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _arena(ceiling := false) -> void:
	var rows := PackedStringArray()
	for y in 24:
		var row := "#".repeat(40) if y == 20 else ".".repeat(40)
		if ceiling and y == 6:
			row = ".".repeat(8) + "#".repeat(4) + ".".repeat(28)
		rows.append(row)
	level.grid = rows
	level.map_w = 40
	level.map_h = 24
	level.world_w = 1280
	level.world_h = 768
	level.stairs = []


func _reset(ceiling := false) -> void:
	_arena(ceiling)
	lift.setup(CONFIG, level)
	player.reset_to_spawn()
	player.spawn = Vector2(320, 383.9)
	player.position = player.spawn
	player.on_ground = true
	player.vx = 0.0
	player.vy = 0.0
	player.keys.clear()
	player._prev_keys.clear()
	player.moving_platforms = [lift]
	player._sync_sprite()


func _tick(dt: float, explicit_carry := true, world_dt := -1.0) -> void:
	lift.advance(dt if world_dt < 0.0 else world_dt)
	if explicit_carry:
		lift.carry_rider(player)
	player.step(dt)


func _run() -> void:
	atlas = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json", "res://assets/clips/hero/hero_atlas.json"])
	level = CorridorLevel.new()
	lift = LIFT.new()
	player = KairullPlayer.new()
	player.db = atlas
	player.level = level
	player.spawn = Vector2(320, 383.9)
	player.auto_input = false
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	_test_schema_and_phase()
	for fps in [30, 60, 120]:
		_test_riding_fps(fps)
	_test_idempotence()
	_test_jump_and_land()
	_test_edge_and_below()
	_test_pause()
	_test_clearance()
	_test_earliest_surface()
	for distance in [576.0, 640.0]:
		for fps in [30, 60]:
			_test_long_transport(distance, fps)
	player.moving_platforms.clear()
	player.free()
	lift.free()
	level.free()
	atlas = null
	await process_frame
	print("=== %d 通过, %d 失败 ===" % [passed, failed])
	print("TEST_RESULT: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)


func _test_schema_and_phase() -> void:
	_reset()
	check(lift.top_rect() == Rect2(272, 384, 96, 2), "货梯top_rect为96px宽单向台面")
	check(lift.body_rect() == Rect2(272, 384, 96, 12), "承重平台实体厚12px")
	check(lift.room_id == "lift_test" and lift.locked, "房间和动态阻挡语义可用")
	check(lift.state == "bottom_wait", "初始下端等待")
	lift.advance(1.3)
	check(lift.state == "up" and lift.position.y < 384.0 and lift.delta_y < 0.0, "停靠1.2秒后缓启动上行")
	lift.advance(2.8)
	check(lift.state == "top_wait" and is_equal_approx(lift.position.y, 192), "到上层等待")
	lift.advance(1.2)
	check(lift.state == "down" and lift.delta_y > 0.0, "上端停靠后下行")
	lift.advance(2.8)
	check(lift.state == "bottom_wait" and is_equal_approx(lift.position.y, 384), "完成整轮回到下端")
	check(not lift.has_method("_process") and not lift.has_method("_physics_process"), "无自主_process或Timer")


func _test_riding_fps(fps: int) -> void:
	_reset()
	var max_error := 0.0
	var always_grounded := true
	var phases: Dictionary = {}
	for _index in int(8.0 * fps):
		_tick(1.0 / fps)
		phases[lift.state] = true
		max_error = maxf(max_error, absf(player.position.y - (lift.position.y - 0.1)))
		always_grounded = always_grounded and player.on_ground
	check(max_error < 0.15, "%dHz上下往返主角脚底持续贴台面" % fps)
	check(always_grounded, "%dHz升降中不错误进入下落" % fps)
	check(phases.has("up") and phases.has("top_wait") and phases.has("down"), "%dHz上下两层与停靠均经过" % fps)
	check(is_equal_approx(player.position.y, 383.9), "%dHz整周期末精确回到下层" % fps)
	check(player.w == 22.0 and player.h == 52.0, "%dHz保持原通行碰撞盒" % fps)


func _test_idempotence() -> void:
	_reset()
	for _index in 120:
		_tick(1.0 / 60.0, false)
	check(absf(player.position.y - lift.position.y + 0.1) < 0.1, "仅player.step兜底也能承载")
	lift.advance(1.0 / 60.0)
	check(lift.carry_rider(player), "本步第一次显式承载成功")
	var carried_y := player.position.y
	check(not lift.carry_rider(player), "同次advance第二次承载被幂等拦截")
	player.step(1.0 / 60.0)
	check(absf(player.position.y - carried_y) < 0.1, "显式carry加step不会搬运两次")


func _test_jump_and_land() -> void:
	_reset()
	for _index in 120:
		_tick(1.0 / 60.0)
	player.keys[KEY_W] = true
	_tick(1.0 / 60.0)
	check(not player.on_ground and player.vy < 0.0, "运行中按跳跃能脱离电梯")
	var distance_after_jump := lift.position.y - player.position.y
	for _index in 5:
		_tick(1.0 / 60.0)
	check(lift.position.y - player.position.y > distance_after_jump + 20.0, "起跳后不被承载重新吸回")
	player.keys.clear()
	player._prev_keys.clear()
	player.position = Vector2(lift.position.x, lift.position.y - 60.0)
	player.vy = 2.0
	player.on_ground = false
	for _index in 90:
		_tick(1.0 / 60.0, true, 0.0)
	check(player.on_ground and absf(player.position.y - lift.position.y + 0.1) < 0.1, "落回停驻电梯会被台面接住")
	for _index in 30:
		_tick(1.0 / 60.0)
	check(player.on_ground and absf(player.position.y - lift.position.y + 0.1) < 0.1, "落回后重新正常随动")


func _test_edge_and_below() -> void:
	_reset()
	player.keys[KEY_D] = true
	for _index in 14:
		_tick(1.0 / 60.0)
	check(player.position.x > lift.top_rect().end.x + 10, "能够横向走出承重台边缘")
	check(not player.on_ground and player.position.y > lift.position.y + 3, "走出边缘开始下落而非悬空")
	_reset()
	player.position.y = 420.0
	player.on_ground = false
	player.vy = -9.0
	for _index in 8:
		_tick(1.0 / 60.0, true, 0.0)
	check(player.position.y < lift.position.y and player.vy < 0.0, "从下方起跳可单向穿过电梯台面")
	check(not player.on_ground, "上升跳穿不能被当成下落着陆")


func _test_pause() -> void:
	_reset()
	for _index in 132:
		_tick(1.0 / 60.0)
	var old_y := lift.position.y
	var old_phase: float = lift.phase_time
	player.set_time_focus(true)
	for _index in 90:
		_tick(1.0 / 60.0, true, 0.0)
	check(lift.position.y == old_y and lift.phase_time == old_phase and lift.delta_y == 0.0, "时停中电梯位置和相位完全冻结")
	check(player.on_ground and absf(player.position.y - old_y + 0.1) < 0.1, "时停慢速主角仍站稳冻结电梯")
	player.set_time_focus(false)
	_tick(1.0 / 60.0)
	check(lift.position.y < old_y and player.on_ground, "时停解除从原相位继续上行")


func _test_clearance() -> void:
	_reset(true)
	var saw_stall := false
	for _index in 360:
		_tick(1.0 / 60.0)
		saw_stall = saw_stall or lift.stalled
	check(saw_stall, "上升遇天花板停止本次平台运动")
	check(player.position.y - player.h >= 223.9, "头部不穿入192~224实心天花板")
	check(player.on_ground and absf(player.position.y - lift.position.y + 0.1) < 0.1, "净空受阻仍安全站在原平台")
	var stop_y := lift.position.y
	for _index in 30:
		_tick(1.0 / 60.0)
	check(lift.position.y == stop_y, "受阻时平台相位也回滚，不累积突然穿墙的进度")
	_reset()
	var door := TestDoor.new()
	lift.door_blockers = [door]
	for _index in 240:
		_tick(1.0 / 60.0)
	check(lift.stalled and player.position.y - player.h >= 259.9, "锁门同样阻止货梯把人顶入门板")
	door.locked = false
	for _index in 180:
		_tick(1.0 / 60.0)
	check(player.position.y < 280.0, "锁门解除后从原相位正常通行")
	lift.door_blockers.clear()
	door.free()


func _test_earliest_surface() -> void:
	_reset()
	# 台面较低时，脚底先经过静态格子顶沿不能被电梯吸到地板下。
	level.grid[10] = ".".repeat(8) + "#".repeat(4) + ".".repeat(28)
	player.position = Vector2(320, 310)
	player.vy = 5.0
	player.on_ground = false
	for _index in 4:
		_tick(1.0 / 60.0, true, 0.0)
	check(player.on_ground and absf(player.position.y - 319.9) < 0.1, "静态楼板先于下方电梯承接")
	_reset()
	level.stairs = [{"left_c": 8, "bottom_row": 12, "steps": 4, "rise_dir": 1}]
	var lower_config := CONFIG.duplicate(true)
	lower_config["pos"] = [320.0, 344.0]
	lift.setup(lower_config, level)
	player.position = Vector2(320, 330)
	player.vy = 40.0
	player.on_ground = false
	_tick(1.0 / 60.0, true, 0.0)
	check(player.on_ground and absf(player.position.y - 335.9) < 0.1, "同一步跨楼梯和电梯时取更早的336px踏面")
	_reset()
	player.position = Vector2(320, 420)
	player.vy = 4.0
	player.on_ground = false
	_tick(1.0 / 60.0, true, 0.0)
	check(player.position.y > 420.0 and not player.on_ground, "已经在平台下方不会被远距离向上吸附")
	check(not KairullPlayer.GUN_ENABLED and not KairullPlayer.SLIDE_ENABLED, "枪械和旧滑铲保持关闭")


func _long_reset(distance: float, ceiling := false) -> void:
	# 真实18/20格竖井，侧壁紧贴96px平台外缘；上站与右侧出口连廊同高无缝。
	var long_config := CONFIG.duplicate(true)
	long_config["pos"] = [336.0, 192.0 + distance]
	var bottom_row := int((192.0 + distance) / 32.0)
	var rows := PackedStringArray()
	for y in 40:
		var row := ".".repeat(40)
		if y == bottom_row:
			row = "#".repeat(40)
		elif y == 6:
			row = ".".repeat(12) + "#".repeat(18) + ".".repeat(10)
		elif y > 6 and y < bottom_row:
			row = ".".repeat(8) + "#...#" + ".".repeat(27)
		if ceiling and y == 12:
			row = ".".repeat(8) + "#".repeat(5) + ".".repeat(27)
		rows.append(row)
	level.grid = rows
	level.map_w = 40
	level.map_h = 40
	level.world_w = 1280
	level.world_h = 1280
	level.stairs = []
	lift.setup(long_config, level)
	player.reset_to_spawn()
	player.spawn = Vector2(336.0, 192.0 + distance - 0.1)
	player.position = player.spawn
	player.vx = 0.0
	player.vy = 0.0
	player.on_ground = true
	player.keys.clear()
	player._prev_keys.clear()
	player.moving_platforms = [lift]
	player._sync_sprite()


func _test_long_transport(distance: float, fps: int) -> void:
	var label := "%dpx/%dHz" % [int(distance), fps]
	var dt := 1.0 / float(fps)
	_long_reset(distance)
	var max_error := 0.0
	var max_displacement := 0.0
	var min_feet := player.position.y
	var grounded_all := true
	var clear_all := true
	var phases: Dictionary = {}
	for _index in int(8.0 * fps):
		_tick(dt)
		max_error = maxf(max_error, absf(player.position.y - lift.position.y + 0.1))
		max_displacement = maxf(max_displacement, absf(lift.delta_y))
		min_feet = minf(min_feet, player.position.y)
		grounded_all = grounded_all and player.on_ground
		clear_all = clear_all and player._body_clear_at(player.position.x, player.position.y)
		phases[lift.state] = true
	check(max_error < 0.15 and grounded_all, label + "整段长程上下运输持续贴台，无中途坠落")
	check(absf(min_feet - 191.9) < 0.15, label + "真实运抵18~20格上方站点")
	check(is_equal_approx(player.position.y, 192.0 + distance - 0.1), label + "整轮回到原下站而非累计漂移")
	check(clear_all and not lift.stalled, label + "96px长井两侧实墙全程保留角色净空")
	check(phases.has("up") and phases.has("top_wait") and phases.has("down"), label + "上行停站下行状态完整")
	check(max_displacement > 4.0 and max_displacement < 12.0, label + "长程单步位移超过短梯但仍安全连续承载")
	_long_reset(distance)
	for _index in int(2.6 * fps):
		_tick(dt)
	var paused_y := lift.position.y
	var paused_phase: float = lift.phase_time
	var paused_clock: float = lift._clock
	player.set_time_focus(true)
	for _index in fps:
		_tick(dt, true, 0.0)
	check(lift.position.y == paused_y and lift.phase_time == paused_phase and lift._clock == paused_clock,
		label + "长井半程时停一秒，位置/相位/运输进度均冻结")
	check(player.on_ground and absf(player.position.y - paused_y + 0.1) < 0.15,
		label + "长井时停慢速主角仍由冻结货梯承重")
	player.set_time_focus(false)
	_tick(dt)
	check(lift.position.y < paused_y and player.on_ground, label + "解除时停继续余下运输，不瞬移补进度")
	_long_reset(distance)
	for _index in int(4.1 * fps):
		_tick(dt)
	check(lift.state == "top_wait" and absf(player.position.y - 191.9) < 0.15,
		label + "2.8秒运输结束后可用1.2秒上端停靠窗")
	player.keys[KEY_D] = true
	for _index in int(0.4 * fps):
		_tick(dt)
	check(player.position.x > 440.0 and player.on_ground and absf(player.position.y - 191.9) < 0.15,
		label + "上端无需补跳，直接走入右侧出口连廊")
	player.keys.clear()
	_long_reset(distance, true)
	var saw_stall := false
	for _index in int(6.0 * fps):
		_tick(dt)
		saw_stall = saw_stall or lift.stalled
	check(saw_stall and player.position.y - player.h >= 415.9,
		label + "长井高速度遇中段横梁依然停止，不顶进实心砖")
	check(player.on_ground and absf(player.position.y - lift.position.y + 0.1) < 0.15,
		label + "净空停止后仍稳定站立，不把乘客遗留半空")
	var stalled_y := lift.position.y
	var stalled_clock: float = lift._clock
	for _index in fps:
		_tick(dt)
	check(lift.position.y == stalled_y and lift._clock == stalled_clock,
		label + "受阻后一秒不积攒隐藏进度或穿梁")
