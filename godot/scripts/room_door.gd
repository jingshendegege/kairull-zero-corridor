extends Node2D
class_name RoomDoor
## M02 房门：数据塔房间之间的锁定门（武士零式清房开门）。
## position 锚点 = 门洞中心脚底（门洞 2 列宽 × 3 格高 = 64×96px；
## 地图 D 标记在门洞左格，game 创建时把锚点右移半格到中心）。
##
## 视觉构成（KZ 洋馆门 ≈1.5× 角色身高的门洞 + 贴在上方墙面上的高门框）：
##   门洞 64×96（碰撞只在锁定时生效，恰好覆盖 D 格起的 2×3 门洞）；
##   装饰门框：两侧壁柱 + 门洞上方过梁板 + 凸出门楣横梁，
##   总视觉高 200px ≈ 玩家（93.6px）的 2.14 倍——门框全画在墙面上，纯视觉。
##
## 锁定 ⇔ 所属房间还有活敌（game 每帧调 set_locked()）：
##   锁定 —— 暗门板 + 暗红边光 + 门楣红灯，碰撞挡住玩家/小怪（手动推出，
##           与玩家逐轴碰撞同语义：门体是 64px 宽竖板，只往两侧推）；
##   解锁 —— 门板 0.45s 沉入地面读作开门，品红/青边灯交替亮 + 门楣青灯
##           + 底部调地光，由 game 在锁定→解锁瞬间播一声高音金属响。
##
## 子弹封堵由 game 的 enemy_bullets 循环查 body_rect() 完成（锁定时挡子弹）。

const W := 64.0          ## 门洞宽 = 2 格
const H := 96.0          ## 门洞高 = 3 格
const FRAME_TOP := 200.0 ## 视觉总高（脚底 → 门楣顶），≈2.1× 玩家
const POST_W := 12.0     ## 侧壁柱宽（压在门洞两侧墙面上，纯视觉）
const LINTEL_H := 14.0   ## 门楣横梁厚
const LEAF_SINK_TIME := 0.45  ## 解锁门板沉地动画时长（秒）

var locked := true
var room_idx := -1        ## 所属房间（level.rooms 下标，game 注入）
var game: Node2D          ## game 注入：查房间活敌 / 播解锁音 / 推角色

var _phase := 0.0
var _leaf := 1.0          ## 门板剩余比例：1=全关 0=全开（沉入地面）


func body_rect() -> Rect2:
	return Rect2(position.x - W * 0.5, position.y - H, W, H)


## 视觉总高（含墙面上的门框/门楣），门人比例验收用
func visual_height() -> float:
	return FRAME_TOP


func _physics_process(_dt: float) -> void:
	if game == null:
		return
	# 锁定状态从所属房间活敌派生；锁定→解锁瞬间播一声高音金属响
	var alive: int = game.room_alive_count(room_idx)
	var want_locked := alive > 0   ## 房间无活敌（含无房 -1）→ 常开
	if want_locked != locked:
		locked = want_locked
		if not locked:
			game.play_sfx("wall", 1.6)   ## 解锁：金属回响升调读作门闩弹开
		queue_redraw()
	if not locked:
		return
	# 锁定时把嵌入门体的角色水平推出（门在 player/minions 之后创建，
	# 本函数在它们移动之后执行，与逐轴碰撞同帧序）
	push_out(game.player, game.player.w / 2.0, game.player.h)
	for m in game.minions:
		if is_instance_valid(m) and not m.dead:
			var br: Rect2 = m.body_rect()   ## 与小怪实际碰撞体一致（grunt 放大后不再硬编码）
			push_out(m, br.size.x * 0.5, br.size.y)


## 锁定时把嵌入门体的角色水平推出（玩家与小怪通用，逐帧调用）
func push_out(body: Node2D, half_w: float, height: float) -> void:
	if not locked:
		return
	var pr := Rect2(body.position.x - half_w, body.position.y - height,
			half_w * 2.0, height)
	var dr := body_rect()
	if not pr.intersects(dr):
		return
	# 推向更近的一侧，并清水平速度（与玩家撞墙同语义）
	if body.position.x < dr.get_center().x:
		body.position.x = dr.position.x - half_w - 0.1
	else:
		body.position.x = dr.end.x + half_w + 0.1
	if "vx" in body:
		body.vx = 0.0


func _process(dt: float) -> void:
	_phase += dt
	# 门板沉地/回弹动画（解锁沉下、回锁立起）
	var target := 1.0 if locked else 0.0
	if _leaf != target:
		_leaf = move_toward(_leaf, target, dt / LEAF_SINK_TIME)
	queue_redraw()


func _draw() -> void:
	var left := -W * 0.5          ## -32
	var top := -H                 ## -96
	var panel_top := -FRAME_TOP + LINTEL_H   ## 过梁板顶（门楣梁下沿）= -186
	var pulse := 0.5 + 0.5 * sin(_phase * 2.2)
	var red: Color = KZPalette.DOOR_LOCKED
	var mag: Color = KZPalette.NEON_MAGENTA
	var cyn: Color = KZPalette.NEON_CYAN

	# ---- 门洞底色：解锁后门洞读作近黑洞口（沉板动画期间也先垫黑）----
	if not locked:
		draw_rect(Rect2(left, top, W, H), Color("#0a0812"))
		draw_rect(Rect2(left + 4, top + 4, W - 8, H - 8), Color("#050410"))

	# ---- 门板（先画，侧柱/门楣压边）：解锁时沉入地面并淡出 ----
	if _leaf > 0.001:
		var sink := (1.0 - _leaf) * H
		var fade := clampf(_leaf * 1.6, 0.0, 1.0)   ## 沉到后 40% 开始淡出
		var c_body := Color(KZPalette.BG_BASE.r, KZPalette.BG_BASE.g,
				KZPalette.BG_BASE.b, fade)
		var c_face := Color(KZPalette.BG_WALL.r, KZPalette.BG_WALL.g,
				KZPalette.BG_WALL.b, fade)
		draw_rect(Rect2(left, top + sink, W, H - sink), c_body)
		draw_rect(Rect2(left + 4, top + sink + 4, W - 8,
				maxf(0.0, H - sink - 8)), c_face)
		# 门板中缝（双开门读法）+ 竖棱
		draw_line(Vector2(0, top + sink + 6), Vector2(0, -6),
				Color(KZPalette.FLOOR_BOTTOM.r, KZPalette.FLOOR_BOTTOM.g,
						KZPalette.FLOOR_BOTTOM.b, fade), 1.0)
		draw_line(Vector2(left + 10, top + sink + 6), Vector2(left + 10, -6),
				Color(KZPalette.FLOOR_BOTTOM.r, KZPalette.FLOOR_BOTTOM.g,
						KZPalette.FLOOR_BOTTOM.b, fade * 0.6), 1.0)
		draw_line(Vector2(-left - 10, top + sink + 6), Vector2(-left - 10, -6),
				Color(KZPalette.FLOOR_BOTTOM.r, KZPalette.FLOOR_BOTTOM.g,
						KZPalette.FLOOR_BOTTOM.b, fade * 0.6), 1.0)
		# 门把手小块（左右扇各一，随门板下沉）
		for hx in [-6.0, 2.0]:
			draw_rect(Rect2(Vector2(hx, top + sink + H * 0.55), Vector2(4, 6)),
					Color(KZPalette.RAIL.r, KZPalette.RAIL.g, KZPalette.RAIL.b, fade))

	# ---- 装饰门框（全画在墙面上，纯视觉；KZ 式高门框）----
	# 过梁板：门洞正上方、两侧柱之间的墙面嵌板
	draw_rect(Rect2(left, panel_top, W, panel_top * -1.0 + top), KZPalette.BG_WALL)
	draw_rect(Rect2(left + 2, panel_top + 2, W - 4, (panel_top * -1.0 + top) - 4.0),
			KZPalette.BG_PANEL)
	# 过梁板装饰横棱（两条细金属）
	draw_rect(Rect2(left + 6, panel_top + 22.0, W - 12, 2), KZPalette.RAIL)
	draw_rect(Rect2(left + 6, panel_top + 42.0, W - 12, 2), KZPalette.RAIL)
	# 侧壁柱：从过梁板顶一路落地，压在门洞两侧墙上
	for px in [left - POST_W, -left]:
		draw_rect(Rect2(px, panel_top, POST_W, -panel_top), KZPalette.WALL_PANEL)
		draw_rect(Rect2(px, panel_top, POST_W, 2), KZPalette.PIPE_HI)      ## 柱顶受光
		draw_rect(Rect2(px - 2, -10.0, POST_W + 4, 10.0),
				KZPalette.FLOOR_SIDE_DARK)                              ## 柱础
	# 门楣横梁（凸出、全场最高点）
	draw_rect(Rect2(left - POST_W - 2, -FRAME_TOP, W + POST_W * 2 + 4, LINTEL_H),
			KZPalette.FLOOR_SIDE)
	draw_rect(Rect2(left - POST_W - 2, -FRAME_TOP, W + POST_W * 2 + 4, 2),
			KZPalette.PIPE_HI)                                            ## 楣顶受光
	draw_rect(Rect2(left - POST_W - 2, -FRAME_TOP + LINTEL_H - 2,
			W + POST_W * 2 + 4, 2), KZPalette.FLOOR_BOTTOM)               ## 楣底阴缝
	# 门楣中央状态灯：锁定红 / 解锁青
	var lamp := red if locked else cyn
	var lamp_a := 0.35 + 0.45 * pulse if locked else 0.45 + 0.45 * pulse
	draw_rect(Rect2(Vector2(-4, -FRAME_TOP + 3), Vector2(8, 8)),
			Color(lamp.r, lamp.g, lamp.b, lamp_a))
	draw_rect(Rect2(Vector2(-2, -FRAME_TOP + 5), Vector2(4, 4)),
			Color(lamp.r, lamp.g, lamp.b, minf(1.0, lamp_a + 0.3)))

	# ---- 门洞边灯（锁定红 dim / 解锁品红+青）----
	if locked:
		var glow := 0.22 + 0.20 * pulse
		draw_rect(Rect2(left - 1, top, 2, H), Color(red.r, red.g, red.b, glow))
		draw_rect(Rect2(left + W - 1, top, 2, H), Color(red.r, red.g, red.b, glow))
		draw_rect(Rect2(left - 3, top, 2, H), Color(red.r, red.g, red.b, glow * 0.3))
		draw_rect(Rect2(left + W + 1, top, 2, H),
				Color(red.r, red.g, red.b, glow * 0.3))
	else:
		var a := 0.45 + 0.45 * pulse
		# 左右边灯交替呼吸（品红左 / 青右，错半拍）
		draw_rect(Rect2(left - 2, top, 2, H), Color(mag.r, mag.g, mag.b, a))
		draw_rect(Rect2(left + W, top, 2, H), Color(cyn.r, cyn.g, cyn.b, 0.9 - a + 0.45))
		draw_rect(Rect2(left - 4, top, 2, H), Color(mag.r, mag.g, mag.b, a * 0.25))
		draw_rect(Rect2(left + W + 2, top, 2, H), Color(cyn.r, cyn.g, cyn.b, a * 0.2))
		# 门楣下沿灯（青）
		draw_rect(Rect2(left - 2, top - 2, W + 4, 2), Color(cyn.r, cyn.g, cyn.b, a * 0.8))
		# 底部调地光：青色薄晕
		draw_rect(Rect2(left - 10, -4, W + 20, 5),
				Color(cyn.r, cyn.g, cyn.b, 0.08 + 0.08 * pulse))
