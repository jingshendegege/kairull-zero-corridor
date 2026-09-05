extends Node2D
class_name PropBarrel
## 爆炸桶（武士零式场景互动物件）：20×28 像素油桶，程序绘制，无外部素材。
## 接口与敌人一致：body_rect() / take_hit() / dead，由 game 统一调度。
## 任意命中（棍击判定盒、枪手子弹）→ 0.35s 白热频闪引信 → exploded 信号。
## 爆炸效果（液爆/杀伤半径/连锁/震屏/污渍/音效）全部在 game 侧处理，
## 本节点只管自身状态机与绘制。连锁通过 take_hit(from_x, dmg, fuse_delay)
## 传入短引信实现错峰引爆。
## position 锚点 = 脚底中心（与地图标记 feet 语义一致）。

signal exploded(barrel: PropBarrel)

const W := 20.0
const H := 28.0
const FUSE_TIME := 0.35        ## 默认引信（白热频闪窗口）
const KILL_RADIUS := 110.0     ## 爆炸杀伤/连锁半径（game 侧使用）
const CHAIN_FUSE := 0.10       ## 连锁桶引信（≈6 tick 错峰）

var dead := false
var fusing := false
var fuse_t := 0.0
var _phase := 0.0              ## 环境光呼吸相位


func body_rect() -> Rect2:
	return Rect2(position.x - W * 0.5, position.y - H, W, H)


## fuse_delay ≥0 时覆盖默认引信（连锁错峰用）。已在引信中/已炸则忽略。
func take_hit(_from_x: float, _damage := 1, fuse_delay := -1.0) -> bool:
	if dead or fusing:
		return false
	fusing = true
	fuse_t = fuse_delay if fuse_delay >= 0.0 else FUSE_TIME
	queue_redraw()
	return true


func step(dt: float) -> void:
	if dead:
		return
	_phase += dt
	if fusing:
		fuse_t -= dt
		if fuse_t <= 0.0:
			dead = true
			fusing = false
			exploded.emit(self)
	queue_redraw()


func _draw() -> void:
	if dead:
		return
	var left := -W * 0.5
	var top := -H
	# 暖琥珀环境光晕：让桶在繁忙霓虹背景里跳出来（慢呼吸）
	var glow_a := 0.16 + 0.07 * sin(_phase * 2.4)
	draw_circle(Vector2(0, top + H * 0.5), 26.0, Color(1.0, 0.62, 0.18, glow_a))
	draw_circle(Vector2(0, top + H * 0.5), 17.0, Color(1.0, 0.55, 0.14, glow_a * 0.8))
	# 桶体：暗红锈铁
	var body_col := Color("#6b2a26")
	var rim_col := Color("#40191a")
	if fusing:
		# 白热频闪：引信期间高频向白色冲
		var k: float = 0.5 + 0.5 * sin(_phase * 60.0)
		body_col = body_col.lerp(Color(1.0, 0.98, 0.9), k * 0.9)
		rim_col = rim_col.lerp(Color(1.0, 0.95, 0.8), k * 0.8)
	# 外轮廓（1px 深色描边，像素感）
	draw_rect(Rect2(left - 1, top - 1, W + 2, H + 2), Color("#170d12"))
	draw_rect(Rect2(left, top, W, H), body_col)
	# 上下桶箍
	draw_rect(Rect2(left, top, W, 4), rim_col)
	draw_rect(Rect2(left, top + H - 4, W, 4), rim_col)
	# 中部警示带：琥珀底 + 黑色斜纹（2px 像素块）
	draw_rect(Rect2(left, top + 11, W, 7), Color("#e8a33d") if not fusing
			else Color(1.0, 0.9, 0.6))
	for i in range(0, int(W), 4):
		draw_rect(Rect2(left + i, top + 12, 2, 5), Color("#241016"))
	# 桶身高光（左侧 2px 亮条）
	draw_rect(Rect2(left + 2, top + 4, 2, H - 8), Color(1.0, 0.75, 0.55, 0.22))
