extends SceneTree
## 扩展流程静态布置 + 正式 PropBatCargo 弹道验收；不以它替代动态 AI 实玩。
## 保持所有敌人的真实身体尺寸，验证首个命中对象与墙体阻挡，不绕过2px扫掠。

const DATA := preload("res://generated/m01_protocol_quarantine_data.gd")
var passed := 0
var failed := 0
var last_target: Node2D


class LayoutEnemy extends Node2D:
	var dead := false
	var width := 44.0
	func body_rect() -> Rect2:
		return Rect2(position - Vector2(width * 0.5, 96.0), Vector2(width, 96.0))


func _init() -> void:
	call_deferred("_run")


func check(condition: bool, label: String, detail := "") -> void:
	passed += int(condition)
	failed += int(not condition)
	print("  PASS " if condition else "  FAIL ", label, " ", detail)


func _feet(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32.0 + 16.0, (cell.y + 1) * 32.0 - 0.1)


func _run() -> void:
	# 只构造查询所需网格；不启动 game、AI、音频或渲染流程。
	var level := CorridorLevel.new()
	level.map_w = DATA.MAP_WIDTH
	level.map_h = DATA.MAP_HEIGHT
	level.world_w = DATA.MAP_WIDTH * 32
	level.world_h = DATA.MAP_HEIGHT * 32
	for row in DATA.MAP_TEXT.strip_edges().split("\n"):
		level.grid.append(row)
	for source: Dictionary in DATA.STAIRS:
		level.stairs.append({"left_c": mini(int(source["bottom_cell"][0]), int(source["top_cell"][0])),
			"bottom_row": int(source["bottom_cell"][1]), "steps": int(source["steps"]),
			"rise_dir": 1 if source["direction"] == "right_up" else -1})
	var enemies: Array = []
	var cargo_cells: Array[Vector2i] = []
	for entity: Dictionary in DATA.ENTITIES:
		var cell := Vector2i(int(entity["cell"][0]), int(entity["cell"][1]))
		if entity["kind"] == "BatCargo":
			cargo_cells.append(cell)
		elif entity["kind"] in ["Gunner", "MeleeInspector"]:
			var enemy := LayoutEnemy.new()
			enemy.position = _feet(cell)
			enemy.width = GruntGunner.BODY_W if entity["kind"] == "Gunner" else FreightInspector.BODY_W
			enemy.set_meta("spawn_cell", cell)
			enemies.append(enemy)
	check(enemies.size() == 20 and cargo_cells.size() == 11, "20敌和11箱均来自正式生成数据")
	var no_overlap := true
	for cell in cargo_cells:
		var box := Rect2(_feet(cell) - Vector2(16, 36), Vector2(32, 36))
		for enemy: Node2D in enemies:
			no_overlap = no_overlap and not enemy.body_rect().intersects(box)
	check(no_overlap, "所有箱子出生时都不与敌人身体重叠")
	check(cargo_cells.has(Vector2i(228, 22)) and not cargo_cells.has(Vector2i(226, 22)),
		"核心入口箱移至c228，左右敌人各隔3格")
	var cases := [
		[28, 27, 1, 36, 27], [40, 27, 1, 47, 27],
		[76, 22, 1, 84, 22], [85, 19, 1, 89, 19],
		[148, 27, 1, 156, 27], [164, 27, 1, 172, 27],
		[176, 25, 1, 179, 25], [186, 27, 1, 190, 27],
		[228, 22, 1, 231, 22], [234, 20, 1, 236, 20], [243, 22, 1, 249, 22],
		# 反向与高打低机会：真实敌人高96px，所以低一层的身体顶部仍能被箱子扫到。
		[228, 22, -1, 225, 22], [176, 25, -1, 172, 27],
		[234, 20, -1, 231, 22], [85, 19, -1, 82, 19], [148, 27, -1, 142, 27],
		# 这两条反向线必须被高台挡住，不能为了爽感穿过实心地形。
		[243, 22, -1, -1, -1], [186, 27, -1, -1, -1],
	]
	for item: Array in cases:
		var source := Vector2i(int(item[0]), int(item[1]))
		var expected := Vector2i(int(item[3]), int(item[4]))
		var cargo := PropBatCargo.new()
		cargo.position = _feet(source)
		last_target = null
		cargo.impacted.connect(func(_cargo: PropBatCargo, target: Node2D, _direction: Vector2) -> void:
			last_target = target)
		cargo.launch(float(item[2]))
		cargo.advance(1.1, level, enemies, [])
		var actual: Vector2i = last_target.get_meta("spawn_cell") if last_target != null else Vector2i(-1, -1)
		check(cargo.dead and actual == expected, "%s 向%s → %s" % [str(source),
			"右" if int(item[2]) > 0 else "左", "地形阻挡" if expected.x < 0 else str(expected)], str(actual))
		cargo.free()
	for enemy: Node2D in enemies:
		enemy.free()
	level.free()
	print("CAMPAIGN_CARGO_LANES: %d PASS / %d FAIL" % [passed, failed])
	quit(0 if failed == 0 else 1)
