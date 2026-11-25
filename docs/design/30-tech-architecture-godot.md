# 30 · 《尘缘问道》Godot 4 技术架构规范（Technical Architecture）

- **文档版本**：v1.0（基于 2026-11-25 访谈技术拍板编制）
- **状态**：已定稿
- **前置依赖**：[`00-gdd.md`](00-gdd.md) · [`10-combat-system.md`](10-combat-system.md) · [`11-progression-and-math.md`](11-progression-and-math.md) · [`21-ui-ux-spec.md`](21-ui-ux-spec.md)
- **下游文档**：[`31-content-pipeline.md`](31-content-pipeline.md) · `40-vertical-slice-plan.md`

---

## 1. 设计目标

1. **三层严格解耦，根除“35,000 行意大利面条单文件”历史包袱**：全工程使用 **Godot 4.3+ 强类型 GDScript（开启 `untyped_declaration = error` 静态检查）**，物理隔离 **`core_rules`（纯数学战斗与经济规则） → `game_state`（运行时与存档状态） → `presentation`（2D 场景与 UI 表现）**，既支持毫秒级命令行无头战斗仿真（闸门 2），又 100% 无缝导出 Steam PC（Windows/Linux/macOS）与早期试玩 Web（WASM）。
2. **坚如磐石的 40–60 小时单机存档安全体系**：完整吸收原型 M7b 沉淀的容错经验，建立版本化 JSON 信封、`.tmp` 原子落盘、`.bak` 自动滚动备份与读档损坏零覆盖保护。

---

## 2. 工程目录与三层物理隔离规范

Godot 工程根目录位于仓库 `project/`，严格执行单向依赖（`presentation` → `game_state` → `core_rules`，**严禁反向引用**）：

```
project/
├── data/                    # 只读 JSON 配表源（技能、阵法、装备、丹方、怪物、对话）
├── locales/                 # 本地化 CSV / PO 翻译表（zh_CN 基准，预留 zh_TW / en）
├── src/
│   ├── core_rules/          # 【第一层：纯逻辑规则层（继承 RefCounted，0 Node2D/UI 引用！）】
│   │   ├── stat_ledger.gd   # 45/35/20 三桶属性账本与四绿字递减公式
│   │   ├── rtwp_sim_step.gd # GCD、吟唱打断、杀意仇恨表、五行破罡与相生母印结算核
│   │   ├── formation_rules.gd # 奇门五阵光环与阵阵相克纯函数
│   │   └── economy_rules.gd # 灵石买卖、炼丹提纯与炼器回炉公式
│   ├── game_state/          # 【第二层：状态与服务层（Autoload 单例严格限 5 个以内）】
│   │   ├── campaign_state.gd# 当前队伍、行囊、剑匣槽、声望、手札与因果签状态树
│   │   ├── save_manager.gd  # 版本化 JSON 信封读写、原子替换与迁移链
│   │   ├── input_router.gd  # 唯一 PC 键鼠映射路由与状态互斥锁（战斗/对话/凝时）
│   │   └── notify_hub.gd    # 唯一通知中枢四级仲裁队列
│   └── presentation/        # 【第三层：表现与场景层（Node2D / Control）】
│       ├── world/           # 四层 Y-Sort 区域无缝箱庭、明雷视野与引灵石碑
│       ├── actors/          # 角色/灵宠/首领状态机动画与头顶杀意姓名板
│       ├── ui/              # 魔兽式 HUD、悬停施法框体、《万象道匣》5页签、立绘演剧台
│       └── audio/           # 双轨同 BPM 动态混音器与空格凝时低通滤波器
└── tests/                   # GUT / 命令行无头单元测试、仿真矩阵与 UI 静态扫描
```

---

## 3. 核心架构机制

### 3.1 无缝 RTwP 逻辑帧与【战术凝时】时钟解耦

- 战斗核 `rtwp_sim_step.gd` 驱动一套独立的**战术逻辑时钟 `combat_delta`**（与引擎 UI 帧率 `process_delta` 分离）：
  - 常态实时战斗：`combat_delta = physics_delta`（固定 60 Hz 确定性步进）；
  - 按下 `Space` 开启【战术凝时】：`combat_scale = 0.0`（战场实体移动、GCD、读条吟唱 100% 精准冻结），但 **UI 层、摄像机微移、鼠标左键框选与路径预览线、技能预排队列仍以满帧率丝滑响应**！
- **场景纪元守卫（`scene_epoch`）**：每次跨区域切换、读档或退回引灵石碑时递增全局 `scene_epoch: int`；任何异步延迟回调（如 0.8s 清场收束计时器）触发前必校验 `epoch == current_epoch`，从根源杜绝跨场景残留飘字或野指针报错。

### 3.2 版本化 JSON 信封存档与 9 条安全铁律

存档目录位于 `user://saves/`（对齐 Steam Auto-Cloud 路径规范），严禁使用存在代码注入风险与重构脆弱性的二进制 `.res/.tres` 存档：

1. **信封结构（Envelope Schema）**：
   ```json
   {
     "magic": "CHENYUAN_XIANXIA_SAVE",
     "schema_version": 1,
     "game_build": "0.1.0-slice",
     "saved_at_utc": "2026-11-25T08:00:00Z",
     "chapter_id": "ch01_qinglan",
     "summary": { "realm": "炼气二层", "location": "苍木古窟·石碑", "playtime_sec": 4820 },
     "checksum_sha256": "...",
     "payload": { ... }
   }
   ```
2. **原子写入与双备份（防断电/崩溃坏档）**：保存时先写入 `slot_01.json.tmp` 并刷盘校验，再将原 `slot_01.json` 轮转为 `slot_01.json.bak`，最后原子重命名 `.tmp` → `.json`。
3. **损坏零覆盖铁律**：若文件被外部篡改或损坏导致 JSON 解析/校验失败，**严禁静默新建空档覆盖原文件**！立即弹出 P0 警报框提供【尝试加载自动 `.bak` 备份】【打开存档文件夹保留原文件】选项。
4. **纯单向版本迁移链**：每次结构升级编写纯函数 `migrate_v1_to_v2(dict)`，确保早期存档跨版本平滑续玩且绝不回溯削弱玩家已获装备。
5. **非正式模式硬隔离**：无头仿真器、开发调试沙盒运行在独立内存实例 `sandbox://`，物理禁用写入 `user://saves/`。

### 3.3 全文本本地化抽取规范

- 严禁在 `.gd` 脚本或 `.tscn` 按钮属性中硬编码裸中文业务文案；全部通过 `tr("UI_BTN_ENTER_CONTINUE")` 或数据表 `text_key` 索引 `locales/zh_CN.csv`，确保日后导出繁体中文与英文版零代码重构。

---

## 4. 性能预算与自动化测试门禁

- **性能硬指标（1920×1080 标准独显/主流核显 PC）**：无缝箱庭探索与 5v6 首领团战稳定 **`60 FPS`（帧时间 P95 < 14.0ms）**；区域切换加载耗时 `< 1.5s`；Web 试玩切片首包压缩体积控制在 `< 85 MB`。
- **四层自动化 CI 门禁（每次 PR 必跑 `godot --headless`）**：
  1. `test_unit`：验证三桶属性账本、四绿字递减、五行破罡连携、仇恨 OT 阈值与存档损坏恢复；
  2. `combat_sim_matrix`（闸门 2）：固定随机种子跑通各章标准/毕业/乱按对照矩阵；
  3. `audit_data_and_economy`：配表外键完整性 + 零买拆套利审计；
  4. `audit_ui_and_manifest`：扫描全部 `.tscn` 确保无 `< 16px` 字号、无 `Space` 绑定对话按钮，且全部美术音频哈希与 `manifest` 100% 匹配。

---

## 5. 决策记录（2026-11-25 访谈确认）

| 编号 | 议题 | 拍板结论 |
|---|---|---|
| TA-01 | 引擎语言与分层架构 | Godot 4.3+ 纯强类型 GDScript + `core_rules / game_state / presentation` 三层物理隔离，兼顾毫秒级无头仿真与 PC/Web 双端无痛导出 |
| TA-02 | 存档安全架构 | 纯数据版本化 JSON 信封（SHA-256 校验 + `.tmp` 原子写入 + `.bak` 备份 + 损坏零覆盖保护 + 20 手动槽/3 自动槽） |
