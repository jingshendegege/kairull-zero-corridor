extends Node2D
## 仅第三关使用的静态楼层导向；位置来自ROOM_FLOORS+房间元数据，不另手摆一份地图。
## 只有短色条和文字，无大黑框、无每帧脚本、无额外碰撞。

const DATA := preload("res://generated/m05_vertical_freight_data.gd")
const CODES := ["B3", "B2", "B1", "F1", "F2", "F3"]
const NAMES := ["井底", "配重", "检修", "中枢", "上联", "塔冠"]
const COLORS := [QuarantineArchitecture.AMBER, QuarantineArchitecture.CYAN,
	QuarantineArchitecture.EDGE, QuarantineArchitecture.CYAN,
	QuarantineArchitecture.AMBER, QuarantineArchitecture.MAGENTA]
var signs: Array[Dictionary] = []
var sign_count := 0
var _font: SystemFont


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Segoe UI"])
	_font.fallbacks = [preload("res://NotoSansCJKsc-Regular.otf")]
	for index in DATA.ROOM_FLOORS.size():
		var floor: int = int(DATA.ROOM_FLOORS[index]["center_floor"])
		for room: Dictionary in DATA.ROOMS:
			var rect: Array = room["rect"]
			if room["role"] != "connector" or int(rect[1]) + int(rect[3]) - 1 != floor:
				continue
			var hint := "↑ 返回中枢" if floor == 105 else "↓ 返回下层" if floor == 15 \
				else "↑ 塔冠  /  ↓ 井底" if floor == 51 else "↑ 上层  /  ↓ 下层"
			signs.append({"code": CODES[index], "name": NAMES[index], "floor": floor,
				"room_id": room["room_id"], "color": COLORS[index], "hint": hint,
				"pos": Vector2(float(rect[0]) * 32.0 + 28.0, (float(rect[1]) + 1.0) * 32.0 + 40.0)})
			break
	sign_count = signs.size()
	set_process(false)
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	for sign: Dictionary in signs:
		var at: Vector2 = sign["pos"]
		var tint: Color = sign["color"]
		var title := String(sign["code"]) + "  " + String(sign["name"])
		# 文字宽度实际测量，色条只跟随标题而不扩成覆盖整面墙的大框。
		var text_w := ceilf(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x)
		draw_string(_font, at + Vector2(1, 1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			QuarantineArchitecture.VOID)
		draw_string(_font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, tint)
		draw_line(at + Vector2(0, 6), at + Vector2(text_w, 6), Color(tint, .72), 2.0)
		draw_string(_font, at + Vector2(0, 23), sign["hint"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(tint, .76))
