# 《尘缘问道》项目总览

> **英文工作名**：*Seeking Immortality through Mortal Bonds*
> **品类**：大型单机古典仙侠 RPG（2D 斜俯视 · 无缝实时战术小队 RTwP · 魔兽式 GCD 循环 + 梦幻式奇门阵法与灵宠）
> **引擎与平台**：Godot 4 · PC 原生键鼠操作（Steam 买断制，1920×1080 基准，不做手柄适配；Web 仅作试玩切片分发）
> **当前阶段**：设计立项期（先完成全套子系统设计文档并通过评审闸门，再实施 1–2 小时精品垂直切片）

## 仓库结构规划

- `docs/design/` —— 全套游戏设计文档（总纲、世界观、剧情、战斗、数值、关卡、经济、叙事、美术圣经、UI/UX、音频、技术架构、生产管线、原型迁移清单、垂直切片计划）
- `docs/reviews/` —— 评审记录、仿真验证报告与试玩记录
- `assets_src/` —— 原始制作素材（分层草稿、提示词与来源许可台账）
- `project/` —— Godot 4 工程目录（待闸门 4 通过后初始化）
- `tools/` —— 战斗数值仿真器、素材清单与许可校验脚本、数据表校验工具

## 设计文档导航

参见 [`docs/design/README.md`](docs/design/README.md) 与总纲 [`docs/design/00-gdd.md`](docs/design/00-gdd.md)。

## 与原型仓库的关系

原型仓库 `GOD-OF-PPT/chenyaun-v2`（《尘缘问道 · 剑阵万象》Web 动作原型）已在 PR #39 合并后冻结归档。本作独立立项，仅按 [`docs/design/32-prototype-migration.md`](docs/design/32-prototype-migration.md) 选择性继承世界观骨架、人物设定、古典术语库与工程验证方法论，**不继承任何未经确权的美术资产与动作运行时代码**。
