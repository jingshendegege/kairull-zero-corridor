extends RefCounted
class_name KZPalette
## M02 数据塔共享调色板：tiles / 背景 / 门 / HUD 全部从这里取色。
##
## 明度阶梯铁律（对照武士零实拍）：
##   背景层 < 玩法层（可走几何）< 交互信号（门/血/霓虹）
## 即任何背景用色的感知亮度必须明显低于玩法层的墙体/地板，
## 玩法层的亮顶沿又必须让位于最高饱和的交互色。
## 测试 test_m02_tower.gd 有亮度断言守住这条阶梯。
##
## 三段式地板板结构（每块可走楼板）：
##   FLOOR_TOP 亮顶沿 2-3px → FLOOR_SIDE 中段侧板（材质细节）→ FLOOR_BOTTOM 暗底线

## ---- 背景层（最暗、最低饱和）----
const BG_BASE := Color("#16101f")        ## 深紫黑底（渐变兜底同色）
const BG_PANEL := Color("#171021")       ## 背景墙面板（CFG_TOWER_DIM 平铺色）
const BG_WALL := Color("#1d1529")        ## 背景砖墙（比 BG_PANEL 略冷）

## ---- 玩法层（可走几何，中等明度）----
const WALL_PANEL := Color("#241a33")     ## 室内墙板（| 与 # 侧壁基调）
const FLOOR_SIDE := Color("#2e2340")     ## 楼板侧立面
const FLOOR_SIDE_DARK := Color("#251b35")## 楼板侧立面暗缝
const FLOOR_TOP := Color("#e8a0e0")      ## 楼板亮顶沿（薰衣草粉，squint-test 主信号）
const FLOOR_TOP_DIM := Color("#a86fa8")  ## 顶沿第二排（厚度感）
const FLOOR_BOTTOM := Color("#120c1c")   ## 楼板底部阴影线
const GRATE_BODY := Color("#241c33")     ## 单向平台格栅体
const GRATE_EDGE := Color("#7ec8ff")     ## 单向平台青色亮顶沿
const RAIL := Color("#3a2f52")           ## 栏杆细金属
const PIPE := Color("#33284a")           ## 管道体
const PIPE_HI := Color("#564673")        ## 管道高光

## ---- 交互信号（最高饱和，只给门/血/霓虹/出口）----
const NEON_MAGENTA := Color("#ff4fa3")
const NEON_CYAN := Color("#7ec8ff")
const AMBER := Color("#ffd166")
const BLOOD := Color("#c22338")
const DOOR_LOCKED := Color("#ff3b4e")    ## 锁定门红边光（dim 使用，不铺满）

## ---- 窗（玩法层与背景层之间的过渡：暗框 + 极暗城市灯点）----
const WINDOW_FRAME := Color("#221736")
const WINDOW_GLASS := Color("#141026")
const WINDOW_CITY_A := Color("#8a66b0")  ## 城市灯点（压暗的紫）
const WINDOW_CITY_B := Color("#5480aa")  ## 城市灯点（压暗的青）
const WINDOW_AMBER := Color("#c98f3d")   ## 楼里亮灯的窗（压暗的琥珀）

## ---- 室内墙面 backdrop（背景层，task B；明度全部 < WALL_PANEL）----
## 三段式楼层色带：F1 冷蓝紫 / F2 服务器绿调 / F3 红色警戒调——全部重去饱和。
const BACKDROP_BASE := Color("#191223")      ## 房间墙底（通用）
const BACKDROP_F1 := Color("#1b1630")        ## F1 大堂/事务所/楼梯间A：冷蓝紫
const BACKDROP_F2 := Color("#161d19")        ## F2 休息室/服务器厅/楼梯间B：暗绿调
const BACKDROP_F3 := Color("#21161a")        ## F3 核心前厅/塔心：暗红调
const BACKDROP_SEAM := Color("#100a1a")      ## 墙板接缝（比底色更暗）
const BACKDROP_PILASTER := Color("#1e182e")  ## 竖向壁柱（比底色略亮一档）
const BACKDROP_BASEBOARD := Color("#201828") ## 踢脚线带（楼板顶沿下沿的墙裙）
const BACKDROP_HI := Color("#201a30")        ## 板缝右侧 1px 受光边（仍 < WALL_PANEL）

## 楼层色带点缀条（背景层内的低明度信号，< WALL_PANEL；不作交互语义）
const BAND_F1 := Color("#1c1a32")            ## F1 冷蓝腰线
const BAND_F2 := Color("#16241d")            ## F2 服务器绿腰线
const BAND_F3 := Color("#2a161d")            ## F3 红色警戒腰线

## ---- 房间装饰剪影（背景层；LED/警示纹/橱窗是小面积信号点缀，不参与明度阶梯断言）----
const DECOR_BODY := Color("#0f0a19")         ## 家具/机柜剪影体（近黑，剪影读法）
const DECOR_FACE := Color("#181126")         ## 剪影受光面
const DECOR_EDGE := Color("#221a2d")         ## 剪影顶沿/轮廓线（< WALL_PANEL）
const LED_GREEN := Color("#3fae62")          ## 服务器 LED 绿（小点信号）
const LED_RED := Color("#c24040")            ## 服务器 LED 红（小点信号）
const VEND_GLOW := Color("#2a5a66")          ## 售货机橱窗暗青辉光（小面信号，低 alpha 使用）
const WARN_STRIPE := Color("#4a3a1c")        ## 警示纹琥珀（小面信号色，压暗的琥珀）
const WARN_DARK := Color("#161020")          ## 警示纹暗格
