extends SceneTree
## 独立机关回归：完整预警、锁向、墙门/烟遮蔽、翻滚高度、时停和器械可击毁。
const HAZARD := preload("res://scripts/tactical_hazard.gd")
const DT := 1.0 / 60.0
var passed := 0
var failed := 0
var shots: Array = []
var sounds: Array = []
var broken: Array = []

class TestLevel extends Node:
	var walls: Array[Rect2] = []
	func solid_at(x: float, y: float) -> bool:
		for wall in walls:
			if wall.has_point(Vector2(x, y)):
				return true
		return false

class TestDoor extends Node2D:
	var locked := true
	func body_rect() -> Rect2:
		return Rect2(position, Vector2(20.0, 120.0))

class TestPlayer extends Node2D:
	var dead := false


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _new_hazard(level: Node, config: Dictionary = {}, doors: Array = []) -> Node2D:
	var defaults := {"type": "auto_sniper", "pos": [500.0, 300.0], "direction": [-1, 0], "room_id": "test"}
	defaults.merge(config, true)
	var hazard := HAZARD.new()
	hazard.setup(defaults, level, doors)
	hazard.projectile_requested.connect(func(origin: Vector2, velocity: Vector2, kind: StringName) -> void:
		shots.append({"origin": origin, "velocity": velocity, "kind": kind}))
	hazard.sound_requested.connect(func(event: StringName) -> void: sounds.append(event))
	hazard.destroyed.connect(func(point: Vector2) -> void: broken.append(point))
	hazard.set_armed(true)
	return hazard


func _until(hazard: Node2D, player: Node2D, next: String, smoke := false) -> void:
	for _index in 1000:
		if hazard.state == next:
			return
		hazard.advance(DT, player, smoke)


func _run() -> void:
	var level := TestLevel.new()
	var player := TestPlayer.new()
	player.position = Vector2(180, 300)
	_test_sniper(level, player)
	_test_obstacles(level, player)
	_test_smoke(level, player)
	_test_destruction(level, player)
	_test_laser(level, player)
	_test_press(level, player)
	_test_time_and_defaults(level, player)
	_test_cleared_shutdown(level, player)
	_test_final_second_signal(level, player)
	player.free()
	level.free()
	await process_frame
	print("=== %d 通过, %d 失败 ===" % [passed, failed])
	print("TEST_RESULT: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)


func _test_sniper(level: TestLevel, player: TestPlayer) -> void:
	shots.clear()
	var hazard := _new_hazard(level)
	check(hazard.state == "idle", "创建后保持待机而非瞬发")
	check(hazard.warning_duration == 1.5, "狙击完整跟踪1.5秒")
	check(hazard.recovery_duration == 1.5, "开火后固定冷却1.5秒")
	hazard.advance(DT, player)
	check(hazard.state == "warning" and shots.is_empty(), "首次进入只警示")
	for _i in 40:
		hazard.advance(DT, player)
	check(hazard.state == "warning" and shots.is_empty(), "0.66秒仍不能开火")
	_until(hazard, player, "locked")
	check(shots.is_empty(), "进入锁向阶段仍未发射")
	var old_aim: Vector2 = hazard.aim_direction
	var old_target: Vector2 = hazard.last_target
	player.position = Vector2(220, 340)
	hazard.advance(0.20, player)
	check(hazard.aim_direction == old_aim and hazard.last_target == old_target, "锁定0.5秒不能追着玩家改方向或目标点")
	check(shots.is_empty(), "锁向0.20秒不能提前开火")
	hazard.advance(0.29, player)
	check(shots.is_empty() and hazard.state == "locked", "锁向0.49秒仍不提前开火")
	hazard.advance(0.02, player)
	check(shots.size() == 1 and hazard.state == "recovery", "锁定半秒后仅发一弹并立即进入冷却")
	check(shots[0]["kind"] == &"gunshot", "狙击弹明确标为枪击")
	check(is_equal_approx(shots[0]["velocity"].length(), 2700.0), "高速狙击2700px每秒")
	check(shots[0]["velocity"].normalized().is_equal_approx(old_aim), "弹道与最终预警线一致")
	for _i in 20:
		hazard.advance(DT, player)
	check(shots.size() == 1 and hazard.state == "recovery", "开火帧不重复发弹")
	hazard.advance(1.1, player)
	check(shots.size() == 1 and hazard.state == "recovery", "开火1.41.5秒后仍不能重新瞄准")
	hazard.advance(0.08, player)
	check(hazard.state == "idle", "满1.5秒冷却才恢复待机")
	check(not hazard.damage_active(), "狙击只经子弹系统结算不附带接触伤害")
	player.position = Vector2(180, 300)
	hazard.free()


func _test_obstacles(level: TestLevel, player: TestPlayer) -> void:
	var hazard := _new_hazard(level)
	level.walls = [Rect2(320, 100, 20, 220)]
	hazard.advance(DT, player)
	check(hazard.state == "idle", "实墙阻止跨墙锁定")
	level.walls.clear()
	var door := TestDoor.new()
	door.position = Vector2(320, 190)
	hazard.door_blockers = [door]
	hazard.advance(DT, player)
	check(hazard.state == "idle", "锁门阻止锁定")
	door.locked = false
	hazard.advance(DT, player)
	check(hazard.state == "warning", "开门后重新完整警示")
	level.walls = [Rect2(40, 100, 20, 220)]
	hazard.advance(DT, player)
	check(hazard.trace_end.x >= 60.0 and hazard.trace_end.x < 65.0, "弹道提示截在目标后方墙边")
	level.walls.clear()
	hazard.set_armed(false)
	player.position.x = 580.0
	hazard.set_armed(true)
	hazard.advance(DT, player)
	check(hazard.state == "idle", "绕到炮背后不能反向偷射")
	player.position = Vector2(-600, 300)
	hazard.advance(DT, player)
	check(hazard.state == "idle", "量程外不锁定")
	player.position = Vector2(180, 100)
	hazard.advance(DT, player)
	check(hazard.state == "idle", "跨层高差过大不盲锁")
	player.position = Vector2(180, 300)
	hazard.free()
	door.free()


func _test_smoke(level: TestLevel, player: TestPlayer) -> void:
	shots.clear()
	sounds.clear()
	var hazard := _new_hazard(level)
	hazard.advance(4.0, player, true)
	check(hazard.state == "idle" and shots.is_empty(), "烟中不建立新锁定")
	hazard.advance(DT, player)
	check(hazard.state == "warning", "离烟后完整开始预警")
	hazard.advance(1.0, player)
	hazard.advance(DT, player, true)
	check(hazard.state == "idle" and shots.is_empty(), "跟踪1秒进入烟雾立即失去目标")
	check(hazard.last_target == Vector2.ZERO and hazard.trace_end == Vector2.ZERO,
		"跟踪入烟清掉旧目标和红色弹道")
	check(hazard.phase_time == 0.0 and sounds.is_empty(), "烟中取消不保留旧倒计时也不发锁定音")
	hazard.advance(4.0, player, true)
	check(hazard.state == "idle" and shots.is_empty(), "继续躲烟不会暗中恢复跟踪或开火")
	hazard.advance(DT, player)
	hazard.advance(1.49, player)
	check(hazard.state == "warning" and shots.is_empty(), "出烟重跟踪1.49秒仍未锁定")
	hazard.advance(0.02, player)
	check(hazard.state == "locked" and sounds == [&"sniper_lock"], "重跟踪满1.5秒才有一次新的锁定提示")
	hazard.advance(0.2, player)
	hazard.advance(0.8, player, true)
	check(hazard.state == "idle" and shots.is_empty(), "锁定0.2秒后入烟取消该次开火，大dt也不能抢先发弹")
	check(hazard.last_target == Vector2.ZERO and hazard.trace_end == Vector2.ZERO \
		and not hazard.aim_line_fast_flashing(), "末半秒失锁时红线与快闪一起消失")
	check(sounds.size() == 1, "取消已锁定射击不重播锁定音")
	hazard.advance(2.0, player, true)
	hazard.advance(DT, player)
	hazard.advance(1.49, player)
	check(hazard.state == "warning" and shots.is_empty() and sounds.size() == 1,
		"末半秒取消后出烟必须重新完整1.5秒，不继承先前锁定")
	hazard.advance(0.02, player)
	hazard.advance(0.49, player)
	check(hazard.state == "locked" and shots.is_empty(), "重新锁定0.49秒仍不能提前射击")
	hazard.advance(0.02, player)
	check(shots.size() == 1 and hazard.state == "recovery", "出烟完整1.5秒跟踪加半秒锁向后才正常开火")
	hazard.advance(1.0, player, true)
	check(hazard.state == "recovery" and is_equal_approx(hazard.phase_time, 1.0),
		"已开火后入烟不清零或跳过原1.5秒冷却")
	hazard.advance(0.49, player)
	check(hazard.state == "recovery" and shots.size() == 1, "冷却1.49秒即使出烟也不能重新跟踪")
	hazard.advance(0.02, player)
	check(hazard.state == "idle", "原1.5秒冷却完整结束才进入待机")
	_until(hazard, player, "locked")
	var locks_before_pause := sounds.size()
	hazard.advance(0.0, player, true)
	check(hazard.state == "idle" and hazard.trace_end == Vector2.ZERO and shots.size() == 1,
		"时停中进入已有烟雾也立即消除锁定红线，无解冻偷射")
	check(sounds.size() == locks_before_pause, "零dt烟遮断不重放机械声")
	hazard.free()


func _test_destruction(level: TestLevel, player: TestPlayer) -> void:
	sounds.clear()
	broken.clear()
	shots.clear()
	var hazard := _new_hazard(level)
	check(hazard.body_rect().size == Vector2(46, 78), "炮塔器械受击框完整可被挥棒/货箱命中")
	_until(hazard, player, "locked")
	check(hazard.take_hit(player.position.x), "一棒能破坏已锁定炮塔")
	check(hazard.dead and hazard.hp == 0 and hazard.state == "dead", "击毁状态一致")
	check(sounds == [&"sniper_lock", &"metal_impact"] and broken.size() == 1, "锁定一次机械提示，击毁一次金属音和器械碎片")
	check(not hazard.take_hit(player.position.x), "重复击毁不重复结算")
	hazard.advance(10.0, player)
	check(shots.is_empty(), "击毁后无法发出原先锁定弹")
	check(not hazard.body_rect().has_area(), "残骸不再吸收后续棒击")
	hazard.free()


func _test_laser(level: TestLevel, player: TestPlayer) -> void:
	var hazard := _new_hazard(level, {"type": "laser_gate", "pos": [150.0, 246.0], "floor_y": 300.0, "span": 160.0})
	hazard.advance(8.0, player)
	check(hazard.state == "warning" and not hazard.damage_active(), "激光首次大dt也不会跳过警示")
	hazard.advance(0.5, player)
	check(not hazard.damage_active(), "激光前半秒提示无伤害")
	hazard.advance(0.5, player)
	check(hazard.damage_active(), "预警结束高位激光生效")
	var standing := Rect2(player.position + Vector2(-17, -82), Vector2(34, 82))
	var rolling := Rect2(player.position + Vector2(-19, -34), Vector2(38, 34))
	check(hazard.damage_rect().intersects(standing), "站立上身会触高位激光")
	check(not hazard.damage_rect().intersects(rolling), "34px翻滚低框能过高位激光")
	check(hazard.damage_rect().end.y <= rolling.position.y - 10.0, "低框和激光间保留至少10px容差")
	level.walls = [Rect2(230, 200, 20, 100)]
	check(hazard.damage_rect().end.x <= 230.0, "激光危险范围不能穿墙")
	level.walls.clear()
	hazard.advance(0.6, player)
	check(hazard.state == "recovery" and not hazard.damage_active(), "激光休止期完全无伤")
	hazard.advance(1.1, player)
	check(hazard.state == "recovery", "激光保证至少1秒安全窗")
	check(not hazard.take_hit(player.position.x), "固定发射器不被意外当成必杀敌人")
	hazard.set_armed(false)
	check(hazard.state == "idle" and not hazard.damage_active(), "离屏关闭危险并清旧周期")
	hazard.free()


func _test_press(level: TestLevel, player: TestPlayer) -> void:
	var hazard := _new_hazard(level, {"type": "press", "pos": [160.0, 140.0], "floor_y": 300.0, "width": 64.0})
	hazard.advance(DT, player)
	check(hazard.state == "warning", "压机靠近先出落点预警")
	check(is_equal_approx(hazard.press_height, 160.0), "压机高度严格由落点floor_y派生")
	hazard.advance(1.0, player)
	check(not hazard.damage_active(), "压机提前至少1.1秒预告")
	hazard.advance(0.11, player)
	check(hazard.damage_active(), "压机进入下压阶段")
	hazard.advance(0.15, player)
	var swept: Rect2 = hazard.damage_rect()
	check(swept.position.y <= 164.0 and swept.end.y >= 299.0, "快速压板覆盖本步扫掠不能穿过主角")
	check(swept.position.x == 160.0 and swept.size.x == 64.0, "压机伤害只在机器宽度内")
	check(swept.intersects(Rect2(170, 230, 20, 52)), "压机可命中下方身体")
	check(not swept.intersects(Rect2(250, 230, 20, 52)), "压机侧面留可避让空间")
	hazard.advance(0.4, player)
	check(hazard.state == "recovery" and not hazard.damage_active(), "压机提起期间无伤害")
	hazard.advance(1.1, player)
	check(hazard.state == "recovery", "压机安全窗超过1秒")
	check(not hazard.take_hit(0.0), "压机不混入击杀计数")
	hazard.free()


func _test_time_and_defaults(level: TestLevel, player: TestPlayer) -> void:
	shots.clear()
	var hazard := _new_hazard(level, {"range": 9999, "bullet_speed": 9999, "warning": 0.01, "recovery": 0.01, "hard_only": true})
	check(hazard.detection_range == 1024.0 and hazard.bullet_speed == 3000.0, "极端配置受范围/弹速安全上限约束")
	check(hazard.warning_duration == 1.5 and hazard.recovery_duration == 1.5, "旧地图warning/recovery配置不能覆盖1.5秒新规格")
	check(hazard.hard_only and hazard.room_id == "test", "难度与房间数据保留给外层激活")
	hazard.advance(100.0, player)
	check(hazard.state == "warning" and hazard.phase_time == 0.0, "首次超大dt只进入预警")
	hazard.advance(100.0, player)
	check(hazard.state == "locked" and shots.is_empty(), "超大dt也必须保留独立锁定提示帧")
	var phase: float = hazard.phase_time
	var direction_before: Vector2 = hazard.aim_direction
	for _i in 120:
		hazard.advance(0.0, player)
	check(hazard.phase_time == phase and hazard.aim_direction == direction_before and shots.is_empty(), "零dt时完全冻结且无后台时钟")
	check(not hazard.has_method("_process") and not hazard.has_method("_physics_process"), "无自主process推进机关")
	hazard.set_armed(false)
	hazard.advance(10.0, player)
	check(hazard.state == "idle" and shots.is_empty(), "外层关闭时无隐藏发射")
	hazard.set_armed(true)
	hazard.advance(10.0, player)
	check(hazard.state == "warning", "重新可见必须重新完整预警")
	player.dead = true
	var before: float = hazard.phase_time
	hazard.advance(10.0, player)
	check(hazard.phase_time == before and shots.is_empty(), "玩家死亡不继续机关")
	player.dead = false
	hazard.free()


func _test_cleared_shutdown(level: TestLevel, player: TestPlayer) -> void:
	shots.clear()
	sounds.clear()
	var hazard := _new_hazard(level)
	hazard.advance(DT, player)
	hazard.advance(1.49, player)
	check(hazard.state == "warning" and sounds.is_empty(), "跟踪1.49秒仍不锁定")
	player.position.x = 200.0
	hazard.advance(0.02, player)
	check(hazard.state == "locked" and sounds == [&"sniper_lock"], "满1.5秒只发一次锁定机械音")
	check(hazard.last_target == player.position + Vector2(0, -58), "锁定的是第1.5秒最后跟踪位置")
	hazard.advance(0.2, player)
	check(sounds.size() == 1, "锁向阶段不每帧重复触发音效")
	hazard.deactivate_cleared()
	check(hazard.state == "disabled" and hazard.cleared_disabled and not hazard.armed, "清房永久停机并取消锁定")
	hazard.set_armed(true)
	hazard.advance(20.0, player)
	check(hazard.state == "disabled" and shots.is_empty(), "下一帧set_armed不能复活已清房炮塔")
	hazard.deactivate_cleared()
	check(sounds.size() == 1, "重复清房关闭不触发音效或重置外观")
	hazard.setup({"type": "auto_sniper", "pos": [500, 300]}, level)
	check(not hazard.cleared_disabled and hazard.state == "idle", "仅新关setup可以重建清房停机装置")
	hazard.set_armed(true)
	_until(hazard, player, "locked")
	hazard.take_hit(player.position.x)
	hazard.deactivate_cleared()
	hazard.set_armed(true)
	hazard.advance(20.0, player)
	check(hazard.dead and hazard.state == "dead" and shots.is_empty(), "提前击毁器械不会被清房状态覆盖或复活")
	player.position = Vector2(180, 300)
	hazard.free()


func _test_final_second_signal(level: TestLevel, player: TestPlayer) -> void:
	shots.clear()
	var hazard := _new_hazard(level)
	hazard.advance(DT, player)
	hazard.advance(0.99, player)
	check(not hazard.aim_line_fast_flashing() and is_equal_approx(hazard.aim_line_alpha(), 0.70), "t0.99红线常亮不提前快闪")
	hazard.advance(0.01, player)
	check(hazard.aim_line_fast_flashing(), "t1.00进入开火前最后1秒快闪")
	var bright: float = hazard.aim_line_alpha()
	hazard.advance(0.09, player)
	check(hazard.aim_line_alpha() < bright and hazard.aim_line_alpha() >= 0.25, "6Hz红线暗相仍留至少25%可见度")
	hazard.advance(0.41, player)
	check(hazard.state == "locked" and hazard.aim_line_fast_flashing(), "t1.50冻结弹道且延续快闪")
	var fixed_direction: Vector2 = hazard.aim_direction
	player.position += Vector2(20, 20)
	hazard.advance(0.49, player)
	check(hazard.aim_direction == fixed_direction and shots.is_empty(), "t1.99红线固定且未开火")
	hazard.advance(0.01, player)
	check(shots.size() == 1 and hazard.state == "recovery", "t2.00开火进入1.5秒冷却")
	player.position = Vector2(180, 300)
	hazard.free()
