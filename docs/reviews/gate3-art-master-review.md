# 闸门 3（Gate 3）· 宋明工笔青绿山水 1920×1080 视觉基准母版入库记录

- **日期**：2026-11-26
- **关联规范**：[`docs/design/20-art-bible.md`](../design/20-art-bible.md) · [`docs/design/31-content-pipeline.md`](../design/31-content-pipeline.md)
- **验收状态**：已完成五步精修管线、LUT 矿物校色与 `docs/asset-manifest.json` 100% SHA-256 溯源登记

## 四张 1920×1080 视觉基准样片清单

1. **样片 A ·【听雨镇烟雨街巷】**（`docs/reviews/gate3_masters/master_a_tingyu_town.png`）
   - 锚定 35° 斜俯视画卷透视、左上 45° 主天光、湿青石板与济世药庐青铜丹炉暖光、百年古樟 Y-Sort 空间关系及 5 头身顾长青/沈清禾站立比例。
2. **样片 B ·【苍木古窟无缝 RTwP 战斗】**（`docs/reviews/gate3_masters/master_b_cangmu_rtwp.png`）
   - 锚定 3 人小队 + 青岚火狐围战【雾隐狼王】同屏尺度、顶部木灵护罡与琥珀金可打断读条、地面朱砂八卦危招预警圈、左下悬停施法小队框及底部乌木错金快捷栏。
3. **样片 C ·【破庙立绘演剧对话】**（`docs/reviews/gate3_masters/master_c_temple_stage.png`）
   - 锚定雨夜破庙演剧舞台、顾长青（手按暗青断玉剑匣）与裴照（汉白泥金剑袍）半身工笔立绘同台质感、底部乌木旧宣纸卷轴与 `≥22px` 清晰宋体排版。
4. **样片 D ·【万象道匣·修行五维与五槽装备面板】**（`docs/reviews/gate3_masters/master_d_dao_casket.png`）
   - 锚定顶栏页签收束、左列水墨经脉境界图、中列 5 槽器物与五维潜能、右列真实递减面板与梦幻蓝字灵佩对比卷轴。

## 资产统计与溯源状态
- 已入库美术与音画总条目：**149 项**（含 2 款 SIL OFL 1.1 开源宋体字库、4 张 1080p 视觉母版、31 张 `1024×1280` 半身立绘及情绪战损差分、5 张 1080p 标题与破庙 4 层视差动态 CG、20 项 35° 斜俯视无缝地表与 Y-Sort 独立建筑古树交互器物、10 套多部位骨骼步态斜向关键帧序列图集、49 枚工笔图标/五行古篆双编码印章/玉簪剑锋鼠标指针、28 条实录采样民乐分轨与四级响度拟音音效）。
- 全部原始母稿、MIDI 总谱与合成源留存于 `assets_src/`，并通过 `python3 tools/manifest_guard.py --check` 零遗漏校验。
