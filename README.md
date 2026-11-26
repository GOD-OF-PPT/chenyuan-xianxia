# 《尘缘问道》 (Seeking Immortality through Mortal Bonds)

> **品类**：大型单机古典仙侠 RPG（2D 35° 斜俯视 · 无缝实时战术小队 RTwP · 魔兽式 GCD 职责循环 + 梦幻式奇门阵法与灵宠）
> **引擎与平台**：Godot 4.3 · 纯正 PC 键鼠原生设计（1920×1080 基准，强类型 GDScript，零手柄妥协；同步支持 Web WASM 免安装试玩与 Linux / Windows 独立可执行包）
> **当前里程碑**：**第一章《青岚境 · 山雨欲来风满楼》精品垂直切片 (`v0.1.0-slice`) 已完成合龙与封包**

---

## 一、快速启动与实机试玩方式

### 1. 直接运行已导出的独立可执行包 / Web 试玩包

本仓库导出的三端发行产物位于本地 `builds/` 目录（可通过 `bash tools/export_builds.sh` 一键重构建）：

- **Web 浏览器免安装版 (`builds/web/`)**：
  - 产物：`builds/web/index.html`、`index.wasm`、`index.pck`、`index.js`（单线程 `gl_compatibility` 模式，无需特殊 COOP/COEP 响应头，支持任意现代桌面浏览器全屏游玩，自动通过浏览器 IndexedDB 持久化存档与设置）。
  - 本地启动静态服务示例：`python3 -m http.server 8080 --directory builds/web`
- **Windows 桌面版 (`builds/windows/`)**：
  - 产物：`builds/windows/chenyuan-xianxia.exe` + `chenyuan-xianxia.pck`（保持同目录双击 `chenyuan-xianxia.exe` 即可运行）。
- **Linux x86_64 桌面版 (`builds/linux/`)**：
  - 产物：`builds/linux/chenyuan-xianxia.x86_64`（内嵌 `.pck` 单文件可执行程序，直接执行 `./builds/linux/chenyuan-xianxia.x86_64` 即可运行）。

### 2. 使用 Godot 4.3 编辑器打开源码工程

```bash
# 校验 149 项入库美术与民乐音效资产 SHA-256 及来源台账
python3 tools/manifest_guard.py --check

# 使用 Godot 4.3 直接启动运行工程
godot --path project

# 一键重新导出 Web / Linux / Windows 三端构建包
bash tools/export_builds.sh
```

---

## 二、纯正 PC 键鼠操作速查表

| 操作分类 | 默认键鼠绑定 | 功能说明 |
| :--- | :--- | :--- |
| **主控走位** | `W / A / S / D` 或 **地面右键** | 驱动当前主控角色平滑走位；走位中自动平砍计时不重置（支持走 A 拉怪） |
| **点选与框选** | **鼠标左键点选 / 拖拽框选** | 左键仅用于点选锁定敌方、点击小队框切主控或拖拽矩形框选多名同伴指挥散开躲圈 |
| **锁定普攻 / 交互** | **敌方右键** / `F`（或近距右键） | 右键敌方锁定并开启自动平砍；靠近 NPC、引灵石碑、丹炉、五行禁制按 `F` 交互 |
| **战术凝时** | `Space`（空格键） | **仅在实时交战中生效**（弹窗与对话中 100% 屏蔽）：瞬间 0.0 倍速冻结全场读条与位移，支持从容拉框走位与预排破招 |
| **推进对白 / CG** | `Enter` 或 **鼠标左键点击卷轴** | 附带 `400ms` 切入防连点锁；已读对白支持按住 `Ctrl` 快进；分支道心抉择须主动点击选项 |
| **小队主控切换** | `F1 ~ F4` / `Tab` | `F1~F4` 瞬切 1~4 号阵位同伴（双击镜头居中）；`Tab` 智能优先锁定正在吟唱危招的敌方 |
| **核心战技栏** | `1 ~ 4` / `Q` / `E` / `R` / `G` | `1~4` 常驻循环（`1.5s` GCD）、`Q` 离轴秒断/位移、`E` 职责招牌技、`R` 本命古宝、`G` 双人羁绊合击【青莲引剑】 |
| **灵丹与奇门抽屉** | `5 ~ 6` / `Z` / `Ctrl+1 ~ 2` | `5~6` 战中瞬回丹药、`Z` 奇门阵图切换抽屉、`Ctrl+1/2` 灵宠手动护主与破敌技 |
| **Mouseover 悬停施法** | **鼠标悬停左下小队框 + 按技能键** | 无需切换当前敌方锁定目标，鼠标指谁即可对谁秒放治疗、护盾或净衣驱散 |
| **《万象道匣》与舆图** | `C` / `N` / `B` / `J` / `M` / `Esc` | 修行·兵甲 (`C`)、道途·奇门 (`N`)、行囊·剑匣 (`B`)、问道手札 (`J`)、手绘淡墨舆图 (`M`)、设置 (`Esc`) |

---

## 三、工程三层架构与目录导航

- `docs/design/` —— 全部 15 份定稿系统与关卡设计规格书（[`00-gdd.md`](docs/design/00-gdd.md) 至 [`40-vertical-slice-plan.md`](docs/design/40-vertical-slice-plan.md)）
- `docs/asset-manifest.json` & `assets_src/` —— 全量 149 项宋明工笔青绿山水美术与民乐音效资产的来源台账、SHA-256 校验值与原始分层母版
- `project/src/core_rules/` —— **第一层：纯数学与确定性规则核**（`StatLedger` 45/35/20 三桶账本与双曲递减、`FormationRules` 奇门阵法、`RtwpSimStep` RTwP 步进与五行相生破罡、`EconomyRules` 丹道控火与防套利公式，零场景节点依赖）
- `project/src/game_state/` —— **第二层：战役状态与持久化服务**（`DataDB`、`NotifyHub` 唯一四级通知中枢、`InputRouter` 唯一键鼠路由、`CampaignState`、`SaveManager` SHA-256 信封校验与 `.tmp`/`.bak` 零覆盖保护）
- `project/src/presentation/` —— **第三层：青岚三连无缝箱庭、RTwP 战场演出、古典器物 UI 与动态双轨民乐**
- `project/data/` & `project/locales/zh_CN.csv` —— 第一章完整结构化 JSON 配表与 503 条古典白话文本表

## 四、原型归档说明

原型仓库 `GOD-OF-PPT/chenyaun-v2` 已冻结归档；本仓遵循零历史包袱准则独立全新构建，未拷贝旧仓任何代码或未确权素材。详见 [`docs/design/32-prototype-migration.md`](docs/design/32-prototype-migration.md) 与 [`docs/reviews/slice-delivery-guide.md`](docs/reviews/slice-delivery-guide.md)。
