extends Node2D
class_name QuarantineArchitecture
## 正式第一关“协议检疫站”的语义美术层。
##
## 只读取 LDtk 编译出来的房间/语义数据，不靠房间中文名猜装饰。后景只在可玩房间
## 内绘制，房间外保持纯黑，形成《武士零》式剖面；前景只画少量梁、管、链和格栅。
## 所有坐标均落在 32px 网格或整数像素上，避免破坏工程的 nearest 像素规则。

const TS := 32
const SCANNER_TEXTURE := preload("res://assets/maps/quarantine_slice/quarantine_scanner.png")

const VOID := Color("#05070b")
const SEAM := Color("#1d2b36")
const EDGE := Color("#667c8a")
const EDGE_DIM := Color("#4d6370")
const STEEL := Color("#3f5262")
const STEEL_DARK := Color("#263744")
const STEEL_DEEP := Color("#15222c")
const GLASS := Color("#294a58")
const GLASS_HI := Color("#3f6873")
const CYAN := Color("#43e8ff")
const AMBER := Color("#ffb347")
const MAGENTA := Color("#ff4fa3")
const RED := Color("#e75963")
const RUST := Color("#70493f")
const STAIR_RISE := 16.0
const STAIR_SHADOW_TRANSITION_PX := 32.0
const ROOM_BOUNDARY_BAND_PX := 8.0

var level: CorridorLevel
var semantic_layers: Dictionary = {}
var semantic_ids: Dictionary = {}
var front_only := false

## 无头测试读取的结构预算；不依赖 _draw 是否在当前渲染后端执行。
var room_count := 0
var landmark_count := 0
var light_count := 0
var foreground_cell_count := 0
var outside_color := VOID
var stair_visual_count := 0
var stair_tread_count := 0
var stair_stringer_count := 0
var stair_shadow_wedge_count := 0
var stair_shadow_transition_band_count := 0
var service_void_transition_band_count := 0
var room_boundary_transition_band_count := 0
var shaft_display_dynamic_channel_count := 0
## 检疫厅主地标预算：扫描幕/货物读数/门架状态三路动态信息，供专项验收读取。
var cargo_scanner_dynamic_channel_count := 0
var cargo_gantry_span_px := 0.0
var cargo_conveyor_span_px := 0.0
var large_wall_panel_count := 0
var wall_wear_cluster_count := 0
## 后半程专项结构预算；测试只读这些结果，不依赖无头模式是否真正执行 Canvas 绘制。
var extended_profile_count := 0
var extended_landmark_count := 0
var rear_palette_count := 0
var archive_branch_lane_count := 0
var service_bench_visual_count := 0
var coolant_tank_visual_count := 0
var freight_hoist_visual_count := 0
var containment_ring_visual_count := 0
var stair_semantic_cell_count := 0
var stair_semantics_valid := false

var _phase := 0.0
## 语义层在setup中深复制，运行时只有灯/屏_phase变化；边界和行合并可安全复用整关。
## 缓存完整几何而非裁掉离屏房间，避免换镜头后前景缺失或暗边/设备外延被截断。
var _value_bounds_cache: Dictionary = {}
var _scoped_bounds_cache: Dictionary = {}
var _horizontal_runs_cache: Dictionary = {}
var _cache_build_counts := {"value_bounds": 0, "scoped_bounds": 0, "horizontal_runs": 0}


func setup(p_level: CorridorLevel, p_layers: Dictionary, p_ids: Dictionary,
		p_front_only := false) -> void:
	level = p_level
	semantic_layers = p_layers.duplicate(true)
	semantic_ids = p_ids.duplicate(true)
	# 同实例可被测试/新关setup复用，必须在预算统计前清缓存，不带入上一地图的空结果或范围。
	_value_bounds_cache.clear()
	_scoped_bounds_cache.clear()
	_horizontal_runs_cache.clear()
	_cache_build_counts = {"value_bounds": 0, "scoped_bounds": 0, "horizontal_runs": 0}
	front_only = p_front_only
	room_count = level.rooms.size() if level != null else 0
	landmark_count = _distinct_values("Architecture")
	light_count = (semantic_layers.get("Lights", []) as Array).size()
	foreground_cell_count = (semantic_layers.get("ForegroundTiles", []) as Array).size()
	var backdrop_ids: Dictionary = semantic_ids.get("BackdropTiles", {})
	var service_void_id := int(backdrop_ids.get("ServiceVoid", -1))
	service_void_transition_band_count = 4 \
			if _value_bounds("BackdropTiles", service_void_id).size != Vector2i.ZERO else 0
	room_boundary_transition_band_count = 4 if room_count > 0 else 0
	var architecture_ids: Dictionary = semantic_ids.get("Architecture", {})
	shaft_display_dynamic_channel_count = 3 \
			if int(architecture_ids.get("ShaftStatusDisplay", -1)) >= 0 else 0
	var chamber_id := int(architecture_ids.get("QuarantineChamber", -1))
	var chamber_bounds := _value_bounds("Architecture", chamber_id)
	cargo_scanner_dynamic_channel_count = 3 if chamber_bounds.size != Vector2i.ZERO else 0
	_recount_wall_art_budget()
	_recount_extended_art_budget()
	_recount_stair_visual_budget()
	set_process(not front_only)
	queue_redraw()


func _process(dt: float) -> void:
	# 只有告警灯轻微明灭；几何与墙板保持静止，避免整张地图闪烁。
	_phase = fmod(_phase + dt, TAU)
	queue_redraw()


func _draw() -> void:
	if level == null:
		return
	if front_only:
		_draw_foreground()
		return
	_draw_room_shells()
	_draw_backdrop_semantics()
	_draw_architecture()
	_draw_lights()


## 用于血迹/测试判断：只有 LDtk 明确声明的房间内部才算有可见墙面。
func has_visible_backdrop_at(wx: float, wy: float) -> bool:
	if level == null:
		return false
	var cell := Vector2i(floori(wx / TS), floori(wy / TS))
	for room: Dictionary in level.rooms:
		var rect: Rect2i = room["rect"]
		var interior := Rect2i(rect.position + Vector2i(0, 1),
				Vector2i(rect.size.x, maxi(0, rect.size.y - 2)))
		if interior.has_point(cell):
			return true
	return false


func _draw_room_shells() -> void:
	# 先把墙色向地图外黑暗递减四档，再画实心房间；相邻房间会覆盖彼此的外沿，
	# 因此只有真正暴露在虚空中的地图边界保留过渡。
	for room: Dictionary in level.rooms:
		var transition_rect := _room_shell_rect(room)
		_draw_room_boundary_transition(transition_rect,
				_profile_color(String(room.get("decor_profile", ""))))
	for room: Dictionary in level.rooms:
		var rect: Rect2i = room["rect"]
		var profile := String(room.get("decor_profile", ""))
		var shell := _room_shell_rect(room)
		var x0 := shell.position.x
		var y0 := shell.position.y
		var w := shell.size.x
		var h := shell.size.y
		var base := _profile_color(profile)
		draw_rect(shell, base)

		# 大尺度不等宽墙板取代 64×48 满屏网格；断缝和破损只落在少数板块。
		_draw_large_wall_panels(profile, shell)
		_draw_base_utility_strip(profile, shell)

		# 房间边缘只留细钢框；框外仍由纯黑虚空包裹。
		draw_line(Vector2(x0, y0), Vector2(x0 + w, y0), EDGE_DIM, 2.0)
		draw_line(Vector2(x0, y0 + h - 1.0), Vector2(x0 + w, y0 + h - 1.0),
				STEEL_DEEP, 2.0)
		_draw_profile_marks(profile, shell)


## 每块墙板宽 5–8 格，纵向接缝刻意错开；不再生成可读成“瓷砖墙纸”的小方格。
func _draw_large_wall_panels(profile: String, rect: Rect2) -> void:
	var widths := PackedInt32Array([192, 256, 160, 224, 256, 192])
	var seed := _profile_art_seed(profile)
	var x := int(rect.position.x)
	var right := int(rect.end.x)
	var panel_index := 0
	while x < right:
		var panel_w := widths[(panel_index + seed) % widths.size()]
		var panel_right := mini(right, x + panel_w)
		if x > int(rect.position.x):
			draw_rect(Rect2(x - 2, rect.position.y, 3, rect.size.y), SEAM)
			draw_line(Vector2(x + 1, rect.position.y + 6),
					Vector2(x + 1, rect.end.y - 7), Color(EDGE_DIM, 0.42), 1.0)

		# 大板面只给极轻的明暗差，仍保持 26%–34% 的可染血墙面预算。
		var face_alpha := 0.085 if (panel_index + seed) % 2 == 0 else 0.025
		draw_rect(Rect2(x + 4, rect.position.y + 5,
				maxi(0, panel_right - x - 9), rect.size.y - 11),
				Color(EDGE if (panel_index + seed) % 2 == 0 else STEEL_DEEP, face_alpha))
		draw_line(Vector2(x + 7, rect.position.y + 8),
				Vector2(panel_right - 12, rect.position.y + 8), Color(EDGE, 0.20), 2.0)
		var joint_y := int(rect.position.y + 128.0
				+ float((panel_index + seed) % 3) * 80.0)
		if joint_y < int(rect.end.y - 88.0):
			draw_line(Vector2(x + 8, joint_y), Vector2(panel_right - 10, joint_y),
					Color(SEAM, 0.68), 2.0)
			draw_line(Vector2(x + 18, joint_y + 2), Vector2(panel_right - 28, joint_y + 2),
					Color(EDGE_DIM, 0.24), 1.0)

		# 每三块才出现一处缺角/补丁，形成较大、可辨认的废弃轮廓。
		if (panel_index + seed) % 3 == 1 and panel_right - x >= 150:
			var patch := Rect2(x + 24, rect.position.y + 54
					+ float((panel_index * 37) % 82), 108, 54)
			draw_rect(patch, Color(STEEL_DEEP, 0.74))
			draw_colored_polygon(PackedVector2Array([
				patch.position + Vector2(8, 5),
				Vector2(patch.end.x - 6, patch.position.y + 5),
				patch.end - Vector2(12, 7),
				Vector2(patch.position.x + 4, patch.end.y - 13),
			]), Color("#334956"))
			draw_line(patch.position + Vector2(15, 13),
					patch.position + Vector2(60, 13), Color(EDGE_DIM, 0.72), 2.0)
			draw_rect(Rect2(patch.position + Vector2(10, 29), Vector2(18, 3)),
					Color(RUST, 0.52))
		panel_index += 1
		x = panel_right


## 底部只保留低对比阴影和少量检修盒；不沿整房铺一排相同的小方格。
func _draw_base_utility_strip(profile: String, rect: Rect2) -> void:
	var base_y := rect.end.y - 48.0
	draw_rect(Rect2(rect.position.x, base_y, rect.size.x, 48.0),
			Color(STEEL_DEEP, 0.42))
	draw_line(Vector2(rect.position.x, base_y), Vector2(rect.end.x, base_y),
			Color(EDGE_DIM, 0.48), 2.0)
	var seed := _profile_art_seed(profile)
	var segment_w := minf(248.0, rect.size.x * 0.30)
	for i in range(2):
		var usable := maxf(1.0, rect.size.x - segment_w - 48.0)
		var phase := fmod(float(seed * 73 + i * 311), usable)
		var x := rect.position.x + 24.0 + phase
		var box := Rect2(roundf(x), base_y + 13.0, segment_w, 24.0)
		draw_rect(box, Color("#1b2a35"))
		draw_line(box.position + Vector2(5, 5),
				Vector2(box.end.x - 7, box.position.y + 5), Color(EDGE_DIM, 0.54), 1.0)
		for slot_x in range(int(box.position.x + 12), int(box.end.x - 14), 38):
			draw_rect(Rect2(slot_x, box.position.y + 12, 20, 4), Color("#0e1821"))


func _profile_art_seed(profile: String) -> int:
	match profile:
		"safe_entry":
			return 1
		"quarantine_scanner":
			return 3
		"coolant_shaft":
			return 4
		"archive_sorter":
			return 2
		"egress_lock":
			return 5
		"service_bay":
			return 6
		"coolant_reservoir":
			return 7
		"freight_crossfire":
			return 8
		"relay_service":
			return 9
		"containment_core":
			return 10
	return 0


func _recount_wall_art_budget() -> void:
	large_wall_panel_count = 0
	wall_wear_cluster_count = 0
	cargo_gantry_span_px = 0.0
	cargo_conveyor_span_px = 0.0
	if level == null:
		return
	var widths := PackedInt32Array([192, 256, 160, 224, 256, 192])
	for room: Dictionary in level.rooms:
		var rect := _room_shell_rect(room)
		var seed := _profile_art_seed(String(room.get("decor_profile", "")))
		var consumed := 0
		var panel_index := 0
		while consumed < int(rect.size.x):
			large_wall_panel_count += 1
			if (panel_index + seed) % 3 == 1:
				wall_wear_cluster_count += 1
			consumed += widths[(panel_index + seed) % widths.size()]
			panel_index += 1
	var architecture_ids: Dictionary = semantic_ids.get("Architecture", {})
	var chamber_id := int(architecture_ids.get("QuarantineChamber", -1))
	var chamber_bounds := _value_bounds("Architecture", chamber_id)
	var hall := _room_by_profile("quarantine_scanner")
	if chamber_bounds.size != Vector2i.ZERO and not hall.is_empty():
		var chamber := _cell_rect(chamber_bounds)
		var shell := _room_shell_rect(hall)
		var rail_left := maxf(shell.position.x + 192.0, chamber.position.x - 96.0)
		var rail_right := minf(shell.end.x + 32.0, chamber.end.x + 448.0)
		cargo_gantry_span_px = maxf(0.0, rail_right - rail_left)
		cargo_conveyor_span_px = maxf(0.0, rail_right - rail_left - 44.0)


func _recount_extended_art_budget() -> void:
	extended_profile_count = 0
	extended_landmark_count = 0
	rear_palette_count = 0
	archive_branch_lane_count = 0
	service_bench_visual_count = 0
	coolant_tank_visual_count = 0
	freight_hoist_visual_count = 0
	containment_ring_visual_count = 0
	if level == null:
		return
	var rear_profiles := {
		"archive_sorter": true,
		"service_bay": true,
		"coolant_reservoir": true,
		"freight_crossfire": true,
		"relay_service": true,
		"containment_core": true,
		"egress_lock": true,
	}
	var palette := {}
	var architecture_ids: Dictionary = semantic_ids.get("Architecture", {})
	for room: Dictionary in level.rooms:
		var profile := String(room.get("decor_profile", ""))
		if not rear_profiles.has(profile):
			continue
		extended_profile_count += 1
		palette[_profile_color(profile).to_html(false)] = true
		var landmark_name := _landmark_name_for_profile(profile)
		var landmark_id := int(architecture_ids.get(landmark_name, -1))
		var bounds := _value_bounds_in_rect("Architecture", landmark_id, room["rect"])
		if bounds.size == Vector2i.ZERO:
			continue
		extended_landmark_count += 1
		match landmark_name:
			"ArchiveSorter":
				archive_branch_lane_count += 2
			"ServiceBench":
				service_bench_visual_count += 1
			"CoolantReservoir":
				coolant_tank_visual_count += 3
			"FreightGantry":
				freight_hoist_visual_count += 2
			"ContainmentCore":
				containment_ring_visual_count += 1
	rear_palette_count = palette.size()


func _landmark_name_for_profile(profile: String) -> String:
	match profile:
		"safe_entry":
			return "EntryScanner"
		"quarantine_scanner":
			return "QuarantineChamber"
		"coolant_shaft":
			return "ShaftStatusDisplay"
		"archive_sorter":
			return "ArchiveSorter"
		"service_bay", "relay_service":
			return "ServiceBench"
		"coolant_reservoir":
			return "CoolantReservoir"
		"freight_crossfire":
			return "FreightGantry"
		"containment_core":
			return "ContainmentCore"
		"egress_lock":
			return "ExitSeal"
	return ""


func _room_shell_rect(room: Dictionary) -> Rect2:
	var rect: Rect2i = room["rect"]
	return Rect2(float(rect.position.x * TS), float((rect.position.y + 1) * TS),
			float(rect.size.x * TS), float(maxi(0, rect.size.y - 2) * TS))


func _draw_room_boundary_transition(rect: Rect2, base: Color) -> void:
	# 过渡只延伸 32px，仍保留大面积纯黑负空间；四档硬边比滤镜模糊更适合像素画。
	var alphas := PackedFloat32Array([0.08, 0.16, 0.30, 0.52])
	# shell 上下各隔着一行不透明碰撞 tile；过渡必须画到 tile 外侧才真正可见。
	var visible_top := rect.position.y - TS
	var visible_bottom := rect.end.y + TS
	for i in range(4):
		var distance := float((4 - i) * ROOM_BOUNDARY_BAND_PX)
		var color := Color(base, alphas[i])
		draw_rect(Rect2(rect.position.x - distance, rect.position.y,
				ROOM_BOUNDARY_BAND_PX, rect.size.y), color)
		draw_rect(Rect2(rect.end.x + distance - ROOM_BOUNDARY_BAND_PX, rect.position.y,
				ROOM_BOUNDARY_BAND_PX, rect.size.y), color)
		draw_rect(Rect2(rect.position.x, visible_top - distance,
				rect.size.x, ROOM_BOUNDARY_BAND_PX), color)
		draw_rect(Rect2(rect.position.x,
				visible_bottom + distance - ROOM_BOUNDARY_BAND_PX,
				rect.size.x, ROOM_BOUNDARY_BAND_PX), color)


func _profile_color(profile: String) -> Color:
	match profile:
		"safe_entry":
			return Color("#354a59")
		"quarantine_scanner":
			return Color("#3f5262")
		"coolant_shaft":
			return Color("#304953")
		"archive_sorter":
			return Color("#43545c")
		"egress_lock":
			return Color("#463f49")
		"service_bay":
			return Color("#3c4e4b")
		"coolant_reservoir":
			return Color("#304b55")
		"freight_crossfire":
			return Color("#514b43")
		"relay_service":
			return Color("#354744")
		"containment_core":
			return Color("#493f4b")
	return STEEL_DARK


func _draw_profile_marks(profile: String, rect: Rect2) -> void:
	# 每房只给一种辅助语言；真正主地标由 Architecture 层决定。
	if profile == "safe_entry":
		for x in [rect.position.x + 42.0, rect.end.x - 182.0]:
			draw_rect(Rect2(x, rect.position.y + 16, 116, 3), Color(CYAN, 0.20))
	elif profile == "quarantine_scanner":
		var band_y := rect.position.y + rect.size.y * 0.58
		# 只在扫描舱两侧留短电缆槽，禁止用贯穿全厅的发光横线切碎构图。
		for cable_rect in [
			Rect2(rect.position.x + 28.0, band_y, 214.0, 7.0),
			Rect2(rect.end.x - 286.0, band_y, 238.0, 7.0),
		]:
			draw_rect(cable_rect, STEEL_DEEP)
			draw_line(cable_rect.position, Vector2(cable_rect.end.x, cable_rect.position.y),
					Color(CYAN, 0.18), 1.0)
	elif profile == "coolant_shaft":
		for x in range(int(rect.position.x + 26), int(rect.end.x), 112):
			draw_rect(Rect2(x, rect.position.y, 5, rect.size.y), STEEL_DEEP)
			draw_line(Vector2(x + 1, rect.position.y), Vector2(x + 1, rect.end.y),
					Color(EDGE_DIM, 0.45), 1.0)
	elif profile == "archive_sorter":
		for y in [rect.position.y + 94.0, rect.position.y + 286.0]:
			if y < rect.end.y - 20.0:
				draw_rect(Rect2(rect.position.x + 26, y, rect.size.x - 52, 3), STEEL_DEEP)
	elif profile == "egress_lock":
		draw_rect(Rect2(rect.position.x, rect.position.y + 18, rect.size.x, 4),
				Color(RED, 0.22))
	elif profile == "service_bay" or profile == "relay_service":
		# 检查点房只留墙挂供电轨；地面由真实 CheckpointBeacon 独占，避免重复假交互物。
		var rail_y := rect.position.y + 42.0
		draw_rect(Rect2(rect.position.x + 28.0, rail_y, rect.size.x - 56.0, 8.0),
				Color("#1d302f"))
		draw_line(Vector2(rect.position.x + 36.0, rail_y + 1.0),
				Vector2(rect.end.x - 36.0, rail_y + 1.0), Color(CYAN, 0.16), 1.0)
	elif profile == "coolant_reservoir":
		# 冷却区的墙面只保留两条粗回流槽，主罐体由 Architecture 语义负责。
		for y in [rect.position.y + 54.0, rect.end.y - 132.0]:
			draw_rect(Rect2(rect.position.x + 22.0, y, rect.size.x - 44.0, 9.0),
					Color("#182b32"))
	elif profile == "freight_crossfire":
		# 琥珀导向线只在收货端局部出现，不能再次变成贯穿整房的霓虹地板。
		draw_line(rect.position + Vector2(32.0, 34.0),
				Vector2(rect.position.x + minf(300.0, rect.size.x * 0.26), rect.position.y + 34.0),
				Color(AMBER, 0.28), 3.0)
	elif profile == "containment_core":
		# 收容区暗红信号锁在上缘，给最终战斗留出干净的中亮染血墙面。
		for x in range(int(rect.position.x + 52.0), int(rect.end.x - 40.0), 176):
			draw_rect(Rect2(x, rect.position.y + 28.0, 72.0, 4.0), Color(RED, 0.20))


func _draw_backdrop_semantics() -> void:
	var ids: Dictionary = semantic_ids.get("BackdropTiles", {})
	var service_void_id := int(ids.get("ServiceVoid", -1))
	# 后段会在多个房间复用 ServiceVoid；必须逐房裁切，否则同 value 的远端暗井会
	# 被一个跨房间大矩形连起来，盖住正常墙面和行走路线。
	for room: Dictionary in level.rooms:
		var room_rect: Rect2i = room["rect"]
		var service_void_bounds := _value_bounds_in_rect(
				"BackdropTiles", service_void_id, room_rect)
		if service_void_bounds.size != Vector2i.ZERO:
			_draw_service_void(_cell_rect(service_void_bounds))
	for run: Dictionary in _horizontal_runs("BackdropTiles"):
		var value := int(run["value"])
		var rect := _cell_rect(run["rect"])
		if value == int(ids.get("Recess", -1)):
			draw_rect(rect, STEEL_DEEP)
			draw_rect(rect.grow(-3.0), Color("#20313e"))
		elif value == int(ids.get("ObservationGlass", -1)):
			draw_rect(rect, Color("#142833"))
			draw_rect(rect.grow(-3.0), GLASS)
			draw_line(rect.position + Vector2(5, 6),
					Vector2(rect.end.x - 5, rect.position.y + 6), Color(GLASS_HI, 0.75), 1.0)
		elif value == service_void_id:
			# ServiceVoid 已按完整边界一次绘制，避免逐行矩形留下接缝。
			continue
		elif value == int(ids.get("WallShell", -1)):
			# 墙壳只补非常轻的板面差，不重复覆盖房间基底。
			draw_rect(rect, Color(STEEL, 0.055))


func _draw_service_void(rect: Rect2) -> void:
	# 左右吃黑带按 64px 段错开深度，不再形成笔直等宽的矩形黑框。
	var alphas := PackedFloat32Array([0.14, 0.30, 0.58, 0.82])
	for i in range(4):
		var y := int(rect.position.y)
		var segment := 0
		while y < int(rect.end.y):
			var segment_h := mini(64 + ((segment + i) % 2) * 32, int(rect.end.y) - y)
			var stagger := float(((segment * 3 + i) % 3) * 4)
			var left_x := rect.position.x - TS + float(i * 8) - stagger
			var right_x := rect.end.x + float(i * 8) + stagger
			draw_rect(Rect2(left_x, y, 8.0 + stagger, segment_h),
					Color(VOID, alphas[i]))
			draw_rect(Rect2(right_x, y, 8.0 + stagger, segment_h),
					Color(VOID, alphas[3 - i]))
			y += segment_h
			segment += 1
	# 半透明底层先把墙色压入暗部，再用错齿多边形画实黑核心；边缘不再是整高直线。
	draw_rect(rect, Color(VOID, 0.72))
	draw_colored_polygon(_service_void_core_polygon(rect), VOID)
	# 少量断口钢片压住两侧直边，让黑暗像设备后方的深层空腔而不是贴上去的色块。
	for y in range(int(rect.position.y + 46), int(rect.end.y - 24), 112):
		draw_rect(Rect2(rect.position.x - 5, y, 12, 22), STEEL_DEEP)
		draw_line(Vector2(rect.position.x - 4, y + 2), Vector2(rect.position.x + 5, y + 2),
				Color(EDGE_DIM, 0.48), 1.0)
		draw_rect(Rect2(rect.end.x - 7, y + 43, 12, 17), STEEL_DEEP)


func _service_void_core_polygon(rect: Rect2) -> PackedVector2Array:
	var left_steps := PackedInt32Array([8, 0, 12, 4, 16, 6])
	var right_steps := PackedInt32Array([4, 14, 2, 10, 0, 16])
	var segment_h := 64.0
	var segments := maxi(1, ceili(rect.size.y / segment_h))
	var polygon := PackedVector2Array()
	for i in range(segments + 1):
		var y := minf(rect.end.y, rect.position.y + i * segment_h)
		polygon.append(Vector2(rect.position.x + left_steps[i % left_steps.size()], y))
	for i in range(segments, -1, -1):
		var y := minf(rect.end.y, rect.position.y + i * segment_h)
		polygon.append(Vector2(rect.end.x - right_steps[i % right_steps.size()], y))
	return polygon


func _draw_architecture() -> void:
	var ids: Dictionary = semantic_ids.get("Architecture", {})
	# 先按房间作用域派发；扩展地图允许同一类设备在远端再次出现，不能使用全图 bounds。
	for room: Dictionary in level.rooms:
		var room_rect: Rect2i = room["rect"]
		var profile := String(room.get("decor_profile", ""))
		var name := _landmark_name_for_profile(profile)
		if name.is_empty():
			continue
		var value := int(ids.get(name, -1))
		var bounds := _value_bounds_in_rect("Architecture", value, room_rect)
		if bounds.size == Vector2i.ZERO:
			continue
		match name:
			"EntryScanner":
				_draw_entry_scanner(bounds)
			"QuarantineChamber":
				_draw_quarantine_chamber(_cell_rect(bounds))
			"ShaftStatusDisplay":
				_draw_shaft_status_display(bounds, room_rect)
			"ArchiveSorter":
				_draw_archive_sorter(_cell_rect(bounds))
			"ServiceBench":
				_draw_service_bench(_cell_rect(bounds), profile)
			"CoolantReservoir":
				_draw_coolant_reservoir(_cell_rect(bounds))
			"FreightGantry":
				_draw_freight_gantry(_cell_rect(bounds))
			"ContainmentCore":
				_draw_containment_core(_cell_rect(bounds))
			"ExitSeal":
				_draw_exit_seal(_cell_rect(bounds))
	_draw_stairs()


func _draw_entry_scanner(_semantic_bounds: Rect2i) -> void:
	var room := _room_by_profile("safe_entry")
	if room.is_empty():
		return
	var rr: Rect2i = room["rect"]
	# 512×320 原生像素整尺寸放入 19×10 格入口，不做非整数缩放。
	var x := float(rr.position.x * TS + (rr.size.x * TS - 512) / 2)
	var y := float((rr.position.y + 1) * TS)
	draw_texture(SCANNER_TEXTURE, Vector2(x, y))


func _draw_quarantine_chamber(rect: Rect2) -> void:
	var room := _room_by_profile("quarantine_scanner")
	if room.is_empty():
		return
	var shell := _room_shell_rect(room)
	_draw_loading_gantry(shell, rect)

	var body := rect.grow(-8.0)
	draw_rect(body.grow(5.0), Color("#0a1118"))
	draw_rect(body, STEEL_DEEP)
	draw_rect(body, EDGE_DIM, false, 4.0)
	# 上盖故意做成不对称的两块厚钢板，右块缺角，避免三等分玻璃柜观感。
	draw_rect(Rect2(body.position.x + 8, body.position.y + 8,
			body.size.x * 0.58, 30), Color("#405561"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(body.position.x + body.size.x * 0.62, body.position.y + 8),
		Vector2(body.end.x - 14, body.position.y + 8),
		Vector2(body.end.x - 14, body.position.y + 30),
		Vector2(body.end.x - 38, body.position.y + 38),
		Vector2(body.position.x + body.size.x * 0.62, body.position.y + 38),
	]), Color("#344854"))
	draw_line(body.position + Vector2(14, 10),
			Vector2(body.position.x + body.size.x * 0.54, body.position.y + 10),
			Color(EDGE, 0.72), 2.0)

	var inner := Rect2(body.position + Vector2(20, 50), body.size - Vector2(40, 94))
	var aperture_w := floorf(inner.size.x * 0.68)
	var aperture := Rect2(inner.position, Vector2(aperture_w, inner.size.y))
	var console := Rect2(inner.position + Vector2(aperture_w + 12, 0),
			Vector2(inner.size.x - aperture_w - 12, inner.size.y))

	# 左侧是货物扫描暗腔：低亮玻璃、货箱轮廓与动态扫描幕共同说明用途。
	draw_rect(aperture.grow(5.0), Color("#101820"))
	draw_rect(aperture, Color("#17303b"))
	draw_rect(aperture, Color("#55717b"), false, 2.0)
	for i in range(4):
		var data_w := 26.0 + i * 13.0
		draw_rect(Rect2(aperture.position.x + 13, aperture.position.y + 13 + i * 9,
				data_w, 3), Color(CYAN if i == 0 else GLASS_HI, 0.48 - i * 0.06))
	for y in range(int(aperture.position.y + 16), int(aperture.end.y - 8), 28):
		draw_line(Vector2(aperture.position.x + 8, y), Vector2(aperture.end.x - 8, y),
				Color(CYAN, 0.075), 1.0)
	var cargo_w := minf(142.0, aperture.size.x - 64.0)
	var cargo := Rect2(aperture.position.x + 32, aperture.end.y - 101, cargo_w, 82)
	draw_rect(cargo, Color("#263842"))
	draw_rect(cargo, Color("#6b7e82"), false, 2.0)
	draw_line(cargo.position + Vector2(8, 10), cargo.end - Vector2(9, 10),
			Color("#8b6d4c"), 3.0, false)
	draw_line(Vector2(cargo.end.x - 9, cargo.position.y + 10),
			Vector2(cargo.position.x + 8, cargo.end.y - 10), Color("#536971"), 2.0, false)
	draw_rect(Rect2(cargo.position + Vector2(14, 23), Vector2(54, 6)),
			Color(AMBER, 0.30))
	draw_rect(Rect2(cargo.position + Vector2(17, 43), Vector2(29, 18)),
			Color("#172831"))
	draw_rect(Rect2(cargo.position + Vector2(54, 39), Vector2(19, 24)),
			Color("#324b55"))
	# 四角锁定框把屏幕内容读成正在识别的货物，而不是空白装饰窗。
	var bracket := Color(CYAN, 0.62)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := cargo.get_center() + Vector2(sx * (cargo.size.x * 0.5 + 7),
					sy * (cargo.size.y * 0.5 + 7))
			draw_line(corner, corner + Vector2(-sx * 13, 0), bracket, 2.0)
			draw_line(corner, corner + Vector2(0, -sy * 13), bracket, 2.0)
	var scan_span := maxi(1, int(aperture.size.x - 22.0))
	var scan_x := roundf(aperture.position.x + 11.0 + fmod(_phase * 39.0, scan_span))
	draw_rect(Rect2(scan_x - 3, aperture.position.y + 8, 7, aperture.size.y - 16),
			Color(CYAN, 0.055))
	draw_line(Vector2(scan_x, aperture.position.y + 6),
			Vector2(scan_x, aperture.end.y - 6), Color(CYAN, 0.76), 2.0)

	# 右侧窄控制柜保留动态路线、载荷与检疫状态，不使用文字和抗锯齿字体。
	draw_rect(console, Color("#14242d"))
	draw_rect(console, Color("#405d68"), false, 2.0)
	for i in range(3):
		var row_y := console.position.y + 16.0 + i * 34.0
		draw_rect(Rect2(console.position.x + 10, row_y, console.size.x - 20, 19),
				Color("#0d1d25"))
		var load := 0.30 + 0.55 * (0.5 + 0.5 * sin(_phase * (1.4 + i * 0.22) + i))
		draw_rect(Rect2(console.position.x + 14, row_y + 7,
				roundf((console.size.x - 30) * load), 4),
				Color(AMBER if i == 1 else CYAN, 0.64))
	var route_y := console.end.y - 29.0
	draw_line(Vector2(console.position.x + 13, route_y),
			Vector2(console.end.x - 13, route_y), Color("#42616b"), 3.0)
	for i in range(3):
		var node_x := lerpf(console.position.x + 16, console.end.x - 16, float(i) / 2.0)
		var active := posmod(floori(_phase * 1.7), 3) == i
		draw_rect(Rect2(node_x - 3, route_y - 4, 7, 8),
				Color(AMBER if active else CYAN, 0.82 if active else 0.34))

	# 厚脚把扫描舱落到输送带后方；角色活动层仍在本建筑之上。
	for support_x in [body.position.x + 26.0, body.end.x - 38.0]:
		draw_rect(Rect2(support_x, body.end.y, 12, shell.end.y - body.end.y - 20),
				Color("#182630"))
		draw_line(Vector2(support_x + 3, body.end.y),
				Vector2(support_x + 3, shell.end.y - 20), Color(EDGE_DIM, 0.62), 2.0)
	draw_rect(Rect2(body.position.x + 12, body.end.y - 8, body.size.x - 24, 12),
			Color("#111a22"))
	draw_line(Vector2(body.position.x + 16, body.end.y - 8),
			Vector2(body.end.x - 16, body.end.y - 8), Color(EDGE, 0.70), 2.0)


## 检疫厅运输线：两只吊具对齐正式 bat_cargo 站位，右柱落在楼梯入口前形成空间门槛。
func _draw_loading_gantry(shell: Rect2, chamber: Rect2) -> void:
	var rail_left := maxf(shell.position.x + 192.0, chamber.position.x - 96.0)
	var rail_right := minf(shell.end.x + 32.0, chamber.end.x + 448.0)
	var rail_y := maxf(shell.position.y + 40.0, chamber.position.y - 44.0)
	draw_rect(Rect2(rail_left, rail_y, rail_right - rail_left, 20), Color("#101820"))
	draw_rect(Rect2(rail_left, rail_y + 4, rail_right - rail_left, 10), Color("#3d515c"))
	draw_line(Vector2(rail_left, rail_y + 4), Vector2(rail_right, rail_y + 4),
			Color("#83969a"), 2.0)
	for x in range(int(rail_left + 36), int(rail_right - 28), 144):
		draw_line(Vector2(x, rail_y + 15), Vector2(x + 46, rail_y + 5),
				Color("#263842"), 5.0, false)
		draw_line(Vector2(x + 4, rail_y + 14), Vector2(x + 43, rail_y + 6),
				Color(EDGE_DIM, 0.64), 2.0, false)

	# 左右立柱避开扫描舱正面；右柱与楼梯入口之间仍留完整角色通道。
	for post_x in [rail_left, rail_right - 14.0]:
		draw_rect(Rect2(post_x, rail_y + 18, 14, shell.end.y - rail_y - 26),
				Color("#17242d"))
		draw_line(Vector2(post_x + 3, rail_y + 20),
				Vector2(post_x + 3, shell.end.y - 10), Color("#566b73"), 2.0)

	# c28/c40 两只货箱正上方的吊具；暖色只用于操作头和任务灯。
	for i in range(2):
		var hoist_x := chamber.position.x + (3.5 + i * 12.0) * TS
		var carriage := Rect2(hoist_x - 17, rail_y + 12, 34, 16)
		draw_rect(carriage, Color("#111a22"))
		draw_rect(carriage.grow(-3.0), Color("#4a5d65"))
		draw_rect(Rect2(hoist_x - 5, rail_y + 16, 10, 4), Color(AMBER, 0.78))
		draw_line(Vector2(hoist_x, carriage.end.y),
				Vector2(hoist_x, shell.end.y - 78), Color("#26343c"), 3.0)
		draw_line(Vector2(hoist_x + 2, carriage.end.y),
				Vector2(hoist_x + 2, shell.end.y - 78), Color("#65767a"), 1.0)
		draw_rect(Rect2(hoist_x - 7, shell.end.y - 79, 16, 9), Color("#1a2730"))
		draw_rect(Rect2(hoist_x - 3, shell.end.y - 76, 7, 3), Color(AMBER, 0.58))
		for light_step in range(3):
			var half_w := 12.0 + light_step * 9.0
			draw_rect(Rect2(hoist_x - half_w, rail_y + 30 + light_step * 9,
					half_w * 2.0, 9), Color(AMBER, 0.045 - light_step * 0.010))

	# 低位输送带落在地面上方，不改变碰撞；稀疏滚轮避免又变成 32px 方格带。
	var belt_left := rail_left + 28.0
	var belt_right := rail_right - 16.0
	var belt_y := shell.end.y - 29.0
	draw_rect(Rect2(belt_left, belt_y, belt_right - belt_left, 18), Color("#111b23"))
	draw_line(Vector2(belt_left, belt_y), Vector2(belt_right, belt_y), EDGE, 2.0)
	draw_line(Vector2(belt_left, belt_y + 16), Vector2(belt_right, belt_y + 16),
			Color("#24343d"), 2.0)
	for x in range(int(belt_left + 18), int(belt_right - 12), 52):
		draw_circle(Vector2(x, belt_y + 9), 5.0, Color("#0b131b"))
		draw_circle(Vector2(x, belt_y + 9), 2.0, Color("#52646a"))
	# 两个装载位以低饱和钢板和小琥珀角标收边，给真实货箱明确落脚位置。
	for i in range(2):
		var station_x := chamber.position.x + (3.5 + i * 12.0) * TS
		var station := Rect2(station_x - 28, belt_y - 3, 56, 20)
		draw_rect(station, Color("#1d2c35"))
		draw_line(station.position, Vector2(station.end.x, station.position.y),
				Color("#718186"), 2.0)
		draw_rect(Rect2(station.position + Vector2(3, 3), Vector2(7, 3)),
				Color(AMBER, 0.56))
		draw_rect(Rect2(station.end - Vector2(10, 17), Vector2(7, 3)),
				Color(AMBER, 0.56))


func _draw_shaft_status_display(fallback_bounds: Rect2i, room_rect: Rect2i) -> void:
	# 大屏以维护井的 ServiceVoid 凹槽为边界；Architecture 格只声明地标种类，
	# 不再让三列孤立管线决定画面布局。
	var backdrop_ids: Dictionary = semantic_ids.get("BackdropTiles", {})
	var service_id := int(backdrop_ids.get("ServiceVoid", -1))
	var service_bounds := _value_bounds_in_rect("BackdropTiles", service_id, room_rect)
	var recess := _cell_rect(service_bounds if service_bounds.size != Vector2i.ZERO \
			else fallback_bounds)
	var frame := Rect2(recess.position + Vector2(20.0, 26.0),
			Vector2(recess.size.x - 40.0, 250.0))
	var screen := frame.grow(-10.0)

	# 厚重嵌墙边框和单块显示面先建立主次关系。
	draw_rect(frame.grow(6.0), Color("#0a0f15"))
	draw_rect(frame, STEEL_DEEP)
	draw_rect(frame, EDGE_DIM, false, 4.0)
	draw_rect(screen, Color("#0a1820"))
	draw_rect(screen, Color("#355362"), false, 2.0)
	draw_rect(Rect2(screen.position, Vector2(screen.size.x, 22.0)), Color("#142a34"))
	draw_line(Vector2(screen.position.x, screen.position.y + 22.0),
			Vector2(screen.end.x, screen.position.y + 22.0), Color(CYAN, 0.46), 2.0)

	# 顶部状态槽、中央检疫路线和右侧诊断柱共同说明这是一块系统屏，而非黑洞。
	for i in range(6):
		var slot_x := screen.position.x + 10.0 + i * 34.0
		draw_rect(Rect2(slot_x, screen.position.y + 8.0, 24.0, 5.0), Color("#203944"))
		if i in [0, 3, 5]:
			var signal_color := CYAN if i == 0 else (AMBER if i == 3 else MAGENTA)
			draw_rect(Rect2(slot_x + 3.0, screen.position.y + 9.0, 12.0, 3.0),
					Color(signal_color, 0.78))
	for y in range(int(screen.position.y + 34.0), int(screen.end.y - 8.0), 12):
		draw_line(Vector2(screen.position.x + 8.0, y),
				Vector2(screen.end.x - 8.0, y), Color(CYAN, 0.055), 1.0)
	# 扫描线只按整数像素移动，保持 nearest 画面稳定。
	var scan_span := maxi(1, int(screen.size.y - 42.0))
	var scan_y := roundf(screen.position.y + 30.0 + fmod(_phase * 31.0, scan_span))
	draw_line(Vector2(screen.position.x + 8.0, scan_y),
			Vector2(screen.end.x - 8.0, scan_y), Color(CYAN, 0.20), 1.0)

	var route_y := screen.position.y + 112.0
	draw_line(Vector2(screen.position.x + 26.0, route_y),
			Vector2(screen.end.x - 58.0, route_y), Color("#315866"), 4.0)
	for i in range(5):
		var node_x := screen.position.x + 30.0 + i * 36.0
		var node_color := AMBER if i == 3 else CYAN
		var active_node := posmod(floori(_phase * 1.5), 5) == i
		draw_rect(Rect2(node_x - 5.0, route_y - 7.0, 11.0, 14.0), Color("#10232b"))
		draw_rect(Rect2(node_x - 3.0, route_y - 4.0, 7.0, 8.0),
				Color(node_color, 0.88 if active_node else (0.62 if i == 3 else 0.38)))
	# 左下波形与右侧五级仪表保持硬边、低亮，不与角色轮廓争抢。
	var wave := PackedVector2Array()
	for i in range(12):
		var wave_x := screen.position.x + 20.0 + i * 14.0
		var wave_y := roundf(screen.position.y + 176.0
				+ sin(_phase * 2.4 + i * 0.78) * 10.0)
		wave.append(Vector2(wave_x, wave_y))
	draw_polyline(wave, Color(CYAN, 0.48), 2.0, false)
	for i in range(5):
		var meter_y := screen.position.y + 64.0 + i * 28.0
		var meter_w := roundf(10.0 + i * 3.0
				+ (sin(_phase * 1.8 + i * 0.9) + 1.0) * 3.0)
		draw_rect(Rect2(screen.end.x - 44.0, meter_y, 28.0, 9.0), Color("#132a34"))
		draw_rect(Rect2(screen.end.x - 41.0, meter_y + 3.0,
				meter_w, 3.0), Color(AMBER if i == 4 else CYAN, 0.58))

	# 下方控制台与两根短支架把显示屏落实到建筑结构上。
	var console := Rect2(frame.position.x + 14.0, frame.end.y + 20.0,
			frame.size.x - 28.0, 58.0)
	draw_rect(console, Color("#111c24"))
	draw_line(console.position, Vector2(console.end.x, console.position.y), EDGE, 3.0)
	for i in range(4):
		var panel := Rect2(console.position.x + 12.0 + i * 58.0,
				console.position.y + 13.0, 44.0, 27.0)
		draw_rect(panel, Color("#20323d"))
		draw_rect(Rect2(panel.position + Vector2(6.0, 7.0), Vector2(21.0, 3.0)),
				Color(CYAN if i != 2 else AMBER, 0.46))
	for support_x in [console.position.x + 28.0, console.end.x - 38.0]:
		draw_rect(Rect2(support_x, console.end.y, 10.0, 38.0), STEEL_DEEP)
		draw_line(Vector2(support_x + 3.0, console.end.y),
				Vector2(support_x + 3.0, console.end.y + 38.0), EDGE_DIM, 2.0)


func _draw_archive_sorter(rect: Rect2) -> void:
	var body := rect.grow(-8.0)
	draw_rect(body, Color("#17232a"))
	draw_rect(body, Color("#59666a"), false, 3.0)
	# 双路分流机取代旧版散落档案箱：一条进料轨在中心机械转盘处分叉，功能一眼可读。
	var fork := Vector2(body.position.x + body.size.x * 0.48,
			body.position.y + body.size.y * 0.56).round()
	var inlet_y := fork.y
	var upper_y := maxf(body.position.y + 76.0, fork.y - 92.0)
	var lower_y := minf(body.end.y - 84.0, fork.y + 92.0)
	var inlet_start := Vector2(body.position.x + 22.0, inlet_y)
	var upper_end := Vector2(body.end.x - 24.0, upper_y)
	var lower_end := Vector2(body.end.x - 24.0, lower_y)
	for route in [PackedVector2Array([inlet_start, fork]),
			PackedVector2Array([fork, upper_end]), PackedVector2Array([fork, lower_end])]:
		draw_polyline(route, Color("#0d151b"), 18.0, false)
		draw_polyline(route, Color("#53666b"), 8.0, false)
		draw_polyline(route, Color("#819095"), 2.0, false)
	# 中央六边转盘与两枚方向锁，构成“档案分叉”而不是普通仓库。
	draw_colored_polygon(PackedVector2Array([
		fork + Vector2(-30, -18), fork + Vector2(0, -34), fork + Vector2(30, -18),
		fork + Vector2(30, 18), fork + Vector2(0, 34), fork + Vector2(-30, 18),
	]), Color("#111b22"))
	draw_colored_polygon(PackedVector2Array([
		fork + Vector2(-18, -10), fork + Vector2(0, -20), fork + Vector2(18, -10),
		fork + Vector2(18, 10), fork + Vector2(0, 20), fork + Vector2(-18, 10),
	]), Color("#3f5259"))
	var active_lane := posmod(floori(_phase * 1.25), 2)
	for i in range(2):
		var target := upper_end if i == 0 else lower_end
		var marker := fork.lerp(target, 0.52)
		draw_rect(Rect2(marker - Vector2(13, 6), Vector2(26, 12)), Color("#142229"))
		draw_rect(Rect2(marker - Vector2(8, 2), Vector2(16, 4)),
				Color(AMBER, 0.82 if active_lane == i else 0.32))
	# 档案胶囊沿三条轨道按相同规格排列，重复体现流程而非随机堆箱。
	for i in range(4):
		var t := 0.12 + i * 0.19
		_draw_archive_capsule(inlet_start.lerp(fork, t), i == 3)
	for i in range(3):
		var t := 0.28 + i * 0.25
		_draw_archive_capsule(fork.lerp(upper_end, t), i == active_lane)
		_draw_archive_capsule(fork.lerp(lower_end, t), i != active_lane)
	# 右侧两组竖向接收槽收住分支终点，不铺满整面墙。
	for lane_y in [upper_y, lower_y]:
		var receiver := Rect2(body.end.x - 70.0, lane_y - 36.0, 46.0, 72.0)
		draw_rect(receiver, Color("#202f35"))
		draw_rect(receiver, Color("#6b7879"), false, 2.0)
		for slot in range(3):
			draw_rect(Rect2(receiver.position.x + 9.0, receiver.position.y + 12.0 + slot * 17,
					28.0, 5.0), Color(AMBER, 0.20 + slot * 0.08))


func _draw_archive_capsule(center: Vector2, active: bool) -> void:
	var p := center.round()
	draw_rect(Rect2(p - Vector2(13, 8), Vector2(26, 16)), Color("#16242b"))
	draw_rect(Rect2(p - Vector2(9, 5), Vector2(18, 10)), Color("#43565c"))
	draw_rect(Rect2(p - Vector2(6, 2), Vector2(12, 4)),
			Color(AMBER, 0.68 if active else 0.30))


func _draw_service_bench(rect: Rect2, profile: String) -> void:
	# 两个检查点共用 ServiceBench 枚举，但按 profile 显示维修台或中继台；全部墙挂，
	# 底部至少留 64px 空白给真实 CheckpointBeacon 和角色站位。
	if rect.size.x <= 128.0:
		_draw_compact_relay_bench(rect)
		return
	var margin := 10.0
	var unit_h := minf(210.0, maxf(104.0, rect.size.y - 84.0))
	var unit := Rect2(rect.position + Vector2(margin, margin),
			Vector2(rect.size.x - margin * 2.0, unit_h))
	draw_rect(unit.grow(5.0), Color("#111a1d"))
	draw_rect(unit, Color("#263a39" if profile == "service_bay" else "#243735"))
	draw_rect(unit, Color("#647773"), false, 3.0)
	var screen_w := maxf(76.0, unit.size.x * 0.42)
	var screen := Rect2(unit.position + Vector2(16.0, 18.0),
			Vector2(screen_w, minf(94.0, unit.size.y - 42.0)))
	draw_rect(screen.grow(4.0), Color("#101719"))
	draw_rect(screen, Color("#0c2021"))
	draw_rect(screen, Color("#456963"), false, 2.0)
	for i in range(4):
		var line_y := screen.position.y + 15.0 + i * 16.0
		var line_w := screen.size.x * (0.72 - i * 0.10)
		draw_rect(Rect2(screen.position.x + 11.0, line_y, line_w, 4.0),
				Color(CYAN, 0.34 if i != 2 else 0.58))
	var module_x := screen.end.x + 16.0
	var module_w := maxf(34.0, unit.end.x - module_x - 14.0)
	for i in range(3):
		var module := Rect2(module_x, unit.position.y + 18.0 + i * 40.0,
				module_w, 28.0)
		draw_rect(module, Color("#172726"))
		draw_rect(Rect2(module.position + Vector2(8.0, 8.0),
				Vector2(maxf(10.0, module.size.x - 24.0), 4.0)),
				Color(AMBER if profile == "service_bay" and i == 1 else CYAN, 0.46))
	# 中继检查点多一枚中央数据耦合器；维修间则画工具/电源插槽，语义彼此可辨。
	if profile == "relay_service":
		var relay := Vector2(module_x + module_w * 0.5, unit.end.y - 35.0).round()
		draw_colored_polygon(PackedVector2Array([
			relay + Vector2(-22, 0), relay + Vector2(-11, -19), relay + Vector2(11, -19),
			relay + Vector2(22, 0), relay + Vector2(11, 19), relay + Vector2(-11, 19),
		]), Color("#152626"))
		draw_rect(Rect2(relay - Vector2(7, 7), Vector2(14, 14)), Color(CYAN, 0.48))
	else:
		var tool_y := unit.end.y - 27.0
		draw_rect(Rect2(unit.position.x + 18.0, tool_y, unit.size.x - 36.0, 7.0),
				Color("#172523"))
		for i in range(4):
			draw_rect(Rect2(unit.position.x + 28.0 + i * 31.0, tool_y - 13.0,
					5.0, 13.0), Color("#75827b"))
	# 两根短墙撑在设备底部结束，不延伸到地面形成假墙。
	for support_x in [unit.position.x + 24.0, unit.end.x - 31.0]:
		draw_rect(Rect2(support_x, unit.end.y, 7.0, 22.0), Color("#172522"))


func _draw_compact_relay_bench(rect: Rect2) -> void:
	# 上联房的语义仅 96×96：改用单列耦合器，不把宽屏/模块强塞出房框。
	var unit := rect.grow(-7.0)
	draw_rect(unit.grow(4.0), Color("#111a1d"))
	draw_rect(unit, Color("#243735"))
	draw_rect(unit, Color("#647773"), false, 2.0)
	var screen := Rect2(unit.position + Vector2(9.0, 9.0),
			Vector2(unit.size.x - 18.0, 35.0))
	draw_rect(screen, Color("#0c2021"))
	draw_rect(screen, Color("#456963"), false, 2.0)
	for i in range(3):
		draw_rect(Rect2(screen.position.x + 8.0, screen.position.y + 9.0 + i * 8.0,
				maxf(8.0, screen.size.x - 18.0 - i * 7.0), 3.0), Color(CYAN, 0.42))
	var relay := Vector2(unit.get_center().x, unit.end.y - 20.0).round()
	draw_colored_polygon(PackedVector2Array([
		relay + Vector2(-15, 0), relay + Vector2(-8, -12), relay + Vector2(8, -12),
		relay + Vector2(15, 0), relay + Vector2(8, 12), relay + Vector2(-8, 12),
	]), Color("#152626"))
	draw_rect(Rect2(relay - Vector2(5, 5), Vector2(10, 10)), Color(CYAN, 0.52))


func _draw_coolant_reservoir(rect: Rect2) -> void:
	var body := rect.grow(-8.0)
	draw_rect(body, Color("#14282f"))
	draw_rect(body, Color("#557078"), false, 3.0)
	# 顶部总管与三只同规格重型罐构成明确的冷却工艺线；罐间泵组有逻辑连接。
	var header_y := body.position.y + 26.0
	draw_rect(Rect2(body.position.x + 18.0, header_y, body.size.x - 36.0, 18.0),
			Color("#16242a"))
	draw_line(Vector2(body.position.x + 20.0, header_y + 4.0),
			Vector2(body.end.x - 20.0, header_y + 4.0), Color("#607b80"), 3.0)
	var group_w := minf(body.size.x - 44.0, 650.0)
	var group_x := body.get_center().x - group_w * 0.5
	var gap := 18.0
	var tank_w := floorf((group_w - gap * 4.0) / 3.0)
	var tank_top := header_y + 52.0
	var tank_bottom := body.end.y - 42.0
	for i in range(3):
		var tank := Rect2(Vector2(group_x + gap + i * (tank_w + gap), tank_top),
				Vector2(tank_w, maxf(120.0, tank_bottom - tank_top)))
		_draw_coolant_tank(tank, i)
		var neck_x := tank.get_center().x - 7.0
		draw_rect(Rect2(neck_x, header_y + 15.0, 14.0, tank_top - header_y - 15.0),
				Color("#1b3137"))
		draw_line(Vector2(neck_x + 3.0, header_y + 17.0),
				Vector2(neck_x + 3.0, tank_top), Color("#58777c"), 2.0)
	# 罐底回流泵只占背景下缘，颜色压低避免误读为实体台阶。
	for i in range(2):
		var pump_x := group_x + (i + 1) * (tank_w + gap) - 16.0
		var pump := Rect2(pump_x, tank_bottom - 28.0, 48.0, 34.0)
		draw_rect(pump, Color("#18292f"))
		draw_rect(pump, Color("#526b70"), false, 2.0)
		draw_rect(Rect2(pump.position + Vector2(12.0, 12.0), Vector2(24.0, 6.0)),
				Color(CYAN, 0.34))


func _draw_coolant_tank(tank: Rect2, index: int) -> void:
	var cut := minf(14.0, tank.size.x * 0.16)
	draw_colored_polygon(_cut_corner_polygon(tank, cut), Color("#0e1b21"))
	var inner := tank.grow(-5.0)
	draw_colored_polygon(_cut_corner_polygon(inner, maxf(4.0, cut - 4.0)), Color("#2c464e"))
	# 中央观察窗显示不同液位，冷青仅占窄条，不把整只罐做成霓虹灯。
	var window := Rect2(inner.position + Vector2(inner.size.x * 0.24, 24.0),
			Vector2(inner.size.x * 0.52, inner.size.y - 52.0))
	draw_rect(window, Color("#10262d"))
	draw_rect(window, Color("#58747a"), false, 2.0)
	var fill_ratio := 0.50 + 0.10 * sin(_phase * (0.58 + index * 0.07) + index)
	var fill_h := floorf((window.size.y - 8.0) * fill_ratio)
	draw_rect(Rect2(window.position.x + 4.0, window.end.y - 4.0 - fill_h,
			window.size.x - 8.0, fill_h), Color(CYAN, 0.16))
	draw_line(Vector2(window.position.x + 5.0, window.end.y - 5.0 - fill_h),
			Vector2(window.end.x - 5.0, window.end.y - 5.0 - fill_h), Color(CYAN, 0.60), 2.0)
	for y in range(int(inner.position.y + 30.0), int(inner.end.y - 18.0), 48):
		draw_rect(Rect2(inner.position.x + 4.0, y, inner.size.x - 8.0, 5.0),
				Color("#526970"))


func _draw_freight_gantry(rect: Rect2) -> void:
	var body := rect.grow(-8.0)
	# 暖灰收货门架与冷却区形成明确色温切换；结构全在背景层，不创建碰撞或门板。
	draw_rect(body, Color("#2a2b2a"))
	draw_rect(body, Color("#756b5d"), false, 3.0)
	var rail_y := body.position.y + 34.0
	# 两扇低对比卷门把大内腔说明为收货口，而不是空白显示屏；分缝保持宽尺度。
	var shutter_top := rail_y + 48.0
	var shutter_bottom := body.end.y - 82.0
	var shutter_gap := 24.0
	var shutter_w := (body.size.x - 64.0 - shutter_gap) * 0.5
	for bay in range(2):
		var shutter := Rect2(body.position.x + 32.0 + bay * (shutter_w + shutter_gap),
				shutter_top, shutter_w, maxf(64.0, shutter_bottom - shutter_top))
		draw_rect(shutter, Color("#242522"))
		draw_rect(shutter, Color("#575247"), false, 2.0)
		for y in range(int(shutter.position.y + 20.0), int(shutter.end.y - 8.0), 28):
			draw_line(Vector2(shutter.position.x + 6.0, y),
					Vector2(shutter.end.x - 6.0, y), Color("#343530"), 3.0)
		# 每个门底仅两枚琥珀定位角，不把整条地面染亮。
		for side in range(2):
			var marker_x := shutter.position.x + 12.0 if side == 0 else shutter.end.x - 24.0
			draw_rect(Rect2(marker_x, shutter.end.y - 13.0, 12.0, 4.0), Color(AMBER, 0.36))
	draw_rect(Rect2(body.position.x + 16.0, rail_y, body.size.x - 32.0, 24.0),
			Color("#191b1d"))
	draw_rect(Rect2(body.position.x + 20.0, rail_y + 5.0, body.size.x - 40.0, 10.0),
			Color("#61594d"))
	draw_line(Vector2(body.position.x + 22.0, rail_y + 5.0),
			Vector2(body.end.x - 22.0, rail_y + 5.0), Color("#a19278"), 2.0)
	for x in range(int(body.position.x + 52.0), int(body.end.x - 48.0), 128):
		draw_line(Vector2(x, rail_y + 19.0), Vector2(x + 38.0, rail_y + 7.0),
				Color("#393832"), 5.0, false)
	# 两台吊秤等距服务两段货箱战斗线，暖任务灯只落在吊头周围。
	for i in range(2):
		var hoist_x := lerpf(body.position.x + body.size.x * 0.30,
				body.position.x + body.size.x * 0.70, float(i))
		var carriage := Rect2(hoist_x - 24.0, rail_y + 15.0, 48.0, 23.0)
		draw_rect(carriage, Color("#17191b"))
		draw_rect(carriage.grow(-4.0), Color("#655e52"))
		draw_rect(Rect2(hoist_x - 8.0, rail_y + 23.0, 16.0, 4.0), Color(AMBER, 0.72))
		var hook_y := body.end.y - 118.0
		draw_line(Vector2(hoist_x, carriage.end.y), Vector2(hoist_x, hook_y),
				Color("#24262a"), 4.0)
		draw_line(Vector2(hoist_x + 2.0, carriage.end.y), Vector2(hoist_x + 2.0, hook_y),
				Color("#766f61"), 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(hoist_x - 12.0, hook_y), Vector2(hoist_x + 12.0, hook_y),
			Vector2(hoist_x + 7.0, hook_y + 14.0), Vector2(hoist_x - 7.0, hook_y + 14.0),
		]), Color("#25292b"))
		for light_step in range(3):
			var half_w := 15.0 + light_step * 12.0
			draw_rect(Rect2(hoist_x - half_w, rail_y + 42.0 + light_step * 10.0,
					half_w * 2.0, 10.0), Color(AMBER, 0.050 - light_step * 0.012))
	# 接收滚床与称重段靠近地面但无高轮廓，确保冲刺、翻滚和球棒弹道视觉上畅通。
	var belt := Rect2(body.position.x + 30.0, body.end.y - 58.0, body.size.x - 60.0, 24.0)
	draw_rect(belt, Color("#17191a"))
	draw_line(belt.position, Vector2(belt.end.x, belt.position.y), Color("#8b8170"), 3.0)
	for x in range(int(belt.position.x + 18.0), int(belt.end.x - 10.0), 46):
		draw_circle(Vector2(x, belt.position.y + 13.0), 6.0, Color("#0d1012"))
		draw_circle(Vector2(x, belt.position.y + 13.0), 2.0, Color("#776f61"))
	var scale := Rect2(belt.get_center().x - 66.0, belt.position.y - 11.0, 132.0, 13.0)
	draw_rect(scale, Color("#2f302d"))
	draw_rect(Rect2(scale.position.x + 7.0, scale.position.y + 3.0, 22.0, 4.0),
			Color(AMBER, 0.58))
	draw_rect(Rect2(scale.end.x - 29.0, scale.position.y + 3.0, 22.0, 4.0),
			Color(AMBER, 0.58))


func _draw_containment_core(rect: Rect2) -> void:
	var body := rect.grow(-8.0)
	draw_rect(body, Color("#211d25"))
	draw_rect(body, Color("#685c69"), false, 3.0)
	# 终战地标是一枚嵌墙八角隔离环；中央保持暗而非高亮，角色和血色仍优先。
	var center := body.get_center().round()
	var outer_size := Vector2(minf(430.0, body.size.x * 0.58),
			minf(360.0, body.size.y - 74.0)).floor()
	var outer := Rect2(center - outer_size * 0.5, outer_size)
	draw_colored_polygon(_cut_corner_polygon(outer, 42.0), Color("#111017"))
	var middle := outer.grow(-14.0)
	draw_colored_polygon(_cut_corner_polygon(middle, 34.0), Color("#544853"))
	var inner := outer.grow(-35.0)
	draw_colored_polygon(_cut_corner_polygon(inner, 24.0), Color("#15121a"))
	var core := inner.grow(-22.0)
	draw_colored_polygon(_cut_corner_polygon(core, 16.0), Color("#251d29"))
	# 四枚锁爪与断续暗红状态灯建立封锁方向，避免画成无用途的巨大空框。
	for offset in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var lock_center := center + Vector2(offset.x * (outer.size.x * 0.5 - 12.0),
				offset.y * (outer.size.y * 0.5 - 12.0))
		var lock_size := Vector2(54.0, 22.0) if offset.y != 0.0 else Vector2(22.0, 54.0)
		draw_rect(Rect2(lock_center - lock_size * 0.5, lock_size), Color("#16151b"))
		draw_rect(Rect2(lock_center - lock_size * 0.30, lock_size * 0.60),
				Color(RED, 0.38))
	var pulse := 0.42 + 0.18 * (0.5 + 0.5 * sin(_phase * 2.2))
	for i in range(5):
		var y := core.position.y + 28.0 + i * maxf(18.0, (core.size.y - 56.0) / 4.0)
		draw_rect(Rect2(core.position.x + 22.0, y, core.size.x - 44.0, 4.0),
				Color(RED if i in [1, 3] else MAGENTA, pulse * (0.68 if i % 2 else 0.36)))
	# 左右控制塔显示能量汇入中心的逻辑，压在墙上，不延伸成实际门或障碍。
	for side_index in range(2):
		var side := -1.0 if side_index == 0 else 1.0
		var tower_x: float = center.x + side * (outer.size.x * 0.5 + 70.0) - 28.0
		var tower := Rect2(tower_x, center.y - 112.0, 56.0, 224.0)
		draw_rect(tower, Color("#191820"))
		draw_rect(tower, Color("#5c5360"), false, 2.0)
		for i in range(5):
			draw_rect(Rect2(tower.position.x + 12.0, tower.position.y + 18.0 + i * 39.0,
					32.0, 7.0), Color(RED if i == 4 else CYAN, 0.24 + i * 0.04))
		draw_line(Vector2(tower.get_center().x, tower.get_center().y),
				Vector2(center.x + side * outer.size.x * 0.30, center.y),
				Color(RED, 0.26), 5.0, false)


func _cut_corner_polygon(rect: Rect2, cut: float) -> PackedVector2Array:
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.34)
	return PackedVector2Array([
		rect.position + Vector2(c, 0), Vector2(rect.end.x - c, rect.position.y),
		Vector2(rect.end.x, rect.position.y + c), Vector2(rect.end.x, rect.end.y - c),
		Vector2(rect.end.x - c, rect.end.y), Vector2(rect.position.x + c, rect.end.y),
		Vector2(rect.position.x, rect.end.y - c), Vector2(rect.position.x, rect.position.y + c),
	])


func _draw_exit_seal(rect: Rect2) -> void:
	var body := rect.grow(-9.0)
	draw_rect(body, Color("#151a23"))
	draw_rect(body, EDGE_DIM, false, 4.0)
	var center := body.get_center()
	draw_rect(Rect2(center.x - 34, body.position.y + 10, 68, body.size.y - 20),
			Color("#242934"))
	draw_line(Vector2(center.x, body.position.y + 14),
			Vector2(center.x, body.end.y - 14), Color(RED, 0.72), 3.0)
	for y in range(int(body.position.y + 18), int(body.end.y - 12), 24):
		draw_rect(Rect2(body.position.x + 8, y, 14, 5), Color(RED, 0.52))
		draw_rect(Rect2(body.end.x - 22, y, 14, 5), Color(RED, 0.52))


func _draw_stairs() -> void:
	# OpenStair 必须与楼梯元数据吻合；生成器会拒绝漂移，这里再做运行时保险。
	if not stair_semantics_valid:
		return
	for stair: Dictionary in level.stairs:
		_draw_stair_shadow(stair)
		_draw_stair_structure(stair)


func _draw_stair_shadow(stair: Dictionary) -> void:
	# 梯下黑暗属于后景，不遮住玩家；四级硬边透明带模拟像素画中的柔和吃黑。
	draw_colored_polygon(_stair_shadow_polygon(stair, -STAIR_SHADOW_TRANSITION_PX),
			Color(VOID, 0.14))
	draw_colored_polygon(_stair_shadow_polygon(stair, -22.0), Color(VOID, 0.30))
	draw_colored_polygon(_stair_shadow_polygon(stair, -12.0), Color(VOID, 0.62))
	draw_colored_polygon(_stair_shadow_polygon(stair, 0.0), VOID)


func _draw_stair_structure(stair: Dictionary) -> void:
	var left_x := float(int(stair["left_c"]) * TS)
	var bottom_y := float(int(stair["bottom_row"]) * TS)
	var steps := int(stair["steps"])
	var rise_dir := int(stair["rise_dir"])
	var edge := _stair_shadow_edge(stair, 0.0)

	# 参考开放工业梯：主承重梁和下缘副梁都位于踏板下，不再画悬空高栏杆。
	draw_polyline(edge, Color("#0b1118"), 13.0, false)
	draw_polyline(edge, Color("#354955"), 7.0, false)
	draw_polyline(PackedVector2Array([edge[0] - Vector2(0, 3),
			edge[1] - Vector2(0, 3)]), Color("#7d8f95"), 2.0, false)
	var lower_edge := PackedVector2Array([edge[0] + Vector2(0, 10),
			edge[1] + Vector2(0, 10)])
	draw_polyline(lower_edge, Color("#0a1016"), 7.0, false)
	draw_polyline(lower_edge, Color("#263842"), 2.0, false)

	for i in range(steps):
		var rank := i + 1 if rise_dir > 0 else steps - i
		var x := left_x + i * TS
		var y := bottom_y - rank * STAIR_RISE
		var center_x := x + TS * 0.5
		var along := (center_x - left_x) / float(steps * TS)
		var beam_y := lerpf(edge[0].y, edge[1].y, along)
		# 短吊耳把每块踏板明确接到斜梁，避免再次出现悬浮横条观感。
		draw_line(Vector2(center_x, y + 7), Vector2(center_x, beam_y),
				Color("#101a22"), 5.0, false)
		draw_line(Vector2(center_x, y + 7), Vector2(center_x, beam_y),
				Color("#4d626b"), 2.0, false)
		# 走行顶面继续与 32×16 高度场逐级吻合；面板只向下增厚。
		draw_rect(Rect2(x, y + 2, TS, 7), Color("#1a2832"))
		draw_rect(Rect2(x, y, TS, 4), Color("#70858e"))
		draw_line(Vector2(x, y), Vector2(x + TS, y), Color("#a9b8b9"), 1.0)
		draw_line(Vector2(x + 4, y + 7), Vector2(x + TS - 4, y + 7),
				Color("#40545e"), 1.0)
		# 每级只给下坡端一枚低饱和铜色扣件，保留参考图节奏但不做霓虹边。
		var nose_x := x if rise_dir > 0 else x + TS - 6
		draw_rect(Rect2(nose_x, y, 6, 2), Color("#c28a43"))
		draw_rect(Rect2(nose_x, y + 2, 2, 5), Color("#69482f"))


## 返回与绘制共用的梯下吃黑强度；测试可验证过渡单调且不会覆盖角色身体区。
func stair_darkness_alpha_at(world_pos: Vector2) -> float:
	if level == null or not stair_semantics_valid:
		return 0.0
	for stair: Dictionary in level.stairs:
		var edge := _stair_shadow_edge(stair, 0.0)
		var bottom_y := float(int(stair["bottom_row"]) * TS + TS)
		var rise_dir := int(stair["rise_dir"])
		var min_x := edge[0].x - (TS if rise_dir < 0 else 0)
		var max_x := edge[1].x + (TS if rise_dir > 0 else 0)
		if world_pos.x < min_x or world_pos.x > max_x or world_pos.y > bottom_y:
			continue
		var edge_y: float
		if world_pos.x < edge[0].x:
			edge_y = edge[0].y
		elif world_pos.x > edge[1].x:
			edge_y = edge[1].y
		else:
			var t := inverse_lerp(edge[0].x, edge[1].x, world_pos.x)
			edge_y = lerpf(edge[0].y, edge[1].y, t)
		var depth := world_pos.y - edge_y
		if depth >= 0.0:
			return 1.0
		if depth >= -12.0:
			return 0.78
		if depth >= -22.0:
			return 0.40
		if depth >= -STAIR_SHADOW_TRANSITION_PX:
			return 0.14
	return 0.0


func _stair_shadow_polygon(stair: Dictionary, edge_offset_y: float) -> PackedVector2Array:
	var edge := _stair_shadow_edge(stair, edge_offset_y)
	var bottom_y := float(int(stair["bottom_row"]) * TS + TS)
	# 高端收进一格落脚平台下方，使梯下与平台下的不可达黑暗连成整体。
	if int(stair["rise_dir"]) > 0:
		return PackedVector2Array([
			edge[0], edge[1], edge[1] + Vector2(TS, 0),
			Vector2(edge[1].x + TS, bottom_y), Vector2(edge[0].x, bottom_y),
		])
	return PackedVector2Array([
		edge[0] - Vector2(TS, 0), edge[0], edge[1],
		Vector2(edge[1].x, bottom_y), Vector2(edge[0].x - TS, bottom_y),
	])


func _stair_shadow_edge(stair: Dictionary, edge_offset_y: float) -> PackedVector2Array:
	var left_x := float(int(stair["left_c"]) * TS)
	var bottom_y := float(int(stair["bottom_row"]) * TS)
	var steps := int(stair["steps"])
	var rise_dir := int(stair["rise_dir"])
	# 斜线穿过各踏板中心下方 14px；两端多出的半级由楼板接口收住。
	var left_rank := 0 if rise_dir > 0 else steps
	var right_rank := steps if rise_dir > 0 else 0
	return PackedVector2Array([
		Vector2(left_x, bottom_y - left_rank * STAIR_RISE + 6.0 + edge_offset_y),
		Vector2(left_x + steps * TS,
				bottom_y - right_rank * STAIR_RISE + 6.0 + edge_offset_y),
	])


func _recount_stair_visual_budget() -> void:
	stair_visual_count = 0
	stair_tread_count = 0
	stair_stringer_count = 0
	stair_shadow_wedge_count = 0
	stair_shadow_transition_band_count = 0
	stair_semantic_cell_count = 0
	stair_semantics_valid = false
	if level == null:
		return
	var open_stair_id := int((semantic_ids.get("Architecture", {}) as Dictionary)
			.get("OpenStair", -1))
	var actual := {}
	for raw in semantic_layers.get("Architecture", []):
		if int(raw[2]) == open_stair_id:
			actual[Vector2i(int(raw[0]), int(raw[1]))] = true
	stair_semantic_cell_count = actual.size()
	var expected := {}
	for stair: Dictionary in level.stairs:
		var left_c := int(stair["left_c"])
		var bottom_y := float(int(stair["bottom_row"]) * TS)
		var steps := int(stair["steps"])
		var rise_dir := int(stair["rise_dir"])
		for i in range(steps):
			var rank := i + 1 if rise_dir > 0 else steps - i
			var row := floori((bottom_y - rank * STAIR_RISE) / TS)
			expected[Vector2i(left_c + i, row)] = true
	stair_semantics_valid = actual.size() == expected.size()
	if stair_semantics_valid:
		for cell: Vector2i in expected:
			if not actual.has(cell):
				stair_semantics_valid = false
				break
	if not stair_semantics_valid:
		return
	stair_visual_count = level.stairs.size()
	stair_shadow_wedge_count = stair_visual_count
	stair_shadow_transition_band_count = stair_visual_count * 4
	stair_stringer_count = stair_visual_count * 2
	for stair: Dictionary in level.stairs:
		stair_tread_count += int(stair["steps"])


func _draw_lights() -> void:
	var colors := {1: CYAN, 2: AMBER, 3: MAGENTA, 4: RED}
	for raw in semantic_layers.get("Lights", []):
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		var value := int(raw[2])
		var color: Color = colors.get(value, CYAN)
		var pulse := 1.0
		if value >= 3:
			pulse = 0.55 + 0.35 * (0.5 + 0.5 * sin(_phase * 4.0 + cell.x))
		var p := Vector2(cell.x * TS, cell.y * TS)
		# 四段硬像素光锥替代 96×58 半透明贴纸；暖光只围绕真实任务灯向下扩散。
		var center_x := p.x + 16.0
		for i in range(4):
			var half_w := 15.0 + i * 11.0
			var band_y := p.y + 18.0 + i * 10.0
			draw_rect(Rect2(center_x - half_w, band_y, half_w * 2.0, 10.0),
					Color(color, (0.072 - i * 0.012) * pulse))
		# 支架、深色外壳、次级钢边和灯芯分层，仍全部落在整数像素。
		draw_rect(Rect2(p + Vector2(5, 6), Vector2(22, 5)), Color("#101820"))
		draw_rect(Rect2(p + Vector2(2, 10), Vector2(28, 10)), STEEL_DEEP)
		draw_rect(Rect2(p + Vector2(4, 11), Vector2(24, 6)), Color("#52656c"))
		draw_rect(Rect2(p + Vector2(6, 14), Vector2(20, 4)), Color(color, 0.78 * pulse))
		draw_rect(Rect2(p + Vector2(10, 14), Vector2(7, 2)), Color(1.0, 0.95, 0.80, pulse))


func _draw_foreground() -> void:
	var ids: Dictionary = semantic_ids.get("ForegroundTiles", {})
	for run: Dictionary in _horizontal_runs("ForegroundTiles"):
		var value := int(run["value"])
		var rect := _cell_rect(run["rect"])
		if value == int(ids.get("NearBeam", -1)):
			var bx := rect.position.x + rect.size.x * 0.5 - 5.0
			draw_rect(Rect2(bx, rect.position.y, 11, rect.size.y), Color("#101720"))
			draw_line(Vector2(bx + 2, rect.position.y), Vector2(bx + 2, rect.end.y),
					Color("#344754"), 2.0)
		elif value == int(ids.get("NearPipe", -1)):
			draw_rect(Rect2(rect.position.x, rect.position.y + 11, rect.size.x, 12),
					Color("#17252e"))
			draw_line(Vector2(rect.position.x, rect.position.y + 12),
					Vector2(rect.end.x, rect.position.y + 12), Color("#3d5962"), 2.0)
		elif value == int(ids.get("HangingChain", -1)):
			var x := rect.position.x + rect.size.x * 0.5
			for y in range(int(rect.position.y), int(rect.end.y), 8):
				draw_rect(Rect2(x - 2 + (2 if int(y / 8) % 2 else 0), y, 4, 6),
						Color("#26343e"))
		elif value == int(ids.get("NearGrate", -1)):
			draw_rect(rect, Color("#111922"))
			for x in range(int(rect.position.x + 5), int(rect.end.x), 10):
				draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y),
						Color("#34434d"), 2.0)


func _room_by_profile(profile: String) -> Dictionary:
	for room: Dictionary in level.rooms:
		if String(room.get("decor_profile", "")) == profile:
			return room
	return {}


func _distinct_values(layer_name: String) -> int:
	var found := {}
	for raw in semantic_layers.get(layer_name, []):
		found[int(raw[2])] = true
	return found.size()


func _value_bounds(layer_name: String, value: int) -> Rect2i:
	var key := layer_name + ":" + str(value)
	if _value_bounds_cache.has(key):
		return _value_bounds_cache[key]
	_cache_build_counts["value_bounds"] += 1
	var min_cell := Vector2i(1 << 20, 1 << 20)
	var max_cell := Vector2i(-1, -1)
	for raw in semantic_layers.get(layer_name, []):
		if int(raw[2]) != value:
			continue
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	if max_cell.x < 0:
		_value_bounds_cache[key] = Rect2i()
		return Rect2i()
	var result := Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)
	_value_bounds_cache[key] = result
	return result


## 只统计指定房框里的同值语义；后半程重复使用同类设备时不得跨房间合并边界。
func _value_bounds_in_rect(layer_name: String, value: int, clip: Rect2i) -> Rect2i:
	if value < 0 or clip.size == Vector2i.ZERO:
		return Rect2i()
	# 相同设备profile在多房复用时，房框必须参与键；不能只按value缓存后串到首房。
	var key := "%s:%d:%d,%d,%d,%d" % [layer_name, value, clip.position.x, clip.position.y, clip.size.x, clip.size.y]
	if _scoped_bounds_cache.has(key):
		return _scoped_bounds_cache[key]
	_cache_build_counts["scoped_bounds"] += 1
	var min_cell := Vector2i(1 << 20, 1 << 20)
	var max_cell := Vector2i(-1, -1)
	for raw in semantic_layers.get(layer_name, []):
		if int(raw[2]) != value:
			continue
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		if not clip.has_point(cell):
			continue
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	if max_cell.x < 0:
		_scoped_bounds_cache[key] = Rect2i()
		return Rect2i()
	var result := Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)
	_scoped_bounds_cache[key] = result
	return result


## 稀疏 IntGrid 按行合并，避免每个背景格一次 draw call。
func _horizontal_runs(layer_name: String) -> Array[Dictionary]:
	if _horizontal_runs_cache.has(layer_name):
		return _horizontal_runs_cache[layer_name]
	_cache_build_counts["horizontal_runs"] += 1
	var triples: Array = semantic_layers.get(layer_name, [])
	var runs: Array[Dictionary] = []
	var current := Rect2i()
	var current_value := -1
	for raw in triples:
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		var value := int(raw[2])
		if current_value == value and current.position.y == cell.y \
				and current.end.x == cell.x:
			current.size.x += 1
		else:
			if current_value >= 0:
				runs.append({"rect": current, "value": current_value})
			current = Rect2i(cell, Vector2i.ONE)
			current_value = value
	if current_value >= 0:
		runs.append({"rect": current, "value": current_value})
	_horizontal_runs_cache[layer_name] = runs
	return runs


func _cell_rect(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position * TS), Vector2(rect.size * TS))
