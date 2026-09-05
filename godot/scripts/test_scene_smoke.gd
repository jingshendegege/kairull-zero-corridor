extends SceneTree

## 场景冒烟测试（纯七档静态枪）：无头实例化 aim_prototype.tscn，
## 跑若干帧，检查贴图加载、pivot 对齐、muzzle 查表在真实节点上是否成立。
##
## 跑法：
##   Godot_..._console.exe --headless --path godot --script scripts/test_scene_smoke.gd

var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	print("=== 场景冒烟测试（纯七档静态枪）===\n")

	var packed: PackedScene = load("res://scenes/aim_prototype.tscn")
	ok(packed != null, "场景可加载")
	if packed == null:
		quit(1)
		return

	var node: Node2D = packed.instantiate()
	ok(node != null, "场景可实例化")
	root.add_child(node)

	# ⚠ 必须等一帧：@onready 变量与 _ready() 的赋值在 add_child 后
	# 不是立刻可见的。之前在这里直接断言 texture，拿到 null 误判为
	# "贴图加载失败"，实际是断言太早。
	await process_frame

	var body: Sprite2D = node.get_node("Body")
	ok(body.texture != null, "身体贴图已加载")
	ok(node.rig != null, "AimRig 已构造")

	# 场景里不该再有独立枪械节点（纯静态枪方案）
	ok(not node.has_node("Gun"),
		"场景已移除独立 Gun 节点（不再叠动态枪）")

	# 七档贴图全部存在且尺寸一致
	var missing := []
	for name in AimRig.POSES:
		var t: Texture2D = load("res://assets/aim/pose_%s.png" % name)
		if t == null:
			missing.append(name)
		elif t.get_size() != AimRig.POSE_CANVAS:
			missing.append("%s(尺寸%s)" % [name, t.get_size()])
	ok(missing.is_empty(), "七档贴图齐全且均为 360x460", str(missing))

	# 再跑几帧，让 _process 写入位置（无头下鼠标在 (0,0)）
	for i in 5:
		await process_frame

	var muzzle: Node2D = node.get_node("MuzzleMarker")
	ok(is_finite(muzzle.position.x) and is_finite(muzzle.position.y),
		"muzzle 位置为有限值（无 NaN）", str(muzzle.position))

	# 身体位置应固定在 anchor，切档只改 offset
	ok(body.position == node._anchor,
		"身体位置固定在 anchor（切档靠 offset 对齐）",
		"body=%s anchor=%s" % [body.position, node._anchor])

	# 纹理过滤必须是 Point（像素画硬边）
	ok(body.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"身体贴图为 Nearest 过滤（无插值模糊）", str(body.texture_filter))

	# 逐档驱动一遍：贴图应换、offset 应变、muzzle 距离应对得上标定表
	print("\n  逐档驱动核验：")
	var rig: AimRig = node.rig
	var seen_tex := {}
	var all_match := true
	for name in AimRig.POSES:
		var ang: float = AimRig.POSES[name]["angle"]
		# 按该档角度反算一个瞄准点注入
		var rad := deg_to_rad(-ang)
		node.aim_override = node._anchor + Vector2(cos(rad), sin(rad)) * 300.0
		await process_frame
		await process_frame

		var got: String = node._pose["name"]
		seen_tex[str(body.texture.get_rid())] = true
		# 期望 muzzle 世界坐标 = anchor + (muzzle-pivot)*scale
		var want: Vector2 = rig.muzzle_world(node._anchor, got, 2.0, true)
		want = AimRig.snap_px(want, 2.0)
		var dev: float = muzzle.position.distance_to(want)
		var offset_ok: bool = body.offset.is_equal_approx(
			AimRig.pose_offset(got, true))
		if got != name or dev > 0.01 or not offset_ok:
			all_match = false
			print("      ✗ 注入%-8s 实得%-8s muzzle偏差%.2f offset%s" % [
				name, got, dev, "OK" if offset_ok else "错"])
		else:
			print("      ✓ %-8s 实测%+6.1f° → muzzle(%.0f,%.0f) offset%s" % [
				got, ang, muzzle.position.x, muzzle.position.y, body.offset])
	ok(all_match, "七档逐一驱动：选档/offset/muzzle 全部一致")
	ok(seen_tex.size() >= 6, "至少 6 种不同贴图被实际换上",
		"实得 %d" % seen_tex.size())

	print("\n=== %s ===" % ("PASS" if _fail == 0 else "FAIL(%d)" % _fail))
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
