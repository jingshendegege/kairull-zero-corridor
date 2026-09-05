extends Node2D
class_name GameBackground
## M01 四层视差背景：武士零风格管线产物（像素化版，贴合角色画风）。
## 自绘视差：每帧 position 对齐相机左上角，_draw 局部坐标 = 屏幕坐标。
## 横向按 factor 偏移平铺（L0 无缝循环，L1/L2/L3 镜像平铺消重复感）；
## 纵向各层有固定基准：L2 走道带与世界地面顶（row 19）对齐，L1 楼带压在天际线下。
## 素材：assets/bg/m01/*_px.png（源图 1536×1024，3px 像素块，元数据见 deliverables/maps/M01）。

const SCALE := 0.75            ## 1152×768 贴住 1360×765 视野
const GROUND_WY := 608.0       ## 世界地面顶 = row 19 × 32
const L2_WALKWAY_SY := 697.0   ## L2 走道带在源图中的 Y（M01_meta.json）

## base：屏幕基准 Y（相机 tl.y=0 时）；factor：视差系数；mirror：镜像平铺
## L2 设施后墙：走道带顶缘在源图 y≈800；L3 工业前景：警戒线顶缘在源图 y≈455，
## 两者都与世界地面顶（608）对齐。塔内场景不使用街景 L0/L1。
const CFG := [
	{"file": "res://assets/bg/m01/M01_L2_facility_px.png", "factor": 1.0, "mirror": true,
		"base": GROUND_WY - 800.0 * SCALE},
	{"file": "res://assets/bg/m01/M01_L3_industrial_px.png", "factor": 1.3, "mirror": true,
		"base": GROUND_WY - 455.0 * SCALE},
]

## 空洞武士（HollowKatana）移植仓库地图：原生像素画不缩像素块，
## 走道带顶缘在源图 y=615（程序实测），与世界地面顶对齐。镜像平铺消重复感。
const CFG_HK_STREET := [
	{"file": "res://assets/bg/m02_hk/HK_street.png", "factor": 1.0, "mirror": true,
		"base": GROUND_WY - 615.0 * SCALE},
]

## M01 旧城区霓虹街：4 层视差（元数据 deliverables/maps/M01/M01_meta.json）。
##   L0 天空远城区 0.15 不透明无缝横铺，底边锚世界地面（远楼从地平线升起）
##   L1 中景霓虹楼面 0.45 alpha，按 meta 建议再下移 120px（Godot 屏幕坐标）
##   L2 街面立面+走道 1.0 不透明，走道带（源图 y=697）对齐世界地面顶 608
##      —— 楼体顶天立地，walkway 锚定本身就是"向下偏移"，天空带在顶部露出
##   L3 前景电线/霓虹残段 1.3 alpha（覆盖 ~14%），由 front_only 实例画在角色之上；
##      底部栏杆霓虹顶沿（源图 y≈867）对齐到腰际（地面顶上方 38px），栏杆柱遮挡脚踝
## 绘制约定：后景实例画除末层外的所有层，前景实例（front_only）只画末层。
const CFG_M01_NEON := [
	{"file": "res://assets/bg/m01/M01_L0_sky_px.png", "factor": 0.15, "mirror": false,
		"base": GROUND_WY - 1024.0 * SCALE},
	{"file": "res://assets/bg/m01/M01_L1_mid_px.png", "factor": 0.45, "mirror": true,
		"base": GROUND_WY - 1024.0 * SCALE + 120.0},
	{"file": "res://assets/bg/m01/M01_L2_main_px.png", "factor": 1.0, "mirror": true,
		"base": GROUND_WY - L2_WALKWAY_SY * SCALE},
	{"file": "res://assets/bg/m01/M01_L3_front_px.png", "factor": 1.3, "mirror": true,
		"base": GROUND_WY - 867.0 * SCALE - 38.0},
]

## M02 数据塔（task A 临时背景）：单块极暗平铺色，叠在深紫渐变兜底之上。
## 真正的室内墙面 backdrop 留给 task B；此层只保证不露白、明度压过渐变。
## 取色对齐 KZPalette.BG_PANEL，{"color": ...} 层直接整屏平涂（无视差）。
const CFG_TOWER_DIM := [
	{"color": "#171021"},
]

## 正式第一关剖面底色：可玩房间由 QuarantineArchitecture 单独绘制，
## 房间外、楼板实体内部和不可达空间保持近黑，不用紫色渐变填满视野。
const CFG_QUARANTINE := [
	{"color": "#05070b"},
]

## 场景实例化前可整体换配置（渲染测试/后续关卡用），为空用默认 CFG。
static var active_cfg: Array = []

var host: Node2D   ## game，读 cam_tl
var front_only := false   ## true 时只画 L3（作为前景遮挡层，由 game 放在角色之上）
var _grad: GradientTexture2D
var _tex: Array = []


func _ready() -> void:
	# 深色兜底渐变：任何一层加载失败也不会露白
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([
		Color("#1A0B2E"), Color("#241343"), Color("#12081f")])
	_grad = GradientTexture2D.new()
	_grad.gradient = g
	_grad.fill_from = Vector2(0, 0)
	_grad.fill_to = Vector2(0, 1)
	_grad.width = 16
	_grad.height = 256
	var cfg_set: Array = active_cfg if not active_cfg.is_empty() else CFG
	for cfg in cfg_set:
		var file: String = cfg.get("file", "")
		_tex.append(load(file) if not file.is_empty() and ResourceLoader.exists(file) else null)


func _process(_dt: float) -> void:
	if host != null:
		position = host.cam_tl
	queue_redraw()


func _draw() -> void:
	if host == null:
		return
	var view := get_viewport_rect().size
	if not front_only:
		draw_texture_rect(_grad, Rect2(Vector2.ZERO, view), false)
	var tl: Vector2 = host.cam_tl
	var cfg_set: Array = active_cfg if not active_cfg.is_empty() else CFG
	for i in cfg_set.size():
		# 后景实例画除末层外的层，前景实例只画末层（若仅单层则只由后景实例绘制）
		if cfg_set.size() > 1 and front_only != (i == cfg_set.size() - 1):
			continue
		if cfg_set.size() == 1 and front_only:
			continue
		var cfg: Dictionary = cfg_set[i]
		# 平涂色层（M02 临时背景用）：整屏压一块极暗色，无贴图无视差
		if cfg.has("color"):
			if not front_only:
				draw_rect(Rect2(Vector2.ZERO, view), Color(cfg["color"]))
			continue
		var t: Texture2D = _tex[i]
		if t == null:
			continue
		var tw: float = t.get_width() * SCALE
		var y0: float = float(cfg["base"]) - tl.y * float(cfg["factor"])
		var scroll: float = tl.x * float(cfg["factor"])
		var first := floori(scroll / tw) - 1
		var last := first + ceili(view.x / tw) + 3
		for k in range(first, last):
			var x: float = k * tw - scroll
			var flip: bool = cfg["mirror"] and absi(k) % 2 == 1
			if flip:
				draw_set_transform(Vector2(x + tw, y0), 0.0, Vector2(-SCALE, SCALE))
			else:
				draw_set_transform(Vector2(x, y0), 0.0, Vector2(SCALE, SCALE))
			draw_texture(t, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
