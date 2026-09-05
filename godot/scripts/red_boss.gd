extends Node2D
class_name RedBoss
## Red 关底 Boss（小苏皂水 Cute Pixel 素材，66×66 帧单行图集）。
## 地面型高攻击性 Boss：100 血，奔跑追击，贴身双段连击，攻击冷却极短。
##
## AI：idle（待机）→ chase（700px 内追击 200px/s）→ attack1/attack2 交替连击
##     （<110px）→ hurt（受击 0.25s 硬直）→ death（停末帧）
## 近战命中由 game 在攻击活跃帧判身体重叠。有重力，会掉下平台（守出口高台即可）。

signal boss_died

const FS := 66.0
const SCALE := 2.2            ## 66px → 145px
const FPS := 14.0
const HP_MAX := 100
const CHASE_RANGE := 700.0
const ATTACK_RANGE := 110.0
const CHASE_SPEED := 200.0
const ATTACK_CD := 0.45       ## 攻击欲望：连击间隔极短
const HURT_T := 0.22
## 攻击活跃帧（攻击判定窗口）
const ATK_ACTIVE := {"attack1": [5, 9], "attack2": [7, 12]}
const GRAV := 0.72

var state := "idle"
var frame := 0
var t := 0.0
var face := -1
var hp := HP_MAX
var dead := false
var vy := 0.0
var on_ground := false
var attack_cd := 0.0
var hurt_t := 0.0
var next_attack := "attack1"
var player: Node2D
var level: CorridorLevel

var _tex := {}
var _frames := {"idle": 8, "run": 10, "jump": 9, "attack1": 15, "attack2": 18,
	"hurt": 4, "death": 16}
const CLIP_OF := {"idle": "idle", "chase": "run", "attack1": "attack1",
	"attack2": "attack2", "hurt": "hurt", "death": "death", "jump": "jump"}
## 剪辑名 → 素材文件名（首字母大写；hurt 用 Hit.png）
const FILE_OF := {"idle": "Idle", "run": "Run", "jump": "Jump",
	"attack1": "Attack1", "attack2": "Attack2", "hurt": "Hit", "death": "Death"}
var _sprite: Sprite2D


func _ready() -> void:
	for k in _frames:
		_tex[k] = load("res://assets/red/%s.png" % FILE_OF[k])
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_sync_sprite()


func body_rect() -> Rect2:
	return Rect2(position.x - 40, position.y - 120, 80, 120)


func set_state(s: String) -> void:
	if state != s:
		state = s
		frame = 0
		t = 0.0


func take_hit(from_x: float, damage := 1) -> bool:
	if dead:
		return false
	hp = maxi(0, hp - damage)
	if hp <= 0:
		dead = true
		set_state("death")
		boss_died.emit()
	elif hurt_t <= 0.0 and state != "attack1" and state != "attack2":
		# 受击硬直（攻击动作中不被打断——有攻击欲望的 Boss 不怂）
		hurt_t = HURT_T
		set_state("hurt")
	queue_redraw()
	return true


func step(dt: float) -> void:
	hurt_t = maxf(0.0, hurt_t - dt)
	attack_cd = maxf(0.0, attack_cd - dt)
	if not dead and player != null:
		var dx: float = player.position.x - position.x
		var dist := absf(dx)
		if absf(dx) > 1.0:
			face = 1 if dx > 0 else -1
		match state:
			"idle":
				if dist < CHASE_RANGE:
					set_state("chase")
			"chase":
				if dist > CHASE_RANGE * 1.3:
					set_state("idle")
				elif dist < ATTACK_RANGE and attack_cd <= 0.0 and on_ground:
					set_state(next_attack)
				elif on_ground:
					position.x += CHASE_SPEED * face * dt
			"attack1", "attack2":
				pass   ## 帧推进驱动；命中判定在 game
			"hurt":
				if hurt_t <= 0.0:
					set_state("chase")
		# 重力 + 地面
		if level != null:
			vy += GRAV * dt * 60.0
			position.y += vy * dt * 60.0
			on_ground = false
			if vy >= 0.0 and level.solid_at(position.x, position.y):
				position.y = floori(position.y / 32) * 32 - 0.1
				vy = 0.0
				on_ground = true
			position.x = clampf(position.x, 20.0, level.world_w - 20.0)
	# 帧推进
	t += dt
	var fi := int(floor(t * FPS))
	var total: int = _frames[CLIP_OF[state]]
	if fi >= total:
		match state:
			"idle", "chase":
				frame = 0
				t -= float(total) / FPS
			"attack1", "attack2":
				attack_cd = ATTACK_CD
				next_attack = "attack2" if state == "attack1" else "attack1"
				set_state("chase")
			"hurt":
				set_state("chase")
			"death":
				frame = total - 1
	else:
		frame = fi
	_sync_sprite()


## 当前攻击是否处于活跃帧（game 用来判命中）
func attack_active() -> bool:
	if state != "attack1" and state != "attack2":
		return false
	var win: Array = ATK_ACTIVE[state]
	return frame >= win[0] and frame <= win[1]


func _draw() -> void:
	# 血条（头顶）
	if dead:
		return
	var w := 110.0
	var ratio := float(hp) / HP_MAX
	var top := -FS * SCALE - 14.0
	draw_rect(Rect2(-w / 2, top, w, 9), Color(0.08, 0.1, 0.16, 0.85))
	var col := Color(0.95, 0.45, 0.55) if ratio > 0.25 else Color(1.0, 0.25, 0.3)
	draw_rect(Rect2(-w / 2, top, w * ratio, 9), col)


func _sync_sprite() -> void:
	if _sprite == null:
		return
	var clip: String = CLIP_OF[state]
	_sprite.texture = _tex[clip]
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(frame * FS, 0, FS, FS)
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * SCALE
	_sprite.flip_h = face > 0
	# 锚点：底部中心；翻面绕左缘镜像需补偿
	_sprite.position = Vector2(-FS * 0.5 * SCALE, -FS * SCALE)
	# 受击无敌期闪烁（视觉反馈）
	_sprite.modulate.a = 0.5 if hurt_t > 0.0 else 1.0
