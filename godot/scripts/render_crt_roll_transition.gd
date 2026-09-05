extends SceneTree
## 真窗口 GPU 验收：以正式 M01 世界和 HUD 为底图，拍摄两帧 SCREEN_TEXTURE 垂直环回。

const TRANSITION := preload("res://scripts/crt_roll_transition.gd")
const SESSION := preload("res://scripts/run_session.gd")

var _failed := false


class MockTimelineHost extends Node:
	var progress := 0.0

	func timeline_view_model() -> Dictionary:
		return {"phase": "interference", "glitch_progress": progress}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("CRT 垂直回卷必须在真窗口 GPU 后端验收")
		quit(1)
		return
	SESSION.begin_run("easy")
	var world_scene: PackedScene = load("res://scenes/m01_protocol_quarantine.tscn")
	var world: Node = world_scene.instantiate()
	get_root().add_child(world)
	for i in range(12):
		await process_frame
	var game: Variant = world.find_child("Game", true, false)
	if game == null:
		push_error("正式 M01 未生成 Game")
		_failed = true
	else:
		# 底图必须是真实关卡合成；只停游戏逻辑，建筑和 HUD 仍按正常 GPU 路径绘制。
		game.set_process(false)
		game.set_physics_process(false)
		if game.player != null:
			game.player.set_physics_process(false)

	var mock := MockTimelineHost.new()
	var transition = TRANSITION.new()
	transition.host = mock
	get_root().add_child(mock)
	get_root().add_child(transition)
	await _capture_at(transition, mock, 0.25, "shot_crt_roll_25")
	await _capture_at(transition, mock, 0.68, "shot_crt_roll_68")

	transition.free()
	mock.free()
	world.free()
	SESSION.reset_for_tests()
	for i in range(5):
		await process_frame
	print("RENDER_RESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _capture_at(transition, mock: MockTimelineHost,
		progress: float, stem: String) -> void:
	mock.progress = progress
	transition.apply_view_model(mock.timeline_view_model())
	# 两帧让 BackBufferCopy 和 shader 都在当前正式合成画面上稳定执行。
	for i in range(3):
		await process_frame
	# 读回只用于 QA 截图；运行时效果从未把屏幕拷回 CPU 或再上传为纹理。
	var image := get_root().get_texture().get_image()
	var path := "user://%s.png" % stem
	var error := image.save_png(path)
	if error != OK or image.is_empty():
		_failed = true
	print("  截图 ", stem, " -> ", ProjectSettings.globalize_path(path), " err=", error)
