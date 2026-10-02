---
name: gdframe-framework
description: >-
  Author and review GDScript with lean style:
  writing norms, strong typing, official GDScript naming, no redundant defenses or symptom-patch retries,
  performance-first. Runtime paths must not hold editor-only scripts.
  Use for business GDScript (gdframe_project, data, gameplay) and any other GDScript in a GDFrame project.
  When editing addons/gdframe or addons/gdframe_<id>, also follow gdframe-addon.
---

# GDFrame 书写规范（性能优先）

适用于 GDFrame 工程里的 GDScript（玩法、`gdframe_project/`、`data/`，以及框架代码的通用部分）。

## Hard rules

1. **无兼容垫片**：不留旧 API / 路径 / 字段双轨；迁移写 Changelog，不写兼容层。
2. **无过度防御**：已知不变量不再判；禁止恒真/恒假分支、无调用方的 `clear_*` 与延时包装。失败只留一种回退。同一状态写两次（`call_deferred` 再设一遍、下一帧再钉、挡 N 帧的旗标）是症状补丁：先改会被覆盖的源状态，源状态已对就删补偿。引擎本帧不能接受的那一次延迟（如输入帧里 `grab_focus`）保留。
3. **注释只写当前**：禁止「此前 / 对比旧实现 / formerly」类讨论残留。
4. **命名**：达意；改行为就改名并改全调用处。Godot 风格：文件、函数、变量、信号 snake_case，缩写全小写（`yaml_parser.gd`）；类、节点、枚举 PascalCase，缩写连续大写（`YAMLParser`、`Camera3D`）；常量、枚举成员 CONSTANT_CASE（`MAX_SPEED`）；preload 公开 PascalCase（`Weapon`），私有 CONSTANT_CASE（`_MAX_SPEED`）。
5. **重复只抽一次**：同一职责只实现一处；调用链上不叠相同判断或处理。
6. **强类型为主**：能定死就写死（`Array[T]`、具体 `class_name`）；禁止对已知类型 `has_method` / `call("…")`。弱类型仅用于：线协议 `Dictionary`、动态方法名、引擎无类型 API、不定宿主 duck typing——拿到后立刻收窄。扩展调用 `GDFrame.<模块>.方法()`，未安装的不要调用。
7. **性能优先**：遇问题先估热路径代价再定写法；能缓存/复用不每帧重算。
8. **进包禁纯编辑器代码**：会进导出包的路径（如 `res://data/`）只放运行时会用到的脚本和资源。

## 复查

风格问题直接改。症状补丁（含「系统还会再改一次」）直接删。仅当去掉后当前路径必然失败才列争议：两种做法、代价、为何没改。
