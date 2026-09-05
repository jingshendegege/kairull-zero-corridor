extends Node2D
class_name SlimeRibbonBurst
## 连续单色族液幕：死亡完整版 / 受击弱化版。
## 全部代码构建（tscn 是空壳）。N 条拉丝沿受力方向喷射渐隐，M 颗重液滴
## 做抛物线飞行，撞上地形时通过 level.surface_at 判定撞墙/撞地并发
## wall_impact 信号（墙渍层据此在精确撞点留渍）。
##
## 行为合同（test_slime_ribbon_burst.gd）：
##   play(power, direction, seed, weak)
##   死亡版：5 条拉丝 + 11 颗液滴；~0.15s 发一次 paint_requested；1.2s 后 finished
##   弱化版：3 条短液丝 + 4 颗液滴；0.55s 生命周期
##   debug_stats() -> {streams, droplets, weak, direction, duration}

signal finished(effect: SlimeRibbonBurst)
signal paint_requested(world_position: Vector2, direction: Vector2, power: float,
		seed: int, weak: bool)
signal wall_impact(world_position: Vector2, radius: float, slot: int,
		on_wall: bool, weak: bool)

const DUR_FULL := 1.2
const DUR_WEAK := 0.55
const PAINT_AT_FULL := 0.15
const PAINT_AT_WEAK := 0.12
const STREAM_GROW_T := 0.12     ## 拉丝伸到全长的时长
const GRAV := 1550.0            ## 液滴重力 px/s²

## 单色族色板：每次爆裂按 seed 选定一个霓虹主色，整束在该色相的
## 明暗族内变化——单次打击干净，多次打击墙面自然攒出彩色渍迹。
const HUE_PALETTE: Array[Color] = [
	Color("#ff4fa3"), Color("#43e8ff"), Color("#9b5cff"),
	Color("#ffb347"), Color("#7dff6a"), Color("#5c8aff"),
]


## seed -> 本次爆裂主色（测试与回放可稳定复现）。
static func hue_for_seed(seed: int) -> Color:
	return HUE_PALETTE[posmod(seed, HUE_PALETTE.size())]

var level: Node = null    ## CorridorLevel；为空时液滴不做地形碰撞
var active := false
var weak_mode := false    ## 弱化受击版标记（test_slime_game_fx 用）
var elapsed := 0.0        ## 当前已播放时长
var duration := DUR_FULL  ## 本次播放的生命周期

var _power := 1.0
var _dir := Vector2.RIGHT
var _seed := 0
var _weak := false
var _t := 0.0
var _dur := DUR_FULL
var _paint_at := PAINT_AT_FULL
var _paint_sent := false
var _streams: Array = []    ## {angle, length, width, color, delay}
var _droplets: Array = []   ## {pos, vel, radius, color, alive, slot}

## 本次爆裂主色（单色族墙渍/撞点留渍据此取色）。
var current_color := Color.WHITE

## 近战模式（棒球棍）：更紧的喷射扇面、更猛的液滴初速，
## 以及撞击瞬间的放射星芒 + 冲击环。
var _melee := false


func _ready() -> void:
	# 新建及回池的液幕都不应执行空的逐帧回调；play() 会按需重新启用。
	visible = false
	set_process(false)


func play(power: float, direction: Vector2, seed: int, weak: bool,
		melee := false) -> void:
	_power = clampf(power, 0.25, 2.0) * (1.25 if melee else 1.0)
	_melee = melee
	_dir = direction.normalized()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	_seed = seed if seed != 0 else int(Time.get_ticks_usec())
	current_color = hue_for_seed(_seed)
	_weak = weak
	weak_mode = weak
	_t = 0.0
	_dur = DUR_WEAK if weak else DUR_FULL
	duration = _dur
	elapsed = 0.0
	_paint_at = PAINT_AT_WEAK if weak else PAINT_AT_FULL
	_paint_sent = false
	active = true
	visible = true
	set_process(true)

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	# 单色族明暗：主色 / 压暗 / 提亮，整束同色相。
	var shades: Array[Color] = [current_color, current_color.darkened(0.28),
			current_color.lightened(0.40)]
	_streams.clear()
	var stream_count := 3 if weak else 5
	# 近战（棒球棍）：扇面收紧、主液柱更长，像被棍头"抽"出去的一束
	var spread := deg_to_rad((20.0 if _melee else 24.0) if weak \
			else (22.0 if _melee else 38.0))
	for i in stream_count:
		var main := i == 0
		var length := (176.0 if main else rng.randf_range(72.0, 168.0)) * _power
		if main and _melee:
			length *= 1.3
		if weak:
			length = rng.randf_range(40.0, 90.0) * _power
		_streams.append({
			"angle": 0.0 if main else rng.randf_range(-spread, spread),
			"length": length,
			"width": rng.randf_range(2.5, 5.5) * _power * (1.4 if main else 1.0),
			"color": current_color.lightened(0.18) if main else shades[i % 3],
			"delay": rng.randf_range(0.0, 0.05),
		})

	_droplets.clear()
	var droplet_count := 4 if weak else 11
	for i in droplet_count:
		var speed := rng.randf_range(180.0, 320.0) if weak \
				else rng.randf_range(260.0, 520.0)
		if _melee:
			speed *= 1.35   ## 棍击把液滴抽得更远更猛
		speed *= pow(_power, 0.7)
		var vel := _dir.rotated(rng.randf_range(-0.55, 0.55)) * speed
		vel.y -= rng.randf_range(40.0, 140.0)   ## 先向上抛一点再下落
		_droplets.append({
			"pos": Vector2.ZERO,
			"vel": vel,
			"radius": rng.randf_range(2.5, 4.5) * _power,
			"color": shades[(i + 1) % 3],
			"alive": true,
			"slot": i,
		})
	queue_redraw()


## 立即停播（回池/重置用）：不清配置，只停生命周期。
func stop() -> void:
	if not active:
		visible = false
		set_process(false)
		return
	active = false
	visible = false
	set_process(false)
	for d in _droplets:
		d["alive"] = false
	queue_redraw()


func debug_stats() -> Dictionary:
	return {
		"streams": _streams.size(),
		"droplets": _droplets.size(),
		"weak": _weak,
		"direction": _dir,
		"duration": _dur,
	}


func _process(dt: float) -> void:
	if not active:
		return
	_t += dt
	elapsed = _t
	if not _paint_sent and _t >= _paint_at:
		_paint_sent = true
		paint_requested.emit(global_position, _dir, _power, _seed, _weak)
	for d in _droplets:
		if not d["alive"]:
			continue
		d["vel"].y += GRAV * dt
		d["pos"] += d["vel"] * dt
		if level != null:
			var wp: Vector2 = global_position + d["pos"]
			if level.solid_at(wp.x, wp.y):
				d["alive"] = false
				var surf: Dictionary = level.surface_at(wp.x, wp.y)
				# 撞墙（侧面）留墙渍，撞地/平台顶面瘫开
				var on_wall: bool = surf.get("kind", "none") == "wall"
				wall_impact.emit(wp.round(), d["radius"], d["slot"], on_wall, _weak)
	if _t >= _dur:
		stop()
		finished.emit(self)
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	# 白芯只占命中最初几帧，缩小面积，让后续彩色血液而非白圈抢眼。
	const FLASH_T := 0.045
	if _t < FLASH_T:
		var fp := _t / FLASH_T
		draw_circle(Vector2.ZERO, (5.0 + 12.0 * fp) * _power,
				Color(1.0, 0.96, 0.9, 0.7 * (1.0 - fp)))
		draw_rect(Rect2(Vector2(-3, -3) * _power, Vector2(6, 6) * _power),
				Color(current_color.lightened(0.6), 1.0 - fp))
	# 短促定向破口取代八向大星芒；受力方向更明确，不遮掉敌人前摇。
	const MELEE_T := 0.11
	if _melee and _t < MELEE_T:
		var mp := _t / MELEE_T
		var fade_m := 1.0 - mp
		for i in 3:
			var dir := _dir.rotated((i - 1) * 0.5)
			var length := (20.0 + 34.0 * mp) * _power
			var inner := (dir * length * 0.25).round()
			var outer := (dir * length).round()
			draw_line(inner, outer, Color(current_color.lightened(0.3), 0.9 * fade_m),
					maxf(1.0, roundf(5.0 * fade_m * _power)), false)
			if i == 1:
				draw_line(inner, outer, Color(1.0, 0.95, 0.88, 0.65 * fade_m), 1.0, false)
	# 液束在 0.12s 展开，随后尾端追上前端并分离；不再像激光固定连着伤口 1.2s。
	var fade := clampf((_dur - _t) / (_dur * 0.4), 0.0, 1.0)
	for s in _streams:
		var stream_age := maxf(0.0, _t - float(s["delay"]))
		var progress := clampf(stream_age / STREAM_GROW_T, 0.0, 1.0)
		if progress <= 0.0:
			continue
		var dir := _dir.rotated(s["angle"])
		var end: Vector2 = dir * float(s["length"]) * progress
		end += Vector2(0.0, 180.0 * pow(maxf(0.0, stream_age - 0.12), 2.0))
		var tail_progress := smoothstep(0.10, 0.50, stream_age)
		var start := end * tail_progress
		var col: Color = s["color"]
		col.a = 0.9 * fade * (1.0 - smoothstep(0.22, 0.50, stream_age))
		if col.a <= 0.01:
			continue
		var w: float = float(s["width"]) * (1.0 - 0.6 * progress * (_t / _dur))
		# 固定种子的短液节替代一根笔直长线；冻结到墙上后是断续浸染，不像常亮激光。
		# 不逐帧随机，分节只随原液束伸长/收尾，保留喷射方向与像素稳定性。
		var normal := Vector2(-dir.y, dir.x)
		for segment in 7:
			var wobble := sin(float(s["length"]) + segment * 4.8)
			var offset := normal * wobble * w * 0.65
			# 长短/间距一次性由液束种子决定，避免等距虚线像弹道指示器。
			var pattern := float(s["length"]) * 0.17 + segment * 2.173
			var from_ratio := float(segment) / 7.0 + 0.008 + absf(sin(pattern)) * 0.028
			var to_ratio := float(segment + 1) / 7.0 - 0.012 - absf(cos(pattern * 1.71)) * 0.058
			var a := (start.lerp(end, from_ratio) + offset).round()
			var b := (start.lerp(end, to_ratio) + offset).round()
			var thickness := maxf(1.0, roundf(w * (1.35 + wobble * 0.34)
					* lerpf(1.0, 0.58, float(segment) / 6.0)))
			draw_line(a, b, col, thickness, false)
			if segment % 3 == 1:
				# 间隔的小团块补回分节留白的体积，主色与强度不减。
				var bead_size := maxf(2.0, roundf(thickness * 1.35))
				draw_rect(Rect2(b - Vector2.ONE * floorf(bead_size * 0.5),
						Vector2.ONE * bead_size), col)
	# 液滴：像素方块 + 短拖尾
	for d in _droplets:
		if not d["alive"]:
			continue
		var col: Color = d["color"]
		col.a = 0.95 * fade
		var vel: Vector2 = d["vel"]
		var r := float(d["radius"])
		var tail: Vector2 = -vel.normalized() * minf(10.0, r * 2.2)
		var p: Vector2 = Vector2(d["pos"]).round()
		draw_line(p, (p + tail).round(), col, maxf(1.0, roundf(r * 0.9)), false)
		draw_rect(Rect2((p - Vector2.ONE * r * 0.5).round(),
				Vector2.ONE * maxf(1.0, r)), col)
