# 凯露尔：零号回廊

Godot 4.7.2 单人横版像素动作游戏。球棒近战、时停、冲刺与翻滚，三张正式地图、三档难度和关内检查点。

## 操作

A/D 移动，W 跳跃，左键挥棒，Shift 冲刺，Ctrl 翻滚，按住右键时停。
按住 R 瞄准烟雾弹，左键投掷。Esc 暂停，Backspace 从检查点重试。

## Web 构建

`npm run build` 或 `bun run build`，输出 `dist/index.html`。
Linux 构建脚本从 Godot 官方发行下载固定版本引擎和 Web 模板。
Windows 设置 GODOT_BIN，并将对应官方模板中的 web_nothreads_release.zip 放入 .build-tools。
使用 Compatibility 渲染器。新 Web 预设使用单线程，不启用 PWA；中文字体随游戏打包，许可见 godot/FONT-LICENSE.txt。

本作只有单人模式，采用本机权威演算，不建立联机房间、不同步实时状态。
账号登录与退出使用 VibeHub v3 稳定 SDK；游客可直接游玩。

发布与更新只使用 VibeHub 官方 CLI。GitHub 工作流和仓库保护交由官方 github-setup 管理。
