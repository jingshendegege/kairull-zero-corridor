# 02 时差货运场

技术文件 ID 为 `m04_chrono_freight`，是为了保留历史 M02/M03 试作；菜单正式显示“02 时差货运场”。
旧第一关、旧试作及原素材不覆盖、不删除。

## 地图合同

- 真源：`godot/maps/m04_chrono_freight.ldtk`。
- 编译器：`playground/tools/gen_m04_chrono_freight.py`。
- 运行数据：`godot/generated/m04_chrono_freight_data.gd`，禁止手改。
- 460×36 格，14 房，五段十级 32×16px 开放钢梯。
- 出生 c4→出口 c454，水平 14,400px；约为第一关的 1.67 倍。四条上层维护支路需要真实返回/起跳，不把水平长度冒充通关时长。
- 38敌：19近战＋19枪手。20只可击飞货箱，6只烟雾弹补给，3光栅、2冲压机关、2后段狙击、2座可乘货梯。
- 战斗房至少3敌，前两个3敌、其余8个战斗房4敌；入口/两安全间/出口保留零敌喘息。
- 唯一检查点在安全观察间`[278,26]`，前22/38敌清完后靠近激活；遭遇仍分10／12／16敌三个段落，记录点与唤醒边界分开。

## 路线与物品逻辑

| 房间 | 列范围 | 结构和用途 |
|---|---|---|
| 卸货闸口 | 1–16 | 安全起步、观察控件，避免出生立即交叉射击 |
| 货轨上联 | 17–56 | 两箱对应近战/枪手，十级上梯后给第一只烟雾 |
| 光栅校验 | 57–94 | 束线长128px、中心离地54px，翻滚可低身穿越；也可等休止窗或警示时停 |
| 双层分拣 | 95–134 | 下层货运线＋192px完整上廊；可乘货梯或经96px中继分两次跳上，货箱击高位枪手，再从右端落回 |
| 静音维修间 | 135–150 | 零敌安全观察和一只烟；只有遭遇边界，无存档/回血 |
| 冲压车间 | 151–190 | 冲压口前有两格以上等候地面；高路枪手后下楼梯接低路近战 |
| 冷却下沉池 | 191–230 | 96px高路能绕过地面束线；低路可以翻滚；出口补给交叉仓 |
| 交叉转运仓 | 231–270 | 两箱两条攻击线，避开梯面刷敌；钢梯高端有独立枪手 |
| 安全观察间 | 271–286 | 零敌、烟雾备战、观察后段；前段清场后激活唯一中段检查点 |
| 高架瞄准桥 | 287–326 | 下层狙击火线＋192px高架上廊；乘货梯或两段跳绕后，高处货箱先清上层枪手 |
| 泵房下行线 | 327–366 | 第二个冲压口，后接下梯换层；下层箱对同层枪手 |
| 上行搬运道 | 367–406 | 最后一段高位光栅，翻滚或观察周期；钢梯前后各有交战落脚点 |
| 终端封锁线 | 407–446 | 末段狙击普通模式也启用；低路烟幕＋上路货箱，杀清小兵后停机 |
| 货运气闸 | 447–458 | 清场出口，不继续跳往旧试作 |

烟雾不是万能钥匙：入口补给是选择资源，不强制捡起；时停没有能量时，机关仍有观测安全窗。
高位光栅中心距地54px，翻滚34px受击框留有余量，不让“看起来能躲”的姿势硬吃伤害。
狙击炮不是必杀目标，清空其房间小兵即可停机；避免打完战斗还必须站着等炮。

TACTICAL_OBJECTS 每项保存世界坐标、room_id、purpose、至少两种 solutions。
laser_gate 的 pos 是左端束线中心，span 是长度，floor_y 是地面；press 的 pos 是顶部左端，width 是闸宽，floor_y 是落闸地面；auto_sniper/smoke_pickup 的 pos 是脚底锚点。
freight_lift 的 pos 是平台中心x/下站顶面y；top_y是上站顶面，width96、height12、单程2.8秒、停站1.2秒。
两座货梯分别在c112、c299，从row27到row21；两条上廊c114–130和c301–321。
桥下只有rows22–23为暗空腔，下路站立人物的头部区域row24之后仍保留正常背景，不能把真正可走通道涂黑。

## 修改和验证

```powershell
# 只在不存在文件时首次建档；已存在时会拒绝覆盖。
python playground/tools/gen_m04_chrono_freight.py --seed --write --check

# 日常 LDtk 编辑后编译。
python playground/tools/gen_m04_chrono_freight.py --write --check
python playground/tools/test_m04_chrono_freight.py

# 可审计的六点加防：只补六个空Entities格，重复运行不覆盖后来编辑。
python playground/tools/gen_m04_chrono_freight.py --augment-defenders --write --check

# 可审计的双层升级：仅两房地形/五个敌箱位置＋两货梯，总数不变。
python playground/tools/gen_m04_chrono_freight.py --upgrade-multilevel --write --check

# 使用本机 Godot，GDScript 一律先check-only再运行。
Godot --headless --path godot --script scripts/test_m04_chrono_traversal.gd --check-only
Godot --headless --path godot --script scripts/test_m04_chrono_traversal.gd
Godot --headless --path godot --script scripts/test_m04_chrono_freight.gd --check-only
Godot --headless --path godot --script scripts/test_m04_chrono_freight.gd
```

真实Player贯通测试涵盖：@→>全程不传送/不复活，四条可选高路（含两条192px双层连廊，不使用电梯也实际可达）、全部敌人/货箱/烟雾格、五梯50踏面；再从出口原路走回出生。
另20个独立局部测试覆盖五梯×左右方向×冲刺/翻滚，明确不把局部起点设置当作整关贯通。
真窗口验收由运行整关渲染完成；headless图和上述解析/合同测试不能替代观感。

六个新增守点为：冲压车间c189低路枪手、冷却池c217货箱后枪手、转运仓c262高端近战、
狙击桥c324后卫枪手、泵房c359低路近战、上联c404高端后卫枪手。
没有新敌刷在踏面、冲压落区、光栅正下或与货箱重叠；32个旧位置和全部地形保持原样。

## 回退

本地图文件均为新增；在菜单选回“01 协议检疫站”即可不加载新关，原地图资源无需恢复。
若回退整项功能，应只撤销本轮 `level.gd`/菜单/game接线的备份差异；不要从3318c4d恢复整个仓库，也不要删除旧M03试作。
