extends SceneTree
## 货运枪手无头验收：透明图集契约、六行动画、单次出弹、后摇复用待机与死亡定格。
## 跑法：godot --headless --path godot --script scripts/test_grunt_gunner.gd

const GUNNER_SCRIPT := preload("res://scripts/grunt.gd")
const ATLAS_PATH := "res://assets/enemy/grunt/atlas.png"
const META_PATH := "res://assets/enemy/grunt/atlas.json"
const FRAME_COUNTS := [3, 4, 8, 5, 4, 6]
const ANIMATION_NAMES := ["idle", "alert", "run", "aim", "fire", "death"]

var _pass := 0
var _fail := 0


func ok(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("== 货运枪手生产图集 ==")
	# 直接解码源 PNG 做 Alpha 契约检查，避免导入器的 fix_alpha_border 改写透明区 RGB。
	var atlas := Image.new()
	var png_error := atlas.load_png_from_buffer(FileAccess.get_file_as_bytes(ATLAS_PATH))
	ok(png_error == OK, "源 PNG 可解码", str(png_error))
	ok(not atlas.is_empty() and atlas.get_size() == Vector2i(2048, 1536),
			"图集为 2048x1536（8x6 个 256 格）", str(atlas.get_size()))
	ok(atlas.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF,
			Image.FORMAT_RGBAH, Image.FORMAT_RGBA4444], "图集含 Alpha 通道")
	var bytes := atlas.get_data()
	var binary_alpha := true
	var transparent_rgb_zero := true
	for index in range(3, bytes.size(), 4):
		var alpha := int(bytes[index])
		if alpha != 0 and alpha != 255:
			binary_alpha = false
			break
		if alpha == 0 and (bytes[index - 3] != 0 or bytes[index - 2] != 0
				or bytes[index - 1] != 0):
			transparent_rgb_zero = false
	ok(binary_alpha, "Alpha 仅含 0/255 硬边")
	ok(transparent_rgb_zero, "透明区 RGB 为 0，不会产生黑色插值边")

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	var meta: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	var cell_size: Array = meta.get("cell_size", []) as Array
	ok(not meta.is_empty() and cell_size.size() == 2 and int(cell_size[0]) == 256
			and int(cell_size[1]) == 256 and int(meta.get("baseline_y", -1)) == 224,
			"元数据格尺寸与脚底基线正确")
	var animations: Dictionary = meta.get("animations", {}) as Dictionary
	var counts_ok := true
	for index in ANIMATION_NAMES.size():
		var value: Variant = animations.get(ANIMATION_NAMES[index], {})
		if not value is Dictionary or int((value as Dictionary).get("frames", 0)) \
				!= FRAME_COUNTS[index]:
			counts_ok = false
	ok(counts_ok, "六行动画帧数为 3/4/8/5/4/6")
	var unused_clear := true
	var active_cells_valid := true
	var minimum_margin := 256
	for row in FRAME_COUNTS.size():
		for column in FRAME_COUNTS[row]:
			var active_cell := atlas.get_region(Rect2i(column * 256, row * 256, 256, 256))
			var used := active_cell.get_used_rect()
			if used.size == Vector2i.ZERO or used.end.y != 224:
				active_cells_valid = false
			else:
				minimum_margin = mini(minimum_margin, used.position.x)
				minimum_margin = mini(minimum_margin, used.position.y)
				minimum_margin = mini(minimum_margin, 256 - used.end.x)
				minimum_margin = mini(minimum_margin, 256 - used.end.y)
		for column in range(FRAME_COUNTS[row], 8):
			var cell := atlas.get_region(Rect2i(column * 256, row * 256, 256, 256))
			if cell.get_used_rect().size != Vector2i.ZERO:
				unused_clear = false
	ok(active_cells_valid, "30 个有效格均非空且脚底统一为 y=224")
	ok(minimum_margin >= 2, "有效帧为 2 texel 描边保留安全透明边距", str(minimum_margin))
	ok(unused_clear, "18 个未使用格完全透明")

	print("== 警戒、瞄准、开火与后摇 ==")
	var player := Node2D.new()
	var enemy: GruntGunner = GUNNER_SCRIPT.new()
	player.position = Vector2(200.0, 0.0)
	enemy.player = player
	get_root().add_child(player)
	get_root().add_child(enemy)
	await process_frame
	ok(is_equal_approx(enemy.standing_height(), 96.0)
			and enemy.body_rect().size == Vector2(44.0, 96.0),
			"新美术保持 96px 站高与 44x96 碰撞预算",
			"height=%.2f body=%s" % [enemy.standing_height(), enemy.body_rect().size])
	ok(enemy.debug_animation_name() == "idle" and enemy.debug_animation_frame() == 0,
			"出生播放 idle")
	var shots: Array = []
	enemy.shoot_orb.connect(func(from_pos: Vector2, velocity: Vector2) -> void:
		shots.append([from_pos, velocity]))
	enemy.step(1.0 / 60.0)
	ok(enemy.state == "alert" and enemy.debug_animation_name() == "alert",
			"发现玩家先进入警戒行")
	for index in range(enemy.ALERT_TICKS):
		enemy.step(1.0 / 60.0)
	ok(enemy.state == "aim" and shots.is_empty(), "警戒结束后瞄准，未提前出弹")
	var locked_face := enemy.face
	player.position.x = -200.0
	for index in range(enemy.AIM_TICKS):
		enemy.step(1.0 / 60.0)
	ok(enemy.state == "fire" and enemy.face == locked_face and shots.is_empty(),
			"瞄准期间锁朝向并完整进入 fire")
	for index in range(enemy.FIRE_SHOT_TICK - 1):
		enemy.step(1.0 / 60.0)
	ok(shots.is_empty(), "枪口焰帧之前不会提前出弹")
	enemy.step(1.0 / 60.0)
	ok(shots.size() == 1, "枪口焰帧只发射一颗子弹", str(shots.size()))
	if not shots.is_empty():
		var shot: Array = shots[0]
		var from_pos: Vector2 = shot[0]
		var velocity: Vector2 = shot[1]
		ok(signf(velocity.x) == float(locked_face)
				and signf(from_pos.x - enemy.position.x) == float(locked_face),
				"玩家绕背时枪口和子弹仍沿锁定朝向")
		ok(is_equal_approx(velocity.length(), enemy.BULLET_SPEED), "子弹速度保持 520px/s",
				str(velocity.length()))
	var repeat_ticks := 0
	for index in range(enemy.FIRE_TICKS - enemy.FIRE_SHOT_TICK):
		enemy.step(1.0 / 60.0)
		repeat_ticks += 1
	ok(enemy.state == "recover" and shots.size() == 1,
			"fire 播完进入无重复出弹的 recover")
	ok(enemy.debug_animation_name() == "idle"
			and int(enemy._sprite.region_rect.position.y) == 0,
			"后摇按要求复用 idle 行")
	while shots.size() < 2 and repeat_ticks < 100:
		enemy.step(1.0 / 60.0)
		repeat_ticks += 1
	ok(shots.size() == 2 and repeat_ticks == 80,
			"近距第二枪恢复旧版约 80 tick 节奏", "ticks=%d shots=%d" % [repeat_ticks, shots.size()])
	# 阈值外 1px 也必须先重走警戒；允许约 2 tick 走入 260px 射程。
	player.position.x = enemy.position.x + enemy.SHOOT_RANGE + 1.0
	var threshold_ticks := 0
	while shots.size() < 3 and threshold_ticks < 110:
		enemy.step(1.0 / 60.0)
		threshold_ticks += 1
	ok(shots.size() == 3 and threshold_ticks >= 81 and threshold_ticks <= 83,
			"261px 阈值外复射没有绕过警戒窗口",
			"ticks=%d shots=%d" % [threshold_ticks, shots.size()])

	print("== 受击死亡 ==")
	ok(enemy.take_hit(player.position.x, 1) and enemy.dead and enemy.state == "dead",
			"球棒一击进入死亡状态")
	ok(enemy.debug_animation_name() == "death"
			and int(enemy._sprite.region_rect.position.y) == 5 * 256,
			"死亡切到第六行首帧")
	# 正式球棒链会用约 0.3s hitstop 锁住 AI、同时持续推动尸体；倒地动画不能随之冻结。
	enemy.hitstop = 0.30
	var death_start_x := enemy.position.x
	for index in range(10):
		enemy.position.x += 1.0
		enemy.step(1.0 / 60.0)
	ok(enemy.debug_animation_frame() > 0 and enemy.position.x > death_start_x,
			"击退用 hitstop 期间死亡动画仍推进，不会直立滑行")
	for index in range(enemy.DEATH_TICKS + 12):
		enemy.step(1.0 / 60.0)
	ok(enemy.debug_animation_frame() == 5, "六帧死亡动画播放完后停在末帧")
	ok(not enemy._rim.visible and enemy.corpse_extent() == 96.0
			and enemy._sprite.scale.x < enemy.SCALE,
			"尸体摘轮廓光并压到 96px 最长边")
	ok(not enemy.take_hit(player.position.x, 1), "尸体不会重复结算命中")

	enemy.free()
	player.free()
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
