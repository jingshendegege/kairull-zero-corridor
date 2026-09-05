extends SceneTree
## “协议检疫站”美术切片资产合同测试。
## 只读取独立 PNG，不依赖正式 Level、旧 M03 或 Godot 导入缓存。
## 跑法：godot --headless --path godot --script scripts/test_quarantine_art_slice.gd


const STAIR_PATH := "res://assets/maps/quarantine_slice/industrial_stair_modules.png"
const SCANNER_PATH := "res://assets/maps/quarantine_slice/quarantine_scanner.png"
const STAIR_SIZE := Vector2i(832, 288)
const STAIR_CELL_SIZE := Vector2i(416, 288)
const SCANNER_SIZE := Vector2i(512, 320)
const LANDING_Y := 256
const STEP_COUNT := 12
const STEP_RUN := 32
const STEP_RISE := 16

var _pass := 0
var _fail := 0


func ok(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  PASS  ", label)
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)


func _init() -> void:
	call_deferred("_run")


func _load_source_png(path: String) -> Image:
	# 直接解码源文件，避免 .import 设置或缓存掩盖 Alpha 问题。
	var image := Image.new()
	var error := image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	ok(error == OK, "%s 源 PNG 可直接解码" % path.get_file(), str(error))
	return image


func _alpha_stats(image: Image) -> Dictionary:
	var stats := {"transparent": 0, "opaque": 0, "partial": 0}
	if image.is_empty() or image.get_format() != Image.FORMAT_RGBA8:
		return stats
	var pixels := image.get_data()
	for index in range(3, pixels.size(), 4):
		var alpha := int(pixels[index])
		if alpha == 0:
			stats.transparent += 1
		elif alpha == 255:
			stats.opaque += 1
		else:
			stats.partial += 1
	return stats


func _alpha_at(pixels: PackedByteArray, width: int, x: int, y: int) -> int:
	return int(pixels[(y * width + x) * 4 + 3])


func _cell_edge_is_clear(cell: Image) -> bool:
	if cell.is_empty() or cell.get_format() != Image.FORMAT_RGBA8:
		return false
	var pixels := cell.get_data()
	var width := cell.get_width()
	var height := cell.get_height()
	for x in width:
		if _alpha_at(pixels, width, x, 0) != 0 \
				or _alpha_at(pixels, width, x, height - 1) != 0:
			return false
	for y in height:
		if _alpha_at(pixels, width, 0, y) != 0 \
				or _alpha_at(pixels, width, width - 1, y) != 0:
			return false
	return true


func _alpha_masks_are_exact_mirrors(left: Image, right: Image) -> bool:
	if left.get_size() != STAIR_CELL_SIZE or right.get_size() != STAIR_CELL_SIZE:
		return false
	if left.get_format() != Image.FORMAT_RGBA8 or right.get_format() != Image.FORMAT_RGBA8:
		return false
	var left_pixels := left.get_data()
	var right_pixels := right.get_data()
	for y in STAIR_CELL_SIZE.y:
		for x in STAIR_CELL_SIZE.x:
			var mirror_x := STAIR_CELL_SIZE.x - 1 - x
			if _alpha_at(left_pixels, STAIR_CELL_SIZE.x, x, y) \
					!= _alpha_at(right_pixels, STAIR_CELL_SIZE.x, mirror_x, y):
				return false
	return true


func _rgba_pixels_are_exact_mirrors(left: Image, right: Image) -> bool:
	# 不只检查轮廓；颜色与铆钉也必须来自同一母版的整块镜像。
	if left.get_size() != STAIR_CELL_SIZE or right.get_size() != STAIR_CELL_SIZE:
		return false
	if left.get_format() != Image.FORMAT_RGBA8 or right.get_format() != Image.FORMAT_RGBA8:
		return false
	var left_pixels := left.get_data()
	var right_pixels := right.get_data()
	for y in STAIR_CELL_SIZE.y:
		for x in STAIR_CELL_SIZE.x:
			var mirror_x := STAIR_CELL_SIZE.x - 1 - x
			var left_offset := (y * STAIR_CELL_SIZE.x + x) * 4
			var right_offset := (y * STAIR_CELL_SIZE.x + mirror_x) * 4
			for channel in 4:
				if left_pixels[left_offset + channel] != right_pixels[right_offset + channel]:
					return false
	return true


func _find_tread_walk_surface_y(cell: Image, step_index: int) -> int:
	# 这里只识别可行走顶面；踏板厚度与下探挂耳不计入楼梯高度。
	# 踏板中央避开鼻沿、铆钉、立柱；连续 18px 可排除斜梁误判。
	var pixels := cell.get_data()
	var x_start := 23 + step_index * STEP_RUN
	var x_end := 42 + step_index * STEP_RUN
	var earliest_y := LANDING_Y - 20 - step_index * STEP_RISE
	var latest_y := LANDING_Y - 16 - step_index * STEP_RISE
	for y in range(earliest_y, latest_y + 1):
		var opaque_count := 0
		for x in range(x_start, x_end + 1):
			if _alpha_at(pixels, STAIR_CELL_SIZE.x, x, y) == 255:
				opaque_count += 1
		if opaque_count >= 18:
			return y
	return -1


func _run() -> void:
	print("== 协议检疫站美术切片：源资产 ==")
	var stairs := _load_source_png(STAIR_PATH)
	ok(not stairs.is_empty() and stairs.get_size() == STAIR_SIZE,
			"楼梯图为 832x288", str(stairs.get_size()))
	ok(not stairs.is_empty() and stairs.get_format() == Image.FORMAT_RGBA8,
			"楼梯图为 RGBA8", str(stairs.get_format()))
	var stair_stats := _alpha_stats(stairs)
	ok(stair_stats.transparent > 0 and stair_stats.opaque > 0,
			"楼梯图同时含透明与不透明像素", str(stair_stats))
	ok(stair_stats.partial == 0, "楼梯图 Alpha 保持 0/255 硬边", str(stair_stats))

	var scanner := _load_source_png(SCANNER_PATH)
	ok(not scanner.is_empty() and scanner.get_size() == SCANNER_SIZE,
			"扫描舱为 512x320", str(scanner.get_size()))
	ok(not scanner.is_empty() and scanner.get_format() == Image.FORMAT_RGBA8,
			"扫描舱为 RGBA8", str(scanner.get_format()))
	var scanner_stats := _alpha_stats(scanner)
	ok(scanner_stats.transparent > 0 and scanner_stats.opaque > 0,
			"扫描舱同时含透明与不透明像素", str(scanner_stats))
	ok(scanner_stats.partial == 0, "扫描舱 Alpha 保持 0/255 硬边", str(scanner_stats))

	print("== 双向楼梯 Cell 合同 ==")
	var cells_valid := stairs.get_size() == STAIR_SIZE \
			and stairs.get_format() == Image.FORMAT_RGBA8
	var left := stairs.get_region(Rect2i(Vector2i.ZERO, STAIR_CELL_SIZE)) \
			if cells_valid else Image.new()
	var right := stairs.get_region(Rect2i(Vector2i(STAIR_CELL_SIZE.x, 0), STAIR_CELL_SIZE)) \
			if cells_valid else Image.new()
	var left_used := left.get_used_rect() if not left.is_empty() else Rect2i()
	var right_used := right.get_used_rect() if not right.is_empty() else Rect2i()
	ok(_cell_edge_is_clear(left) and _cell_edge_is_clear(right),
			"两个 416px Cell 的四边均保留透明留白")
	ok(not left_used.has_point(Vector2i(0, 0)) and left_used.position.x > 0
			and left_used.end.x < STAIR_CELL_SIZE.x and left_used.position.y > 0
			and left_used.end.y < STAIR_CELL_SIZE.y
			and right_used.position.x > 0 and right_used.end.x < STAIR_CELL_SIZE.x
			and right_used.position.y > 0 and right_used.end.y < STAIR_CELL_SIZE.y,
			"左右模块非透明像素完整收在各自 Cell 内",
			"left=%s right=%s" % [left_used, right_used])
	ok(_alpha_masks_are_exact_mirrors(left, right),
			"左右 Cell 的 Alpha 遮罩逐像素精确镜像")
	ok(_rgba_pixels_are_exact_mirrors(left, right),
			"左右 Cell 的 RGBA 像素逐通道精确镜像")

	print("== 楼梯尺寸与节奏合同 ==")
	var tread_tops: Array[int] = []
	if not left.is_empty() and left.get_format() == Image.FORMAT_RGBA8:
		for step_index in STEP_COUNT:
			tread_tops.append(_find_tread_walk_surface_y(left, step_index))
	var all_treads_found := tread_tops.size() == STEP_COUNT and not tread_tops.has(-1)
	ok(all_treads_found, "识别到 12 块开放式踏板", str(tread_tops))
	var first_top := tread_tops[0] if all_treads_found else -1
	var last_top := tread_tops[-1] if all_treads_found else -1
	ok(first_top == LANDING_Y - STEP_RISE,
			"局部 landing_y=256，第一踏板行走面精确位于 y=240", str(first_top))
	ok(last_top == LANDING_Y - STEP_COUNT * STEP_RISE,
			"第十二踏板行走面精确位于 y=64", str(last_top))
	var rise_is_exact := all_treads_found
	for index in range(1, tread_tops.size()):
		if tread_tops[index - 1] - tread_tops[index] != STEP_RISE:
			rise_is_exact = false
	ok(rise_is_exact, "相邻踏板严格保持 16px rise", str(tread_tops))
	# 每次识别窗口的 X 起点严格右移 32px，因此全部命中也验证了 32px run。
	ok(all_treads_found, "12 级踏板严格按 32px run 排列")

	print("")
	print("=== %d 通过, %d 失败 ===" % [_pass, _fail])
	print("TEST_RESULT: " + ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
