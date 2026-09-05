extends Node2D
class_name ExitDoor
## 塔门出口视觉：程序绘制的暗色门洞 + 慢脉冲青色描边光。
## 纯视觉节点；玩家重叠 → 过关流程由 game 判定（body_rect 相交）。
## position 锚点 = 门口地面中心（与 > 标记 feet 语义一致）。
## 尺寸故意高过玩家（92px）：玩家站在门里时门楣与侧柱仍露出，
## 底部有青色调地光，繁忙霓虹背景里也能一眼认出"这是出口"。

const W := 44.0
const H := 92.0

## 过关触发区：门宽 × 2 格门洞脚高（64px），底边贴在门口地面层。
## 不用 92px 全高视觉体做判定：旧区向上探出 ≈3 格（顶沿距上方 = 台面
## 平面仅 4px），脚不在门口地面层的玩家会被隔空判定过关（playtest round4）。
const TRIGGER_W := 44.0
const TRIGGER_H := 64.0

var _phase := 0.0

## 清场闸门状态（game 每帧写入）：true = 出口锁定（暗红边光 + 门楣红灯，
## 触发区不放行）；false = 解锁（青色呼吸描边 + 门楣青灯）。默认 false，
## 未开闸门的关卡视觉与旧版完全一致。
var locked := false


func body_rect() -> Rect2:
	return Rect2(position.x - W * 0.5, position.y - H, W, H)


## 过关判定区（game._physics_process 用）：玩家必须真的站在门口地面层
func trigger_rect() -> Rect2:
	return Rect2(position.x - TRIGGER_W * 0.5, position.y - TRIGGER_H,
			TRIGGER_W, TRIGGER_H)


func _process(dt: float) -> void:
	_phase += dt
	queue_redraw()


func _draw() -> void:
	var left := -W * 0.5
	var top := -H
	# 慢脉冲（武士零式冷光呼吸）
	var pulse := 0.5 + 0.5 * sin(_phase * 1.8)
	# 锁定时切 RoomDoor 同款暗红语言（DOOR_LOCKED）；解锁维持青色冷光
	var edge := Color("#7ec8ff")
	if locked:
		edge = KZPalette.DOOR_LOCKED
	# 底部调地光：薄晕，玩家站位时从脚下透出（锁定红色 / 解锁青色）
	draw_rect(Rect2(left - 16, -6, W + 32, 8),
			Color(edge.r, edge.g, edge.b, 0.10 + 0.10 * pulse))
	# 门洞：近黑竖井，内嵌一层更暗
	draw_rect(Rect2(left, top, W, H), Color("#0a0812"))
	draw_rect(Rect2(left + 3, top + 3, W - 6, H - 3), Color("#050410"))
	# 门内微弱环境光（底部一点点，像远处的光漏进来；锁定时不漏光读作封闭）
	if not locked:
		draw_rect(Rect2(left + 3, -16, W - 6, 13),
				Color(0.2, 0.5, 0.7, 0.10 + 0.08 * pulse))
	# 门框：深色门柱
	draw_rect(Rect2(left - 5, top - 5, 5, H + 5), Color("#191325"))
	draw_rect(Rect2(left + W, top - 5, 5, H + 5), Color("#191325"))
	draw_rect(Rect2(left - 5, top - 5, W + 10, 5), Color("#191325"))
	# 霓虹描边：左右柱 + 门楣，脉冲呼吸 + 外晕（锁定时整体压暗一档）
	var glow := 0.35 + 0.45 * pulse
	if locked:
		glow = 0.18 + 0.18 * pulse
	var ec := Color(edge.r, edge.g, edge.b, glow)
	var ec_soft := Color(edge.r, edge.g, edge.b, glow * 0.30)
	var ec_halo := Color(edge.r, edge.g, edge.b, glow * 0.12)
	draw_rect(Rect2(left - 6, top - 4, 2, H + 4), ec_halo)
	draw_rect(Rect2(left + W + 4, top - 4, 2, H + 4), ec_halo)
	draw_rect(Rect2(left - 4, top - 3, 2, H + 3), ec_soft)
	draw_rect(Rect2(left + W + 2, top - 3, 2, H + 3), ec_soft)
	draw_rect(Rect2(left - 2, top - 2, 2, H + 2), ec)
	draw_rect(Rect2(left + W, top - 2, 2, H + 2), ec)
	draw_rect(Rect2(left - 2, top - 2, W + 4, 2), ec)
	draw_rect(Rect2(left - 4, top - 3, W + 8, 1), ec_soft)
	# 门楣中央状态灯（RoomDoor 同款读法）：锁定红 / 解锁青；解锁时错半拍叠品红
	var lamp_a := (0.18 + 0.18 * pulse) if locked else (0.45 + 0.45 * pulse)
	draw_rect(Rect2(Vector2(-4, top - 11), Vector2(8, 8)),
			Color(edge.r, edge.g, edge.b, lamp_a))
	draw_rect(Rect2(Vector2(-2, top - 9), Vector2(4, 4)),
			Color(edge.r, edge.g, edge.b, minf(1.0, lamp_a + 0.3)))
	if not locked:
		var mag := KZPalette.NEON_MAGENTA
		draw_rect(Rect2(left - 2, top - 4, W + 4, 1),
				Color(mag.r, mag.g, mag.b, 0.5 + 0.4 * (1.0 - pulse)))
