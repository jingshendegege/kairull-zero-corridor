extends Node2D
class_name PropCrt
## 可击碎物：板条箱上的 CRT 显示器（26×22，程序绘制，无外部素材）。
## 一击即碎：青白像素碎屑抛散 + 屏幕闪白，随后留下破裂外壳剪影。
## 接口与敌人/爆炸桶一致：body_rect() / take_hit() / dead；
## 音效与额外反馈由 game 监听 shattered 信号处理。
## position 锚点 = 脚底中心（与地图标记 feet 语义一致）。

signal shattered(crt: PropCrt)

const W := 26.0
const H := 22.0
const SHARD_GRAVITY := 520.0
const SHARD_LIFE := 0.65

var dead := false

var _phase := 0.0
var _flash_t := 0.0
var _shards: Array[Dictionary] = []


func body_rect() -> Rect2:
	return Rect2(position.x - W * 0.5, position.y - H, W, H)


func take_hit(_from_x: float, _damage := 1) -> bool:
	if dead:
		return false
	dead = true
	_flash_t = 0.12
	_spawn_shards()
	shattered.emit(self)
	queue_redraw()
	return true


func step(dt: float) -> void:
	_phase += dt
	if _flash_t > 0.0:
		_flash_t -= dt
	if not _shards.is_empty():
		for s in _shards:
			s["p"] += s["v"] * dt
			s["v"].y += SHARD_GRAVITY * dt
			s["life"] -= dt
		_shards = _shards.filter(func(s: Dictionary) -> bool: return s["life"] > 0.0)
	queue_redraw()


## 青/白像素碎屑：从屏幕中心向四周抛，重力下坠
func _spawn_shards() -> void:
	_shards.clear()
	var origin := Vector2(0, -H + 9.0)   ## 屏幕中心（局部坐标）
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	for i in 14:
		var ang := rng.randf_range(-PI, 0.0)
		var spd := rng.randf_range(60.0, 190.0)
		_shards.append({
			"p": origin + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4)),
			"v": Vector2(cos(ang), sin(ang)) * spd + Vector2(0, -40.0),
			"life": rng.randf_range(0.35, SHARD_LIFE),
			"size": 2.0 if i % 3 else 3.0,
			"color": Color("#e8fbff") if i % 4 == 0 else Color("#7ee8fa"),
		})


func _draw() -> void:
	var left := -W * 0.5
	var top := -H
	if not dead:
		# 板条箱：深棕木箱 + 边条
		draw_rect(Rect2(left - 2, top + 13, W + 4, 9), Color("#3a2a20"))
		draw_rect(Rect2(left - 2, top + 13, W + 4, 2), Color("#57402e"))
		# CRT 机身：深灰塑料
		draw_rect(Rect2(left, top, W, 15), Color("#23202e"))
		draw_rect(Rect2(left, top, W, 15), Color("#0f0d16"), false, 1.0)
		# 屏幕：青色荧光 + 两条扫描线 + 慢闪烁
		var flick := 0.85 + 0.15 * sin(_phase * 7.0)
		var scr := Rect2(left + 3, top + 2, W - 6, 10)
		draw_rect(scr, Color("#0d4a56"))
		draw_rect(scr, Color(0.49, 0.91, 0.98, 0.35 * flick))
		draw_rect(Rect2(scr.position + Vector2(0, 2), Vector2(scr.size.x, 1)),
				Color(0.62, 0.95, 1.0, 0.5 * flick))
		draw_rect(Rect2(scr.position + Vector2(0, 6), Vector2(scr.size.x, 1)),
				Color(0.62, 0.95, 1.0, 0.35 * flick))
	else:
		# 破裂外壳剪影：机身压暗、屏幕碎成黑 + 裂纹
		draw_rect(Rect2(left - 2, top + 13, W + 4, 9), Color("#241a14"))
		draw_rect(Rect2(left, top, W, 15), Color("#141220"))
		draw_rect(Rect2(left + 3, top + 2, W - 6, 10), Color("#05070c"))
		draw_line(Vector2(left + 4, top + 3), Vector2(left + 12, top + 11),
				Color("#2c3140"), 1.0)
		draw_line(Vector2(left + 12, top + 11), Vector2(left + 20, top + 4),
				Color("#2c3140"), 1.0)
	# 碎屏闪白
	if _flash_t > 0.0:
		var a: float = clampf(_flash_t / 0.12, 0.0, 1.0)
		draw_rect(Rect2(left - 4, top - 4, W + 8, H + 8),
				Color(0.85, 0.98, 1.0, a * 0.85))
	# 像素碎屑
	for s in _shards:
		var col: Color = s["color"]
		col.a = clampf(s["life"] / SHARD_LIFE, 0.0, 1.0)
		draw_rect(Rect2(s["p"], Vector2(s["size"], s["size"])), col)
