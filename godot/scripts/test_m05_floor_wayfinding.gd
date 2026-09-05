extends SceneTree
## 楼层标识只从第三关数据推导，不能变成另一套手填坐标或每帧重建节点。
const LABELS := preload("res://scripts/m05_floor_wayfinding.gd")
const DATA := preload("res://generated/m05_vertical_freight_data.gd")
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	passed += int(value)
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)


func _run() -> void:
	var labels := LABELS.new()
	root.add_child(labels)
	check(labels.sign_count == DATA.ROOM_FLOORS.size() and labels.sign_count == 6, "六层ROOM_FLOORS生成六个导向标")
	check(not labels.is_processing(), "静态路牌不执行每帧脚本")
	var codes: Array[String] = []
	for sign: Dictionary in labels.signs:
		codes.append(sign["code"])
		var matched := false
		for room: Dictionary in DATA.ROOMS:
			if room["room_id"] != sign["room_id"]:
				continue
			var rr: Array = room["rect"]
			var rect := Rect2(float(rr[0]) * 32, float(rr[1]) * 32, float(rr[2]) * 32, float(rr[3]) * 32)
			matched = room["role"] == "connector" and rect.has_point(sign["pos"])
		check(matched, String(sign["code"]) + "在其真实中央桥墙面内")
	check(codes == ["B3", "B2", "B1", "F1", "F2", "F3"], "楼层命名从井底到塔冠一致")
	labels.free()
	await process_frame
	print("M05_WAYFINDING_RESULT: %d PASS / %d FAIL" % [passed, failed])
	quit(int(failed > 0))
