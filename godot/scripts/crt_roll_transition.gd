class_name CRTRollTransition
extends CanvasLayer
## 老电视垂直回卷：只在 interference 阶段启用 GPU 屏幕复制与全屏 shader。
## layer=4 高于 HUD/TimeSignal(layer=3)，因此回卷的是包含人物和界面的最终合成画面。

const EFFECT_LAYER := 4
const CRT_SHADER := preload("res://shaders/crt_vertical_roll.gdshader")
const ROLL_SEGMENTS := 6.0

@export_range(0.0, 1.0, 0.05) var fault_strength := 0.75
@export_range(10.0, 24.0, 1.0) var sync_tear_px := 18.0
@export_range(3.0, 5.0, 0.5) var rgb_separation_px := 4.0
@export_range(0.0, 0.08, 0.002) var snow_amount := 0.028
@export_range(0.0, 1.0, 0.05) var retrace_strength := 0.72

var host: Node
var _copy: BackBufferCopy
var _quad: ColorRect
var _material: ShaderMaterial
var _active := false
var _progress := 0.0


## 与 shader 的确定性停顿/抽动曲线同义；始终单调，fault=0 退回匀速上卷。
static func roll_offset_for_progress(progress: float, fault: float = 0.75) -> float:
	var p := clampf(progress, 0.0, 1.0)
	var strength := clampf(fault, 0.0, 1.0)
	if p >= 0.999999:
		return 1.0
	var segment := floorf(p * ROLL_SEGMENTS)
	var local_progress := fposmod(p * ROLL_SEGMENTS, 1.0)
	var jerk := smoothstep(0.55, 0.85, local_progress)
	var stepped_roll := (segment + jerk) / ROLL_SEGMENTS
	return lerpf(p, stepped_roll, strength)


## 与 shader 的 fract(SCREEN_UV.y + roll_offset) 同义，供测试校验上卷方向与底部环回。
static func source_y_for_output(output_y: float, progress: float, fault: float = 0.75) -> float:
	return fposmod(output_y + roll_offset_for_progress(progress, fault), 1.0)


func _ready() -> void:
	layer = EFFECT_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_capture_stack()
	_apply_state(false, 0.0)
	get_viewport().size_changed.connect(_sync_viewport_size)
	_sync_viewport_size()


func _process(_dt: float) -> void:
	if is_instance_valid(host) and host.has_method("timeline_view_model"):
		var raw: Variant = host.call("timeline_view_model")
		apply_view_model(raw if raw is Dictionary else {})
	else:
		apply_view_model({})


## 测试与宿主都走同一入口；未知 phase、NaN 或越界进度一律安全关闭/钳制。
func apply_view_model(raw: Dictionary) -> void:
	var phase := str(raw.get("phase", "playing"))
	var value: Variant = raw.get("glitch_progress", 0.0)
	var progress: float = float(value) if value is float or value is int else 0.0
	if not is_finite(progress):
		progress = 0.0
	_apply_state(phase == "interference", clampf(progress, 0.0, 1.0))


func effect_state() -> Dictionary:
	return {
		"active": _active,
		"progress": _progress,
		"fault_strength": fault_strength,
		"layer": layer,
		"copy_mode": _copy.copy_mode if _copy != null else BackBufferCopy.COPY_MODE_DISABLED,
		"quad_visible": _quad.visible if _quad != null else false,
		"copy_before_quad": _copy != null and _quad != null and _copy.get_index() < _quad.get_index(),
		"mouse_filter": _quad.mouse_filter if _quad != null else Control.MOUSE_FILTER_STOP,
	}


func _build_capture_stack() -> void:
	# 顺序是功能合同：VIEWPORT 拷贝必须先于 SCREEN_TEXTURE ColorRect 绘制。
	_copy = BackBufferCopy.new()
	_copy.name = "FinalViewportCopy"
	_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_copy)

	_material = ShaderMaterial.new()
	_material.shader = CRT_SHADER
	_quad = ColorRect.new()
	_quad.name = "CRTVerticalRoll"
	_quad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quad.color = Color.WHITE
	_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quad.material = _material
	_quad.visible = false
	add_child(_quad)


func _apply_state(active: bool, progress: float) -> void:
	_active = active
	_progress = progress
	if _copy == null or _quad == null or _material == null:
		return
	# 非花屏阶段彻底关闭复制和绘制，不留下常驻全屏采样成本。
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if active \
			else BackBufferCopy.COPY_MODE_DISABLED
	_quad.visible = active
	_material.set_shader_parameter("roll_progress", progress)
	_material.set_shader_parameter("fault_strength", clampf(fault_strength, 0.0, 1.0))
	_material.set_shader_parameter("sync_tear_px", clampf(sync_tear_px, 10.0, 24.0))
	_material.set_shader_parameter("rgb_separation_px", clampf(rgb_separation_px, 3.0, 5.0))
	_material.set_shader_parameter("snow_amount", clampf(snow_amount, 0.0, 0.08))
	_material.set_shader_parameter("retrace_strength", clampf(retrace_strength, 0.0, 1.0))


func _sync_viewport_size() -> void:
	if _material == null:
		return
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	_material.set_shader_parameter("viewport_size", viewport_size.max(Vector2.ONE))
