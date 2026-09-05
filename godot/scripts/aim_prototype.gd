extends Node2D

## 七档吸附瞄准原型（纯静态枪方案）
##
## 用户决策 2026-08-31：只用姿势图里的静态枪，不叠独立旋转枪。
## 画面上只有一把枪，不存在重影。代价是瞄准是七档离散的，
## 且向下封顶 -25.1°（七档美术缺陷，见 aim_rig.gd 注释）。
##
## 操作：
##   鼠标移动  = 瞄准（按实测角吸到最近一档）
##   A         = 左右翻面
##   S         = 开/关像素取整
##   F         = 开/关调试信息
##   左键      = 打一发（弹道从该档实测 muzzle 出膛）

const PIXEL_SCALE := 2.0        ## 整体放大倍数（像素画用整数倍）

var rig: AimRig

var _facing_right := true
var _snap_enabled := true
var _debug_visible := true
var _aim_deg := 0.0             ## 鼠标原始角
var _fire_deg := 0.0            ## 实际发射角 = 所选档位实测角
var _pose: Dictionary = {}

# 姿势贴图缓存：档位名 → Texture2D
var _pose_tex: Dictionary = {}

# 角色 pivot（握把）对齐到的世界坐标。
# 取 y=400：muzzle 最大偏移约 200px*2，pivot 放太低时向下瞄会被画面裁掉。
var _anchor := Vector2(420, 400)

@onready var body_sprite: Sprite2D = $Body
@onready var muzzle_marker: Node2D = $MuzzleMarker
@onready var debug_label: Label = $UI/DebugLabel
@onready var tracer_layer: Node2D = $Tracers
@onready var debug_overlay: Node2D = $DebugOverlay


func _ready() -> void:
	rig = AimRig.new()

	for name in AimRig.POSES:
		var path := "res://assets/aim/pose_%s.png" % name
		var tex: Texture2D = load(path)
		if tex == null:
			push_error("缺少姿势贴图: " + path)
		_pose_tex[name] = tex

	body_sprite.scale = Vector2.ONE * PIXEL_SCALE

	# 调试叠加层要作为最后一个子节点绘制，才不会被 BG 盖住（见 aim_debug_overlay.gd）
	debug_overlay.host = self

	set_process(true)
	set_process_input(true)


## 无头渲染 / 自动化测试用：覆盖鼠标位置。
## 设为非空时 _process 与叠加层都用它代替真实鼠标。
var aim_override: Variant = null


func _aim_point() -> Vector2:
	if aim_override != null:
		return aim_override as Vector2
	return get_global_mouse_position()


func _process(_dt: float) -> void:
	var mouse := _aim_point()
	var pivot_world := _anchor

	_aim_deg = rig.aim_angle_deg(pivot_world, mouse, _facing_right)
	_pose = rig.pick_body_pose(_aim_deg)
	_fire_deg = float(_pose["angle"])

	var pose_name: String = _pose["name"]

	# 身体+枪一体：只换贴图和翻面，不做旋转
	body_sprite.texture = _pose_tex[pose_name]
	body_sprite.position = pivot_world
	body_sprite.flip_h = not _facing_right
	# 按该档 pivot 对齐，消除切档时的整体跳动
	body_sprite.offset = AimRig.pose_offset(pose_name, _facing_right)

	# 枪口挂点：查该档实测 muzzle，不做旋转变换
	var mw := rig.muzzle_world(pivot_world, pose_name, PIXEL_SCALE, _facing_right)
	if _snap_enabled:
		mw = AimRig.snap_px(mw, PIXEL_SCALE)
	muzzle_marker.position = mw

	debug_overlay.queue_redraw()
	_update_debug()


func _input(ev: InputEvent) -> void:
	if ev.is_action_pressed("flip_side"):
		_facing_right = not _facing_right
	elif ev.is_action_pressed("toggle_snap"):
		_snap_enabled = not _snap_enabled
	elif ev.is_action_pressed("toggle_debug"):
		_debug_visible = not _debug_visible
		debug_label.visible = _debug_visible
	elif ev is InputEventMouseButton and ev.pressed \
			and ev.button_index == MOUSE_BUTTON_LEFT:
		_fire()


func _fire() -> void:
	# 弹道从该档实测 muzzle 出膛，方向 = 该档实测角。
	# 用档位角而非鼠标原始角，保证弹道与画面上那把静态枪的指向严格一致。
	var origin := muzzle_marker.position
	var deg := _fire_deg if _facing_right else 180.0 - _fire_deg
	var dir := Vector2(cos(deg_to_rad(-deg)), sin(deg_to_rad(-deg)))
	var tracer := Line2D.new()
	tracer.width = 2.0
	tracer.default_color = Color(1.0, 0.85, 0.3, 0.9)
	tracer.add_point(origin)
	tracer.add_point(origin + dir * 900.0)
	tracer_layer.add_child(tracer)
	var t := get_tree().create_timer(0.06)
	t.timeout.connect(func():
		if is_instance_valid(tracer):
			tracer.queue_free())


func _update_debug() -> void:
	if not _debug_visible:
		return
	var pose_name: String = _pose.get("name", "?")
	var polar: Dictionary = rig.muzzle_offset_polar(pose_name) if pose_name != "?" \
		else {"length": 0.0, "angle_deg": 0.0}
	var snap_err: float = absf(_aim_deg - _fire_deg)
	var lines := [
		"七档吸附瞄准原型 [纯静态枪·无重影]",
		"",
		"鼠标角       %+7.2f°" % _aim_deg,
		"发射角(档位) %+7.2f°   吸附误差 %.2f°" % [_fire_deg, snap_err],
		"当前档       %-9s" % pose_name,
		"",
		"pivot(握把)  (%.1f, %.1f) 贴图内" % [
			_pose.get("pivot", Vector2.ZERO).x, _pose.get("pivot", Vector2.ZERO).y],
		"muzzle(枪口) (%.1f, %.1f) 贴图内 → (%.0f, %.0f) 世界" % [
			_pose.get("muzzle", Vector2.ZERO).x, _pose.get("muzzle", Vector2.ZERO).y,
			muzzle_marker.position.x, muzzle_marker.position.y],
		"该档偏移     长%.1fpx 角%+.1f°" % [polar["length"], polar["angle_deg"]],
		"",
		"朝向 %s   像素取整 %s   缩放 x%.0f" % [
			"右" if _facing_right else "左",
			"开" if _snap_enabled else "关",
			PIXEL_SCALE],
		"",
		"[A]翻面  [S]取整开关  [F]调试  [左键]开火",
		"瞄准范围 %.1f°~%.1f°（向下封顶：七档美术缺陷）" % [
			AimRig.AIM_ANGLE_MIN, AimRig.AIM_ANGLE_MAX],
	]
	debug_label.text = "\n".join(lines)
