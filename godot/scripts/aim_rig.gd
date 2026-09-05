extends RefCounted
class_name AimRig

## 七档吸附瞄准的纯数学部分（不碰节点，可无头单测）。
##
## 方案（用户决策 2026-08-31）：**只用姿势图里的静态枪**。
##   身体+枪一体 —— 七档姿势贴图，按**实测角**做最近吸附
##   不再叠加独立枪械层做连续旋转
##
## 为什么放弃连续旋转的独立枪：
##   连续枪械角 + 离散身体档 = 固有矛盾。姿势图自带一把画死的枪，
##   叠上独立枪必然出现两把枪。实测重合度：角度正好落在档位实测值上时完美贴合，
##   落在两档之间就张开，最大残差约等于相邻档距的一半（实测最差 7~8°，
##   按 128.64px 力臂换算枪口分离约 30px，肉眼可见）。
##   收紧限位和向档位收拢都只能减小误差，无法消除。
##   彻底解决需要"无枪身体层"素材，用户选择不重画，改为纯七档。
##
## 为什么必须用实测角而不是名义角：
##   gpt-image-2 画的七档，名义 -70°~+70°，实测只有 -25.1°~+52.3°。
##   down45(-24.1°) 和 down70(-25.1°) 只差 1.0°，视觉上几乎同一个姿势。
##   按名义角吸附会导致鼠标往下摆时身体档位乱跳。
##
## 为什么弹道起点要查表而不是算：
##   旧网页原型用 hero.anchorX + 155*cos(角度) 凭空推算枪口，
##   假设"枪口在肩点外 155px 且落在瞄准射线上"。七张图手臂长度、握枪高度、
##   枪身倾角各不相同，真实枪口不在那条射线上 —— 这是"枪手脱节"的直接原因。
##   现在每档的 pivot/muzzle 都由连通域主轴法实测标定，直接查表。

## 七档实测数据。来自 data/aim_poses_calibrated_v2.json，
## 连通域主轴法标定，坐标为各自 360x460 画布内像素。
##   angle  —— 实测枪身角（度，正为向上），吸附判据
##   pivot  —— 握把枢轴，用于各档对齐绘制（消除切档跳动）
##   muzzle —— 枪口，弹道起点 / 枪口火光挂点
const POSES := {
	"up70":    {"angle": 52.3,  "pivot": Vector2(196.5, 199.3), "muzzle": Vector2(315.7, 45.4)},
	"up45":    {"angle": 38.0,  "pivot": Vector2(159.7, 241.3), "muzzle": Vector2(316.0, 119.4)},
	"up20":    {"angle": 12.9,  "pivot": Vector2(119.6, 240.3), "muzzle": Vector2(314.6, 195.6)},
	"forward": {"angle": -0.0,  "pivot": Vector2(115.2, 240.8), "muzzle": Vector2(311.6, 240.8)},
	"down20":  {"angle": -18.3, "pivot": Vector2(124.3, 240.9), "muzzle": Vector2(306.7, 301.1)},
	"down45":  {"angle": -24.1, "pivot": Vector2(115.2, 249.8), "muzzle": Vector2(292.7, 329.1)},
	"down70":  {"angle": -25.1, "pivot": Vector2(165.3, 292.0), "muzzle": Vector2(318.8, 363.7)},
}

## 姿势贴图画布尺寸（七张一致）
const POSE_CANVAS := Vector2(360, 460)

## 瞄准 / 发射角范围。由七档实测值决定，不是名义 ±70°。
## 向下封顶 -25.1° 是已知的美术缺陷（打不到正脚下的敌人），
## 用户已接受这个取舍，改素材才能突破。
const AIM_ANGLE_MIN := -25.1
const AIM_ANGLE_MAX := 52.3

var _pose_names: Array[String] = []
var _pose_angles: Array[float] = []


func _init() -> void:
	# 按角度从大到小排好，便于吸附时线性扫描
	var pairs: Array = []
	for name in POSES:
		pairs.append([name, float(POSES[name]["angle"])])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	for p in pairs:
		_pose_names.append(p[0])
		_pose_angles.append(p[1])


## 鼠标位置 → 瞄准角（度，正为向上）。
## pivot_world 是当前档 pivot 在世界坐标里的位置：角度必须从 pivot 起算，
## 不能从画布中心或拍脑袋的 anchor 起算，否则枪口指向和鼠标错开。
func aim_angle_deg(pivot_world: Vector2, mouse_world: Vector2, facing_right: bool) -> float:
	var d := mouse_world - pivot_world
	if not facing_right:
		d.x = -d.x          # 左向时把方向折回右向坐标系，最后由 flip_h 呈现
	# Godot 屏幕 y 轴向下，取负转成"向上为正"的数学角
	return rad_to_deg(atan2(-d.y, d.x))


## 身体层选档：按实测角找最接近的一档。
## 返回 {name, angle, index, pivot, muzzle}
func pick_body_pose(aim_deg: float) -> Dictionary:
	var target := clampf(aim_deg, AIM_ANGLE_MIN, AIM_ANGLE_MAX)
	var best_i := 0
	var best_err := INF
	for i in _pose_angles.size():
		var err: float = absf(_pose_angles[i] - target)
		if err < best_err:
			best_err = err
			best_i = i
	var name: String = _pose_names[best_i]
	var data: Dictionary = POSES[name]
	return {
		"name": name,
		"angle": data["angle"],
		"index": best_i,
		"pivot": data["pivot"],
		"muzzle": data["muzzle"],
	}


## 实际的发射角 = 所选档位的实测角。
## 纯七档方案下枪不再连续旋转，所以射击方向就是档位角，不是鼠标原始角。
## 这保证了弹道方向与画面上那把静态枪的指向严格一致。
func fire_angle_deg(aim_deg: float) -> float:
	return float(pick_body_pose(aim_deg)["angle"])


## 枪口在世界坐标的位置（查表，不做旋转变换）。
## pivot_world 是当前档 pivot 对齐到的世界坐标；
## muzzle 与 pivot 同在一张贴图内，两者差值就是贴图内的固定偏移。
func muzzle_world(pivot_world: Vector2, pose_name: String, scale: float,
		facing_right: bool) -> Vector2:
	var data: Dictionary = POSES[pose_name]
	var local: Vector2 = data["muzzle"] - data["pivot"]   # 贴图内偏移（y 向下）
	if not facing_right:
		local.x = -local.x
	return pivot_world + local * scale


## 某档 pivot→muzzle 的极坐标，供调试显示 / 校验用。
## 注意 angle_deg 是"握把到枪口的连线倾角"，与该档的 measured_angle 略有差异，
## 因为 pivot 在握把（偏下）、muzzle 在枪管末端。
func muzzle_offset_polar(pose_name: String) -> Dictionary:
	var data: Dictionary = POSES[pose_name]
	var d: Vector2 = data["muzzle"] - data["pivot"]
	return {
		"length": d.length(),
		"angle_deg": rad_to_deg(atan2(-d.y, d.x)),
	}


## Sprite2D 的 offset：把该档的 pivot 挪到节点原点。
## 七张图 alpha_bbox 的 top 从 35 到 125 相差 90px，
## 不按 pivot 对齐就会在切档时整体上下跳动。
static func pose_offset(pose_name: String, facing_right: bool) -> Vector2:
	var pv: Vector2 = POSES[pose_name]["pivot"]
	if facing_right:
		return POSE_CANVAS * 0.5 - pv
	# 翻面时 x 分量镜像，否则 pivot 会偏
	return Vector2(pv.x - POSE_CANVAS.x * 0.5, POSE_CANVAS.y * 0.5 - pv.y)


## 像素画取整：把世界坐标吸到整像素，避免亚像素抖动。
## Godot 的 Point Filter 只解决采样插值，位置仍是浮点。
static func snap_px(v: Vector2, pixel_scale: float) -> Vector2:
	if pixel_scale <= 0.0:
		return v
	return Vector2(
		round(v.x / pixel_scale) * pixel_scale,
		round(v.y / pixel_scale) * pixel_scale
	)


## 身体档位之间的实测间距，用来说明"向下三档基本重合"这个美术缺陷。
func pose_gaps() -> Array[float]:
	var gaps: Array[float] = []
	for i in _pose_angles.size() - 1:
		gaps.append(_pose_angles[i] - _pose_angles[i + 1])
	return gaps


func pose_names() -> Array[String]:
	return _pose_names.duplicate()


func pose_angles() -> Array[float]:
	return _pose_angles.duplicate()
