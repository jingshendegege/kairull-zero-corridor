extends SceneTree
## 墙面血迹管理器无头逻辑测试。
## 跑法：godot --headless --path godot --script scripts/test_blood_wall_manager.gd

const MANAGER_PATH := "res://scripts/blood_wall_manager.gd"
const SHADER_PATH := "res://shaders/blood_wall.gdshader"
const SNAPSHOT_PATH := "res://assets/vfx/blood_wall_snapshot.png"

var _pass := 0
var _fail := 0


func ok(condition: bool, label: String, detail := "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func approx(actual: float, expected: float, tolerance := 0.001) -> bool:
	return absf(actual - expected) <= tolerance


func approx_angle(actual: float, expected: float, tolerance := 0.01) -> bool:
	return absf(wrapf(actual - expected, -180.0, 180.0)) <= tolerance


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("== BloodWallManager 资源与逻辑 ==")
	# 忽略 ResourceLoader 缓存，确保测试的是磁盘上的实际脚本，而不是旧 class_name 缓存。
	var manager_script := ResourceLoader.load(
			MANAGER_PATH, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	var shader := ResourceLoader.load(
			SHADER_PATH, "Shader", ResourceLoader.CACHE_MODE_IGNORE) as Shader
	var snapshot := ResourceLoader.load(
			SNAPSHOT_PATH, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	ok(manager_script != null and manager_script.can_instantiate(),
			"实际管理器脚本可载入并实例化")
	ok(shader != null and shader.code.contains("shader_type canvas_item"),
			"墙面融合 Shader 可载入")
	ok(snapshot != null and snapshot.get_width() == 1920 and snapshot.get_height() == 192,
			"六帧冻结血迹图集可载入", str(snapshot.get_size()) if snapshot != null else "null")
	if manager_script == null or not manager_script.can_instantiate() or snapshot == null:
		_finish()
		return

	_test_four_directions(manager_script)
	_test_fifo_and_materials(manager_script)
	_test_fixed_pool_stress_and_clear(manager_script)
	_test_dynamic_capacity(manager_script)
	_test_disabled_request(manager_script)
	_test_uniform_sync(manager_script)
	_finish()


func _new_manager(manager_script: Script, capacity: int) -> Node2D:
	var manager := manager_script.new() as Node2D
	manager.set("max_decals", capacity)
	get_root().add_child(manager)
	return manager


func _spawn(manager: Node2D, world_position: Vector2, direction: Vector2,
		power: float, seed: int, progress: float, effect_color := Color("#c01630"),
		extra_flip_h := false, extra_flip_v := false) -> Sprite2D:
	return manager.call("spawn_snapshot", world_position, direction, power,
			seed, false, progress, effect_color, extra_flip_h, extra_flip_v) as Sprite2D


func _test_four_directions(manager_script: Script) -> void:
	print("== 四向角度与快照状态 ==")
	var manager := _new_manager(manager_script, 8)
	var directions: Array[Vector2] = [
		Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP,
	]
	var expected_angles: Array[float] = [0.0, 90.0, 180.0, -90.0]
	var expected_flip_h: Array[bool] = [false, false, true, false]
	var powers: Array[float] = [0.2, 0.8, 1.2, 2.4]
	var progresses: Array[float] = [-0.2, 0.25, 0.75, 1.4]
	var expected_scales: Array[float] = [0.45, 0.8, 1.2, 1.85]

	for index in directions.size():
		var requested_position := Vector2(100.2 + index * 19.0, 200.7 + index * 13.0)
		var sprite := _spawn(manager, requested_position, directions[index],
				powers[index], index, progresses[index])
		var slot: Dictionary = manager.call("debug_snapshot", index)
		ok(sprite != null and approx_angle(float(slot["spray_angle"]), expected_angles[index]),
				"%s atan2 角度为 %.0f°" % [directions[index], expected_angles[index]],
				str(slot.get("spray_angle")))
		ok(bool(slot["flip_h"]) == expected_flip_h[index]
				and sprite.flip_h == expected_flip_h[index],
				"%s 水平翻转正确" % directions[index])
		ok(Vector2(slot["world_position"]) == requested_position.round()
				and sprite.global_position == requested_position.round(),
				"%s 世界坐标按像素取整" % directions[index], str(sprite.global_position))
		ok(approx(float(slot["progress"]), clampf(progresses[index], 0.0, 1.0)),
				"%s progress 被保存并限幅" % directions[index], str(slot["progress"]))
		var expected_scale := Vector2.ONE * expected_scales[index]
		ok(Vector2(slot["world_scale"]).is_equal_approx(expected_scale)
				and sprite.scale.is_equal_approx(expected_scale),
				"%s scale 被保存并限幅" % directions[index], str(sprite.scale))

	var forced_flip := _spawn(manager, Vector2(301.3, 302.6), Vector2.RIGHT,
			1.0, 7, 0.5, Color("#c01630"), true)
	ok(forced_flip != null and forced_flip.flip_h,
			"额外水平翻转与方向翻转采用异或逻辑")
	manager.free()


func _test_fifo_and_materials(manager_script: Script) -> void:
	print("== 独立材质与 FIFO ==")
	var manager := _new_manager(manager_script, 3)
	var sprites: Array[Sprite2D] = []
	for index in 3:
		sprites.append(_spawn(manager, Vector2(20.0 + index, 40.0), Vector2.RIGHT,
				1.0, index, 0.2))
	var stats: Dictionary = manager.call("debug_stats")
	var unique_rids := {}
	for rid_value in stats["material_rids"]:
		unique_rids[int(rid_value)] = true
	ok(unique_rids.size() == 3 and not unique_rids.has(0),
			"三个槽位各有独立 ShaderMaterial RID", str(stats["material_rids"]))

	var fourth := _spawn(manager, Vector2(99.4, 77.6), Vector2.DOWN,
			1.0, 9, 0.6)
	var slot_zero: Dictionary = manager.call("debug_snapshot", 0)
	stats = manager.call("debug_stats")
	ok(fourth == sprites[0] and int(slot_zero["serial"]) == 4,
			"第 4 次生成按 FIFO 复用第 0 槽", str(slot_zero))
	ok(int(stats["slots"]) == 3 and int(stats["active"]) == 3
			and int(stats["visible"]) == 3 and int(stats["next_reuse"]) == 1,
			"FIFO 复用不扩大池且游标前进", str(stats))
	manager.free()


func _test_fixed_pool_stress_and_clear(manager_script: Script) -> void:
	print("== 固定池压力与清空复用 ==")
	var manager := _new_manager(manager_script, 3)
	for index in 1024:
		var direction := Vector2.RIGHT if index % 2 == 0 else Vector2.LEFT
		_spawn(manager, Vector2(index % 97, index % 53), direction,
				0.6 + float(index % 5) * 0.2, index, float(index % 11) / 10.0)
	var stats: Dictionary = manager.call("debug_stats")
	ok(int(stats["slots"]) == 3 and manager.get_child_count() == 3,
			"连续 1024 次生成仍固定为 3 个槽位", str(stats))
	ok(int(stats["active"]) == 3 and int(stats["visible"]) == 3
			and int(stats["serial"]) == 1024,
			"压力生成后的活跃数和序号正确", str(stats))

	manager.call("clear_all")
	var cleared: Dictionary = manager.call("debug_stats")
	ok(int(cleared["active"]) == 0 and int(cleared["visible"]) == 0
			and int(cleared["slots"]) == 3,
			"clear_all 隐藏血迹但保留对象池", str(cleared))
	_spawn(manager, Vector2(8.3, 9.7), Vector2.UP, 1.0, 1, 0.5)
	var respawned: Dictionary = manager.call("debug_stats")
	ok(int(respawned["active"]) == 1 and int(respawned["visible"]) == 1
			and int(respawned["slots"]) == 3,
			"清空后再生成时 active 与 visible 均为 1", str(respawned))
	manager.free()


func _test_dynamic_capacity(manager_script: Script) -> void:
	print("== 动态降低容量 ==")
	var manager := _new_manager(manager_script, 5)
	for index in 5:
		_spawn(manager, Vector2(index * 10.0, 20.0), Vector2.RIGHT,
				1.0, index, 0.5)
	manager.set("max_decals", 2)
	manager.call("apply_settings")
	var lowered: Dictionary = manager.call("debug_stats")
	ok(int(lowered["max_decals"]) == 2 and int(lowered["active"]) == 2
			and int(lowered["visible"]) == 2,
			"max 从 5 降至 2 后立即只保留两个可见血迹", str(lowered))
	ok(int(lowered["slots"]) == 5,
			"降容量时保留已分配槽，避免反复分配", str(lowered))

	_spawn(manager, Vector2(66.2, 44.8), Vector2.LEFT, 1.0, 6, 0.5)
	var tail_inactive := true
	for index in range(2, 5):
		var slot: Dictionary = manager.call("debug_snapshot", index)
		var sprite := slot["sprite"] as Sprite2D
		if sprite.visible or int(slot["serial"]) != 0:
			tail_inactive = false
	ok(tail_inactive and int((manager.call("debug_stats") as Dictionary)["active"]) == 2,
			"降容量后的生成只复用新容量范围")

	var kept_zero_serial := int((manager.call("debug_snapshot", 0) as Dictionary)["serial"])
	var kept_one_serial := int((manager.call("debug_snapshot", 1) as Dictionary)["serial"])
	manager.set("max_decals", 5)
	manager.call("apply_settings")
	_spawn(manager, Vector2(77.0, 55.0), Vector2.UP, 1.0, 7, 0.5)
	var raised: Dictionary = manager.call("debug_stats")
	var reopened: Dictionary = manager.call("debug_snapshot", 2)
	ok(int(raised["active"]) == 3 and (reopened["sprite"] as Sprite2D).visible,
			"容量恢复后优先启用此前隐藏的空槽", str(raised))
	ok(int((manager.call("debug_snapshot", 0) as Dictionary)["serial"]) == kept_zero_serial
			and int((manager.call("debug_snapshot", 1) as Dictionary)["serial"]) == kept_one_serial,
			"容量恢复不会提前覆盖仍可见的旧血迹")
	manager.free()


func _test_disabled_request(manager_script: Script) -> void:
	print("== 完全关闭 ==")
	var manager := _new_manager(manager_script, 3)
	_spawn(manager, Vector2(1.0, 2.0), Vector2.RIGHT, 1.0, 1, 0.5)
	_spawn(manager, Vector2(3.0, 4.0), Vector2.LEFT, 1.0, 2, 0.5)
	manager.call("set_persistent_enabled", false)
	var before: Dictionary = manager.call("debug_stats")
	var rejected := _spawn(manager, Vector2(999.0, 999.0), Vector2.DOWN,
			1.8, 99, 1.0)
	var after: Dictionary = manager.call("debug_stats")
	ok(rejected == null and not manager.visible,
			"持久血迹关闭时拒绝生成且管理器不可见")
	ok(_same_stats(before, after),
			"关闭期间的生成请求不改变任何统计", "%s -> %s" % [before, after])
	manager.free()


func _same_stats(left: Dictionary, right: Dictionary) -> bool:
	for key in ["active", "visible", "slots", "max_decals", "next_reuse", "serial"]:
		if left[key] != right[key]:
			return false
	return left["material_rids"] == right["material_rids"]


func _test_uniform_sync(manager_script: Script) -> void:
	print("== Inspector 设置同步 ==")
	var manager := _new_manager(manager_script, 1)
	var effect_color := Color("#42c8aa")
	_spawn(manager, Vector2(10.0, 11.0), Vector2.LEFT, 1.0, 1, 0.5, effect_color)
	manager.set("blood_opacity", 0.37)
	manager.set("multiply_intensity", 1.23)
	manager.set("occlusion_enabled", false)
	manager.set("darkness_enabled", false)
	manager.set("refraction_enabled", false)
	manager.set("linear_refraction_enabled", false)
	manager.set("normal_lighting_enabled", false)
	manager.set("dark_surface_lift_enabled", false)
	manager.set("occlusion_strength", 8.5)
	manager.set("occlusion_ray_steps", 19)
	manager.set("occlusion_ray_length", 21.5)
	manager.set("darkness_threshold", 0.13)
	manager.set("darkness_softness", 0.047)
	manager.set("dark_surface_lift_strength", 0.44)
	manager.set("dark_surface_lift_start", 0.12)
	manager.set("dark_surface_lift_end", 0.29)
	manager.set("deformation_strength", 0.18)
	manager.set("background_bump_strength", 5.5)
	manager.set("blood_bump_strength", 2.5)
	manager.set("light_angle", 32.0)
	manager.set("ambient_light", 0.71)
	manager.set("debug_mode", 4)
	manager.set("spray_angle_offset", 25.0)
	manager.call("apply_settings")

	var slot: Dictionary = manager.call("debug_snapshot", 0)
	var material := slot["material"] as ShaderMaterial
	ok(material.get_shader_parameter("blood_color") == effect_color
			and approx(float(material.get_shader_parameter("blood_opacity")), 0.37)
			and approx(float(material.get_shader_parameter("multiply_intensity")), 1.23),
			"血色、不透明度与正片叠底强度同步")
	ok(not bool(material.get_shader_parameter("enable_occlusion"))
			and not bool(material.get_shader_parameter("enable_darkness"))
			and not bool(material.get_shader_parameter("enable_refraction"))
			and not bool(material.get_shader_parameter("use_linear_refraction"))
			and not bool(material.get_shader_parameter("enable_normal_lighting"))
			and not bool(material.get_shader_parameter("enable_dark_surface_lift")),
			"六个功能开关同步")
	ok(approx(float(material.get_shader_parameter("occlusion_strength")), 8.5)
			and int(material.get_shader_parameter("occlusion_ray_steps")) == 19
			and approx(float(material.get_shader_parameter("occlusion_ray_length")), 21.5),
			"定向遮蔽参数同步")
	ok(approx(float(material.get_shader_parameter("darkness_threshold")), 0.13)
			and approx(float(material.get_shader_parameter("darkness_softness")), 0.047)
			and approx(float(material.get_shader_parameter("luminance_deformation_strength")), 0.18),
			"暗区与折射参数同步")
	ok(approx(float(material.get_shader_parameter("dark_surface_lift_strength")), 0.44)
			and approx(float(material.get_shader_parameter("dark_surface_lift_start")), 0.12)
			and approx(float(material.get_shader_parameter("dark_surface_lift_end")), 0.29),
			"暗墙彩色补偿参数同步")
	ok(approx(float(material.get_shader_parameter("background_bump_strength")), 5.5)
			and approx(float(material.get_shader_parameter("blood_bump_strength")), 2.5)
			and approx(float(material.get_shader_parameter("light_angle")), 32.0)
			and approx(float(material.get_shader_parameter("ambient_light")), 0.71),
			"伪法线与光照参数同步")
	ok(int(material.get_shader_parameter("debug_mode")) == 4
			and approx_angle(float(material.get_shader_parameter("spray_angle")), -155.0),
			"调试模式及喷射角偏移同步")
	manager.call("set_dark_surface_lift_enabled", true)
	ok(bool(material.get_shader_parameter("enable_dark_surface_lift")),
			"运行时开关会立即更新已经存在的血迹材质")

	# 补色只改善可读性，不得把继承的六色霓虹血重新硬编码成红色。
	var fallback_color := Color("#a52238")
	manager.set("inherit_effect_color", false)
	manager.set("red_blood_color", fallback_color)
	_spawn(manager, Vector2(12.0, 13.0), Vector2.RIGHT, 1.0, 2, 0.5,
			Color("#43e8ff"))
	var recolored_slot: Dictionary = manager.call("debug_snapshot", 0)
	material = recolored_slot["material"] as ShaderMaterial
	ok(Color(recolored_slot["color"]) == fallback_color
			and material.get_shader_parameter("blood_color") == fallback_color,
			"关闭颜色继承时才使用可配置的回退血色")
	var neon_color := Color("#9b5cff")
	manager.set("inherit_effect_color", true)
	_spawn(manager, Vector2(14.0, 15.0), Vector2.RIGHT, 1.0, 3, 0.5, neon_color)
	recolored_slot = manager.call("debug_snapshot", 0)
	material = recolored_slot["material"] as ShaderMaterial
	ok(Color(recolored_slot["color"]) == neon_color
			and material.get_shader_parameter("blood_color") == neon_color,
			"开启颜色继承后继续保留本次命中的彩色色相")
	manager.free()


func _finish() -> void:
	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
