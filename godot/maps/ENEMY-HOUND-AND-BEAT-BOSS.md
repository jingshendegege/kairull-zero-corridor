# 新敌人「检疫猎犬」与节奏 Boss「节拍监察官」设计与接口合同

2026-09-28。用户要求：新敌人"看到主角会冲刺飞扑"；有创意的 Boss，"类似喵斯快跑"；旧机关美术重画。
仅本地分支 `codex/art-enemies-20260928`，不推送/合并/发布。Claude 负责设计、美术、配乐与谱面；Codex 负责运行时后端与测试。

---

## A. 检疫猎犬（QuarantineHound）——冲刺飞扑型

**定位**：四足机械猎犬，速度快、血量同其他杂兵（一击死）。发现主角后蓄力，然后沿直线**飞扑**，
扑中造成伤害，扑空落地打滑有明显破绽——鼓励"看准预警→侧闪/翻滚/时停→反打"。

### 状态机（60fps 逻辑 tick；与现有敌人同为 Node2D + 手动 `step(dt)`，由 game 推进）

| state | 时长 | 行为 |
|---|---|---|
| idle | — | 原地嗅探；玩家进入 `AGGRO_RANGE=420px` 且视线未被墙/锁门/烟/玻璃挡住 → alert |
| alert | 14 tick | 竖耳低吼，锁定朝向 |
| run | — | 距离 > `POUNCE_RANGE=200px`（实现时从 260 下调：22 tick×540px/s 最远 198px） 时以 150px/s 贴地追击（不撞墙、不掉平台边：遇边缘停下） |
| windup | 24 tick | 后蹲蓄力，品红眼灯闪烁（预警）；**锁定飞扑目标点 = 此刻玩家脚底位置**，之后不再追踪 |
| pounce | 最长 22 tick | 以 540px/s 朝目标点飞扑（抛物线：初始向上速度使落点 ≈ 目标点；遇墙停止）；**有效攻击窗 = pounce 全程**，攻击盒为身体前半 60×40 |
| recover | 36 tick | 落地打滑 + 硬直（无攻击），是反打窗口 |
| cooldown | 20 tick | 回到 run/alert 判定 |
| dead | 54 tick 播放 | 一击死；倒地动画收尾与即时结算分离（同现有敌人） |

- 空中被击中也一击死（尸体沿当前速度飞出，接 `set_corpse_lift/set_corpse_ground`）。
- 飞扑途中碰到玩家翻滚无敌帧不结算；时停中完全冻结；烟雾遮挡新索敌（已起跳的飞扑照常完成）。
- 伤害只在 pounce 有效窗内结算一次（`attack_active()` / `attack_rect()`），不重复扣血。

### 必须实现的接口（参照 grunt.gd / freight_inspector.gd，搜索所有类型分支）
`player / level / door_blockers / vision_blocker` 注入；字段 `state frame face dead hitstop position _anim_clock`；
方法 `step(dt) body_rect() take_hit(from_x, damage) attack_active() attack_rect() set_corpse_lift() set_corpse_ground()
wound_anchor_world() standing_height() corpse_used_rect() corpse_scale() corpse_extent()`；
timeline / run_checkpoint / pause / glass / kill-refresh-dash 与现有敌人同等对待（game.gd 里对
`GruntGunner or FreightInspector` 的类型分支都要加上猎犬）。碰撞体 `BODY_W=56, BODY_H=48`（矮长体型）。

### 地图接入
LDtk Entities 新值 **7 = `QuarantineHound`，ASCII `h`**；`level.gd` 解析为 `enemy_spawn_kinds` 的 `"hound"`；
`game.gd` 工厂创建猎犬。Claude 会在 M06 生成器里放置若干猎犬（Claude 负责生成器/LDtk）。

### 美术合同（Claude 交付，Codex 按此读取）
`godot/assets/enemy/hound/atlas.png` + `atlas.json`（与 rifleman/loader 同格式：`cell_size`、`baseline_y`、
`animations{name:{row,frames,loop}}`、`frames[{animation,frame,cell_bbox}]`）。
格 `160×96`，`baseline_y = 89`，1:1 显示（`SCALE = 1.0`），面朝右。
动画与帧数：`idle 4 / alert 4 / run 6 / windup 4 / pounce 4 / recover 4 / death 6`。
`pounce` 帧按飞行进度播放；`windup` 最后一帧为最低蹲姿。美术交付前可用纯色矩形占位，接口不变。

---

## B. 节奏 Boss「节拍监察官 BEAT WARDEN」——类喵斯快跑

**概念**：检疫设施的广播塔 AI，占据舞台右侧的巨型音箱机甲。它踩着**原创配乐**的节拍，
沿**地面轨**和**空中轨**两条轨道发射"音符"。玩家在舞台左侧的判定区用**球棒击中音符**，
音符被打回去砸中 Boss 造成伤害——把"喵斯快跑"的双轨打音符移植进本作的挥棒/跳跃/翻滚手感。

### 音符
| 类型 | 轨道 | 处理 |
|---|---|---|
| normal（青色） | ground / air | 挥棒击中 → 反弹飞回 Boss，命中扣 1 血；碰到玩家 = 受伤 |
| heavy（琥珀大音符） | ground | 需要连击 2 次才反弹（第 1 击减速），命中扣 3 血 |
| bomb（品红尖刺） | ground / air | **不能打**（打到 = 受伤）；跳过/翻滚穿过/下蹲躲 |
| air 音符 | air（离地约 72px） | 需起跳挥棒（空中挥棒每次落地前 1 次） |

- 音符从 Boss 发射口水平飞向左侧，速度恒定，**在拍点上正好到达判定线**（`judge_x`，舞台左侧玩家站位处，地面画出两个判定环）。
- 判定：以音符中心到达判定线的时间差评价 Perfect(≤60ms)/Great(≤120ms)/Hit（仍在球棒范围内）→ HUD 显示评价与 COMBO；
  评价只影响分数与 Boss 受击演出，不影响是否反弹（反弹只看挥棒有效帧是否碰到音符）。
- 玩家可以自由走位；音符穿过判定线后继续飞到屏幕左缘消失（仍可能碰到玩家）。

### 阶段（谱面 JSON 里定义）
1. **开场 Intro**（8 小节）：只有地面 normal，教学"站判定环挥棒"。
2. **Verse**：地面 + 空中 normal 交替，出现 heavy。
3. **Drop**：加入 bomb 与双音符（地/空同拍：先打地再起跳打空，或二选一）。
4. **Finale**：Boss 降下舞台露出核心（受击倍率 ×2），最后 16 拍密集音符；Boss 血量归零 → 爆炸演出 → 出口开启。
- 血量不足以在谱面结束前清零时，谱面循环 Drop 段直到击败（不设"时间到失败"）。
- 玩家死亡按现有死亡/倒带/重试规则；重试从 Boss 战开头、音乐从头播放。

### 同步（关键）
- 配乐由 Claude 程序合成（原创，WAV/OGG），谱面由同一份编曲数据导出，**拍点与音频采样级一致**。
- 运行时以 `AudioStreamPlayer.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()`
  得到歌曲时间；音符生成时间 = `note_time - travel_px / note_speed`。时停/暂停：Boss 战中时停冻结音符与 Boss，
  音乐同时暂停（`stream_paused`），恢复后继续对拍。
- 文件（Claude 交付）：`godot/assets/bgm/beat_warden.ogg`（或 .wav）与 `godot/assets/boss/beat_warden_chart.json`：
```json
{"bpm": 128, "offset_sec": 0.0, "beats_per_bar": 4, "note_speed_px": 520,
 "sections": [{"name": "intro", "from_beat": 0}, ...],
 "notes": [{"beat": 16.0, "lane": "ground", "kind": "normal"}, ...],
 "loop_from_beat": 160, "loop_to_beat": 224}
```

### 场景
新关 **05 节拍广播塔**（`M07_BeatTower`，单房竞技场，由 Claude 生成 LDtk）：入口短廊 → 舞台（42×20 格）。
玩家出生左侧；Boss 固定在舞台右侧（不移动，身体受击框只在反弹音符命中时有效）；击败后右侧出口开启。
菜单第 5 关；M06 通关后自动接续。

### 美术（Claude）
Boss 大体积精灵（idle 呼吸随拍、发射、受击、降台露核、爆炸），音符精灵（normal/heavy/bomb × 地/空），
判定环、舞台背景（广播塔内部、音箱墙、随拍闪烁的灯带）。

---

## C. 旧机关美术重画（Claude）
狙击炮台、光栅发射器、压机、货梯、烟雾补给改为像素精灵，只替换 `_draw` 绘制函数，玩法与判定不变。

## D. 文件所有权
| 负责 | 文件 |
|---|---|
| Codex | 新脚本 `quarantine_hound.gd`、`beat_warden.gd`（及音符/判定相关新脚本）、`game.gd`/`level.gd`/`run_session.gd`/`attempt_timeline.gd`/`run_checkpoint.gd` 必要改动、M07 boot/scene、所有新增/修改测试 |
| Claude | `playground/tools/gen_m06*.py`/`gen_m07*.py`、`godot/maps/*.ldtk`、`godot/generated/*`、`godot/assets/**`、`tools/**`、`tactical_hazard.gd`/`freight_lift.gd`/`smoke_tactics.gd` 的绘制函数、`m06/m07` 美术脚本 |

---

## E. 实际交付记录（2026-09-28）

### 猎犬
- 运行时：`quarantine_hound.gd`（Codex，89 项测试）；`POUNCE_RANGE` 由 260 下调到 200px（22 tick×540px/s 最远 198px，站定玩家必被扑到）。
- 美术：`tools/art/enemy3d/hound.py` → `godot/assets/enemy/hound/`。
- M06 放置 4 只（风扇阵列 c55、冷却塔 c126、索桥基座 c242、封锁泵站 c294），全关敌人 26→30。

### 节拍监察官（全部原创，可复跑）
- 配乐 + 谱面：`tools/audio/beat_warden_song.py`（numpy 合成 → ffmpeg Vorbis）。
  128 BPM，A 小调 Am–F–C–G；intro 8 / verse 16 / build 4 / drop 16 / finale 8 小节，共 99.5s。
  谱面 258 音符（normal 222 / heavy 12 / bomb 24），boss_hp 160（≈单遍伤害总量 258 的 62%）。
  循环：`loop_from_beat 112`（drop 起）→ `loop_to_beat 208`（曲末）；一旦进入 finale 露核，循环中保持露核。
- Boss 图集：`tools/art/enemy3d/beat_warden.py`（Blender 基本体 → 像素）→ `godot/assets/boss/beat_warden/atlas.*`，
  格 288×272、脚底 262；idle 4（第 0 帧=拍点）/ fire_ground 3 / fire_air 3 / hurt 3 / expose 4 / core 4 / death 6；
  JSON 附号角口/核心相对脚底坐标（面朝右）。
- 音符/判定环/击碎/灯带与舞台背景：`tools/art/m07/build_m07_art.py`。
- 地图：`playground/tools/gen_m07_beat_tower.py` → `godot/maps/m07_beat_tower.ldtk` / `godot/generated/m07_beat_tower_data.gd`
  （80×25；后台走廊 2 守卫 + 货箱 + 钢梯 → 候场室检查点 → 44×21 舞台；`BOSS_ARENA` 常量给判定线/轨道/Boss 脚底）。
- 几何核对：站立受击框 34×82 从空中轨音符（中心离地 108、半径 14）下方通过；跳跃顶点≈121px 可越过地面音符并够到空中音符。
- 后端（Boss 状态机、指挥器、判定、时停/暂停同步、M07 场景、菜单第 5 关）由 Codex 实现，见其测试 `test_beat_warden.gd`/`test_m07_beat_tower.gd`。

### 2026-09-28 晚：正式配乐换成 Final Stand（用户用 Suno 生成）
- 音频：`godot/assets/bgm/final_stand.ogg`（由用户提供的 Final Stand.mp3 转码）。**Suno 免费版生成，仅限非商用**；若将来商用/公开发售需用付费账号重新生成或另找授权音乐。
- 谱面：`tools/audio/chart_from_audio.py` 从音频自动分析（150.02 BPM、首拍 0.702s，开头/中段/结尾拍点对齐无漂移），
  段落随能量逐段加难：intro → verse → build → drop … → finale（第 352 拍起）。558 音符，Boss 492 血（伤害总量 × 0.85），
  95% 命中率的自动演奏在第 147 秒（终段）完成击杀。
- 重音（黄色）改为**上下一起按的双键音符**：显示在两层中间并有金色光柱提示，两次按键相隔 ≤120ms 才算击中，击中后高抛旋转击飞砸向 Boss（3 伤害，终段 ×2）。
- 击打音效统一为 `godot/assets/sfx/beat_hit.wav`（`tools/audio/beat_hit_sfx.py` 合成）；双键只降调加量，不换音色。
- 旧合成曲 `beat_warden.ogg` 与 `beat_warden_synth_chart.json` 保留为测试夹具。

