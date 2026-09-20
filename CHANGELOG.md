# Changelog

GDFrame 版本变更记录。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)（`major.minor.patch`，系列按 `major.minor` 划分，见根目录 `plugin_index.cfg`）。

## [1.0.0] - 2026-09-20

首次正式发布。面向 Godot 4.3+（开发测试于 4.7），启用插件后注册 Autoload `GDFrame`，工程目录为 `res://gdframe_project/`。

### Added
- **统一 API**：`ui_*`、`save_*`、`settings_*`、`audio_*`、`pause_*`、`pool_*`、`fsm_*` 等前缀接口，经 Autoload `GDFrame` 调用。
- **UI**：预加载 / 打开 / 关闭、图层栈、全屏 dim、Esc 关闭、手柄与键盘焦点导航（`GDFrameUIBase` / `GDFrameUINav`）。
- **UI 导航参与**：导出属性 `ui_nav_participates`（默认 `true`）。为 `false` 时永不进入打开栈，因此不锁定下层、不抢焦点，适合浮层提示 / Toast。Dock **UI管理** 可编辑该开关。
- **Save**：用户目录 profile + 多槽位 `Resource` 存档，原子写与损坏恢复。
- **Settings**：窗口模式、分辨率、垂直同步、语言等，写入 profile。
- **Audio**：BGM 交叉淡入、SFX 池与限流、UI Polyphonic、2D/3D 音效。
- **Pause**：多 reason 暂停栈，同步 `get_tree().paused` 与音频暂停。
- **Pool**：场景对象池，编辑器 Debugger 可查看统计。
- **FSM**：Registry + 状态脚本，按 owner 绑定，支持懒加载与按需 preload。
- **Ext**：可选扩展模块安装 / 更新（独立 `addons/gdframe_<id>/`），支持生成扩展 API。
- **编辑器 Dock**：通用、UI 管理、状态机、对象池、扩展管理、框架更新等页签；安装/更新前会确认，跨系列提示可能有兼容性变化。
- **发布**：`tools/pack_release`（ps1 / bat / sh）打包 `dist/gdframe.zip`（内含 `addons/gdframe/...`）。
- **文档**：根目录 README、`CHANGELOG.md`、`gdframe/editor/README.md`；Cursor Skills（`editor/skills/`）启用插件时同步到 `.cursor/skills/`。
