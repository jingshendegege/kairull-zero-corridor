extends RefCounted
class_name AtlasDB
## 图集数据库：读取 atlas_grid.json（网格版）与 aim_lut.json。
## 不碰节点，可无头单测。
##
## 帧取址：网页原型是单行条带（frame*fw 横移）；Godot 版因 16384px 纹理
## 上限重排成网格（见 playground/tools/repack_atlas_grid.py），
## 帧号 f 的位置 = (f % cols, f / cols)。

var actions: Dictionary = {}        ## 动作名 -> {file, frames, fw, fh, foot_y, body_cx, cols, rows}
var fps: float = 24.0
var lut_entries: Array = []         ## [{ang, f, muzzle:Vector2, grip:Vector2}]
var angle_min := 0.0
var angle_max := 0.0

var _tex_cache: Dictionary = {}     ## 动作名 -> Texture2D


func _init(base_dir: String = "res://assets/clips", extra_atlas: Variant = "") -> void:
	var at: Variant = JSON.parse_string(FileAccess.get_file_as_string(base_dir + "/atlas_grid.json"))
	assert(at is Dictionary, "atlas_grid.json 解析失败")
	fps = float(at.get("fps", 24))
	for k in at["actions"]:
		actions[k] = at["actions"][k]

	# 追加图集（如棒球棍 bat_atlas.json / 新人物 hero_atlas.json）：
	# 键空间合并，file 相对 base_dir；支持单个路径或路径数组。
	var extras: Array = []
	if extra_atlas is String and extra_atlas != "":
		extras.append(extra_atlas)
	elif extra_atlas is Array:
		extras = extra_atlas
	for path in extras:
		var bt: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert(bt is Dictionary, "追加图集解析失败: " + str(path))
		for k in bt["actions"]:
			actions[k] = bt["actions"][k]

	var lu: Variant = JSON.parse_string(FileAccess.get_file_as_string(base_dir + "/aim_lut.json"))
	assert(lu is Dictionary, "aim_lut.json 解析失败")
	angle_min = float(lu["angle_min"])
	angle_max = float(lu["angle_max"])
	for e in lu["entries"]:
		lut_entries.append({
			"ang": float(e["ang"]),
			"f": int(e["f"]),
			"muzzle": Vector2(e["muzzle"][0], e["muzzle"][1]),
			"grip": Vector2(e["grip"][0], e["grip"][1]),
		})


## 瞄准角 → LUT 条目索引（最近邻，二分查找；与网页版 lutIndexFor 同算法）
func lut_index(deg: float) -> int:
	var d := clampf(deg, angle_min, angle_max)
	var lo := 0
	var hi := lut_entries.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) >> 1
		if float(lut_entries[m]["ang"]) <= d:
			lo = m
		else:
			hi = m
	var e_lo: float = lut_entries[lo]["ang"]
	var e_hi: float = lut_entries[hi]["ang"]
	return lo if absf(e_lo - d) <= absf(e_hi - d) else hi


func action(name: String) -> Dictionary:
	return actions[name]


func texture_for(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load("res://assets/clips/" + str(actions[name]["file"]))
	return _tex_cache[name]


## 帧号 → 网格图集中的源矩形
func frame_rect(name: String, frame: int) -> Rect2:
	var a: Dictionary = actions[name]
	var fw: float = a["fw"]
	var fh: float = a["fh"]
	var cols: int = a["cols"]
	var f: int = clampi(frame, 0, int(a["frames"]) - 1)
	return Rect2((f % cols) * fw, (f / cols) * fh, fw, fh)
