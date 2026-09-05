extends SceneTree
## CRT 垂直回卷合同：检查层级、BackBufferCopy 顺序、按阶段零成本开关与循环方向。

const TRANSITION := preload("res://scripts/crt_roll_transition.gd")

var _pass := 0
var _fail := 0


class MockHost extends Node:
	var phase := "playing"
	var progress := 0.0

	func timeline_view_model() -> Dictionary:
		return {"phase": phase, "glitch_progress": progress}


func _init() -> void:
	call_deferred("_run")


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _run() -> void:
	var host := MockHost.new()
	var transition = TRANSITION.new()
	transition.host = host
	get_root().add_child(host)
	get_root().add_child(transition)
	await process_frame

	print("== 合成层与捕获顺序 ==")
	var state: Dictionary = transition.effect_state()
	ok(state["layer"] == 4, "效果层高于 layer=3 的 HUD/时间信号层")
	ok(transition.process_mode == Node.PROCESS_MODE_ALWAYS, "换场冻结期间仍能更新")
	ok(state["copy_before_quad"], "BackBufferCopy 位于 shader ColorRect 之前")
	ok(state["mouse_filter"] == Control.MOUSE_FILTER_IGNORE, "全屏层不拦截键鼠")
	ok(is_equal_approx(float(state["fault_strength"]), 0.75), "故障强度默认 0.75")
	ok(transition._quad.size == get_root().get_visible_rect().size,
			"shader ColorRect 覆盖完整可见视口", str(transition._quad.size))
	ok(transition._material.shader == TRANSITION.CRT_SHADER, "全屏层使用专用 CRT shader")

	print("== 非 interference 零成本 ==")
	ok(not state["active"] and not state["quad_visible"], "初始不绘制全屏 quad")
	ok(state["copy_mode"] == BackBufferCopy.COPY_MODE_DISABLED, "初始不复制视口")
	host.phase = "rewinding"
	host.progress = 0.7
	await process_frame
	state = transition.effect_state()
	ok(not state["active"] and state["copy_mode"] == BackBufferCopy.COPY_MODE_DISABLED,
			"倒带阶段不会误启用 CRT 捕获")

	print("== interference 启用与钳制 ==")
	host.phase = "interference"
	host.progress = 0.35
	await process_frame
	state = transition.effect_state()
	ok(state["active"] and state["quad_visible"], "花屏阶段显示全屏 quad")
	ok(state["copy_mode"] == BackBufferCopy.COPY_MODE_VIEWPORT,
			"花屏阶段使用 COPY_MODE_VIEWPORT")
	ok(is_equal_approx(float(state["progress"]), 0.35), "读取宿主 glitch_progress")
	host.progress = 1.8
	await process_frame
	ok(is_equal_approx(float(transition.effect_state()["progress"]), 1.0), "越界进度钳到 1")
	host.progress = -0.4
	await process_frame
	ok(is_equal_approx(float(transition.effect_state()["progress"]), 0.0), "负进度钳到 0")
	transition.fault_strength = 0.0
	transition.apply_view_model({"phase": "interference", "glitch_progress": 0.4})
	ok(is_equal_approx(float(transition._material.get_shader_parameter("fault_strength")), 0.0),
			"fault_strength=0 可运行时关闭失锁、撕裂、雪花与回扫带")
	transition.fault_strength = 0.75

	print("== 停顿抽动、整幅上卷与底部环回公式 ==")
	var monotonic := true
	var previous := -1.0
	for index in range(101):
		var offset: float = TRANSITION.roll_offset_for_progress(index / 100.0)
		monotonic = monotonic and offset >= previous - 0.000001
		previous = offset
	ok(monotonic and is_equal_approx(previous, 1.0), "分段失锁曲线始终只向上且最终走完一圈")
	var stall_delta: float = TRANSITION.roll_offset_for_progress(0.08) \
			- TRANSITION.roll_offset_for_progress(0.04)
	var jerk_delta: float = TRANSITION.roll_offset_for_progress(0.13) \
			- TRANSITION.roll_offset_for_progress(0.09)
	ok(jerk_delta > stall_delta * 3.0, "同一段内先停顿后明显抽动",
			"stall=%.4f jerk=%.4f" % [stall_delta, jerk_delta])
	ok(is_equal_approx(TRANSITION.roll_offset_for_progress(0.37, 0.0), 0.37),
			"fault_strength=0 恢复匀速整屏上卷")
	var roll_at_quarter: float = TRANSITION.roll_offset_for_progress(0.25)
	ok(is_equal_approx(TRANSITION.source_y_for_output(0.0, 0.25), roll_at_quarter),
			"屏幕顶端采样更靠下内容，因此画面向上移动")
	ok(is_equal_approx(TRANSITION.source_y_for_output(0.90, 0.25),
			fposmod(0.90 + roll_at_quarter, 1.0)),
			"出顶内容通过 fract 从屏幕底部接回")
	var shader_code: String = transition._material.shader.code
	ok("hint_screen_texture" in shader_code and "filter_nearest" in shader_code,
			"shader 只走 GPU SCREEN_TEXTURE 且 nearest 采样")
	ok("fract(sample_uv.y + roll_offset)" in shader_code,
			"shader 实际使用与测试一致的整屏循环公式")
	ok("sync_tear_px" in shader_code and "rgb_separation_px" in shader_code,
			"shader 含可调宽同步撕裂和 3~5px RGB 分离")
	ok("stable_hash" in shader_code and "retrace_strength" in shader_code,
			"shader 含局部确定性雪花和黑色回扫带")
	ok("TIME" not in shader_code, "故障图样不读取 shader 时钟，不会逐像素高频乱闪")

	host.phase = "playing"
	await process_frame
	state = transition.effect_state()
	ok(not state["quad_visible"] and state["copy_mode"] == BackBufferCopy.COPY_MODE_DISABLED,
			"阶段结束立即关闭复制与全屏绘制")

	transition.free()
	host.free()
	for i in range(3):
		await process_frame
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
