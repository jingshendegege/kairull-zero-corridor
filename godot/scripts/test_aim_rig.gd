extends SceneTree

## AimRig 无头单测（纯七档静态枪方案）。跑法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script scripts/test_aim_rig.gd
##
## 只测数学，不依赖场景/贴图，所以能在 CI 里跑。

var _pass := 0
var _fail := 0


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func approx(a: float, b: float, tol: float = 0.01) -> bool:
	return absf(a - b) <= tol


func _init() -> void:
	var rig := AimRig.new()
	print("=== AimRig 无头单测（纯七档静态枪）===\n")

	# --- 1. 鼠标 → 瞄准角 ---
	print("[1] aim_angle_deg：角度必须从 pivot 起算")
	var pv := Vector2(100, 100)
	ok(approx(rig.aim_angle_deg(pv, Vector2(200, 100), true), 0.0),
		"正右方 = 0°")
	ok(approx(rig.aim_angle_deg(pv, Vector2(200, 0), true), 45.0),
		"右上 45°（屏幕y向下，取负后为正）")
	ok(approx(rig.aim_angle_deg(pv, Vector2(200, 200), true), -45.0),
		"右下 -45°")
	ok(approx(rig.aim_angle_deg(pv, Vector2(100, 0), true), 90.0),
		"正上 = 90°")
	ok(approx(rig.aim_angle_deg(pv, Vector2(0, 0), false), 45.0),
		"左向时左上 = 45°（折回右向坐标系）")

	# --- 2. 七档吸附 ---
	print("\n[2] pick_body_pose：按实测角吸附，不用名义角")
	ok(rig.pick_body_pose(50.0)["name"] == "up70",
		"50° → up70（实测52.3）")
	ok(rig.pick_body_pose(0.0)["name"] == "forward",
		"0° → forward")
	var p3: String = rig.pick_body_pose(-24.5)["name"]
	ok(p3 == "down45" or p3 == "down70",
		"-24.5° → down45/down70（两档只差1.0°）", p3)
	# 关键回归：按名义角会选错。名义 -45° 的图实测只有 -24.1°，
	# 所以鼠标指 -45° 时正确行为是吸到最接近实测值的 down70(-25.1)
	ok(rig.pick_body_pose(-45.0)["name"] == "down70",
		"-45° → down70（若按名义角会错选 down45）")
	ok(rig.pick_body_pose(-70.0)["name"] == "down70",
		"-70° 截断到 down70（向下只到 -25.1）")
	ok(rig.pick_body_pose(70.0)["name"] == "up70",
		"70° 截断到 up70（向上只到 +52.3）")
	# 每档都应能被自己的实测角选中（吸附自反性）
	var self_ok := true
	for name in AimRig.POSES:
		var a: float = AimRig.POSES[name]["angle"]
		if rig.pick_body_pose(a)["name"] != name:
			self_ok = false
			print("      ✗ %s 实测 %+.1f° 选中了 %s" % [
				name, a, rig.pick_body_pose(a)["name"]])
	ok(self_ok, "七档各自的实测角都能选中自己（吸附自反）")

	# 返回的数据应带上该档 pivot / muzzle
	var pf: Dictionary = rig.pick_body_pose(0.0)
	ok(pf.has("pivot") and pf.has("muzzle"),
		"选档结果携带 pivot / muzzle 标定值")
	ok(pf["pivot"] == Vector2(115.2, 240.8),
		"forward 档 pivot = (115.2, 240.8)", str(pf["pivot"]))
	ok(pf["muzzle"] == Vector2(311.6, 240.8),
		"forward 档 muzzle = (311.6, 240.8)", str(pf["muzzle"]))

	# --- 3. 发射角 = 档位实测角 ---
	print("\n[3] fire_angle_deg：发射方向 = 档位角，与画面静态枪一致")
	ok(approx(rig.fire_angle_deg(0.0), -0.0),
		"瞄 0° → 发射 -0.0°（forward 实测）")
	ok(approx(rig.fire_angle_deg(30.0), 38.0),
		"瞄 30° → 发射 38.0°（吸到 up45，不是原始30）",
		str(rig.fire_angle_deg(30.0)))
	ok(approx(rig.fire_angle_deg(-100.0), -25.1),
		"瞄 -100° → 发射 -25.1°（截断到 down70）")
	# 发射角必须始终是七档之一，绝不出现档位外的值
	var all_in_set := true
	var angle_set := rig.pose_angles()
	for a in [80.0, 52.3, 40.0, 25.0, 10.0, 0.0, -5.0, -20.0, -24.0, -25.1, -60.0]:
		var f: float = rig.fire_angle_deg(a)
		var found := false
		for s in angle_set:
			if approx(f, s):
				found = true
		if not found:
			all_in_set = false
			print("      ✗ 瞄 %+.1f° 得到档位外的发射角 %+.2f°" % [a, f])
	ok(all_in_set, "任意输入的发射角都落在七档集合内（无连续值泄漏）")

	# --- 4. muzzle 查表（不做旋转变换） ---
	print("\n[4] muzzle_world：按档查表，pivot→muzzle 用贴图内固定偏移")
	var origin := Vector2.ZERO
	# forward 档：muzzle - pivot = (311.6-115.2, 240.8-240.8) = (196.4, 0)
	var mf: Vector2 = rig.muzzle_world(origin, "forward", 1.0, true)
	ok(approx(mf.x, 196.4, 0.01) and approx(mf.y, 0.0, 0.01),
		"forward: 偏移 (196.4, 0)", str(mf))
	# up70 档：(315.7-196.5, 45.4-199.3) = (119.2, -153.9)
	var mu: Vector2 = rig.muzzle_world(origin, "up70", 1.0, true)
	ok(approx(mu.x, 119.2, 0.01) and approx(mu.y, -153.9, 0.01),
		"up70: 偏移 (119.2, -153.9)（y负=向上）", str(mu))
	# down70 档：(318.8-165.3, 363.7-292.0) = (153.5, 71.7)
	var md: Vector2 = rig.muzzle_world(origin, "down70", 1.0, true)
	ok(approx(md.x, 153.5, 0.01) and approx(md.y, 71.7, 0.01),
		"down70: 偏移 (153.5, 71.7)（y正=向下）", str(md))
	# 左向镜像：x 取反、y 不变
	var mL: Vector2 = rig.muzzle_world(origin, "forward", 1.0, false)
	ok(approx(mL.x, -196.4, 0.01) and approx(mL.y, 0.0, 0.01),
		"左向：x 取反、y 不变", str(mL))
	# 缩放
	var m2: Vector2 = rig.muzzle_world(origin, "forward", 2.0, true)
	ok(approx(m2.x, 392.8, 0.01), "scale=2：偏移翻倍", str(m2))
	# 每档的 muzzle 都应在 pivot 的枪口侧（x>0）且距离合理
	var span_ok := true
	for name in AimRig.POSES:
		var m: Vector2 = rig.muzzle_world(origin, name, 1.0, true)
		if m.x <= 0.0 or m.length() < 120.0 or m.length() > 230.0:
			span_ok = false
			print("      ✗ %s 偏移异常 %s 长度%.1f" % [name, m, m.length()])
	ok(span_ok, "七档 muzzle 偏移方向与长度均合理（120~230px）")

	# --- 5. pose_offset：按 pivot 对齐消除切档跳动 ---
	print("\n[5] pose_offset：各档按 pivot 对齐")
	# forward: 360/2-115.2 = 64.8, 460/2-240.8 = -10.8
	var of: Vector2 = AimRig.pose_offset("forward", true)
	ok(approx(of.x, 64.8, 0.01) and approx(of.y, -10.8, 0.01),
		"forward 右向 offset = (64.8, -10.8)", str(of))
	# 左向：x 变成 pv.x - 180 = -64.8
	var ol: Vector2 = AimRig.pose_offset("forward", false)
	ok(approx(ol.x, -64.8, 0.01) and approx(ol.y, -10.8, 0.01),
		"forward 左向 offset x 镜像", str(ol))
	# 关键：七档 offset 各不相同（因为 pivot 不同），这才能抵掉 bbox 差异
	var uniq := {}
	for name in AimRig.POSES:
		uniq[str(AimRig.pose_offset(name, true))] = true
	ok(uniq.size() >= 6,
		"七档 offset 至少 6 种不同值（按各自 pivot 对齐）",
		"实得 %d 种" % uniq.size())

	# --- 6. 像素取整 ---
	print("\n[6] snap_px：吸整像素防亚像素抖动")
	ok(AimRig.snap_px(Vector2(10.4, 20.6), 1.0) == Vector2(10.0, 21.0),
		"scale=1 四舍五入到整像素")
	ok(AimRig.snap_px(Vector2(10.4, 20.6), 4.0) == Vector2(12.0, 20.0),
		"scale=4 吸到 4px 网格")
	ok(AimRig.snap_px(Vector2(10.4, 20.6), 0.0) == Vector2(10.4, 20.6),
		"scale=0 不取整（保护除零）")

	# --- 7. 吸附误差量化（不是断言，是记录） ---
	print("\n[7] 七档实测角与吸附误差")
	var names := rig.pose_names()
	var angles := rig.pose_angles()
	for i in names.size():
		var pol: Dictionary = rig.muzzle_offset_polar(names[i])
		print("      %-9s 实测%+6.1f°  muzzle偏移 长%.1fpx 角%+6.1f°" % [
			names[i], angles[i], pol["length"], pol["angle_deg"]])
	var gaps := rig.pose_gaps()
	var gs := ""
	var worst_gap := 0.0
	for g in gaps:
		gs += "%.1f°  " % g
		worst_gap = maxf(worst_gap, g)
	print("      相邻间距: ", gs)
	print("      最大吸附误差 ≈ 最大间距的一半 = %.1f°" % (worst_gap * 0.5))
	print("      瞄准范围: %+.1f° ~ %+.1f°（名义应为 -70~+70）" % [
		AimRig.AIM_ANGLE_MIN, AimRig.AIM_ANGLE_MAX])
	print("      → 向下封顶 %.1f°，打不到脚下敌人；down45/down70 仅差 %.1f°" % [
		AimRig.AIM_ANGLE_MIN, gaps[gaps.size() - 1]])

	print("\n=== 结果：%d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
