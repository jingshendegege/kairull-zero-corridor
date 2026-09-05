extends SceneTree
## 专用真窗口对照，不进入正式游戏：旧翻滚只改展示节点，不回写生产参数或原图。

const OUT_DIR := "C:/Users/Administrator/Documents/Codex/2026-09-04/windows-godot-4-7-d-hermesprojects/outputs/mobility-collision-20260905"
var _db: AtlasDB
var _players: Array[KairullPlayer] = []


class CompareBoard extends Node2D:
	var font: SystemFont
	var boxes: Array[Dictionary] = []
	var captions: Array[Dictionary] = []
	var draw_boxes := true

	func _init() -> void:
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
		font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]

	func text_at(text: String, at: Vector2, size: int, color: Color) -> void:
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

	func _draw() -> void:
		var muted := Color("9faebb")
		var pale := Color("e0f0f2")
		text_at("翻滚体型 / 受击框", Vector2(36, 48), 30, pale)
		text_at("同一原图 · 六帧顺序不变 · 原生游戏比例 · 真窗口渲染", Vector2(38, 78), 17, muted)
		text_at("调整前", Vector2(36, 135), 23, Color("efba71"))
		text_at("翻滚 0.400  /  原统一判定 22 × 52", Vector2(150, 135), 18, muted)
		text_at("调整后", Vector2(36, 388), 23, Color("64dbe8"))
		text_at("翻滚 0.328  /  站立 34 × 82  /  翻滚 38 × 34", Vector2(150, 388), 18, muted)
		for base in [290.0, 543.0]:
			draw_line(Vector2(36, base), Vector2(1324, base), Color("46616d"), 1)
			draw_line(Vector2(36, base + 42), Vector2(1324, base + 42), Color("243a44"), 1)
		for item in captions:
			var label: String = item.text
			var center: Vector2 = item.at
			text_at(label, center - Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x / 2, 0), 15, muted)
		for item in boxes:
			var foot: Vector2 = item.foot
			draw_line(foot - Vector2(4, 0), foot + Vector2(4, 0), Color("dcecd9"), 2)
			if draw_boxes:
				var box: Rect2 = item.box
				var color: Color = item.color
				draw_rect(box, Color(color, 0.075), true)
				draw_rect(box, color, false, 1)
		text_at("白色短线 = 同一脚底锚点；框线仅用于此对照，不会显示在正式游戏。", Vector2(38, 626), 18, pale)
		text_at("站立仍为 0.400。翻滚六帧统一缩小 18%，起身不再比站立大一圈。", Vector2(38, 660), 18, muted)
		text_at("翻滚仍为 6 格 / 约 0.33 秒；低矮受击框不改变 22 × 52 的地图通行碰撞。", Vector2(38, 692), 18, muted)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("必须使用真实渲染窗口，禁止 headless 截图代替视觉验收")
		quit(1)
		return
	root.title = "凯露尔 / 翻滚体型与受击框验收"
	root.size = Vector2i(1360, 765)
	root.content_scale_size = Vector2i(1360, 765)
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color("101d27"))
	_db = AtlasDB.new("res://assets/clips", ["res://assets/clips/bat/bat_atlas.json", "res://assets/clips/hero/hero_atlas.json"])
	var board := CompareBoard.new()
	board.z_index = 100
	root.add_child(board)
	for row in range(2):
		var y := 290.0 + row * 253.0
		for col in range(7):
			var x := 110.0 if col == 0 else 335.0 + (col - 1) * 180.0
			var player := KairullPlayer.new()
			player.auto_input = false
			player.db = _db
			player.spawn = Vector2(x, y)
			root.add_child(player)
			_players.append(player)
			var rolling := col != 0
			var clip := "hero_roll" if rolling else "hero_idle"
			player.state = "roll" if rolling else "gun_idle"
			player._apply_sprite(clip, col - 1 if rolling else 0)
			# 旧版仅在隔离展示节点上复现；原图/RAW_SCALE 和碰撞代码绝不改写。
			if row == 0 and rolling:
				player._sprite.scale = Vector2.ONE * 0.4
				player._sprite.global_position = (player.position - Vector2(256, 500) * 0.4).round()
				player._sync_readability()
			player._halo.visible = false
			var box := Rect2(player.position - Vector2(11, 52), Vector2(22, 52)) if row == 0 else player.hurtbox_rect()
			board.boxes.append({"foot": player.position, "box": box, "color": Color("efba71") if row == 0 else Color("64dbe8")})
			board.captions.append({"text": "站立参考" if col == 0 else "第 %d 帧" % col, "at": Vector2(x, y + 28)})
	board.queue_redraw()
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var first := OUT_DIR + "/翻滚体型与受击框-真窗口对照.png"
	var first_error := root.get_texture().get_image().save_png(first)
	print("SHOT ", first, " ERROR=", first_error)
	board.draw_boxes = false
	board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var second := OUT_DIR + "/翻滚体型-无判定框对照.png"
	var second_error := root.get_texture().get_image().save_png(second)
	print("SHOT ", second, " ERROR=", second_error)
	for player in _players:
		player.free()
	_players.clear()
	board.free()
	_db = null
	await process_frame
	print("MOBILITY_COMPARE_RENDER_RESULT: ", "PASS" if first_error == OK and second_error == OK else "FAIL")
	quit(0 if first_error == OK and second_error == OK else 1)
