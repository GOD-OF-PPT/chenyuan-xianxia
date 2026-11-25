# 31 · 《尘缘问道》内容生产与质检管线规范（Content Pipeline）

- **文档版本**：v1.0（基于 2026-11-25 访谈拍板编制）
- **状态**：已定稿
- **前置依赖**：[`20-art-bible.md`](20-art-bible.md) · [`22-audio-direction.md`](22-audio-direction.md) · [`30-tech-architecture-godot.md`](30-tech-architecture-godot.md)
- **下游文档**：`40-vertical-slice-plan.md`

---

## 1. 设计目标

在“AI 代理写代码/配表 + AI 初稿人工精修美术 + 负责人把关审美”的敏捷制作模式下，建立一套**Git Diff 完全透明、编译期自动抓虫、100% 版权可追溯**的工业级单机生产管线，彻底杜绝手填二进制面板配错数值或未校色生图混入工程。

---

## 2. 配表、剧本与关卡的四条标准流水线

### 2.1 游戏数值与物品配表管线（Human-Readable JSON）

- **唯一真源（Single Source of Truth）**：所有技能、专精节点、奇门阵法、装备、丹方、怪物、灵宠与兽诀统一存放在 `project/data/*.json`（按模块拆分，格式化缩进 2 空格，Git PR 一眼看清每一行数值改动）。
- **Schema 强校验**：每张 JSON 表配套一份 JSON Schema 定义，由 `tools/validate_data.py` 在提交与 CI 时自动检查：
  - 必填字段、枚举合法性（如五行仅限 `metal/wood/water/fire/earth/none`）；
  - **跨表引用零断链**：丹方引用的灵草 ID、首领掉落的妖核 ID、技能挂载的图标与音效路径必须 100% 存在；
  - **预算越界拦截**：单件装备绿字总权重不得超出 `11` 号文档对应品阶预算上限。

### 2.2 叙事剧本与本地化管线

- 对话与支线事件采用结构化 `project/data/dialogues/chXX_*.json` 编写，内置状态条件语法（如 `"require_bond": {"shen_qinghe": 2}`）与结果动作（如 `"grant_clue": "clue_yaolu_spy"`）。
- 运行 `tools/extract_locales.py` 一键同步生成/更新 `project/locales/zh_CN.csv`，自动检测孤儿翻译键与超长溢出文本（单屏对话栏不超过 2 行 × 34 汉字，保持古典精炼呼吸感）。

### 2.3 美术与音频资产入库质检管线（`manifest_guard`）

承接 `20-art-bible.md` 五步铁律，任何放入 `project/assets/` 的 `.webp / .png / .ogg / .wav` 文件必须通过 `tools/manifest_guard.py --check`：

1. **原始工程留档**：对应的未合并图层稿、AI 垫图与修整前后对比稿存放于仓库 `assets_src/`（打包发行时自动排除 `assets_src/`，不占玩家硬盘）；
2. **台账强制字段**：`docs/asset-manifest.json` 必须完整记录每项资产的 `path`、`category`、`dimensions`、`sha256`、`creation_method`（工具版本 + 核心风格提示词 + 人工修整工序说明）与 `license`；
3. **规格自动门禁**：自动校验立绘透明通道无残损、UI 切片九宫格边距合法、不存在任何标记为 `Unrecorded` 的黑户文件。

### 2.4 区域箱庭关卡“白盒 → 精修”三步法

严禁还没验证拉怪动线就直接画精美大图返工！每张区域地图与奇门迷宫严格分三步交付：

1. **阶段 A · 灰盒战术验证（Greybox）**：用纯色几何碰撞块摆出 35° 斜俯视地形、掩体柱、巡逻怪（110）路径、五行禁制门与回环石门，直接用主队跑通拉怪手感与通关时长（误差控制在目标 ±15% 内）；
2. **阶段 B · 组件拼装与 Y-Sort 校准**：替换为经 LUT 统一校色的手绘地面、独立屋檐树木精灵，实机跑遍每一棵树后遮挡半透与脚底深度排序；
3. **阶段 C · 氛围光影与音景封版**：叠加上方飘雨/竹影前景视差层、丹炉点光源与双轨无缝音乐触发区。

---

## 3. 验收标准

- 克隆仓库后仅需一行命令 `python3 tools/run_all_checks.py`（串联配表校验、经济防套利、Manifest 溯源、Godot 无头单测与战斗仿真矩阵），全绿退出码 `0` 方可合入 `main`。

---

## 4. 决策记录

| 编号 | 议题 | 拍板结论 |
|---|---|---|
| CP-01 | 配表格式与自动化门禁 | 采用 Git 友好的纯文本 JSON 源配表 + 编译期静态外键/预算/防套利/字号/Manifest 全自动校验脚本 |
