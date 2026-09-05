extends SceneTree
## 货运巡检员无头验收：透明图集帧数、状态节奏、锁朝向、攻击有效窗与死亡。
## 跑法：godot --headless --path godot --script scripts/test_freight_inspector.gd

const FREIGHT_SCRIPT := preload("res://scripts/freight_inspector.gd")

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("== 货运巡检员素材 ==")
	var source := Image.load_from_file("res://assets/enemy/freight_inspector/ai_reference.png")
	var atlas := Image.load_from_file("res://assets/enemy/freight_inspector/atlas.png")
	ok(source.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF,
		Image.FORMAT_RGBAH, Image.FORMAT_RGBA4444], "母表含 Alpha 通道")
	ok(atlas.get_size() == Vector2i(1024, 672), "图集为 8x7 个 128x96 正方形格",
		str(atlas.get_size()))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/enemy/freight_inspector/atlas.json"))
	var expected := {"idle": 4, "alert": 5, "run": 8, "windup": 4,
		"attack": 6, "recover": 4, "death": 6}
	var counts_ok := true
	for name in expected:
		counts_ok = counts_ok and int(meta["animations"][name]["frames"]) == expected[name]
	ok(counts_ok, "实际使用帧为 4/5/8/4/6/4/6")
	ok(int(meta["source_frames"]["death"]) == 7
		and int(meta["animations"]["death"]["frames"]) == 6,
		"第七行保留 7 帧但排除最后一帧")

	print("== 货运巡检员状态机 ==")
	CorridorLevel.active_map = CorridorLevel.MAP_M03_ZERO_FREIGHT
	var level := CorridorLevel.new()
	level.build(false)
	var player := Node2D.new()
	get_root().add_child(player)
	var enemy: Node2D = FREIGHT_SCRIPT.new()
	enemy.level = level
	enemy.player = player
	enemy.position = Vector2(40 * 32 + 16, 16 * 32 - 0.1)
	player.position = enemy.position + Vector2(200.0, 0.0)
	get_root().add_child(enemy)
	await process_frame
	ok(enemy.standing_height() == 96.0 and enemy.body_rect().size == Vector2(42.0, 96.0),
		"碰撞体预算为 42x96")
	enemy.step(1.0 / 60.0)
	ok(enemy.state == "alert", "360px 内发现玩家进入警戒")
	for i in range(enemy.ALERT_TICKS):
		enemy.step(1.0 / 60.0)
	ok(enemy.state == "run", "警戒后进入追击")
	player.position = enemy.position + Vector2(60.0, 0.0)
	enemy.step(1.0 / 60.0)
	ok(enemy.state == "windup" and not enemy.attack_active(), "近身后先进入无伤害前摇")
	var locked_face: int = enemy.face
	player.position = enemy.position - Vector2(60.0, 0.0)
	for i in range(enemy.WINDUP_TICKS):
		enemy.step(1.0 / 60.0)
	ok(enemy.state == "attack" and enemy.face == locked_face,
		"前摇期间锁定朝向，允许绕背")
	ok(not enemy.attack_active(), "挥击第 0 帧仍无伤害")
	enemy.step(1.0 / 60.0)
	enemy.step(1.0 / 60.0)
	ok(enemy.attack_active(), "挥击仅在第 2 帧起生效")
	ok(enemy.attack_rect().size == Vector2(84.0, 58.0), "独立攻击盒为 84x58")
	for i in range(enemy.ATTACK_TICKS):
		enemy.step(1.0 / 60.0)
	ok(enemy.state == "recover" and not enemy.attack_active(), "挥击后进入无伤害硬直")
	ok(enemy.take_hit(player.position.x, 1) and enemy.dead and enemy.state == "dead",
		"球棒一击击倒并播放死亡行")
	ok(enemy._sprite.region_rect.position.y == 6 * 96,
		"死亡状态实际切到第七行动画", str(enemy._sprite.region_rect))
	ok(not enemy.take_hit(player.position.x, 1), "死亡后不会重复结算")

	enemy.free()
	player.free()
	level.free()
	CorridorLevel.active_map = ""
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
