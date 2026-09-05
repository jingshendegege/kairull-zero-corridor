extends Node2D
class_name HornetBoss
## 大黄蜂 Boss（空洞武士 HollowKatana 移植：素材 + 索敌机制 + 技能动画）。
## AI 结构逆向自 HollowKatana.exe：
##   索敌 —— |dx| < 520 且 LOS（每 8px 采样实心）才进入战斗；否则 idle
##   技能选择（按距离分档，原作 cmp 分支结构）：
##     < 200px   squat(10帧蓄力) → dash_on_floor(2帧, 620px/s 冲撞, 接触伤害)
##     200-460px throw_sword(16帧, 第8帧出剑 480px/s, 八方瞄准)
##     > 460px   throw_silk(17帧, 第9帧三向丝线 320px/s)
##     每第 3 次技能改用 throw_barb(8帧, 第5帧抛物棘刺, 撞墙 barb_break)
##   技能间冷却 75 tick（逆向帧窗口：25/50/75/80/90）
##   受击：hitstop + 白闪 + 受伤音效变体；5 血，死亡定格尸体
##
## 接口与 RedBoss 一致：player/level/dead/step/take_hit/body_rect/
## attack_active/boss_died。投掷物自管（sword/silk/barb 精灵子节点）。

signal boss_died

const SCALE := 0.75             ## 源帧 ~150px → 约 110px，Boss 体格压玩家一头
const FPS := 12.0
const HP_MAX := 18   ## 用户决策 2026-09-02：血条调高，棍击战更耐打
const AGGRO_RANGE := 520.0
const DASH_RANGE := 200.0
const SWORD_RANGE := 460.0
const RUN_SPEED := 120.0
const DASH_SPEED := 620.0
const DASH_TICKS := 18
const SWORD_SPEED := 480.0
const SILK_SPEED := 320.0
const BARB_GRAVITY := 800.0
const SKILL_CD := 75            ## 技能冷却 tick（逆向窗口值）
const SWORD_RELEASE := 8        ## throw_sword 第 8 帧出剑
const SILK_RELEASE := 9
const BARB_RELEASE := 5

var state := "idle"
var frame := 0                  ## 状态内 tick
var face := -1
var hp := HP_MAX
var dead := false
var hitstop := 0.0
var cooldown := 0
var skill_count := 0
var player: Node2D
var level: CorridorLevel

var _tex := {}                  ## action -> [Texture2D]
var _frames := {"idle": 6, "run": 8, "squat": 10, "dash_on_floor": 2,
	"throw_sword": 16, "throw_silk": 17, "throw_barb": 8, "fall": 4}
var _sprite: Sprite2D
var _projs: Array = []          ## 自管投掷物
var _released := false          ## 本技能已出膛
var _dash_dir := 0
var _game: Node                 ## play_sfx 用


func _ready() -> void:
	_game = get_parent()
	for action in _frames:
		var arr: Array = []
		for i in range(1, _frames[action] + 1):
			arr.append(load("res://assets/enemy/hornet/%s/%d.png" % [action, i]))
		_tex[action] = arr
	for proj in ["sword", "silk", "barb_loose", "barb_break"]:
		var counts := {"sword": 3, "silk": 9, "barb_loose": 5, "barb_break": 3}
		var arr: Array = []
		for i in range(1, counts[proj] + 1):
			arr.append(load("res://assets/enemy/hornet/%s/%d.png" % [proj, i]))
		_tex[proj] = arr
	var vfx_arr: Array = []
	for i in range(1, 7):
		vfx_arr.append(load("res://assets/enemy/hornet/vfx_dash_on_floor/%d.png" % i))
	_tex["vfx_dash"] = vfx_arr
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_sync_sprite()


## 重置（Backspace 连带）：回出口驻守位，血量/技能冷却/投掷物全部还原
func reset_to(pos: Vector2) -> void:
	position = pos
	hp = HP_MAX
	dead = false
	state = "idle"
	frame = 0
	face = -1
	hitstop = 0.0
	cooldown = 0
	skill_count = 0
	_released = false
	_dash_dir = 0
	for p in _projs:
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	_projs.clear()
	if _sprite != null:
		_sprite.modulate = Color.WHITE
		_sprite.visible = true
		_sync_sprite()


func body_rect() -> Rect2:
	return Rect2(position.x - 20 * SCALE * 2, position.y - 130 * SCALE,
			40 * SCALE * 2, 130 * SCALE)


func attack_active() -> bool:
	return state == "dash" and not dead


func take_hit(_from_x: float, _damage := 1) -> bool:
	if dead:
		return false
	hp -= 1
	hitstop = 0.09
	_sprite.modulate = Color(3.0, 3.0, 3.0)   ## 受击白闪
	if hp <= 0:
		hp = 0
		dead = true
		state = "dead"
		boss_died.emit()
	## 受击叫声已关闭（用户决策 2026-09-02），保留白闪与顿帧
	return true


func step(dt: float) -> void:
	_update_projs(dt)
	if hitstop > 0.0:
		hitstop -= dt
		if hitstop <= 0.0 and not dead:
			_sprite.modulate = Color.WHITE
		return
	if dead or player == null:
		_sync_sprite()
		return
	if cooldown > 0:
		cooldown -= 1
	frame += 1
	var dx: float = player.position.x - position.x
	var dist := absf(dx)
	if dist > 1.0 and state != "dash":
		face = 1 if dx > 0 else -1

	match state:
		"idle":
			if dist < AGGRO_RANGE and _has_los():
				_set_state("run")
		"run":
			if not _has_los() or dist >= AGGRO_RANGE * 1.3:
				_set_state("idle")
			elif cooldown <= 0:
				_pick_skill(dist)
			elif dist > 300.0:
				_move(face * RUN_SPEED * dt)
		"squat":
			# 蓄力 10 帧（约 50 tick）→ 冲撞；逆向：squat 是 dash 的前置夸张压缩
			if frame >= 50:
				_dash_dir = face
				_set_state("dash")
				_sfx("enemy_dash")
		"dash":
			_move(_dash_dir * DASH_SPEED * dt)
			# 冲撞残影：每 3 tick 在原地留一段 vfx_dash 序列（播完自毁）
			if frame % 3 == 0:
				_spawn_dash_vfx()
			if frame >= DASH_TICKS:
				cooldown = SKILL_CD
				_set_state("idle")
		"throw_sword":
			if not _released and _anim_frame() >= SWORD_RELEASE:
				_released = true
				_spawn_proj("sword", 520.0 * face, 0.0)
				_sfx("enemy_throw_sword")
			if _anim_frame() >= _frames["throw_sword"] - 1:
				_end_skill()
		"throw_silk":
			if not _released and _anim_frame() >= SILK_RELEASE:
				_released = true
				for ang in [-0.31, 0.0, 0.31]:   ## 三向 ±18°
					var dir := Vector2(face, 0).rotated(ang)
					_spawn_proj("silk", dir.x * SILK_SPEED, dir.y * SILK_SPEED)
				_sfx("enemy_throw_silk")
			if _anim_frame() >= _frames["throw_silk"] - 1:
				_end_skill()
		"throw_barb":
			if not _released and _anim_frame() >= BARB_RELEASE:
				_released = true
				# 抛物棘刺：朝玩家方向抛出，带重力
				_spawn_proj("barb", 260.0 * face, -220.0)
				_sfx("enemy_throw_barbs")
			if _anim_frame() >= _frames["throw_barb"] - 1:
				_end_skill()
	_sync_sprite()


func _pick_skill(dist: float) -> void:
	skill_count += 1
	_released = false
	if skill_count % 3 == 0:
		_set_state("throw_barb")
	elif dist < DASH_RANGE:
		_set_state("squat")
	elif dist < SWORD_RANGE:
		_set_state("throw_sword")
	else:
		_set_state("throw_silk")


func _end_skill() -> void:
	cooldown = SKILL_CD
	_set_state("idle")


func _move(dx: float) -> void:
	var nx: float = position.x + dx
	if level == null or not level.solid_at(nx + signf(dx) * 24.0, position.y - 60.0):
		position.x = nx


## 投掷物：精灵子节点自管生命周期，撞玩家掉血、撞墙消散（棘刺播碎裂）
func _spawn_proj(kind: String, vx: float, vy: float) -> void:
	var s := Sprite2D.new()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(SCALE, SCALE)
	s.flip_h = vx < 0
	add_child(s)
	var anim := "barb_loose" if kind == "barb" else kind
	_projs.append({"kind": kind, "anim": anim, "x": position.x + face * 40.0,
		"y": position.y - 90.0 * SCALE, "vx": vx, "vy": vy, "t": 0.0,
		"node": s, "dead": false})


## 冲撞残影：复用投掷物管道，零速度、barb_break 式播完即毁
func _spawn_dash_vfx() -> void:
	var s := Sprite2D.new()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(SCALE, SCALE)
	s.flip_h = _dash_dir < 0
	s.modulate = Color(1.0, 1.0, 1.0, 0.8)
	add_child(s)
	_projs.append({"kind": "vfx_dash", "anim": "vfx_dash", "x": position.x,
		"y": position.y - 70.0 * SCALE, "vx": 0.0, "vy": 0.0, "t": 0.0,
		"node": s, "dead": false})


func _update_projs(dt: float) -> void:
	for p in _projs:
		if p["dead"]:
			continue
		p["t"] += dt
		if p["kind"] == "barb":
			p["vy"] += BARB_GRAVITY * dt
		p["x"] += p["vx"] * dt
		p["y"] += p["vy"] * dt
		if p["kind"] == "vfx_dash":
			# 冲撞残影：无伤害无碰撞，6 帧播完即毁
			var vfi := int(p["t"] * 18.0)
			if vfi >= _tex["vfx_dash"].size():
				p["dead"] = true
				p["node"].queue_free()
				continue
			p["node"].texture = _tex["vfx_dash"][vfi]
			p["node"].position = Vector2(p["x"], p["y"]) - position
			continue
		var hit := false
		if player != null:
			var pr := Rect2(player.position.x - player.w / 2, player.position.y - player.h,
					player.w, player.h)
			if pr.has_point(Vector2(p["x"], p["y"])):
				player.take_damage(1, p["x"])
				hit = true
		var on_wall: bool = level != null and level.solid_at(p["x"], p["y"])
		if p["kind"] == "barb_break":
			# 碎裂动画播完即销毁
			var fi := int(p["t"] * FPS)
			if fi >= _tex["barb_break"].size():
				p["dead"] = true
				p["node"].queue_free()
				continue
		elif hit or on_wall or p["t"] > 4.0:
			if p["kind"] == "barb" and on_wall:
				# 棘刺撞墙 → 碎裂动画
				p["kind"] = "barb_break"
				p["anim"] = "barb_break"
				p["t"] = 0.0
				p["vx"] = 0.0
				p["vy"] = 0.0
				continue
			p["dead"] = true
			p["node"].queue_free()
			continue
		var frames: Array = _tex[p["anim"]]
		var tex: Texture2D = frames[int(p["t"] * FPS) % frames.size()]
		p["node"].texture = tex
		p["node"].position = Vector2(p["x"], p["y"]) - position
	_projs = _projs.filter(func(p: Dictionary) -> bool: return not p["dead"])


func _has_los() -> bool:
	if level == null:
		return true
	var a := position + Vector2(0, -70.0)
	var b := player.position + Vector2(0, -46.0)
	var d := b - a
	var steps := int(d.length() / 8.0)
	for i in range(1, steps):
		var p := a + d * (float(i) / steps)
		if level.solid_at(p.x, p.y):
			return false
	return true


func _anim_frame() -> int:
	return mini(int(frame / 60.0 * FPS), int(_frames.get(state, 1)) - 1)


func _set_state(s: String) -> void:
	if state != s:
		state = s
		frame = 0


func _sfx(key: String) -> void:
	if _game != null and _game.has_method("play_sfx"):
		_game.play_sfx(key)


func _sync_sprite() -> void:
	var action := "idle"
	if _frames.has(state):
		action = state
	var frames: Array = _tex[action]
	var fi := 0 if dead else mini(int(frame / 60.0 * FPS), frames.size() - 1)
	if dead:
		fi = _tex["fall"].size() - 1
		frames = _tex["fall"]
	var t: Texture2D = frames[fi]
	_sprite.texture = t
	_sprite.flip_h = face > 0   ## 素材朝左；朝右时镜像
	_sprite.position = Vector2(0, -t.get_height() * SCALE * 0.5)
	_sprite.scale = Vector2(SCALE, SCALE)
