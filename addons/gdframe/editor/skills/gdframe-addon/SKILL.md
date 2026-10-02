---
name: gdframe-addon
description: >-
  GDFrame core and extension authoring: editor-only addon layout, extension
  service slots, audio channel API generation, docs and version sync.
  Use when editing addons/gdframe or addons/gdframe_<id>. Also follow gdframe-framework.
---

# GDFrame 插件与扩展

编辑 `addons/gdframe/` 或 `addons/gdframe_<id>/` 时使用。通用书写规范见 **gdframe-framework**。

## 编辑器

仅编辑器使用的代码放 `addons/*/editor/`（目录含 `.gdignore`，不进包）。`plugin.cfg` 指向 `editor/plugin.gd`。运行时读 `data/generated/` 或运行时配置表，不读编辑器草稿。

## 框架

扩展经 `ext_service_type()` 生成 `GDFrame.<模块>` 槽位，业务直调服务方法（如 `GDFrame.example.ping()`），不生成方法透传层。流总线轨方法由 `generate_audio_channels()` 写入 `GDFrame.audio`，不设服务槽位。

文档跟代码：README、导出注释、Dock 同步。改版本时核对 `plugin.cfg` 与 `plugin_index.cfg`。
