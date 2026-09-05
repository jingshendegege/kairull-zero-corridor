extends Node2D
class_name SlimePaintLayer
## 持久液体污渍层：放在关卡之后、角色之前，像油漆一样黏在背景墙面。
## 污渍只有两种来源：
##   1. spray/stamp_origin_burst —— 受击/死亡爆裂的方向性喷溅痕（扁平散射印）。
##   2. add_impact_splat —— 液丝/液滴真实撞上墙/地后的 BD 式撞击印
##      （放射状主印 + 周围卫星小液点）。
## 本层不做任何流淌/下淌动画，污渍生成即定型。

const BloodWallManagerType := preload("res://scripts/blood_wall_manager.gd")

const MAX_SPLATS := 120
## 微粒碎渍上限（每颗血滴的落点是一小块锯齿碎片，数量多但都很小）
const MAX_FLECKS := 900
## 微粒喷溅重力（与液爆液滴一致）
const SPATTER_GRAV := 1550.0
const PALETTE := [
	Color("#35e7ff"), Color("#5cff7a"), Color("#ffe45c"),
	Color("#ff8a4c"), Color("#ff4fa3"), Color("#9a6cff"),
]
const SPRAY_MAIN := Color("#d72d78")
const SPRAY_ACCENT := Color("#5ce8f2")
const SPRAY_HIGHLIGHT := Color("#ffd7ec")
## D 方案：墙漆与空中液柱同一套彩虹色序（沿用 spike 001d 色板）。
const SPRAY_PALETTE := [
	Color("#24cbd9"), Color("#55d66b"), Color("#e3c746"),
	Color("#ec773f"), Color("#df3d88"), Color("#865ad3"),
]
## 血迹色板（武士零参考：亮红喷溅 + 暗红泊）
const BLOOD_MAIN := Color("#c01630")
const BLOOD_DARK := Color("#7d0e22")
const BLOOD_HI := Color("#e83a34")
const BLOOD_PALETTE := [BLOOD_MAIN, BLOOD_DARK, BLOOD_HI]

var splats: Array[Dictionary] = []
## 微粒碎渍：喷溅血滴的真实落点，独立数组、独立上限。
var flecks: Array[Dictionary] = []
var level: CorridorLevel
var blood_wall_manager: BloodWallManagerType


func _ready() -> void:
	# 新墙面快照仍归属世界污渍层，保持“地形之后、角色之前”的既有绘制顺序。
	blood_wall_manager = BloodWallManagerType.new() as BloodWallManagerType
	blood_wall_manager.name = "BloodWallManager"
	add_child(blood_wall_manager)


## 主液幕前缘到位时冻结共享图集的一帧；旧碎渍与血泊仍由本类负责。
func spawn_wall_snapshot(world_position: Vector2, direction: Vector2, power: float,
		seed: int, weak: bool, progress: float, effect_color: Color) -> Sprite2D:
	if blood_wall_manager == null:
		return null
	return blood_wall_manager.spawn_snapshot(world_position, direction, power,
			seed, weak, progress, effect_color)


## 微粒喷溅（独立弹道算法）：每颗血滴在 ±35° 方向锥内独立取样初速，
## 按重力弹道 1/90s 步进，命中实体表面才在真实落点留碎渍——
## 墙上立体锯齿碎片，地上压扁摊片；飞尽没撞到的不留痕。
func spawn_spatter(origin: Vector2, direction: Vector2, power := 1.0, seed := 0,
		hue := SPRAY_MAIN, count := 30) -> int:
	var dir := direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(Time.get_ticks_usec())
	var strength := clampf(power, 0.3, 2.2)
	var landed := 0
	for i in count:
		var vel := dir.rotated(rng.randf_range(-0.62, 0.62)) \
				* rng.randf_range(150.0, 540.0) * strength
		vel.y -= rng.randf_range(30.0, 160.0)   ## 先上抛再坠落
		var p := origin
		var t := 0.0
		var max_t := rng.randf_range(0.30, 0.85)
		var size_base := rng.randf_range(2.0, 4.6)
		while t < max_t:
			var dt := 1.0 / 90.0
			vel.y += SPATTER_GRAV * dt
			p += vel * dt
			t += dt
			if level != null and level.solid_at(p.x, p.y):
				_add_fleck(p.round(), level.surface_at(p.x, p.y), hue, rng, size_base)
				landed += 1
				break
	_trim_flecks()
	queue_redraw()
	return landed


## 单颗血滴的落点碎渍：锯齿小碎片；落地（floor/platform）垂直压扁摊平。
func _add_fleck(point: Vector2, surface: Dictionary, hue: Color,
		rng: RandomNumberGenerator, size_base: float) -> void:
	var r := size_base * rng.randf_range(0.7, 1.4)
	var poly := _jagged_blob(point, r, rng)
	var kind: String = surface.get("kind", "none")
	if kind == "floor" or kind == "platform":
		for j in poly.size():
			poly[j] = Vector2(poly[j].x,
					point.y + (poly[j].y - point.y) * 0.4).round()
	var shade := hue.darkened(rng.randf_range(0.0, 0.22))
	if rng.randf() > 0.9:
		shade = hue.lightened(0.18)
	flecks.append({"polygon": poly, "color": shade})


func _trim_flecks() -> void:
	var limit := 300 if OS.has_feature("web") else MAX_FLECKS
	while flecks.size() > limit:
		flecks.pop_front()


func fleck_count() -> int:
	return flecks.size()


## 依据受力方向生成一束背景涂料；seed 用于测试与回放时稳定复现。
## palette 默认彩虹史莱姆色序；血迹传 BLOOD_PALETTE。
func spray(origin: Vector2, force_direction: Vector2, power := 1.0, seed := 0,
		palette: Array = SPRAY_PALETTE) -> int:
	var direction := force_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var strength := clampf(power, 0.18, 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(Time.get_ticks_usec())
	var count := maxi(2, roundi(7.0 * strength))
	for i in count:
		# 第一束沿主受力方向走最远，保证爆裂轮廓有明确朝向；其余液滴形成扇面。
		var spread_deg := 0.0 if i == 0 else rng.randf_range(-48.0, 48.0)
		var ray := direction.rotated(deg_to_rad(spread_deg))
		var distance := (176.0 if i == 0 else rng.randf_range(72.0, 168.0)) * strength
		var target := origin + ray * distance + Vector2(0, rng.randf_range(6.0, 34.0))
		var projection := _project_to_surface(origin, target)
		_add_splat(projection["center"], palette[i % palette.size()],
				rng.randf_range(7.0, 16.0) * strength, rng, projection["solid"],
				projection["surface"])
	_trim_oldest()
	queue_redraw()
	return count


## 血迹喷溅：与史莱姆同一投影逻辑，但用红系色板（命中墙面/地面真实落点）。
func blood_spray(origin: Vector2, force_direction: Vector2, power := 1.0,
		seed := 0) -> int:
	return spray(origin, force_direction, power, seed, BLOOD_PALETTE)


## 液泊：从击杀点垂直下投找地板/台面，瘫成扁平液泊。
## 中途撞墙则退化为贴墙放射印。落点表面分类由 _project_to_surface 带回。
## color 默认暗红血泊；单色族液爆传本次主色（压暗）。
func blood_pool(origin: Vector2, power := 1.0, seed := 0,
		color := BLOOD_MAIN) -> void:
	if level == null:
		return
	var hit := _project_to_surface(origin, origin + Vector2(0.0, 320.0))
	if not hit["solid"]:
		return
	var center: Vector2 = hit["center"]
	var kind: String = hit["surface"].get("kind", "none")
	if kind == "wall":
		add_impact_splat(center, 9.0 * power, 3, false, seed, true, color)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(Time.get_ticks_usec())
	var r := 14.0 * clampf(power, 0.5, 2.0)
	# 贴地扁平血泊：宽椭圆，上缘贴撞点，下缘薄
	var polygon := PackedVector2Array()
	var points := 12
	for i in points:
		var angle := TAU * float(i) / points
		var rx := r * rng.randf_range(0.8, 1.25)
		var ry := r * 0.30 * rng.randf_range(0.8, 1.2)
		polygon.append((center + Vector2(cos(angle) * rx, sin(angle) * ry - r * 0.10)).round())
	var satellites: Array = []
	for i in 4:
		var off := Vector2(rng.randf_range(-r * 2.2, r * 2.2),
				rng.randf_range(-r * 0.4, r * 0.1))
		var size := maxf(1.5, r * rng.randf_range(0.10, 0.22))
		satellites.append(Rect2((center + off - Vector2.ONE * size * 0.5).round(),
				Vector2(size, size)))
	splats.append({
		"center": center,
		"color": color,
		"solid_contact": true,
		"surface": hit["surface"],
		"polygon": _roughen(polygon, rng, 0.22),
		"drips": satellites,
		"dots": _stipple(center, r * 1.1, color, rng),
	})
	_trim_oldest()
	queue_redraw()


## 爆裂起点立即写入背景墙：一个主体湿斑 + 数条沿受力方向收尖的喷射痕。
## weak=true 用于普通受击，只留下较短、较少的痕迹。
## main_color/accent 默认史莱姆粉青；单色族液爆传入本次主色的明暗族。
func stamp_origin_burst(origin: Vector2, force_direction: Vector2, power := 1.0,
		seed := 0, weak := false, main_color := SPRAY_MAIN,
		accent := SPRAY_ACCENT) -> int:
	var direction := force_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var strength := clampf(power, 0.25, 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(Time.get_ticks_usec())
	var streak_count := 2 if weak else 5
	var main_radius := (7.0 if weak else 17.0) * strength
	_add_splat((origin + direction * main_radius * 0.18).round(), main_color,
			main_radius, rng, false)
	for i in streak_count:
		var ray := direction.rotated(deg_to_rad(rng.randf_range(
				-24.0 if weak else -38.0, 24.0 if weak else 38.0)))
		var length := rng.randf_range(18.0, 38.0) if weak else rng.randf_range(46.0, 92.0)
		length *= strength
		var start := origin + ray * main_radius * 0.28
		var end := origin + ray * length
		var normal := Vector2(-ray.y, ray.x)
		var base_width := rng.randf_range(2.5, 5.5) * strength
		var polygon := PackedVector2Array([
			(start + normal * base_width).round(),
			(end + normal * maxf(1.0, base_width * 0.22)).round(),
			(end - normal * maxf(1.0, base_width * 0.22)).round(),
			(start - normal * base_width).round(),
		])
		var color := accent if i == streak_count - 1 else main_color
		splats.append({
			"center": end.round(),
			"color": color,
			"solid_contact": false,
			"polygon": _roughen(polygon, rng, 0.4),
			"drips": [],
			"dots": _stipple(end, base_width * 2.2, color, rng),
		})
	_trim_oldest()
	queue_redraw()
	return streak_count + 1


func _project_to_surface(origin: Vector2, target: Vector2) -> Dictionary:
	if level == null:
		return {"center": target.round(), "solid": false, "surface": {}}
	var distance := origin.distance_to(target)
	var steps := maxi(1, ceili(distance / 4.0))
	for i in range(1, steps + 1):
		var point := origin.lerp(target, float(i) / steps)
		if level.solid_at(point.x, point.y):
			# 表面分类随撞点一并返回：特效据此区分撞墙/撞地/撞单向台
			return {"center": point.round(), "solid": true,
					"surface": level.surface_at(point.x, point.y)}
	return {"center": target.round(), "solid": false, "surface": {}}


## 锯齿碎片轮廓：尖刺交替的内/外半径（武士零式泼溅剪影），全部像素取整。
func _jagged_blob(center: Vector2, radius: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var points := 14
	var spike := rng.randi() % 2   ## 相位随机，避免每块渍迹同向
	for i in points:
		var angle := TAU * float(i) / points
		var outer := (i + spike) % 2 == 0
		var local_radius := radius * (rng.randf_range(0.95, 1.5) if outer \
				else rng.randf_range(0.36, 0.62))
		polygon.append((center + Vector2(cos(angle), sin(angle)) * local_radius).round())
	return polygon


## 边缘溅点：主形外 0.9~1.8 倍半径撒 1~3px 碎点，明暗抖动代替高光贴纸。
func _stipple(center: Vector2, radius: float, color: Color,
		rng: RandomNumberGenerator) -> Array:
	var dots: Array = []
	var count := int(radius * rng.randf_range(0.9, 1.4))
	for i in count:
		var angle := rng.randf_range(0.0, TAU)
		var dist := radius * rng.randf_range(0.9, 1.85)
		var p := (center + Vector2(cos(angle), sin(angle)) * dist).round()
		var size := float(maxi(1, roundi(rng.randf_range(1.0, 2.6))))
		var shade := color
		var roll := rng.randf()
		if roll < 0.25:
			shade = color.darkened(0.28)
		elif roll > 0.92:
			shade = color.lightened(0.22)
		dots.append({"r": Rect2(p, Vector2(size, size)), "c": shade})
	return dots


## 把光滑多边形的每条边锉出 1~2 个垂直抖动的中点，形成锯齿边缘。
func _roughen(polygon: PackedVector2Array, rng: RandomNumberGenerator,
		amount := 0.3) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := polygon.size()
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		out.append(a)
		var edge := b - a
		var segs := 2 if edge.length() > 14.0 else 1
		var normal := Vector2(-edge.y, edge.x).normalized()
		for s in segs:
			var mid := a + edge * (float(s + 1) / (segs + 1))
			var off := normal * rng.randf_range(-amount, amount) * edge.length() * 0.5
			out.append((mid + off).round())
	return out


func _add_splat(center: Vector2, color: Color, radius: float, rng: RandomNumberGenerator,
		solid_contact: bool, surface: Dictionary = {}) -> void:
	splats.append({
		"center": center,
		"color": color,
		"solid_contact": solid_contact,
		"surface": surface,
		"polygon": _jagged_blob(center, radius, rng),
		"drips": [],
		"dots": _stipple(center, radius, color, rng),
	})


## D 式撞墙/撞地"一滩"：液滴真实命中后在撞点瘫开。
## 形状照搬 spike 001d：撞墙用七角放射形（向受力反向伸出长臂），
## 撞地用扁六角形；外加 3 颗卫星点 + 两道静态流痕（印在撞点上，不生长）。
func add_impact_splat(world_position: Vector2, radius: float, slot: int,
		weak: bool, seed: int, on_wall: bool = true,
		color_override := Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(Time.get_ticks_usec())
	var r := maxf(4.0, radius) * (0.55 if weak else 1.0)
	var color: Color = color_override if color_override.a > 0.0 \
			else SPRAY_PALETTE[posmod(slot, SPRAY_PALETTE.size())]
	var center := world_position.round()
	# 主滩形状：spike 001d 原样的两套多边形，撞墙/撞地分开。
	var polygon: PackedVector2Array
	if on_wall:
		polygon = PackedVector2Array([
			(center + Vector2(-r * 1.35, -r * 0.12)).round(),
			(center + Vector2(-r * 0.48, -r * 0.78)).round(),
			(center + Vector2(r * 0.10, -r * 1.12)).round(),
			(center + Vector2(r * 0.62, -r * 0.42)).round(),
			(center + Vector2(r * 0.52, r * 0.76)).round(),
			(center + Vector2(-r * 0.05, r * 1.08)).round(),
			(center + Vector2(-r * 0.62, r * 0.52)).round(),
		])
	else:
		polygon = PackedVector2Array([
			(center + Vector2(-r * 1.18, -r * 0.24)).round(),
			(center + Vector2(-r * 0.48, -r * 0.86)).round(),
			(center + Vector2(r * 0.62, -r * 0.68)).round(),
			(center + Vector2(r * 1.20, -r * 0.16)).round(),
			(center + Vector2(r * 0.58, r * 0.42)).round(),
			(center + Vector2(-r * 0.62, r * 0.46)).round(),
		])
	# 卫星点：spike 001d 原样的 3 颗，位置/大小由 phase 驱动。
	var satellites: Array = []
	var phase := rng.randf_range(0.0, TAU)
	for i in 3:
		var sat := center + Vector2(
				-r * (1.25 + i * 0.52),
				sin(phase + i * 1.7) * r * 1.28)
		var size := maxf(2.0, r * (0.24 - i * 0.035))
		satellites.append(Rect2((sat - Vector2.ONE * size * 0.5).round(),
				Vector2(size, size)))
	# 两道静态流痕：撞墙瞬间印在撞点下方，一长一短，不生长不变化。
	var drips: Array = satellites
	if on_wall:
		for i in 2:
			var drip_len := r * (2.4 + i * 0.8)
			var drip_x := center.x + r * (-0.18 + i * 0.34)
			drips.append(Rect2(Vector2(round(drip_x), round(center.y + r * 0.32)),
					Vector2(3 - i, round(drip_len))))
	# 主滩形状锉出锯齿 + 边缘溅点，去掉高光贴纸
	polygon = _roughen(polygon, rng)
	splats.append({
		"center": center,
		"color": color,
		"solid_contact": true,
		"polygon": polygon,
		"drips": drips,
		"dots": _stipple(center, r * 1.2, color, rng),
	})
	_trim_oldest()
	queue_redraw()


func _trim_oldest() -> void:
	var limit := 48 if OS.has_feature("web") else MAX_SPLATS
	while splats.size() > limit:
		splats.pop_front()


func _draw() -> void:
	# 微粒碎渍画在大块渍迹下面
	for fleck in flecks:
		draw_colored_polygon(fleck["polygon"], fleck["color"])
	for splat in splats:
		var color: Color = splat["color"]
		for drip in splat["drips"]:
			if drip is PackedVector2Array:
				draw_colored_polygon(drip, color.darkened(0.08))
			elif drip is Rect2:
				draw_rect(drip, color.darkened(0.08))
		draw_colored_polygon(splat["polygon"], color)
		# 边缘碎点：明暗抖动的 1~3px 颗粒，取代高光贴纸
		for dot in splat.get("dots", []):
			draw_rect(dot["r"], dot["c"])


func splat_count() -> int:
	return splats.size()

## 测试用：卫星小液点总数（撞墙印的特征结构）。
func debug_satellite_count() -> int:
	var count := 0
	for splat in splats:
		for drip in splat["drips"]:
			if drip is Rect2:
				count += 1
	return count

func debug_centers() -> Array:
	var centers: Array = []
	for splat in splats:
		centers.append(splat["center"])
	return centers


func debug_solid_contact_count() -> int:
	var count := 0
	for splat in splats:
		if splat["solid_contact"]:
			count += 1
	return count
