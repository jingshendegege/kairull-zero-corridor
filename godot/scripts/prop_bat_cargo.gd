extends Node2D
class_name PropBatCargo
## 球棒击飞的封装货箱：脚底中心锚点，静置时不挡路，只命中敌人、不伤玩家。
## 固定小步扫掠先处理地形再处理敌人，不能隔墙命中；特效数组有硬上限。

signal impacted(cargo: PropBatCargo, target: Node2D, direction: Vector2)

const W := 32.0
const H := 36.0
const LAUNCH_SPEED := 850.0
const LAUNCH_LIFT := -100.0
const GRAVITY := 300.0
const MAX_FLIGHT_TIME := 1.1
const SWEEP_STEP := 2.0
const SHARD_LIFE := 0.34
const MAX_TRAIL := 6

var dead := false
var flying := false
var velocity := Vector2.ZERO
var flight_time := 0.0
var spawn_position := Vector2.ZERO
var launch_stage := 0
var highlighted := false
var _flash := 0.0
var _trail: Array[Dictionary] = []
var _shards: Array[Dictionary] = []
var _hint: Label


func _ready() -> void:
	spawn_position = position
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hint = Label.new()
	_hint.text = "左键 · 击飞"
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	_hint.add_theme_font_override("font", font)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color("#ffdc91"))
	_hint.add_theme_color_override("font_outline_color", Color("#111b23"))
	_hint.add_theme_constant_override("outline_size", 5)
	# 提示高于角色站立轮廓，贴箱时不被白发或球棒遮住。
	_hint.position = Vector2(-42, -112)
	_hint.visible = false
	add_child(_hint)


func body_rect() -> Rect2:
	return Rect2(position - Vector2(W * 0.5, H), Vector2(W, H))


func launch(direction: float, stage := 0) -> bool:
	if dead or flying or is_zero_approx(direction):
		return false
	launch_stage = clampi(stage, 0, 2)
	velocity = Vector2(signf(direction) * (LAUNCH_SPEED + launch_stage * 65.0), LAUNCH_LIFT)
	flying = true
	flight_time = 0.0
	_flash = 0.055
	highlighted = false
	queue_redraw()
	return true


## 通用物件接口：来自左侧的打击向右发射；正式球棒链直接传锁定朝向。
func take_hit(from_x: float, _damage := 1) -> bool:
	return launch(1.0 if from_x <= position.x else -1.0)


func reset_to_spawn() -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	dead = false
	flying = false
	flight_time = 0.0
	_flash = 0.0
	_trail.clear()
	_shards.clear()
	queue_redraw()


## 普通帧仅推进短碎屑；货箱本身由集中式 game 调用 advance 推进。
func step(dt: float) -> void:
	var visual_active := _flash > 0.0 or not _shards.is_empty() or not _trail.is_empty()
	_flash = maxf(0.0, _flash - dt)
	for bit: Dictionary in _shards:
		bit["p"] += bit["v"] * dt
		bit["v"].y += 680.0 * dt
		bit["life"] -= dt
	_shards = _shards.filter(func(bit: Dictionary) -> bool: return bit["life"] > 0.0)
	for point: Dictionary in _trail:
		point["life"] -= dt
	_trail = _trail.filter(func(point: Dictionary) -> bool: return point["life"] > 0.0)
	if _hint != null:
		_hint.visible = highlighted and not flying and not dead
	if visual_active:
		queue_redraw()


func advance(dt: float, level: CorridorLevel, enemies: Array, doors: Array) -> void:
	if not flying or dead or dt <= 0.0:
		return
	# 大帧也按小时间段积分；有限寿命封顶，暂停恢复不会无限扫掠。
	var remaining := minf(dt, MAX_FLIGHT_TIME - flight_time)
	while remaining > 0.00001 and flying:
		var tick := minf(remaining, 1.0 / 120.0)
		var motion := velocity * tick + Vector2(0, GRAVITY * tick * tick * 0.5)
		velocity.y += GRAVITY * tick
		flight_time += tick
		remaining -= tick
		var steps := maxi(1, ceili(motion.length() / SWEEP_STEP))
		for i in steps:
			var before := body_rect()
			var candidate := Rect2(before.position + motion / steps, before.size)
			if _blocked(before, candidate, level, doors):
				_break_apart(null)
				break
			position += motion / steps
			for enemy: Node2D in enemies:
				if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() \
						and not enemy.dead and enemy.body_rect().intersects(body_rect()):
					_break_apart(enemy)
					break
			if not flying:
				break
	if flying and flight_time >= MAX_FLIGHT_TIME - 0.0001:
		_break_apart(null)
	if flying:
		_trail.append({"p": body_rect().get_center(), "life": 0.085})
		if _trail.size() > MAX_TRAIL:
			_trail.pop_front()
	queue_redraw()


func _blocked(before: Rect2, candidate: Rect2, level: CorridorLevel, doors: Array) -> bool:
	for door: Node2D in doors:
		if is_instance_valid(door) and door.locked and door.body_rect().intersects(candidate):
			return true
	if level == null:
		return false
	if candidate.position.x < 0 or candidate.end.x > level.world_w \
			or candidate.position.y < 0 or candidate.end.y > level.world_h:
		return true
	# 遍历 AABB 覆盖的所有格，不只采样角点，避免高速或宽箱漏掉薄墙。
	for y in range(floori(candidate.position.y / 32.0), floori((candidate.end.y - 0.01) / 32.0) + 1):
		for x in range(floori(candidate.position.x / 32.0), floori((candidate.end.x - 0.01) / 32.0) + 1):
			var tile := level.tile_at(x, y)
			if not level.is_solid_char(tile):
				continue
			if tile != "=" or (candidate.end.y > before.end.y and before.end.y <= y * 32.0 + 0.25):
				return true
	if candidate.end.y >= before.end.y:
		for x in [candidate.position.x + 1.0, candidate.get_center().x, candidate.end.x - 1.0]:
			if is_finite(level.stair_surface_crossed(x, before.end.y, candidate.end.y)):
				return true
	return false


func _break_apart(target: Node2D) -> void:
	if not flying:
		return
	flying = false
	dead = true
	var force := velocity.normalized()
	# 暖色金属碎片不同于彩色血液；固定十片，0.34s 后完全回收。
	for i in 10:
		var angle := -PI + float(i) * PI / 9.0
		_shards.append({"p": Vector2(0, -H * 0.5),
			"v": Vector2(cos(angle), sin(angle)) * (80.0 + i * 8.0) + force * 85.0,
			"life": SHARD_LIFE, "size": 2.0 + float(i % 2)})
	_flash = 0.045
	impacted.emit(self, target, force)
	queue_redraw()


func _draw() -> void:
	for point: Dictionary in _trail:
		var color := Color("#f2c16e")
		color.a = 0.5 * float(point["life"]) / 0.085
		draw_rect(Rect2((point["p"] - position).round(), Vector2(8, 2)), color)
	if not dead:
		# 固定像素形状：深边、压铸折边、封装锁扣、黄色撞击条和白色方向箭头。
		var left := -W * 0.5
		draw_rect(Rect2(left - 3, -3, W + 6, 3), Color(0.02, 0.03, 0.04, 0.45))
		draw_rect(Rect2(left, -H, W, H), Color("#17232c"))
		draw_rect(Rect2(left + 2, -H + 2, W - 4, H - 4), Color("#977048"))
		draw_rect(Rect2(left + 4, -H + 4, W - 8, H - 8), Color("#bd9964"))
		draw_rect(Rect2(left + 4, -H + 4, W - 8, 2), Color("#edcf95"))
		draw_rect(Rect2(left + 4, -H + 19, W - 8, 8), Color("#e4b951"))
		for x in [-8, 3]:
			draw_rect(Rect2(x, -H + 20, 5, 6), Color("#374149"))
		draw_rect(Rect2(-3, -H + 3, 6, 11), Color("#465960"))
		draw_rect(Rect2(-1, -H + 5, 2, 5), Color("#a9ecdf"))
		draw_rect(Rect2(left + 3, -5, W - 6, 2), Color("#473e36"))
		if _flash > 0.0:
			draw_rect(Rect2(left, -H, W, H), Color(1, 0.93, 0.74, _flash / 0.055 * 0.65))
	for bit: Dictionary in _shards:
		var color := Color("#efd099")
		color.a = float(bit["life"]) / SHARD_LIFE
		draw_rect(Rect2((bit["p"] as Vector2).round(), Vector2.ONE * float(bit["size"])), color)
