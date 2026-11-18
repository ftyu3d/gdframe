extends Resource
class_name GDFrameSettingsData

## 显示模式：[code]windowed[/code]、[code]maximized[/code]、[code]borderless[/code]、[code]exclusive[/code]。
@export var display_mode: String = "borderless"

## 窗口化模式下的分辨率宽度（像素），与渲染分辨率一致。
@export var window_width: int = 1920

## 窗口化模式下的分辨率高度（像素），与渲染分辨率一致。
@export var window_height: int = 1080

## 垂直同步（[code]ProjectSettings[/code] 项 [code]display/window/vsync/vsync_mode[/code]）。
@export var vsync_enabled: bool = true

## 帧率上限，对应 [member Engine.max_fps]。[code]0[/code] 不限制。
@export var max_fps: int = 0

## [code]automatic[/code] 跟随系统语言；或 BCP 47 代码 [code]zh_CN[/code]、[code]zh_TW[/code]、[code]en[/code]。
@export var locale: String = "automatic"
