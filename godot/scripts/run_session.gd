extends RefCounted
## 一轮录像挑战的内存设置。只由菜单开局启用，不污染直接运行的旧关卡/旧测试。

static var difficulty := "zero" ## 新启动默认武士零1血；测试重置仍显式使用自己的easy基线。
static var timeline_enabled := false
static var attempt := 1
static var start_level := 0 ## 菜单保留旧关，新增第二关；仅选择起始场景，不是中途记录点。
const DIFFICULTIES := ["easy", "hard", "zero"]
static var checkpoint: Dictionary = {} ## 仅当前挑战的内存快照；返回菜单/新开局清空，不跨关串档。
const LEVEL_SCENES := ["res://scenes/m01_protocol_quarantine.tscn", "res://scenes/m04_chrono_freight.tscn",
		"res://scenes/m05_vertical_freight.tscn"]
const LEVEL_NAMES := ["01 协议检疫站", "02 时差货运场", "03 垂直货运井"]


static func selected_scene() -> String:
	return LEVEL_SCENES[clampi(start_level, 0, LEVEL_SCENES.size() - 1)]

static func next_scene_after(scene: String) -> String:
	# 用实际入口判下一关，不依赖菜单可能残留的选中序号；最终关和旧试作不自动跳转。
	var index := LEVEL_SCENES.find(scene)
	return LEVEL_SCENES[index + 1] if index >= 0 and index + 1 < LEVEL_SCENES.size() else ""

static func enter_next_level(scene: String) -> void:
	var index := LEVEL_SCENES.find(scene)
	if index < 0:
		return
	start_level = index
	attempt = 1
	clear_checkpoint() # 新关从入口开始，不把上一关的半程进度或补给带进来；难度保持。

static func begin_run(selected_difficulty: String) -> void:
	difficulty = normalize_difficulty(selected_difficulty)
	timeline_enabled = true
	attempt = 1
	clear_checkpoint()

static func normalize_difficulty(mode: String) -> String:
	return mode if mode in DIFFICULTIES else "easy"

static func health_for_difficulty(mode: String) -> int:
	match normalize_difficulty(mode):
		"zero": return 1
		"hard": return 3
		_: return 5

static func name_for_difficulty(mode: String) -> String:
	match normalize_difficulty(mode):
		"zero": return "武士零"
		"hard": return "困难"
		_: return "简单"

static func max_health() -> int:
	return health_for_difficulty(difficulty)

static func difficulty_label() -> String:
	return "%s · %d格生命" % [name_for_difficulty(difficulty), max_health()]

static func save_checkpoint(scene: String, state: Dictionary) -> void:
	# 深拷贝隔离失败后的场景对象；快照只保存数值/容器，不能持有旧Node或音乐资源。
	checkpoint = state.duplicate(true)
	checkpoint["scene"] = scene
	checkpoint["difficulty"] = difficulty

static func checkpoint_for(scene: String) -> Dictionary:
	if not timeline_enabled or checkpoint.get("scene", "") != scene \
			or checkpoint.get("difficulty", "") != difficulty:
		return {}
	return checkpoint.duplicate(true)

static func clear_checkpoint() -> void:
	checkpoint.clear()

static func next_attempt() -> void:
	attempt += 1

static func leave_run() -> void:
	# 返回电视菜单保留难度选择；再次开始才归零本轮次数。
	timeline_enabled = false
	clear_checkpoint()

static func reset_for_tests() -> void:
	start_level = 0
	difficulty = "easy"
	timeline_enabled = false
	attempt = 1
	clear_checkpoint()
