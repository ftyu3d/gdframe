---
name: gdframe-framework
description: >-
  Author and review GDFrame framework code (addons/gdframe runtime, editor,
  config) with lean SemVer-first style: no compat shims, no over-defensive
  fallbacks, no discussion-residue comments. Also use when reviewing or
  simplifying any GDFrame-related code (including game project scripts or
  user mods of the addon) for redundant/compat/defensive code, naming, or
  leftover comments.
---

# GDFrame 代码风格与复查

框架源码（`gdframe/` / `addons/gdframe/`）、魔改插件、业务侧精简复查。

## Hard rules

1. **无兼容垫片**：不留旧 API / 路径 / 字段双轨；迁移写 Changelog，不写兼容层。
2. **无过度防御**：已知不变量不再判；禁止双回退、无调用方的 `clear_*`、恒真/恒假分支。
3. **无讨论残留注释**：禁止「此前 / 对比旧实现 / formerly」。注释只写当前行为与不变量。
4. **命名达意**：名字反映当前行为；变了就改名并改全调用处，不留旧名包装。删未使用参数，Godot 信号签名强制的除外。
5. **文档跟代码**：同步 README / 导出注释 / Dock；Changelog 面向用户。
6. **重复只抽一次**：共用流水线 / 确认框 / 失败文案，不各抄一套。
7. **失败一种回退**：远端失败 → 会话缓存 **或** 本地文件，不要两层。栈删除用 `remove_at` + 重建索引以保序。

## Anti-patterns

| 类型 | 例子 |
|------|------|
| 兼容 | raw 下载同时保留 JSON API 解包；旧方法名薄包装 |
| 防御 | `typeof` 再判已知 `Dictionary`；`find` 回退已维护的 index map |
| 冗余 | 两套 ConfirmationDialog；updater/ext 各写一份 source 写入 |
| 注释 | 「关闭导航应说明…」「刷新时若已在栈上会移出」类设计讨论 |

复查：对照上表与 Hard rules，按 **高 / 中 / 低** 列出并直接改高、中项。框架维护时核对 `plugin.cfg` 与 `plugin_index.cfg` 系列一致。
