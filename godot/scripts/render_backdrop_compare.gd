extends SceneTree
## 素净版 vs 现行版 墙面对比 demo（纯展示，不进项目主线）
## 跑法：godot --path godot --rendering-driver opengl3 --script scripts/render_backdrop_compare.gd

const W := 680.0
const H := 380.0

var t := 0.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root := get_root()
	var stage := Node2D.new()
	root.add_child(stage)

	# ── 左：素净版（模仿用户参考图）──
	var left := MinimalWall.new()
	left.position = Vector2(10, 10)
	left.size = Vector2(W, H)
	stage.add_child(left)

	# ── 右：现行 KZ 风格 0 ──
	var right := WallBackdrop.new()
	right.position = Vector2(W + 30, 10)
	right.level = _fake_level()
	stage.add_child(right)

	# 标签
	var lbl := Label.new()
	lbl.text = "MINIMAL (ref)          |          CURRENT (KZ style0)"
	lbl.position = Vector2(20, 5)
	lbl.add_theme_font_size_override("font_size", 14)
	stage.add_child(lbl)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var dir := OS.get_environment("USERPROFILE") + "/AppData/Local/Temp"
	img.save_png(dir + "/backdrop_compare.png")
	print("SAVED: " + dir + "/backdrop_compare.png")
	quit(0)


func _fake_level() -> CorridorLevel:
	var lv := CorridorLevel.new()
	lv.rooms = [{"name": "demo", "rect": Rect2i(1, 1, 20, 11)}]
	return lv


## 素净版墙：整体压暗、单色系、极少元素、大块留白
class MinimalWall extends Node2D:
	var size := Vector2.ZERO

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# 1 大面深灰蓝底（低饱和、低明度，参考图主色 #232833 附近）
		draw_rect(Rect2(0, 0, w, h), Color("#20242e"))
		# 2 极淡面板变化：每 160px 一档，明度差 <3%（几乎看不出但有呼吸）
		var px := 0.0
		var i := 0
		while px < w:
			var pw := minf(160.0, w - px)
			if i % 2 == 1:
				draw_rect(Rect2(px, 0, pw, h), Color(0.0, 0.0, 0.01, 0.10))
			px += 160.0
			i += 1
		# 3 唯一的竖缝组：每 320px 一条 1px 暗缝 + 右侧 1px 微亮（不密集）
		var vx := 160.0
		while vx < w - 20.0:
			draw_line(Vector2(vx, 0), Vector2(vx, h), Color("#1a1e26"), 1.0)
			draw_line(Vector2(vx + 1, 0), Vector2(vx + 1, h), Color("#262b36"), 1.0)
			vx += 320.0
		# 4 一扇暗门（唯一重复元素，参考图：等距木门但更暗更素）
		var dx := 220.0
		draw_rect(Rect2(dx - 4, h - 120.0, 70.0, 120.0), Color("#191d25"))
		draw_rect(Rect2(dx, h - 116.0, 62.0, 116.0), Color("#232830"))
		# 5 一盏几乎不发光的灯罩（参考图：KZ 灯几乎不发光）
		draw_rect(Rect2(430, 36, 20, 8), Color("#14181f"))
		draw_rect(Rect2(433, 44, 14, 3), Color("#0e1116"))
		# 6 底部墙裙（一条 12px 深带 + 1px 分界）
		draw_rect(Rect2(0, h - 12.0, w, 12.0), Color("#191422"))
		draw_line(Vector2(0, h - 12.0), Vector2(w, h - 12.0), Color("#120e1a"), 1.0)
		# 7 四角暗角（两层）
		for c in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
			var sx := -1.0 if c.x > 0 else 1.0
			var sy := -1.0 if c.y > 0 else 1.0
			draw_rect(Rect2(c.x if sx > 0 else c.x - 50.0,
					c.y if sy > 0 else c.y - 50.0, 50.0, 50.0),
					Color(0.0, 0.0, 0.0, 0.18))
		# 8 点睛：一处极小的暖光（参考图唯一暖色来源，极低饱和）
		draw_rect(Rect2(436, 47, 8, 3), Color(0.85, 0.72, 0.5, 0.35))
