class_name GDFrameDisplayConfig
extends Resource

enum DefaultDisplayMode {
	WINDOWED,
	MAXIMIZED,
	BORDERLESS,
	EXCLUSIVE,
}


## 帧率上限可选项（对应 [member Engine.max_fps]）。[code]0[/code] 表示不限制，放在第一项。不在列表中的档案值按不限制处理。
@export var max_fps_options: Array[int] = [0, 30, 60, 120]
## 新建档案默认显示模式。Web 仅 [code]WINDOWED[/code] / [code]BORDERLESS[/code]，其余回退 [code]WINDOWED[/code]。
@export var default_display_mode: DefaultDisplayMode = DefaultDisplayMode.BORDERLESS
## 窗口化分辨率下限（像素）。可用区放得下该尺寸时，更小的不进列表，已存的更小尺寸回退为默认窗口大小；放不下时列表仍按缩放档生成。
@export var min_window_size: Vector2i = Vector2i(1920, 1080)
## 相对可用区最大尺寸的缩放档；与最大适配尺寸一起构成推荐分辨率列表。空则列表仅含最大适配尺寸。
@export var window_size_scale_steps: Array[float] = [0.9, 0.8, 0.75, 0.67, 0.5]
## 常见窗口高度（像素）。宽度按当前宽高比换算，超出可用区的不列入。
@export var common_window_heights: Array[int] = [360, 480, 720, 900, 1080, 1200, 1440, 1600, 2160]
