# GDFrame

**面向 Godot 的轻量、高性能、可开箱即用的游戏基础框架**——用统一前缀 API 与编辑器 Dock，把 UI、存档、设置、音频、暂停、对象池与状态机等通用能力收敛到插件里，让你专注玩法与内容。

启用插件后注册 Autoload **`GDFrame`**，通过 `ui_*`、`save_*`、`audio_*`、`fsm_*` 等 API 调用；工程契约在 **`res://gdframe/`**。

## 功能

| 模块 | 说明 |
|------|------|
| **UI** | 预加载 / 打开 / 关闭、图层栈、dim、Esc 关闭、手柄/键盘焦点导航 |
| **Save** | 用户目录 profile + 多槽位 `Resource`，原子写与损坏恢复 |
| **Settings** | 窗口模式、分辨率、垂直同步、语言（写入 profile） |
| **Audio** | BGM 交叉淡入、SFX 池与限流、UI Polyphonic、2D/3D 音效 |
| **Pause** | 多 reason 暂停栈，同步 `get_tree().paused` 与音频暂停 |
| **Pool** | 场景 / 工厂对象池，编辑器 Debugger 统计 |
| **FSM** | Registry + 状态脚本，按 owner 绑定，懒加载 |
| **Ext** | 可选扩展模块，按需安装（见 [GDFrame Ext](https://github.com/ftyu3d/gdframe-ext) / [Gitee](https://gitee.com/ftyu3d/gdframe-ext)） |

## 安装

1. 将本仓库 **`gdframe/`** 目录复制到你的 Godot 项目的 **`addons/`** 下。
2. 打开 **项目 → 项目设置 → 插件**，启用 **GDFrame**。
3. 首次启用会在 **`res://gdframe/`** 自动生成工程契约与 `GDFrameConstants`；之后即可使用 `GDFrame` 与 `GDFrameConstants`。

> 也可从 [GitHub Releases](https://github.com/ftyu3d/gdframe/releases) 或 [Gitee Releases](https://gitee.com/ftyu3d/gdframe/releases) 下载 `gdframe.zip`，解压后将 **`gdframe/` 文件夹**放入工程的 `addons/`（ZIP 内不含 `addons/` 目录）。

## 快速开始

```gdscript
func _ready() -> void:
	# 业务 signal 须在 gdframe_signals.gd 中声明
	await GDFrame.ui_preload(GDFrameConstants.UI_EXAMPLE)
	GDFrame.ui_open(GDFrameConstants.UI_EXAMPLE)
```

UI 场景放在 **`GDFrameConfig.UI_ROOT_DIR`**（`ui_*.tscn`，根脚本 `extends GDFrameUIBase`）；层与遮罩见 [editor/README.md](gdframe/editor/README.md#图层与遮罩)。状态机在 **`GDFrameConfig.FSM_ROOT`**。

## 文档

- **[editor/README.md](gdframe/editor/README.md)** — API 参考、配置项、编辑器 Dock、存档/音频/UI/FSM
- **[GDFrame Ext](https://github.com/ftyu3d/gdframe-ext)** — 可选扩展模块（[Gitee](https://gitee.com/ftyu3d/gdframe-ext)）

## 许可证

[MIT](LICENSE) © Feng Yang
