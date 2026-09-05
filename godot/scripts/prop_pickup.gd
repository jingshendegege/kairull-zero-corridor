extends Node2D
class_name PropPickup
## M03 拾取件：录音带 K / USB 数据件 U。
## 程序绘制 + 浮动呼吸；玩家靠近由 game 判定距离后调 take()。
## 调色纪律：tape 用 KZPalette.AMBER（暖标签光），usb 用青白（CRT_GLOW 系
## —— 数据件呼应 CRT 背光叙事："USB 里是玩家自己的过去"）。
## 亮度压在玩法层之下：拾取件是静置目标，不与角色/信号色抢眼。

const KIND_TAPE := "tape"
const KIND_USB := "usb"

var kind := KIND_TAPE
var taken := false
var _phase := 0.0


func _init(k := KIND_TAPE) -> void:
	kind = k


func _process(dt: float) -> void:
	if taken:
		return
	_phase += dt
	queue_redraw()


func _draw() -> void:
	var float_y := sin(_phase * 2.2) * 3.0 - 6.0   ## 悬浮 + 呼吸，底缘离地
	var pulse := 0.5 + 0.5 * sin(_phase * 3.0)
	if kind == KIND_TAPE:
		_draw_tape(float_y, pulse)
	else:
		_draw_usb(float_y, pulse)
	# 落点接触阴影（武士零式：地面小椭圆暗斑）
	draw_rect(Rect2(-7, -2, 14, 2), Color(0.0, 0.0, 0.0, 0.30))


func _draw_tape(fy: float, pulse: float) -> void:
	# 暖标签微光晕（AMBER，低 alpha）
	draw_rect(Rect2(-14, fy - 10, 28, 24),
			Color(KZPalette.AMBER.r, KZPalette.AMBER.g, KZPalette.AMBER.b, 0.10 + 0.08 * pulse))
	# 磁带盒
	draw_rect(Rect2(-10, fy - 6, 20, 13), Color("#1a1622"))
	draw_rect(Rect2(-10, fy - 6, 20, 1), Color("#2c2438"))          # 顶棱
	draw_rect(Rect2(-8, fy - 4, 16, 5), Color("#241a30"))           # 内窗
	# 双卷轴
	draw_circle(Vector2(-4, fy - 1.5), 2.0, Color("#0e0a16"))
	draw_circle(Vector2(4, fy - 1.5), 2.0, Color("#0e0a16"))
	draw_circle(Vector2(-4, fy - 1.5), 0.8, Color("#3a3450"))
	draw_circle(Vector2(4, fy - 1.5), 0.8, Color("#3a3450"))
	# 标签条（AMBER 低饱和）
	var tag := KZPalette.AMBER.darkened(0.35)
	draw_rect(Rect2(-8, fy + 2, 16, 3), tag)
	# 前缘高光
	draw_rect(Rect2(-10, fy - 6, 2, 13), Color("#40385a"))


func _draw_usb(fy: float, pulse: float) -> void:
	# 青白数据光晕（CRT_GLOW 同族 —— 数据件在"呼唤"玩家）
	draw_circle(Vector2(0, fy), 16.0 + 3.0 * pulse, Color(0.30, 0.62, 0.78, 0.10))
	draw_circle(Vector2(0, fy), 9.0, Color(0.30, 0.62, 0.78, 0.14))
	# 主体：竖立数据件
	draw_rect(Rect2(-6, fy - 11, 12, 22), Color("#16323a"))
	draw_rect(Rect2(-6, fy - 11, 12, 2), Color("#28525e"))          # 顶棱
	draw_rect(Rect2(-6, fy + 7, 12, 4), Color("#0e2026"))           # 接口端
	# 发光数据芯（青白脉冲 —— 里面是"玩家自己的过去"）
	var core := Color(KZPalette.NEON_CYAN.r, KZPalette.NEON_CYAN.g,
			KZPalette.NEON_CYAN.b, 0.55 + 0.40 * pulse)
	draw_rect(Rect2(-2, fy - 8, 4, 12), core)
	draw_rect(Rect2(-1, fy - 6, 2, 8), Color(0.85, 0.98, 1.0, 0.5 + 0.4 * pulse))
	# 侧缘高光
	draw_rect(Rect2(-6, fy - 11, 2, 22), Color("#1f4550"))
