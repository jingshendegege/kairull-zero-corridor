extends SceneTree
## “废弃协议检疫设施”地图美术纵向切片；仅作真窗口方向验收。
## 跑法：Godot --path godot --rendering-driver opengl3 --fixed-fps 30 \
##         --script scripts/render_quarantine_art_slice.gd
## 输出：user://shot_quarantine_art_slice.png


const STAIR_TEXTURE := preload("res://assets/maps/quarantine_slice/industrial_stair_modules.png")
const SCANNER_TEXTURE := preload("res://assets/maps/quarantine_slice/quarantine_scanner.png")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# 分层与正式关卡一致：背景 < 地标 < 血迹 < 玩法 < 前景 < 标注。
	var stage := BackgroundSlice.new()
	stage.z_index = 0
	get_root().add_child(stage)

	var scanner := Sprite2D.new()
	scanner.texture = SCANNER_TEXTURE
	scanner.centered = false
	scanner.position = Vector2(374, 188)
	scanner.z_index = 1
	stage.add_child(scanner)

	# 直接复用正式 BloodWallManager 与 blood_wall shader，不以纯色块冒充验证。
	var blood_manager := BloodWallManager.new()
	blood_manager.name = "BloodWallManager"
	blood_manager.z_index = 2
	stage.add_child(blood_manager)
	await process_frame
	# 三枚无遮挡大样本用于判断实际战斗可读性；正式血液参数保持不变。
	blood_manager.spawn_snapshot(Vector2(150, 205), Vector2(1.0, 0.08), 0.90,
		2, false, 0.62, Color("#ff4fa3"))
	blood_manager.spawn_snapshot(Vector2(485, 350), Vector2(1.0, -0.06), 0.88,
		4, false, 0.68, Color("#43e8ff"))
	blood_manager.spawn_snapshot(Vector2(1125, 235), Vector2(1.0, 0.10), 0.90,
		5, false, 0.56, Color("#ffb347"))
	# 额外青色样本跨过纯黑门洞边界，只检查暗区剔除是否清掉门洞部分。
	blood_manager.spawn_snapshot(Vector2(990, 300), Vector2(1.0, 0.03), 0.66,
		1, false, 0.68, Color("#43e8ff"))

	var gameplay := GameplaySlice.new()
	gameplay.z_index = 4
	stage.add_child(gameplay)

	# 右上行模块只截取母版；第二 cell 是严格像素镜像的左上行版本。
	var stair := Sprite2D.new()
	stair.texture = STAIR_TEXTURE
	stair.region_enabled = true
	stair.region_rect = Rect2(0, 0, 416, 288)
	stair.centered = false
	# 局部行走面 240/64 精确对应世界 624/448。
	stair.position = Vector2(700, 384)
	stair.z_index = 4
	stage.add_child(stair)

	var foreground := ForegroundSlice.new()
	foreground.z_index = 10
	stage.add_child(foreground)

	_add_label(stage, "协议检疫站 / 楼梯与战斗空间纵向切片",
		Vector2(36, 28), 20, Color("#aabdc8"))
	_add_label(stage, "正式 blood_wall shader · 青色样本跨纯黑门洞",
		Vector2(885, 126), 13, Color("#86aab2"))
	_add_label(stage, "镜头级地标 512×320（非 Tile 单件）",
		Vector2(474, 493), 13, Color("#8ba2ad"))

	for _i in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var path := "user://shot_quarantine_art_slice.png"
	var err := image.save_png(path)
	print("检疫设施纵切截图 -> ", ProjectSettings.globalize_path(path), " err=", err)
	print("RENDER_RESULT: ", "PASS" if err == OK else "FAIL")
	quit(0 if err == OK else 1)


func _add_label(parent: Node, text: String, position: Vector2,
		font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = color
	label.z_index = 20
	parent.add_child(label)


## z0：中暗蓝灰墙、纯黑门洞及固定建筑背景。
class BackgroundSlice extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1360, 765), Color("#0c121d"))
		draw_rect(Rect2(0, 74, 1360, 612), Color("#172231"))
		for rect in [
			Rect2(22, 116, 146, 446), Rect2(187, 90, 102, 472),
			Rect2(1070, 104, 116, 458), Rect2(1206, 142, 126, 420),
		]:
			draw_rect(rect, Color("#111b29"))

		# 主附着面避开线性暗区阈值，暗感由凹槽和虚空承担。
		draw_rect(Rect2(78, 104, 1204, 520), Color("#31414f"))
		draw_rect(Rect2(92, 118, 1176, 492), Color("#3f5262"))
		draw_rect(Rect2(92, 119, 1176, 5), Color("#667c8a"))
		draw_rect(Rect2(92, 586, 1176, 24), Color("#202c3a"))
		for x in [174, 346, 902, 1088, 1192]:
			draw_line(Vector2(x, 124), Vector2(x, 585), Color("#2b3946"), 3)
			draw_line(Vector2(x + 3, 124), Vector2(x + 3, 585), Color("#526776"), 1)

		draw_rect(Rect2(112, 150, 224, 160), Color("#31414f"))
		draw_rect(Rect2(124, 162, 200, 136), Color("#435666"))
		for y in [188, 225, 262]:
			draw_line(Vector2(125, y), Vector2(323, y), Color("#2c3e4c"), 2)

		# 纯黑门洞低于 darkness_threshold，供真实 shader 跨边界对照。
		draw_rect(Rect2(1000, 154, 112, 270), Color("#161f2a"))
		draw_rect(Rect2(1008, 162, 96, 262), Color("#020407"))
		draw_rect(Rect2(1015, 174, 6, 238), Color("#0a1018"))

		# 左侧检疫管线构成次级引导。
		draw_rect(Rect2(135, 323, 26, 263), Color("#162431"))
		draw_rect(Rect2(141, 328, 8, 252), Color("#39808b"))
		draw_rect(Rect2(151, 328, 4, 252), Color("#214854"))
		for y in [346, 426, 506]:
			draw_rect(Rect2(128, y, 40, 11), Color("#1b2936"))
			draw_rect(Rect2(133, y + 2, 30, 4), Color("#607780"))

		# 极简空间标识保持在背景层。
		draw_rect(Rect2(108, 536, 112, 28), Color("#17232e"))
		draw_rect(Rect2(114, 542, 58, 6), Color("#37a9ad"))
		draw_rect(Rect2(114, 552, 88, 4), Color("#637885"))


## z4：平台、掩体和真实玩法尺度参照。
class GameplaySlice extends Node2D:
	func _draw() -> void:
		# 上平台从 x=1100、y=448 开始，承接第 12 块踏板末端。
		draw_rect(Rect2(1100, 448, 260, 18), Color("#111b27"))
		draw_rect(Rect2(1100, 448, 260, 4), Color("#8295a0"))
		draw_rect(Rect2(1100, 466, 260, 158), Color("#202e3c"))
		for x in range(1110, 1350, 32):
			draw_rect(Rect2(x, 470, 3, 142), Color("#2f4350"))

		# 下平台 y=640；第一踏板行走面从边缘上抬到 y=624。
		draw_rect(Rect2(0, 640, 716, 125), Color("#131c29"))
		draw_rect(Rect2(0, 640, 716, 5), Color("#9a8aa1"))
		draw_rect(Rect2(0, 645, 716, 5), Color("#493c56"))
		for x in range(20, 700, 96):
			draw_rect(Rect2(x, 674, 70, 36), Color("#202c38"))
			draw_line(Vector2(x + 6, 680), Vector2(x + 64, 680), Color("#334552"), 2)

		draw_rect(Rect2(256, 591, 94, 49), Color("#18232f"))
		draw_rect(Rect2(262, 598, 82, 42), Color("#3a4b57"))
		draw_rect(Rect2(266, 602, 74, 4), Color("#5d727c"))
		draw_rect(Rect2(277, 620, 8, 8), Color("#dfa748"))
		draw_rect(Rect2(322, 620, 8, 8), Color("#dfa748"))

		_draw_player_scale(Vector2(520, 640))
		_draw_enemy_scale(Vector2(630, 640))
		draw_string(ThemeDB.fallback_font, Vector2(824, 704), "12 rises / 32×16",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#94aab5"))


	func _draw_player_scale(feet: Vector2) -> void:
		# 约 94px 视觉轮廓，对应 22×52px 移动碰撞框。
		draw_circle(feet + Vector2(0, -76), 16, Color("#d8e4ec"))
		draw_polygon(PackedVector2Array([
			feet + Vector2(-14, -66), feet + Vector2(15, -66),
			feet + Vector2(21, -21), feet + Vector2(10, -4),
			feet + Vector2(-11, -4), feet + Vector2(-20, -24),
		]), PackedColorArray([Color("#274c6a")]))
		draw_line(feet + Vector2(10, -58), feet + Vector2(36, -22), Color("#b47a55"), 7)
		draw_rect(Rect2(feet + Vector2(-11, -52), Vector2(22, 52)),
			Color("#5fe6df"), false, 2)
		draw_string(ThemeDB.fallback_font, feet + Vector2(-30, 20), "凯露尔 22×52",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#93d9d5"))


	func _draw_enemy_scale(feet: Vector2) -> void:
		# 敌人视觉轮廓保持约 94px；44×96px 框用于占位与通路检查。
		draw_circle(feet + Vector2(0, -76), 17, Color("#222d3d"))
		draw_rect(Rect2(feet + Vector2(-20, -68), Vector2(40, 62)), Color("#253d62"))
		draw_rect(Rect2(feet + Vector2(-15, -70), Vector2(30, 7)), Color("#41cbcf"))
		draw_rect(Rect2(feet + Vector2(18, -58), Vector2(28, 8)), Color("#6d7781"))
		draw_rect(Rect2(feet + Vector2(-22, -96), Vector2(44, 96)),
			Color("#ef5b9f"), false, 2)
		draw_string(ThemeDB.fallback_font, feet + Vector2(-35, 20), "敌人 44×96",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e99abd"))


## z10：只在画面边缘出现的前景桥架和管线。
class ForegroundSlice extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 68, 1360, 24), Color("#0b111a"))
		for x in range(30, 1340, 120):
			draw_rect(Rect2(x, 73, 74, 8), Color("#26333d"))
		draw_polyline(PackedVector2Array([
			Vector2(0, 560), Vector2(62, 540), Vector2(112, 552),
			Vector2(176, 532), Vector2(226, 541),
		]), Color("#080d14"), 8)
		draw_polyline(PackedVector2Array([
			Vector2(1180, 765), Vector2(1208, 674), Vector2(1270, 642),
			Vector2(1360, 628),
		]), Color("#090e16"), 13)
