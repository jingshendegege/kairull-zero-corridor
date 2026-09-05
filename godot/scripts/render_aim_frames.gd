extends SceneTree

## 渲染七档瞄准截图，供视觉验收。
##
## 关键点：不关 _process，而是通过 node.aim_override 注入"鼠标位置"。
## 关掉 _process 手工赋值会让叠加层读到旧状态 + get_global_mouse_position()
## 在无窗口时恒为 0,0，调试十字画不出来。
##
## 跑法（必须带窗口，--headless 用 dummy 渲染后端抓不到帧缓冲）：
##   Godot_..._console.exe --path godot --rendering-driver opengl3 \
##       --script scripts/render_aim_frames.gd

const OUT_DIR := "user://aim_frames"
const RAY_LEN := 300.0      ## 注入的瞄准点到 pivot 的距离


func _init() -> void:
	var packed: PackedScene = load("res://scenes/aim_prototype.tscn")
	var node: Node2D = packed.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("输出目录: ", ProjectSettings.globalize_path(OUT_DIR))

	var muzzle: Node2D = node.get_node("MuzzleMarker")
	var pivot: Vector2 = node._anchor

	# 按七档实测角逐一出图（不再渲染档位之间的中间角，
	# 因为纯七档方案下中间角会吸附到最近档，渲出来是重复画面）
	# 显式标注类型：node 是 Node2D，rig 属性的返回类型推不出来
	var rig: AimRig = node.rig
	var names: Array[String] = rig.pose_names()
	for i in names.size():
		var name: String = names[i]
		var deg: float = AimRig.POSES[name]["angle"]
		var rad := deg_to_rad(-deg)
		node.aim_override = pivot + Vector2(cos(rad), sin(rad)) * RAY_LEN

		# 等两帧：一帧让 _process 消化新瞄准点，一帧让叠加层重绘落地
		await process_frame
		await process_frame

		var img: Image = get_root().get_texture().get_image()
		var fn := "%s/pose_%d_%s.png" % [OUT_DIR, i, name]
		var err := img.save_png(fn)
		print("  %-8s 实测%+6.1f° → 发射%+6.1f°  muzzle(%.0f,%.0f)  %s" % [
			name, deg, node._fire_deg,
			muzzle.position.x, muzzle.position.y,
			"OK" if err == OK else "保存失败 %d" % err])

	print("\n完成: ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)
