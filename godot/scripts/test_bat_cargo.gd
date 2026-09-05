extends SceneTree
## 击飞货箱的扫掠/寿命/回退 + 真实 game 命中链；不依赖渲染截图。

const CARGO := preload("res://scripts/prop_bat_cargo.gd")
var passed := 0
var failed := 0
var impacts := 0
var last_target: Node2D

class DummyEnemy extends Node2D:
	var dead := false
	func body_rect() -> Rect2:
		return Rect2(position - Vector2(16, 84), Vector2(32, 84))


func _init() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	passed += int(condition)
	failed += int(not condition)
	print("  ", "PASS " if condition else "FAIL ", label)


func _arena(wall := -1) -> CorridorLevel:
	var level := CorridorLevel.new()
	level.map_w = 48
	level.map_h = 10
	level.world_w = 48 * 32
	level.world_h = 10 * 32
	for row in 10:
		var line := ".".repeat(48)
		if row == 9:
			line = "#".repeat(48)
		elif wall >= 0:
			line = line.substr(0, wall) + "#" + line.substr(wall + 1)
		level.grid.append(line)
	return level


func _cargo(pos := Vector2(200, 287.9)) -> PropBatCargo:
	var cargo := CARGO.new()
	cargo.position = pos
	get_root().add_child(cargo)
	cargo.impacted.connect(func(_c: PropBatCargo, target: Node2D, _dir: Vector2) -> void:
		impacts += 1
		last_target = target)
	return cargo


func _run() -> void:
	var level := _arena()
	var cargo := _cargo()
	check(cargo.spawn_position == cargo.position and not cargo.flying, "货箱脚底锚点/出生位置正确")
	check(cargo.launch(1), "向右挥棒可发射货箱")
	check(not cargo.launch(-1), "同一飞行箱不被重复打击改向")
	cargo.advance(0.2, level, [], [])
	var right_x := cargo.position.x - 200.0
	check(right_x > 165.0 and right_x < 175.0 and cargo.position.y < 287.9, "高速水平推进并轻微上抛")
	cargo.reset_to_spawn()
	cargo.launch(-1)
	cargo.advance(0.2, level, [], [])
	check(absf((200.0 - cargo.position.x) - right_x) < 0.1, "左右飞行距离对称")
	cargo.reset_to_spawn()
	check(cargo.position == Vector2(200, 287.9) and cargo._trail.is_empty(), "重置清除轨迹并回出生点")
	var enemy := DummyEnemy.new()
	enemy.position = Vector2(460, 287.9)
	get_root().add_child(enemy)
	cargo.launch(1)
	impacts = 0
	cargo.advance(0.4, level, [enemy], [])
	check(cargo.dead and not cargo.flying and last_target == enemy and impacts == 1, "大 dt 扫掠也能命中敌人且只发一次信号")
	cargo.advance(1.0, level, [enemy], [])
	check(impacts == 1 and not cargo.launch(1), "碎箱不继续伤害、不允许重复发射")
	cargo.step(1.0)
	check(cargo._shards.is_empty() and cargo._trail.is_empty(), "碎屑和短轨迹在有限时间回收")
	level.free()
	level = _arena(10)
	cargo.reset_to_spawn()
	cargo.launch(1)
	last_target = enemy
	impacts = 0
	cargo.advance(0.5, level, [enemy], [])
	check(cargo.dead and last_target == null and impacts == 1, "薄墙先于墙后敌人结算")
	check(cargo.body_rect().end.x <= 320.0, "箱体碰撞边缘不穿墙")
	level.free()
	level = _arena()
	var door := RoomDoor.new()
	door.position = Vector2(330, 287.9)
	cargo.reset_to_spawn()
	cargo.launch(1)
	cargo.advance(0.4, level, [enemy], [door])
	check(cargo.dead and last_target == null and cargo.body_rect().end.x <= 298.0, "锁门阻挡箱体和伤害")
	door.locked = false
	cargo.reset_to_spawn()
	cargo.launch(1)
	cargo.advance(0.4, level, [enemy], [door])
	check(last_target == enemy, "解锁门不挡飞行货箱")
	door.free()
	# 单向平台只在下降跨顶时阻挡；侧面/向上经过不假装实体墙。
	level.grid[6] = "=".repeat(48)
	cargo.reset_to_spawn()
	var below := Rect2(200, 200, 32, 36)
	check(not cargo._blocked(below, Rect2(202, 196, 32, 36), level, []), "单向平台从下往上穿行")
	var above := Rect2(200, 154, 32, 36)
	check(cargo._blocked(above, Rect2(202, 158, 32, 36), level, []), "落下跨过平台顶面会破碎")
	level.grid[6] = ".".repeat(48)
	level.stairs = [{"left_c": 6, "bottom_row": 9, "steps": 4, "rise_dir": 1}]
	check(cargo._blocked(Rect2(200, 234, 32, 36), Rect2(202, 238, 32, 36), level, []), "下降时尊重16px楼梯踏面")
	level.stairs.clear()
	cargo.reset_to_spawn()
	cargo.position.y = 80
	cargo.launch(1)
	for i in 120:
		cargo.advance(1.0 / 120.0, level, [], [])
	check(cargo._trail.size() <= CARGO.MAX_TRAIL and cargo._shards.size() <= 10, "飞行轨迹和碎片数量有上限")
	cargo.advance(10.0, level, [], [])
	check(cargo.dead and not cargo.flying, "长帧及出界最终销毁飞行状态")
	cargo.free()
	enemy.free()
	level.free()
	await _integration()
	print("BAT_CARGO_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _integration() -> void:
	var rows := PackedStringArray()
	for y in 10:
		var row := ".".repeat(48)
		if y == 9:
			row = "#".repeat(48)
		elif y == 8:
			for pair in [[3, "@"], [5, "C"], [12, "m"], [22, "x"]]:
				row = row.substr(0, pair[0]) + pair[1] + row.substr(pair[0] + 1)
		rows.append(row)
	CorridorLevel.active_map = "\n".join(rows)
	CorridorLevel.active_minion = "grunt"
	CorridorLevel.active_boss = "none"
	var game = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.player.auto_input = false
	game._sfx.clear()
	check(game.props.size() == 1 and game.props[0] is PropBatCargo, "生产地图 C 标记生成新货箱")
	var cargo: PropBatCargo = game.props[0]
	check(not game.level.solid_at(cargo.position.x, cargo.position.y - 8), "C 标记剥离后不阻挡玩家移动")
	check(game.minions[0] is FreightInspector and game.minions[1] is GruntGunner, "集成测试使用正式近战兵和枪手")
	game.player.face = 1
	game._on_player_bat_swung(cargo.body_rect(), 0)
	check(cargo.flying and game.player.hitstop <= 0.025, "正式挥棒链发射货箱并用短接触顿帧")
	cargo.advance(0.5, game.level, game._enemies(), game.doors)
	check(game.minions[0].dead and not game.minions[1].dead, "货箱杀死第一位近战兵，不穿透第二人")
	check(game.debug_enemy_knockback_count() == 1, "货箱命中接入正式尸体击退")
	check(game.fx_layer.get_child_count() > 0, "货箱命中接入既有彩色喷血特效")
	game._reset_bat_cargo()
	cargo.position = Vector2(560, 287.9)
	cargo.launch(1)
	cargo.advance(0.4, game.level, game._enemies(), game.doors)
	check(game.minions[1].dead, "同一伤害接口可解决正式枪手")
	var event := InputEventKey.new()
	event.keycode = KEY_BACKSPACE
	event.pressed = true
	game._unhandled_input(event)
	check(not cargo.dead and not cargo.flying and cargo.position == cargo.spawn_position, "Backspace恢复箱子，无飞行状态残留")
	check(game.minions[0].dead and game.minions[1].dead, "保留既有重置不复活已清敌人的规则")
	# 从真实输入开始，覆盖最容易被38px前送越过的贴箱起手，而非直接伪造命中盒。
	for side in [-1, 1]:
		for distance in [12.0, 20.0, 64.0]:
			for moving in [false, true]:
				cargo.reset_to_spawn()
				game.player.reset_to_spawn()
				game.player.position = cargo.position - Vector2(side * distance, 0)
				game.player.face = side
				game.player.on_ground = true
				game.player._prev_keys.clear()
				for tick in 24:
					game.player.keys = {}
					if tick == 0:
						game.player.keys[MOUSE_BUTTON_LEFT] = true
					if moving:
						game.player.keys[KEY_D if side > 0 else KEY_A] = true
					game.player.step(1.0 / 60.0)
					if cargo.flying:
						break
				check(cargo.flying and signf(cargo.velocity.x) == side,
						"真实左键朝向%d 距箱%dpx 带步%s可击飞" % [side, distance, moving])
	cargo.reset_to_spawn()
	game.player.reset_to_spawn()
	game.player.position = cargo.position + Vector2(70, 0)
	game.player.face = 1
	game.player.on_ground = true
	game.player._prev_keys.clear()
	for tick in 24:
		game.player.keys = {MOUSE_BUTTON_LEFT: true} if tick == 0 else {}
		game.player.step(1.0 / 60.0)
	check(not cargo.flying, "背对远处箱子不会自动反向命中")
	# 即使箱体处于近战范围，仍禁止隔着一格实体墙或锁门发射。
	cargo.position = Vector2(310, 287.9)
	game.player.position = Vector2(232, 287.9)
	for row in range(6, 9):
		game.level.grid[row] = game.level.grid[row].substr(0, 8) + "#" + game.level.grid[row].substr(9)
	game._on_player_bat_swung(cargo.body_rect(), 0)
	check(not cargo.flying, "近战接触盒不能隔实体墙发射箱子")
	for row in range(6, 9):
		game.level.grid[row] = game.level.grid[row].substr(0, 8) + "." + game.level.grid[row].substr(9)
	var locked_door := RoomDoor.new()
	locked_door.position = Vector2(275, 287.9)
	game.doors.append(locked_door)
	game._on_player_bat_swung(cargo.body_rect(), 0)
	check(not cargo.flying, "近战接触盒不能隔锁门发射箱子")
	game.doors.erase(locked_door)
	locked_door.free()
	game.bat_cargo_enabled = false
	check(game._spawn_prop("bat_cargo", Vector2.ZERO) == null, "开关可关闭新箱子生成")
	game.bat_cargo_enabled = true
	game.player.position = Vector2(430, 287.9)
	for index in 13:
		game._spawn_prop("bat_cargo", Vector2(480, 287.9))
	game._on_player_bat_swung(Rect2(465, 250, 34, 38), 0)
	check(game._flying_cargo_count() == game.MAX_FLYING_CARGO, "同时击飞数量封顶12，超限箱子留在原位")
	game._reset_bat_cargo()
	check(game._flying_cargo_count() == 0, "大量击飞后重置全部停止，无幽灵伤害")
	for audio: AudioStreamPlayer in game._sfx_pool:
		audio.stop()
		audio.stream = null
	game.fx_layer.clear_explosions()
	game.free()
	CorridorLevel.active_map = ""
	CorridorLevel.active_minion = "ghost"
	CorridorLevel.active_boss = "red"
	await process_frame
