extends SceneTree
## 通关层只读宿主：渐黑/白字/延迟输入提示，不能停止音乐/改相机/切关/暂停树。
const VICTORY := preload("res://scripts/victory_transition.gd")
var passed := 0
var failed := 0

class FakeHost extends Node2D:
	var level_cleared := false
	var timeline_enabled := true
	var music := "unchanged-music-instance"
	var camera_position := Vector2(120, 220)


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _run() -> void:
	var host := FakeHost.new()
	root.add_child(host)
	var overlay := VICTORY.new()
	overlay.host = host
	host.add_child(overlay)
	overlay.set_process(false)
	check(not overlay.visible and not overlay.is_ready(), "未通关时完全隐藏，不阻挡游戏")
	overlay.advance(.5)
	check(overlay.elapsed == 0 and overlay.fade_progress == 0, "未通关不偷跑计时")
	host.timeline_enabled = false
	host.level_cleared = true
	overlay.advance(2.0)
	check(not overlay.visible and overlay.elapsed == 0, "非timeline旧关保持原流程")
	host.timeline_enabled = true
	overlay.advance(0.0)
	check(overlay.visible and overlay.fade_progress == 0 and overlay.text_opacity == 0,
		"正式通关从透明状态开始，不瞬间切全黑")
	overlay.advance(.125)
	check(is_equal_approx(overlay.text_opacity, .5) and overlay.fade_progress > 0 and overlay.fade_progress < .1,
		"白字用0.25秒缓显，背景开始缓慢变暗")
	overlay.advance(.125)
	check(overlay.text_opacity == 1 and not overlay.is_ready(), "0.25秒白字清晰，尚不提示重开")
	overlay.advance(.45)
	check(is_equal_approx(overlay.fade_progress, .5), "0.7秒仍保留一半背景，不提前抹黑")
	check(overlay.prompt_opacity == 0, "淡黑中途没有底部操作小字")
	overlay.advance(.7)
	check(is_equal_approx(overlay.elapsed, 1.4) and overlay.fade_progress == 1 and overlay.text_opacity == 1,
		"1.4秒背景全黑，白字仍保留")
	check(not overlay.is_ready(), "到全黑后仍稍留停顿")
	overlay.advance(.21)
	check(overlay.is_ready() and overlay.prompt_opacity > 0, "约1.6秒才允许宿主处理通关确认并显示小字")
	overlay.advance(.2)
	check(overlay.prompt_opacity == 1, "底部Enter/Esc提示缓显完整")
	var old_elapsed: float = overlay.elapsed
	overlay.advance(-1.0)
	check(overlay.elapsed == old_elapsed, "非法负时间不会倒放胜利画面")
	check(host.music == "unchanged-music-instance" and host.camera_position == Vector2(120, 220),
		"模块未碰宿主音乐或相机")
	check(not paused and is_equal_approx(Engine.time_scale, 1.0), "模块没有暂停场景树或改变全局时间倍率")
	check(overlay._surface.mouse_filter == Control.MOUSE_FILTER_IGNORE and overlay.layer == 80,
		"高层画面不吞输入，由宿主继续处理Enter/Esc")
	check(VICTORY.MESSAGE == "很好，这样能行。", "准确使用用户通关文案")
	overlay.reset()
	check(not overlay.visible and overlay.elapsed == 0 and not overlay.is_ready(), "reset立即清除通关状态")
	host.level_cleared = false
	overlay.advance(5.0)
	check(not overlay.visible, "新轮未通关时不会继续显示旧胜利字")
	host.level_cleared = true
	overlay.advance(.3)
	check(overlay.visible and overlay.elapsed < .31, "再次通关从新时间线重新缓显")
	host.timeline_enabled = false
	overlay.advance(.1)
	check(not overlay.visible and overlay.elapsed == 0, "离开正式模式后自动隐藏，不污染旧关")
	host.timeline_enabled = true
	host.level_cleared = true
	host.set_process(false)
	overlay.reset()
	var real_start := Time.get_ticks_usec()
	overlay.set_process(true)
	# 新建fixture首帧的delta可能已很长，短Timer不能冒充真实70ms；按墙钟截止点等待。
	while Time.get_ticks_usec() - real_start < 80000:
		await create_timer(.015, true).timeout
	await process_frame
	overlay.set_process(false)
	var wall_elapsed := float(Time.get_ticks_usec() - real_start) / 1000000.0
	check(overlay.visible and overlay.elapsed >= .04 and absf(overlay.elapsed - wall_elapsed) < .10,
		"宿主_process停住时，叠层仍由自身真实时钟推进")
	check(overlay.process_mode == Node.PROCESS_MODE_ALWAYS, "叠层自身可继续处理，不需要暂停或恢复整棵树")
	host.free()
	await process_frame
	print("VICTORY_TRANSITION_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
