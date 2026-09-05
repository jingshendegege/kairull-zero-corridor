extends Node2D
class_name GameFxLayer
## 子弹与枪口闪光/火花绘制层（画在角色之上，调试层之下）。

const EXPLOSION_SCENE := preload("res://scenes/fx/pixel_explosion.tscn")
const SLIME_RIBBON_SCENE := preload("res://scenes/fx/slime_ribbon_burst.tscn")
const WOUND_BLOOD_SCENE := preload("res://scenes/fx/wound_blood_spray.tscn")
const WoundBloodSprayType := preload("res://scripts/wound_blood_spray.gd")
const CorpseLandingDustType := preload("res://scripts/corpse_landing_dust.gd")
const MAX_EXPLOSION_POOL := 12
const MAX_WOUND_POOL := 16
const MAX_CORPSE_DUST := 12  ## 活跃与闲置总数硬上限；极端连杀复用最旧灰尘。

var host: Node2D   ## game，读 bullets / fx
var _explosion_pool: Array[PixelExplosion] = []
var _slime_pool: Array[SlimeRibbonBurst] = []
var _wound_pool: Array[WoundBloodSprayType] = []
var _corpse_dust_pool: Array[CorpseLandingDustType] = []
var _corpse_dust_active: Array[CorpseLandingDustType] = []


## 第一次尸体落地调用；小反弹的第二次接触不再重复生成主尘爆。
func spawn_corpse_landing_dust(world_position: Vector2, power := 1.0,
		direction := 1.0) -> Node2D:
	var effect: CorpseLandingDustType
	if not _corpse_dust_pool.is_empty():
		effect = _corpse_dust_pool.pop_back()
	elif _corpse_dust_active.size() >= MAX_CORPSE_DUST:
		effect = _corpse_dust_active.pop_front()
		effect.stop()
	else:
		effect = CorpseLandingDustType.new()
		add_child(effect)
		effect.z_index = -2  # 在子弹/彩血下方，仍高于脚边地板，不盖住命中信号。
		effect.finished.connect(_on_corpse_dust_finished)
	effect.global_position = world_position.round()
	effect.play(power, direction, maxi(1, randi()))
	_corpse_dust_active.append(effect)
	return effect


func _on_corpse_dust_finished(effect: Node2D) -> void:
	var dust := effect as CorpseLandingDustType
	if dust == null or _corpse_dust_pool.has(dust):
		return
	_corpse_dust_active.erase(dust)
	_corpse_dust_pool.append(dust)


func corpse_dust_stats() -> Dictionary:
	return {"active": _corpse_dust_active.size(), "pooled": _corpse_dust_pool.size(),
			"total": _corpse_dust_active.size() + _corpse_dust_pool.size()}


## 在世界坐标生成爆炸。播放完的实例回池，连续击杀不会反复分配粒子节点。
func spawn_explosion(world_position: Vector2, power := 1.0) -> PixelExplosion:
	var effect: PixelExplosion
	if not _explosion_pool.is_empty():
		effect = _explosion_pool.pop_back()
	else:
		effect = EXPLOSION_SCENE.instantiate() as PixelExplosion
		add_child(effect)
		effect.finished.connect(_on_explosion_finished)
	effect.position = world_position.round()
	effect.play(power)
	return effect


func _on_explosion_finished(effect: PixelExplosion) -> void:
	if not is_instance_valid(effect) or _explosion_pool.has(effect):
		return
	if _explosion_pool.size() >= MAX_EXPLOSION_POOL:
		effect.queue_free()
	else:
		_explosion_pool.append(effect)


## 跌落/重置时立即清掉仍在播放的爆炸，避免旧位置残留余烟。
func clear_explosions() -> void:
	for child in get_children():
		if child is PixelExplosion:
			var explosion := child as PixelExplosion
			if explosion.active:
				explosion.stop()
			if not _explosion_pool.has(explosion):
				if _explosion_pool.size() >= MAX_EXPLOSION_POOL:
					explosion.queue_free()
				else:
					_explosion_pool.append(explosion)
		elif child is SlimeRibbonBurst:
			var slime := child as SlimeRibbonBurst
			if slime.active:
				slime.stop()
			if not _slime_pool.has(slime):
				if _slime_pool.size() >= MAX_EXPLOSION_POOL:
					slime.queue_free()
				else:
					_slime_pool.append(slime)
		elif child is WoundBloodSprayType:
			var wound := child as WoundBloodSprayType
			if wound.active:
				wound.stop()
			_recycle_wound(wound)
		elif child is CorpseLandingDustType:
			# 重开和倒带与其他特效共用一个清理入口，旧落点不留尘。
			child.stop()
			_on_corpse_dust_finished(child)


func explosion_pool_size() -> int:
	return _explosion_pool.size()


## 死亡完整版：起点立即留墙漆，随后播放连续主液幕、拉丝和重液滴。
func spawn_slime_burst(world_position: Vector2, force_direction: Vector2,
		power := 1.0) -> SlimeRibbonBurst:
	return _spawn_slime_ribbon(world_position, force_direction, power, false)


## 普通受击弱化版：更短、更细、更少液滴，并使用较弱的震屏和起点喷漆。
func spawn_slime_hit(world_position: Vector2, force_direction: Vector2,
		power := 0.36) -> SlimeRibbonBurst:
	return _spawn_slime_ribbon(world_position, force_direction, power, true)


## 棒球棍近战命中：单色族液爆 + 短促定向破口 + 更强震屏。
func spawn_bat_hit(world_position: Vector2, force_direction: Vector2,
		power := 1.0, lethal_override := false,
		follow_target: Node2D = null) -> SlimeRibbonBurst:
	return _spawn_slime_ribbon(world_position, force_direction, power, false, true,
			lethal_override, follow_target)


func _spawn_slime_ribbon(world_position: Vector2, force_direction: Vector2,
		power: float, weak: bool, melee := false,
		lethal_override := false, follow_target: Node2D = null) -> SlimeRibbonBurst:
	var effect: SlimeRibbonBurst
	if not _slime_pool.is_empty():
		effect = _slime_pool.pop_back()
	else:
		effect = SLIME_RIBBON_SCENE.instantiate() as SlimeRibbonBurst
		add_child(effect)
		effect.finished.connect(_on_slime_finished)
		effect.paint_requested.connect(_on_slime_paint_requested.bind(effect))
	effect.position = world_position.round()
	# 注入关卡碰撞并接上撞墙信号：液滴真实撞上哪，污渍就长在哪。
	effect.level = host.level if host != null else null
	var impact_cb := _on_slime_wall_impact.bind(effect)
	if not effect.wall_impact.is_connected(impact_cb):
		effect.wall_impact.connect(impact_cb)
	var seed := randi()
	if seed == 0:
		seed = 1   ## seed=0 会让特效侧改用时间种子，主色推导会跑偏
	effect.play(power, force_direction, seed, weak, melee)
	# 第二层独立伤口微粒：主液幕负责冲击轮廓，小血滴在伤口附近短时续喷。
	_spawn_wound_blood(world_position, force_direction, power, seed,
			weak, melee, lethal_override, effect.current_color, follow_target)
	if host != null and host.has_method("add_camera_shake"):
		# 近战棍击震屏更重：钝器打击的"顿感"
		host.add_camera_shake(force_direction, power * (1.35 if melee else 1.0))
	return effect


func _spawn_wound_blood(world_position: Vector2, force_direction: Vector2,
		power: float, seed: int, weak: bool, melee: bool, lethal_override: bool,
		blood_color: Color, follow_target: Node2D = null) -> WoundBloodSprayType:
	var effect: WoundBloodSprayType
	if not _wound_pool.is_empty():
		effect = _wound_pool.pop_back()
	else:
		effect = WOUND_BLOOD_SCENE.instantiate() as WoundBloodSprayType
		add_child(effect)
		effect.finished.connect(_on_wound_finished)
	effect.position = world_position.round()
	# 明确致命覆盖用于爆炸桶等 1.0 强度击杀；普通高连段仍不会误升为致命档。
	var strong := lethal_override or (not weak and (not melee or power >= 1.2))
	effect.play(power, force_direction, seed, strong, blood_color, follow_target)
	return effect


func _on_wound_finished(effect: WoundBloodSprayType) -> void:
	_recycle_wound(effect)


func _recycle_wound(effect: WoundBloodSprayType) -> void:
	if not is_instance_valid(effect) or _wound_pool.has(effect):
		return
	if _wound_pool.size() >= MAX_WOUND_POOL:
		effect.queue_free()
	else:
		_wound_pool.append(effect)


func _on_slime_finished(effect: SlimeRibbonBurst) -> void:
	if not is_instance_valid(effect) or _slime_pool.has(effect):
		return
	if _slime_pool.size() >= MAX_EXPLOSION_POOL:
		effect.queue_free()
	else:
		_slime_pool.append(effect)


## 液幕前缘到位（0.12~0.15s）时释放微粒喷溅：每颗血滴独立弹道，
## 命中墙面/地面的真实落点才留渍，与本次空中液柱同一色相。
func _on_slime_paint_requested(world_position: Vector2, direction: Vector2,
		power: float, seed: int, weak: bool, effect: SlimeRibbonBurst) -> void:
	if host == null or host.paint_layer == null:
		return
	# 近战棍击按实际 power 从 58 递增到 72 颗；仍沿用本次主液幕的同一霓虹色族。
	var melee_count := clampi(roundi(58.0 + maxf(0.0, effect._power - 1.0) * 20.0),
			58, 72)
	var count := melee_count if effect._melee else (12 if weak else 34)
	host.paint_layer.spawn_spatter(world_position, direction,
			power * (0.5 if weak else 1.0), seed, effect.current_color, count)
	# 同一时刻冻结主液幕图集帧；管理器独立开关，关闭后旧碎渍逻辑不受影响。
	if host.paint_layer.has_method("spawn_wall_snapshot"):
		var progress := effect.elapsed / maxf(effect.duration, 0.001)
		host.paint_layer.spawn_wall_snapshot(world_position, direction, power,
				seed, weak, progress, effect.current_color)


## 液丝/液滴真实撞上墙/地：在精确撞点长出 D 式"一滩"（撞墙/撞地形状不同）。
func _on_slime_wall_impact(world_position: Vector2, radius: float, slot: int,
		on_wall: bool, weak: bool, effect: SlimeRibbonBurst) -> void:
	if host == null or host.paint_layer == null:
		return
	# 单色族：撞点留渍取本次爆裂主色（略压暗，像干掉的液渍）。
	host.paint_layer.add_impact_splat(world_position, radius, slot,
			weak, randi(), on_wall, effect.current_color.darkened(0.12))


func slime_pool_size() -> int:
	return _slime_pool.size()


func wound_pool_size() -> int:
	return _wound_pool.size()


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if host == null:
		return
	# 瞄准时激光指示：枪口 → 鼠标（世界坐标）
	var pl: KairullPlayer = host.player
	if pl != null and pl.aiming and not pl.dead:
		var gp: Dictionary = pl.gun_pose()
		if not gp.is_empty():
			var target: Vector2 = pl._aim_point()
			draw_line(gp["muzzle"], target, Color(1.0, 0.35, 0.4, 0.7), 1.5)
			draw_line(gp["muzzle"], target, Color(1.0, 0.75, 0.75, 0.25), 4.0)
			draw_circle(target, 4.0, Color(1.0, 0.4, 0.45, 0.9))
	for b in host.bullets:
		var p := Vector2(b["x"], b["y"])
		var v := Vector2(b["vx"], b["vy"]) / 60.0   ## 网页拖尾按每帧位移画
		draw_line(p, p - v * 0.9, Color(1, 0.88, 0.55, 0.4), 5.0)
		draw_line(p, p - v * 1.2, Color("#fff1b8"), 2.2)
	# Boss 法球：紫色能量球（外晕+内芯）
	for o in host.enemy_bullets:
		var op := Vector2(o["x"], o["y"])
		draw_circle(op, 9.0, Color(0.62, 0.35, 0.95, 0.35))
		draw_circle(op, 5.0, Color(0.78, 0.5, 1.0, 0.95))
		draw_circle(op, 2.0, Color(0.95, 0.9, 1.0))
	for f in host.fx:
		var fp := Vector2(f["x"], f["y"])
		var is_flash: bool = f["kind"] == "flash"
		var a: float = clampf(f["life"] * (10.0 if is_flash else 6.0), 0.0, 1.0)
		var col := Color("#fff6cf") if is_flash else Color("#ffd48a")
		col.a = a
		draw_circle(fp, 11.0 if is_flash else 5.0, col)
