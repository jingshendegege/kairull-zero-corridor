# LDtk 地图

当前正式地图为三张，均从开始菜单选择；默认仍选第一关：

| 菜单 | LDtk 真源 | 构造 |
|---|---|---|
| 01 协议检疫站 | `m01_protocol_quarantine.ldtk` | 280×30，10房，20敌 |
| 02 时差货运场 | `m04_chrono_freight.ldtk` | 460×36，14房，38敌，双层路线 |
| 03 垂直货运井 | `m05_vertical_freight.ldtk` | 144×114，六层20房，52敌，四座576px货梯 |

地图编辑器统一使用 **LDtk**；Godot 负责运行时、碰撞和真窗口验收，不在 Godot
TileMap 面板里另摆一份地图。

旧 `m03_zero_freight.ldtk` 与 `m03_backroom` 仍按用户要求保留为历史试作，
不参与正式第一关，也不得用批量清理或硬重置删除。

第二/三关详细布局、迁移约束和跑图验收见 `M04-CHRONO-FREIGHT.md`、`M05-VERTICAL-FREIGHT.md`。
三关当前各启用一个独立中途检查点；位置/前置清房由LDtk的`CheckpointMetadata`声明。
下文第一关“完整流程扩展”中的两个`checkpoint_cell`保留为旧布局档案，不在正式时间循环中重复生成终端。

```powershell
# 新关也只改 LDtk / 对应生成器，不手改生成 ASCII。
python playground/tools/gen_m04_chrono_freight.py --write --check
python playground/tools/test_m04_chrono_freight.py
python playground/tools/gen_m05_vertical_freight.py --write --check
python playground/tools/test_m05_vertical_freight.py
```

## 每关唯一检查点（2026-09-06）

统一字段`CheckpointMetadata`为JSON数组，编译为`CHECKPOINTS: Array[Dictionary]`。
boot传入`CorridorLevel.active_checkpoints`；结构为`id / room_index / cell / required_clear_rooms`。
`cell=[c,r]`是脚底标记格，世界坐标为`(c*32+16,(r+1)*32-0.1)`。

| 关卡 | 位置 | 激活前提 |
|---|---|---|
| 01 协议检疫站 | 冷却沉降池出口侧，room5，`[154,27]` | rooms `[1,3,5]`全清，前10/20敌；本房清空后才安全 |
| 02 时差货运场 | 安全观察间，room8，`[278,26]` | rooms `[1,2,3,5,6,7]`全清，前22/38敌 |
| 03 垂直货运井 | 中部安全枢纽，room0，`[71,50]` | 下半三层六战斗房`[3,4,5,6,7,8]`全清，24/52敌，开局不能记录 |

迁移仅追加level元数据/schema和`nextUid`，不改变Collision、Rooms、Entities或任何美术层。
`SingleCheckpointRevision=one_checkpoint_per_level_v1`防止重复迁移覆盖后来编辑的位置；
已有合法检查点字段会被保留，未知/半迁移版本直接报错而非强制修复。

```powershell
python playground/tools/gen_m01_protocol_quarantine.py --add-single-checkpoint --write --check
python playground/tools/gen_m04_chrono_freight.py --add-single-checkpoint --write --check
python playground/tools/gen_m05_vertical_freight.py --add-single-checkpoint --write --check
python playground/tools/test_map_checkpoint_contract.py
```

日常LDtk保存仍只需普通`--write --check`。共同Python合同检查恰好一处、三格宽静态支撑、
三格高净空、无实体/梯面/货梯轨道/机关重叠；战斗房记录点必须把本房列入清场前提。
检查点不参与遭遇边界、敌人总数或地图碰撞；实际快照恢复和音乐连续由运行时专项验证。

## 正式第一关语义层

- `Collision`：`Solid` / `OneWay`，只表达网格碰撞。
- `Rooms`：10 个互不重叠的矩形房框，驱动相机与 HUD。
- `Entities`：唯一出生/出口、近战巡检员、枪手与 `BatCargo` 球棒货箱。
- `Architecture`：入口扫描器、检疫舱、冷却管组、分拣机、出口封锁、开放楼梯。
- `BackdropTiles`：墙壳、凹槽、观察玻璃、维修虚空。
- `ForegroundTiles`：近景梁、管、吊链和格栅。
- `Lights`：青/琥珀工作灯、品红警报、红色封锁灯。
- `Traversal`：主走线、跳跃落点、楼梯上升、房间过渡。

所有层均为 `32px` IntGrid。房间稳定字段、楼梯高度场等元数据保存在 LDtk
level fields 中；生成文件只由编译器产生，禁止手改。

正式竖井楼梯为十级 `32×16px` 高度场，`bottom_cell=[52,28]`、
`top_cell=[62,23]`。`Architecture.OpenStair` 与 `Traversal.StairRise` 必须逐格
匹配十级踏面；碰撞层只允许在 `c62,row23` 留一格同高上端接口，禁止重新加入
覆盖踏面的粗 OneWay 兜底平台。梯下黑暗是角色后方的视觉层，不是实心碰撞。

## 日常修改流程

```powershell
# 仅首次建档；已有文件时会拒绝覆盖
python playground/tools/gen_m01_protocol_quarantine.py --seed --write

# 在 LDtk 保存后，编译 Godot 运行时数据并精确核对
python playground/tools/gen_m01_protocol_quarantine.py --write --check
python playground/tools/test_m01_protocol_quarantine.py

# 地板/平台材质独立生成
python playground/tools/build_quarantine_tileset.py
python playground/tools/test_quarantine_tileset.py
```

输出为 `godot/generated/m01_protocol_quarantine_data.gd`；`level.gd` 直接引用该
文件的 `MAP_TEXT`，boot 同时接入房间、楼梯和美术语义，因此不会出现 LDtk、
ASCII 与运行时三份数据漂移。

同步后必须先跑 GDScript 解析，再跑地图合同、真实 Player 跑图与楼梯专项；
最后运行 `scripts/render_m01_protocol_quarantine.gd` 做 OpenGL 真窗口逐房验收。
headless 截图不能替代视觉验收。

## 球棒货运战斗切片

检疫厅已经迁移为连续地面的货运战斗线：先在 `c21,row27` 认识近战敌人，
再用 `c28,row27` 的货箱击向 `c36,row27` 的枪手；`c40,row27` 第二只货箱
对应 `c47,row27` 巡检员。货箱是 `Entities=5`，编译后为 ASCII `C`，
运行时 `kind=bat_cargo`，不能计入敌人的清场门槛（当前扩展流程共20名敌人）。

原来两组不规则实心基座已移除。`c41–47,row25` 改为单向维护步道：
普通跳跃可上行 96px，也可以直接从其下方通过；不挤占六格翻滚距离或货箱弹道。
这一版迁移当时保留了十级楼梯和其他房间；当前后段扩展见下节，前63列仍原样保留。

本次布局变更由可审计的一次性迁移生成：

```powershell
python playground/tools/gen_m01_protocol_quarantine.py --rework-combat-slice --write --check
```

迁移标记 `CombatSliceRevision=bat_cargo_lane_v1` 保存在 LDtk。重复执行只会
检查/编译，**不会重排用户后来编辑的房间**。后续仍直接在 LDtk 中编辑，再运行
普通 `--write --check`；不能删除版本标记来强制覆盖其他人的更改。

## 完整流程扩展

当前为 `280×30` 格：10 个房间、20 名敌人（11 近战＋9 枪手）、11 只可击飞货箱、
3 段十级钢梯、2 处历史安全补给字段（当前正式记录点以以上`CheckpointMetadata`为准）。从出生 `c4` 到出口 `c274` 的水平距离为 8640px，
是原短切片 `c4→c112` 的 2.5 倍；实际双层战斗路线还有返回与上下台操作，
这个数值不代表承诺的通关时长。

| 房间 | 格坐标矩形 | 玩法与路线 |
|---|---|---|
| 安全入口 | `[1,19,14,10]` | 保留原样 |
| 检疫战斗厅 | `[15,11,36,18]` | 保留已认可的挥棒货箱教学 |
| 维护竖井 | `[51,6,12,23]` | 保留原十级上行楼梯 |
| 档案分流厅 | `[63,6,40,18]` | 上下两条巡检/货运线，分别布敌与货箱 |
| 维修中继站 | `[103,12,16,12]` | 安全检查点 `[111,22]` |
| 冷却沉降池 | `[119,9,42,20]` | 十级向右下行楼梯，高处入口与低处战斗地面 |
| 重载交叉仓 | `[161,9,42,20]` | 维护步道＋64px设备台，分开的货箱射线 |
| 上联维修站 | `[203,17,16,12]` | 十级上行后进入安全检查点 `[215,22]` |
| 封存核心 | `[219,5,42,19]` | 六名混合敌人，中央高台与右侧包抄步道 |
| 撤离气闸 | `[261,12,18,12]` | 清场后的出口 `[274,22]`，不再跳转旧M02 |

迁移命令：

```powershell
python playground/tools/gen_m01_protocol_quarantine.py --extend-campaign --write --check
```

`CampaignRevision=extended_quarantine_run_v1` 保存在 LDtk；迁移只重建 `c63` 之后，
按照旧文件的行宽逐行保留 `c0–62` 的**全部语义层**及前三房元数据。
未知项目字段也保留。重复执行不会重置后来在 LDtk 中编辑的任何房间。

旧版检查点通过可选房间字段 `checkpoint_cell:[c,r]` 声明，只允许放在无敌人的连接房，
必须有稳定地面、三格净空并可普通跑跳到达。运行时须先清空之前的战斗房，
才可在靠近时激活；补充生命并更新复活点。

新增左升楼梯的 `bottom_cell=[134,28]`、`top_cell=[124,23]`。`top_cell` 表示高端边界，
所以左升梯真正外侧接口是 `c123,row23`，不是覆盖最后踏面的 `c124,row23`。
上联梯为 `[204,28]→[214,23]`，右升接口仍在 `c214,row23`。

验收除编译合同外，还必须用真实 Player 连续从出生跑到终点，并覆盖上下两路、
全部敌人/货箱原始刷点与三段楼梯30个踏面；局部单独测试可以设置起点，
但不能把局部传送测试冒充整关贯通。
