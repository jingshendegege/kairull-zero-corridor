extends Node2D
class_name KairullBoss
## 悬浮小怪（小苏 BOSS 系素材降级为小怪：3 血、体型小、会吐法球）。
## AI：idle（悬停）→ chase（640px 内追踪）→ attack（近战接触 / 中距离法球）→ death
##
## AI 状态机：
##   idle   —— 原地悬浮待机
##   chase  —— 玩家在 640px 内：缓慢飞向玩家（约 90px/s）
##   attack —— 贴近（<150px）：播攻击 8 帧，命中帧对玩家造成击退（玩家 HP 系统未做）
##   hurt   —— 受击硬直 6 帧
##   death  —— 3 次受击后死亡，停在末帧
##
## 子弹/近战命中由 game 调 take_hit()。Boss 无重力，世界边界内活动。

signal boss_died
signal shoot_orb(from_pos: Vector2, velocity: Vector2)   ## 远程攻击出膛

const FS := 64.0              ## 帧格边长
const SCALE := 1.3            ## 小怪体型（比 Boss 小）
const FPS := 12.0
const HP_MAX := 3             ## 小怪 3 血（一击大残）
const CHASE_RANGE := 520.0
const ATTACK_RANGE := 150.0   ## 近战触发距离
const SHOOT_RANGE := 460.0    ## 进入此距离改为站定射击
const SHOOT_CD := 1.6         ## 射击冷却
const ORB_SPEED := 240.0
const CHASE_SPEED := 70.0     ## 小怪移速（慢，靠数量取胜）
const ATTACK_HIT_FRAME := 5   ## attack 第 5 帧产生命中判定

var state := "idle"
var frame := 0
var t := 0.0
var face := -1
var hp := HP_MAX
var dead := false
var hitstop := 0.0            ## 受击停帧
var shoot_cd := 0.0
var _orb_fired := false       ## 本次 attack 动作已出膛（每轮攻击只允许一发）
var player: Node2D            ## 由 game 注入

var _tex := {}
var _frames := {"idle": 7, "fly": 6, "attack": 8, "hurt": 6, "death": 8}
## 状态 → 动画名（chase 用 fly 飞行帧）
const CLIP_OF := {"idle": "idle", "chase": "fly", "attack": "attack",
	"hurt": "hurt", "death": "death"}
var _sprite: Sprite2D


func _ready() -> void:
	for k in _frames:
		_tex[k] = load("res://assets/boss/%s.png" % k)
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_sync_sprite()


func body_rect() -> Rect2:
	## 碰撞盒随体型缩放（底部中心）
	return Rect2(position.x - 22 * SCALE, position.y - 55 * SCALE,
			44 * SCALE, 55 * SCALE)


func set_state(s: String) -> void:
	if state != s:
		state = s
		frame = 0
		t = 0.0
		if s == "attack":
			_orb_fired = false


func take_hit(from_x: float, damage := 1) -> bool:
	if dead:
		return false
	hp -= damage
	hitstop = 0.08
	if hp <= 0:
		hp = 0
		dead = true
		set_state("death")
		boss_died.emit()
	else:
		set_state("hurt")
		# 受击击退（远离攻击来源）
		position.x += 26.0 * (1.0 if position.x > from_x else -1.0)
	queue_redraw()
	return true


## 血条：画在自己头顶上方（父节点先渲染，但血条在精灵区域之上不重叠）
func _draw() -> void:
	if dead:
		return
	var w := 90.0
	var ratio := float(hp) / HP_MAX
	var top := -FS * SCALE - 16.0
	draw_rect(Rect2(-w / 2, top, w, 8), Color(0.08, 0.1, 0.16, 0.85))
	var col := Color(0.55, 0.9, 0.45) if ratio > 0.5 else (Color(0.95, 0.75, 0.3) if ratio > 0.25 else Color(0.95, 0.35, 0.4))
	draw_rect(Rect2(-w / 2, top, w * ratio, 8), col)


func step(dt: float) -> void:
	if hitstop > 0.0:
		hitstop -= dt
		_sync_sprite()
		return
	if not dead and player != null:
		var dx: float = player.position.x - position.x
		var dy: float = player.position.y - position.y
		var dist := Vector2(dx, dy).length()
		if absf(dx) > 1.0:
			face = 1 if dx > 0 else -1
		shoot_cd = maxf(0.0, shoot_cd - dt)
		match state:
			"idle":
				if dist < CHASE_RANGE:
					set_state("chase")
			"chase":
				if dist > CHASE_RANGE * 1.25:
					set_state("idle")
				elif dist < ATTACK_RANGE:
					set_state("attack")   ## 贴身近战
				elif dist < SHOOT_RANGE and shoot_cd <= 0.0:
					set_state("attack")   ## 中距离站定射击（同一动画，命中帧出弹）
				else:
					var d := Vector2(dx, dy).normalized()
					position += d * CHASE_SPEED * dt
			"attack":
				# 命中帧：近战贴身→由 game 判重叠；中距离→发射法球
				if frame >= ATTACK_HIT_FRAME and not _orb_fired:
					_orb_fired = true
					if dist >= ATTACK_RANGE:
						shoot_cd = SHOOT_CD
						var from := position + Vector2(face * 30, -80)
						var dir := (player.position + Vector2(0, -30) - from).normalized()
						shoot_orb.emit(from, dir * ORB_SPEED)
			"hurt":
				pass
	# 帧推进
	t += dt
	var fi := int(floor(t * FPS))
	var total: int = _frames[CLIP_OF[state]]
	if fi >= total:
		match state:
			"idle", "chase":
				frame = 0
				t -= float(total) / FPS
				if state == "chase":
					pass
			"attack":
				set_state("chase")
			"hurt":
				set_state("chase")
			"death":
				frame = total - 1   ## 停在死亡末帧
	else:
		frame = fi
	_sync_sprite()


func _sync_sprite() -> void:
	if _sprite == null:
		return
	var clip: String = CLIP_OF[state]
	_sprite.texture = _tex[clip]
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(frame * FS, 0, FS, FS)
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * SCALE
	# 锚点 = 底部中心；翻面时 flip_h 绕左缘镜像，x 偏移取反
	_sprite.flip_h = face > 0
	_sprite.position = Vector2((-FS * 0.5) * SCALE if face < 0 else (-FS * 0.5) * SCALE,
			-FS * SCALE)
