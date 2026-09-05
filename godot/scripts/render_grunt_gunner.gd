extends SceneTree
## 货运枪手真窗口动作抽检；展示实际游戏缩放、脚底线、六行动画与 idle 后摇。
## 跑法：godot --path godot --rendering-driver opengl3 --script scripts/render_grunt_gunner.gd

const GUNNER_SCRIPT := preload("res://scripts/grunt.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("#111322")
	backdrop.size = Vector2(1360, 765)
	get_root().add_child(backdrop)
	var title := Label.new()
	title.text = "货运枪手 · Godot 真窗口生产帧抽检"
	title.position = Vector2(48, 40)
	title.add_theme_font_size_override("font_size", 26)
	backdrop.add_child(title)

	var ground := ColorRect.new()
	ground.color = Color("#5b416e")
	ground.position = Vector2(36, 442)
	ground.size = Vector2(1288, 3)
	backdrop.add_child(ground)

	var samples := [
		["idle", 0, 0.36, "待机 3"],
		["alert", 14, 0.0, "警戒 4"],
		["run", 0, 0.42, "奔跑 8"],
		["aim", 24, 0.0, "瞄准 5"],
		["fire", 5, 0.0, "开火 4"],
		["recover", 6, 0.25, "后摇 = idle"],
		["dead", 44, 0.0, "倒地 6"],
	]
	for index in samples.size():
		var sample: Array = samples[index]
		var enemy: GruntGunner = GUNNER_SCRIPT.new()
		enemy.position = Vector2(112 + index * 184, 442)
		backdrop.add_child(enemy)
		enemy._set_state(String(sample[0]))
		enemy.frame = int(sample[1])
		enemy._anim_clock = float(sample[2])
		if sample[0] == "dead":
			enemy.dead = true
		enemy.face = 1
		enemy._sync_sprite()
		var label := Label.new()
		label.text = String(sample[3])
		label.position = Vector2(enemy.position.x - 58, 470)
		label.add_theme_font_size_override("font_size", 17)
		backdrop.add_child(label)

	var note := Label.new()
	note.text = "紫线 = 脚底基线；角色玩法碰撞仍为 44×96px；透明图集使用 Nearest"
	note.position = Vector2(48, 550)
	note.add_theme_font_size_override("font_size", 18)
	note.modulate = Color("#a9d8ff")
	backdrop.add_child(note)

	for index in range(12):
		await process_frame
	var image := get_root().get_texture().get_image()
	var path := "user://shot_grunt_gunner_states.png"
	var error := image.save_png(path)
	print("枪手动作真窗截图 -> ", ProjectSettings.globalize_path(path), " err=", error)
	print("RENDER_RESULT: ", "PASS" if error == OK else "FAIL")
	quit(0 if error == OK else 1)
