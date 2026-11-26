extends Control
## 标题主界面（Step 1 基础可启动骨架，后续里程碑挂载《问道凡尘》主题曲、水墨绘卷背景、读档与设置卷轴）

func _ready() -> void:
	theme = UIThemeBuilder.get_global_theme()
	InputRouter.set_mode(InputRouter.MODE_MODAL_MENU)
	_build_skeleton_if_empty()


func _build_skeleton_if_empty() -> void:
	if get_child_count() > 0:
		return
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UIThemeBuilder.COL_EBONY_DEEP
	add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	var title_lbl: Label = Label.new()
	title_lbl.text = tr("GAME_TITLE")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_TITLE)
	title_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	box.add_child(title_lbl)

	var sub_lbl: Label = Label.new()
	sub_lbl.text = tr("GAME_SUBTITLE")
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_SUBTITLE)
	box.add_child(sub_lbl)
