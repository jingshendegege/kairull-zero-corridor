extends SceneTree
## 货运巡检员真窗口动作抽检；只用于视觉验收，不参与游戏运行。
## 跑法：godot --path godot --rendering-driver opengl3 \
##         --script scripts/render_freight_inspector.gd

const FREIGHT_SCRIPT := preload("res://scripts/freight_inspector.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("#111322")
	backdrop.size = Vector2(1360, 765)
	get_root().add_child(backdrop)
	var title := Label.new()
	title.text = "货运巡检员 · 实际运行帧抽检"
	title.position = Vector2(48, 48)
	title.add_theme_font_size_override("font_size", 28)
	backdrop.add_child(title)

	var samples := [
		["idle", 2, "待机 4"], ["alert", 4, "警戒 5"],
		["run", 5, "奔跑 8"], ["windup", 3, "前摇 4"],
		["attack", 3, "挥击 6"], ["recover", 3, "收招 4"],
		["dead", 30, "倒地 6/7"],
	]
	for i in samples.size():
		var sample: Array = samples[i]
		var enemy: Node2D = FREIGHT_SCRIPT.new()
		enemy.position = Vector2(105 + i * 185, 420)
		backdrop.add_child(enemy)
		enemy._set_state(sample[0])
		enemy.frame = sample[1]
		enemy._sync_sprite()
		var label := Label.new()
		label.text = sample[2]
		label.position = Vector2(enemy.position.x - 45, 455)
		label.add_theme_font_size_override("font_size", 18)
		backdrop.add_child(label)

	for i in range(12):
		await process_frame
	var image := get_root().get_texture().get_image()
	var path := "user://shot_freight_inspector_states.png"
	var err := image.save_png(path)
	print("动作抽检截图 -> ", ProjectSettings.globalize_path(path), " err=", err)
	print("RENDER_RESULT: ", "PASS" if err == OK else "FAIL")
	quit(0 if err == OK else 1)
