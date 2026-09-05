extends Node2D
class_name WallBackdrop
## M02 室内墙面 backdrop：房间矩形内的程序化墙板填充（武士零式"密而暗"的室内墙）。
## 只画房间内部；房间外的虚空仍由 GameBackground 的极暗平涂/渐变兜底。
##
## 结构（对照武士零工厂内饰参考图）：
##   底色（按楼层染色：F1 冷蓝紫 / F2 暗绿 / F3 暗红，全部重去饱和）
##   → 2 格一组的墙板竖缝 + 板缝右 1px 受光边 +  mid 高度水平缝
##   → 每 ~9 格一根竖向壁柱（略亮一档，带暗边）
##   → 40% 高度处楼层色带腰线（F2 绿 / F3 红 / F1 冷蓝，低明度）
##   → 房间底部 10px 踢脚线带 + 顶端 1px 受光
##   → 四角暗角（两层叠加的近黑透明块，武士零式房间角落压暗）
## 明度铁律：所有用色 < KZPalette.WALL_PANEL（玩法墙），
## test_m02_tower.gd 的明度阶梯断言守着这条线。
##
## 绘制在 bg 之后、TileMapLayer 之前（game 用 move_child 保证顺序），
## 实心 tiles 天然盖住 backdrop 被楼板/墙占住的部分，无需逐格抠空。

const TS := 32

var level: CorridorLevel


## 世界坐标点是否落在任一房间 backdrop 覆盖区（测试与潜在特效查询用）
func has_backdrop_at(wx: float, wy: float) -> bool:
	if level == null:
		return false
	var cell := Vector2i(floori(wx / TS), floori(wy / TS))
	for room in level.rooms:
		if (room["rect"] as Rect2i).has_point(cell):
			return true
	return false


func _draw() -> void:
	if level == null:
		return
	for room in level.rooms:
		_draw_room(room["rect"] as Rect2i)


## 楼层序号：0=F1（rect 顶 r≥16） 1=F2（r≥8） 2=F3（其余）
static func floor_index_of(rect: Rect2i) -> int:
	if rect.position.y >= 16:
		return 0
	if rect.position.y >= 8:
		return 1
	return 2


func _draw_room(rect: Rect2i) -> void:
	var x0 := float(rect.position.x * TS)
	var y0 := float(rect.position.y * TS)
	var w := float(rect.size.x * TS)
	var h := float(rect.size.y * TS)
	var fi := floor_index_of(rect)
	var base: Color = [KZPalette.BACKDROP_F1, KZPalette.BACKDROP_F2,
			KZPalette.BACKDROP_F3][fi]
	var band: Color = [KZPalette.BAND_F1, KZPalette.BAND_F2,
			KZPalette.BAND_F3][fi]

	# 底色
	draw_rect(Rect2(x0, y0, w, h), base)

	# 墙板竖缝：每 2 格一条暗缝 + 右侧 1px 受光边（板与板的拼接感）
	var px := x0 + 64.0
	while px < x0 + w:
		draw_line(Vector2(px, y0), Vector2(px, y0 + h), KZPalette.BACKDROP_SEAM, 1.0)
		draw_line(Vector2(px + 1, y0), Vector2(px + 1, y0 + h), KZPalette.BACKDROP_HI, 1.0)
		px += 64.0
	# 水平板缝：mid 高度一条
	var my := y0 + h * 0.5
	draw_line(Vector2(x0, my), Vector2(x0 + w, my), KZPalette.BACKDROP_SEAM, 1.0)
	draw_line(Vector2(x0, my + 1), Vector2(x0 + w, my + 1), KZPalette.BACKDROP_HI, 1.0)

	# 竖向壁柱：距房左 4 格起每 9 格一根（10px 宽略亮带 + 两侧暗边）
	px = x0 + 4.0 * TS
	while px < x0 + w - 12.0:
		draw_rect(Rect2(px, y0, 10.0, h), KZPalette.BACKDROP_PILASTER)
		draw_line(Vector2(px, y0), Vector2(px, y0 + h), KZPalette.BACKDROP_SEAM, 1.0)
		draw_line(Vector2(px + 10, y0), Vector2(px + 10, y0 + h),
				KZPalette.BACKDROP_SEAM, 1.0)
		px += 9.0 * TS

	# 楼层色带腰线：40% 高度处 5px 横带 + 上下各 1px 暗缝（F2 绿 / F3 红调识别）
	var by := y0 + h * 0.4
	draw_rect(Rect2(x0, by, w, 5.0), band)
	draw_line(Vector2(x0, by - 1), Vector2(x0 + w, by - 1), KZPalette.BACKDROP_SEAM, 1.0)
	draw_line(Vector2(x0, by + 5), Vector2(x0 + w, by + 5), KZPalette.BACKDROP_SEAM, 1.0)

	# 踢脚线带：房间底部 10px（楼板亮顶沿之下的墙裙）
	draw_rect(Rect2(x0, y0 + h - 10.0, w, 10.0), KZPalette.BACKDROP_BASEBOARD)
	draw_line(Vector2(x0, y0 + h - 10.0), Vector2(x0 + w, y0 + h - 10.0),
			KZPalette.BACKDROP_HI, 1.0)

	# 四角暗角：两层叠加近黑透明块（外大内小，越靠角越暗）
	var dark := Color(0.03, 0.02, 0.06, 0.22)
	var dark2 := Color(0.02, 0.015, 0.05, 0.22)
	for cx in [x0, x0 + w]:
		for cy in [y0, y0 + h]:
			var sx := -1.0 if cx > x0 else 1.0
			var sy := -1.0 if cy > y0 else 1.0
			draw_rect(Rect2(cx if sx > 0 else cx - 56.0, cy if sy > 0 else cy - 56.0,
					56.0, 56.0), dark)
			draw_rect(Rect2(cx if sx > 0 else cx - 30.0, cy if sy > 0 else cy - 30.0,
					30.0, 30.0), dark2)
