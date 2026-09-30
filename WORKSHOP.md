# 《凯露尔：零号回廊》创意工坊 Mod 开发约定

本游戏是 Godot 4 导出的网页游戏。Mod 是在游戏网页里运行的 JavaScript，**只能**通过公开对象
`window.KairullMods` 与游戏交互——Mod 看不到、也不应尝试访问 Godot 内部节点。
本文件是作者与 Mod 创作者之间的约定；平台不会扫描或沙箱化 Mod 代码，能力声明也不是安全机制。

- 公开 API 版本：`KairullMods.apiVersion === 1`
- 对应游戏版本：`KairullMods.gameVersion === "0.2.0"`

## 1. 可以制作哪些 Mod

| 能力 ID | 能做什么 |
|---|---|
| `events.observe` | 订阅游戏事件：成就提示、统计面板、击杀字幕、节奏判定特效 |
| `ui.overlay` | 在画面上方画自己的 HTML 界面（提示、计分板、装饰、CRT 滤镜等） |
| `appearance.player_tint` | 给主角叠加颜色（换色皮肤） |
| `rules.difficulty_health` | 修改三档难度的生命上限 |
| `tuning.time_stop` | 调整时停时长与充能速度 |
| `tuning.boss_health` | 调整节奏 Boss（Beat Warden）血量 |

目前**不开放**：新关卡、新敌人、替换角色贴图 / 音乐 / 音效、主角移速跳跃等物理参数、谱面编辑。
这些在当前架构里没有稳定的公开入口，强行开放会让 Mod 依赖私有实现，游戏一更新就会坏。

## 2. 公共对象、注册函数与事件

所有注册函数都要求一个**全局唯一 ID**（3–64 位，小写字母、数字、`.`、`-`、`_`），
建议格式：`<作者>.<mod名>.<用途>`，例如 `alice.redskin.tint`。每个函数返回一个 `unregister()` 函数。

```js
KairullMods.registerDifficultyHealth(id, { easy?: 1-9, hard?: 1-9, zero?: 1-9 })
KairullMods.registerTimeStopTuning(id, { durationScale?: 0.25-4, rechargeScale?: 0.25-4 })
KairullMods.registerBossTuning(id, { hpScale?: 0.25-4 })
KairullMods.registerPlayerTint(id, { color: "#rrggbb", strength?: 0-1 })
KairullMods.createOverlay(id)            // → HTMLElement（pointer-events:none，铺满画面）
KairullMods.unregister(id)               // → boolean
KairullMods.on(eventName, handler)       // → unsubscribe()
KairullMods.getState()                   // → { scene, title, difficulty, maxHealth, gameReady }
KairullMods.listRegistrations()          // → 当前全部注册（排查冲突用）
```

数值超出范围会被限幅；类型错误（非数字、颜色格式不对、ID 不合法或重复）会直接抛出异常。
`durationScale` 是时停最长时长的倍率（原版 2 秒）；`rechargeScale` 是从空到满所需时间的倍率（原版 5 秒，数值越大充得越慢）。

生效时机：
- 主角色调：即时。
- 难度生命：下一次开局、进入下一关或死亡重来时。
- 时停：下一次进入关卡时。
- Boss 血量：下一次进入节拍广播塔时。

### 事件（处理函数收到一个冻结的只读对象）

| 事件 | 参数 |
|---|---|
| `game:ready` | `{ apiVersion }` —— 游戏首个场景已就绪 |
| `menu:enter` | `{}` —— 回到开始菜单 |
| `level:start` | `{ scene, title, difficulty, maxHealth }` |
| `level:clear` | `{ scene, title, difficulty, maxHealth }` |
| `player:hurt` | `{ hp, maxHealth }` |
| `player:death` | `{ scene, title, difficulty, maxHealth }` |
| `rhythm:judge` | `{ rating: "perfect"｜"great"｜"hit"｜"miss", lane: "air"｜"ground"｜"dual"｜"", combo }` |
| `boss:defeat` | `{ boss: "beat_warden"｜"red", scene }` |

`scene` 取值：`m06_exhaust_ridge`（01 排风脊线）、`m07_beat_tower`（01 BOSS 节拍塔）、
`m01_protocol_quarantine`（02 协议检疫站）、`m04_chrono_freight`（03 时差货运场）。
处理函数抛错只会打印到控制台，不影响游戏和其他 Mod。

## 3. 最小可运行 Mod

`vibehub.mod.json`：

```json
{
  "title": "红色凯露尔",
  "summary": "把主角染成红色，并在过关时弹出提示",
  "description": "示例 Mod：主角色调 + 过关提示。",
  "version": "1.0.0",
  "releaseNotes": "首次发布",
  "entry": "main.js",
  "entryType": "classic",
  "styles": [],
  "loadPhase": "after-start",
  "dependencyIds": [],
  "capabilities": ["appearance.player_tint", "events.observe", "ui.overlay"]
}
```

`main.js`：

```js
(() => {
  const mods = window.KairullMods;
  if (!mods || mods.apiVersion !== 1) return;          // 游戏版本不匹配时安静退出
  mods.registerPlayerTint("demo.redskin.tint", { color: "#ff4a4a", strength: 0.6 });
  const layer = mods.createOverlay("demo.redskin.toast");
  mods.on("level:clear", (e) => {
    layer.innerHTML = `<div style="position:absolute;top:18%;width:100%;text-align:center;
      font:700 32px sans-serif;color:#fff;text-shadow:0 0 8px #f44">${e.title} CLEAR!</div>`;
    setTimeout(() => (layer.innerHTML = ""), 2500);
  });
})();
```

## 4. 启动前还是启动后加载

游戏启动顺序：建立 `KairullMods` → 加载 `before-start` Mod → 启动 Godot → 游戏首个场景就绪时
调用 `VibeHubWorkshop.markGameReady()` → 加载 `after-start` Mod。

- **`before-start`**：只做数值注册，例如难度生命、时停调校、Boss 血量，保证第一局就生效；也可以提前订阅事件。
  此时 Godot 尚未运行，`getState().gameReady === false`。
- **`after-start`**：所有界面类（`createOverlay`）、外观类，以及想确认游戏已就绪的 Mod。
  注册同样会被游戏在 0.5 秒内读取；数值类在下一次进入关卡时生效。

## 5. 公共前置依赖与跨阶段规则

- `KairullMods` 本身就是所有 Mod 的公共前置 API，由游戏提供，**不需要**也不应被声明为依赖。
- 可以发布"基础库 Mod"（例如通用提示框、统计工具），挂到 `window` 上一个带作者前缀的对象
  （如 `window.aliceToastKit`），其他 Mod 在 `dependencyIds` 中声明它。
- 基础库 Mod 若要被 `before-start` Mod 依赖，自身也必须是 `before-start`。
- **禁止**：`before-start` Mod 依赖 `after-start` Mod；依赖方在加载时假设被依赖方已执行但阶段更晚。

## 6. 多个 Mod 同时启用：命名、去重与冲突

- ID 全局唯一；同一 ID 第二次注册会抛出异常（不同类别之间也不能重名）。要替换自己的注册，先 `unregister(id)`。
- 同一类别有多个注册时，按**注册顺序**逐字段合并，**后注册的覆盖先注册的**同名字段；
  例如 A 设 `easy: 7`，B 设 `easy: 3, hard: 5`，结果为 `easy: 3, hard: 5`。
  加载顺序由平台决定，不应依赖某个固定次序；可用 `listRegistrations()` 自查冲突。
- 覆盖层各自独立，互不影响；请只修改自己 `createOverlay` 返回的元素。
- 全局变量、CSS 类名、`localStorage` 键都应使用作者前缀，避免与其他 Mod 冲突。

## 7. 存档、联机、加载顺序与版本兼容

- **存档**：游戏只在本轮挑战内保存检查点（内存中），不写入长期存档；Mod 修改的数值不会写进检查点。
  Mod 若需持久化自己的数据，请使用带作者前缀的 `localStorage` 键，并能容忍数据丢失。
- **联机**：游戏目前没有联机模式；工坊联机策略为 `mods-disabled`。今后若加入联机，进入联机前会拒绝任何已启用的 Mod。
- **加载顺序**：同阶段内由平台决定，Mod 之间不要假设先后，冲突规则见第 6 节。
- **版本兼容**：检查 `KairullMods.apiVersion`。
  - 小版本只会新增函数和事件，不改变已有函数的含义；破坏性变更会提升 `apiVersion`。
  - 事件参数可能新增字段，请忽略不认识的字段。
  - 游戏在关卡、数值平衡上的更新可能改变 Mod 的实际效果。

## 8. 明确禁止

- 调用 `KairullMods` 中以下划线开头的内部成员（`_snapshot`、`_emit`、`_gameReady`、`_version`）。
- 读写游戏画布、Godot 引擎对象（`Engine`、`GODOT_CONFIG`、`Module` 等）、页面私有 DOM，或覆盖游戏 / VibeHub 的全局函数。
- 访问、窃取或转发账号凭据、Token、Cookie、VibeHub SDK 登录态、管理接口或任何秘密。
- 伪装、遮挡或修改 VibeHub 登录 / 账号相关界面；用覆盖层拦截全部点击导致游戏无法操作。
- 加载包外远程脚本或资源（所有资源应放在 Mod 包内，用 `VibeHubWorkshop.resolve(modId, path)` 取地址）。
- 挖矿、广告注入、追踪用户、向第三方发送玩家数据。
