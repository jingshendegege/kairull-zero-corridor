extends SceneTree
## 语义查询缓存合同：完整房间边界、重复profile、空结果、setup失效及三关源数据逐项一致。
const ART := preload("res://scripts/quarantine_architecture.gd")
const DATASETS := [preload("res://generated/m01_protocol_quarantine_data.gd"),
	preload("res://generated/m04_chrono_freight_data.gd"), preload("res://generated/m05_vertical_freight_data.gd")]
var passed := 0
var failed := 0
var datasets_completed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, label: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", label)


func _run() -> void:
	var level := CorridorLevel.new()
	level.rooms = [{"rect": Rect2i(0, 0, 12, 12), "decor_profile": "service_bay"},
		{"rect": Rect2i(20, 0, 12, 12), "decor_profile": "service_bay"}]
	var source := {"Architecture": [[2, 2, 7], [3, 2, 7], [22, 5, 7], [23, 5, 7]],
		"BackdropTiles": [[0, 0, 1], [1, 0, 1], [3, 0, 1], [3, 1, 1], [4, 1, 2]],
		"Other": [[1, 8, 7]], "ForegroundTiles": [[0, 0, 1], [1, 0, 1]]}
	var ids := {"Architecture": {"ServiceBench": 7}, "BackdropTiles": {"WallShell": 1}}
	var art := ART.new()
	art.setup(level, source, ids)
	check(art._value_bounds("Architecture", 7) == Rect2i(2, 2, 22, 4), "全层同value范围不被视口裁短")
	var first: Rect2i = art._value_bounds_in_rect("Architecture", 7, level.rooms[0].rect)
	var second: Rect2i = art._value_bounds_in_rect("Architecture", 7, level.rooms[1].rect)
	check(first == Rect2i(2, 2, 2, 1), "重复profile首房仅保留首房设备")
	check(second == Rect2i(22, 5, 2, 1), "重复profile远房不串用首房bounds")
	check(art._value_bounds("Other", 7) == Rect2i(1, 8, 1, 1), "同数字value跨语义层有独立缓存键")
	var runs: Array = art._horizontal_runs("BackdropTiles")
	check(runs.size() == 4, "水平runs保留断格/换行/换value三种分段")
	check(runs[0] == {"rect": Rect2i(0, 0, 2, 1), "value": 1}, "连续同值两格仍合成一条")
	check(is_same(runs, art._horizontal_runs("BackdropTiles")), "重复runs查询复用同一数组，不每帧重建Dictionary")
	art._value_bounds("Architecture", 999)
	art._value_bounds_in_rect("Architecture", 999, level.rooms[0].rect)
	art._horizontal_runs("Missing")
	var counts_before: Dictionary = art._cache_build_counts.duplicate(true)
	for _index in 200:
		art._process(1.0 / 60.0)
		art._value_bounds("Architecture", 7)
		art._value_bounds("Architecture", 999)
		art._value_bounds_in_rect("Architecture", 7, level.rooms[0].rect)
		art._value_bounds_in_rect("Architecture", 7, level.rooms[1].rect)
		art._value_bounds_in_rect("Architecture", 999, level.rooms[0].rect)
		art._horizontal_runs("BackdropTiles")
		art._horizontal_runs("Missing")
	check(art._cache_build_counts == counts_before, "200帧灯屏相位变化不触发任何已缓存层扫描")
	check(art._value_bounds("Architecture", 999) == Rect2i() \
		and art._value_bounds_in_rect("Architecture", 999, level.rooms[0].rect) == Rect2i(), "空bounds也稳定缓存")
	source["Architecture"][0][0] = 999
	check(art.semantic_layers["Architecture"][0][0] == 2, "setup深复制隔离外部源数组修改")
	var replacement := {"Architecture": [[5, 4, 7]], "BackdropTiles": [[7, 2, 2]], "ForegroundTiles": [[9, 9, 1]]}
	art.setup(level, replacement, ids, true)
	check(art.front_only and not art.is_processing(), "前景仍保持非逐帧process的原合同")
	check(art._horizontal_runs_cache.is_empty(), "同实例新setup清掉旧runs，包括空层")
	check(art._value_bounds("Architecture", 7) == Rect2i(5, 4, 1, 1), "新setup全层bounds不返回上轮值")
	check(art._value_bounds_in_rect("Architecture", 7, level.rooms[1].rect) == Rect2i(), "新setup重复profile旧房设备不会残留")
	check(art._horizontal_runs("BackdropTiles") == [{"rect": Rect2i(7, 2, 1, 1), "value": 2}], "新setup重新构建正确runs")
	check(runs.size() == 4, "清缓存不突变外部已取得的旧查询数组")
	art.free()
	level.free()
	for index in DATASETS.size():
		_test_dataset(DATASETS[index], ["M01", "M04", "M05"][index])
	check(datasets_completed == DATASETS.size(), "三关逐项审计全部执行到末尾，不能以提前中断冒充PASS")
	await process_frame
	print("SEMANTIC_CACHE_RESULT: %d PASS, %d FAIL" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _reference_bounds(triples: Array, value: int, clip := Rect2i()) -> Rect2i:
	var minimum := Vector2i(1 << 20, 1 << 20)
	var maximum := Vector2i(-1, -1)
	for raw in triples:
		var cell := Vector2i(raw[0], raw[1])
		if int(raw[2]) != value or (clip.has_area() and not clip.has_point(cell)):
			continue
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	return Rect2i() if maximum.x < 0 else Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _test_dataset(data: Script, label: String) -> void:
	var level := CorridorLevel.new()
	# 实际生成源全量数组，只比较查询输出；不触地图静态active_*或写入生成文件。
	level.rooms = data.ROOMS.duplicate(true)
	for room: Dictionary in level.rooms:
		var raw: Array = room.rect
		room.rect = Rect2i(raw[0], raw[1], raw[2], raw[3])
	var art := ART.new()
	art.setup(level, data.SEMANTIC_LAYERS, data.SEMANTIC_IDS)
	var all_bounds_equal := true
	var all_scoped_equal := true
	var all_runs_equal := true
	for layer_name: String in data.SEMANTIC_LAYERS:
		var triples: Array = data.SEMANTIC_LAYERS[layer_name]
		var values: Dictionary = {}
		for raw in triples:
			values[int(raw[2])] = true
		for value: int in values:
			all_bounds_equal = all_bounds_equal and art._value_bounds(layer_name, value) == _reference_bounds(triples, value)
			for room: Dictionary in level.rooms:
				all_scoped_equal = all_scoped_equal and art._value_bounds_in_rect(layer_name, value, room.rect) \
					== _reference_bounds(triples, value, room.rect)
		var rebuilt: Array = []
		for run: Dictionary in art._horizontal_runs(layer_name):
			var rect: Rect2i = run.rect
			for x in range(rect.position.x, rect.end.x):
				rebuilt.append([x, rect.position.y, run.value])
		all_runs_equal = all_runs_equal and rebuilt == triples
	check(all_bounds_equal, label + "全部语义value缓存bounds与原始扫描一致")
	check(all_scoped_equal, label + "全部房间×全部value不串bounds")
	check(all_runs_equal, label + "runs逐格还原与生成源完全一致，无删可见细节")
	var cache_counts: Dictionary = art._cache_build_counts.duplicate(true)
	for _index in 10:
		for layer_name: String in data.SEMANTIC_LAYERS:
			art._horizontal_runs(layer_name)
	check(art._cache_build_counts == cache_counts, label + "重复runs无额外构造")
	art.free()
	level.free()
	datasets_completed += 1
