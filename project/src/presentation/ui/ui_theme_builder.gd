class_name UIThemeBuilder
extends RefCounted
## 第三层古典器物 UI 样式与字号规范工厂（乌木 · 旧宣 · 错金铜器 · 矿物五色）
## 严格对齐 docs/design/20-art-bible.md 第 3.2 节与 21-ui-ux-spec.md 第 4.1 节：
## 1080p 下锁死全局最小字号 FS_MIN = 16px，正文 18-20px，对白与标题 22-28px。

const FS_MIN: int = 16
const FS_BODY: int = 18
const FS_SUBTITLE: int = 20
const FS_DIALOGUE: int = 22
const FS_HEADER: int = 26
const FS_TITLE: int = 44

const COL_EBONY_BG: Color = Color("#1C1917")
const COL_EBONY_DEEP: Color = Color("#131110")
const COL_XUAN_PAPER: Color = Color("#D8CEBE")
const COL_XUAN_WARM: Color = Color("#E5DDD0")
const COL_INK_DARK: Color = Color("#201B18")
const COL_BRONZE_GOLD: Color = Color("#D6A85A")
const COL_BRONZE_DIM: Color = Color("#7D6339")
const COL_JADE_GREEN: Color = Color("#3E7B67")
const COL_WATER_BLUE: Color = Color("#2E5984")
const COL_CINNABAR_RED: Color = Color("#B84332")
const COL_EARTH_AMBER: Color = Color("#B58942")
const COL_MIASMA_PURPLE: Color = Color("#5A3352")
const COL_BLUE_STUNT: Color = Color("#8FD4E8")

static var _cached_regular_font: Font = null
static var _cached_bold_font: Font = null


static func get_regular_font() -> Font:
	if _cached_regular_font == null and ResourceLoader.exists("res://assets/fonts/NotoSerifCJKsc-Regular.otf"):
		_cached_regular_font = load("res://assets/fonts/NotoSerifCJKsc-Regular.otf") as Font
	if _cached_regular_font != null:
		return _cached_regular_font
	return ThemeDB.fallback_font


static func get_bold_font() -> Font:
	if _cached_bold_font == null and ResourceLoader.exists("res://assets/fonts/NotoSerifCJKsc-Bold.otf"):
		_cached_bold_font = load("res://assets/fonts/NotoSerifCJKsc-Bold.otf") as Font
	if _cached_bold_font != null:
		return _cached_bold_font
	return get_regular_font()


static func clear_cached_fonts() -> void:
	_cached_regular_font = null
	_cached_bold_font = null


static func bind_full_rect(ctrl: Control) -> void:
	var vp: Viewport = ctrl.get_viewport()
	var target_sz: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1920.0, 1080.0)
	if target_sz.x < 100.0 or target_sz.y < 100.0:
		target_sz = Vector2(1920.0, 1080.0)

	if ctrl.get_parent() is Control:
		ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ctrl.size = (ctrl.get_parent() as Control).size
	else:
		ctrl.anchor_left = 0.0
		ctrl.anchor_top = 0.0
		ctrl.anchor_right = 0.0
		ctrl.anchor_bottom = 0.0
		ctrl.position = Vector2.ZERO
		ctrl.custom_minimum_size = target_sz
		ctrl.size = target_sz
		if vp != null:
			vp.size_changed.connect(func() -> void:
				if is_instance_valid(ctrl) and ctrl.is_inside_tree():
					var nsz: Vector2 = ctrl.get_viewport_rect().size
					ctrl.custom_minimum_size = nsz
					ctrl.size = nsz
			)


static func get_global_theme() -> Theme:
	var th: Theme = Theme.new()
	th.default_font_size = FS_BODY
	th.default_font = get_regular_font()

	var btn_normal: StyleBoxFlat = make_ebony_box(Color(0.14, 0.12, 0.11, 0.94), COL_BRONZE_DIM, 2, 4)
	btn_normal.content_margin_left = 16.0
	btn_normal.content_margin_right = 16.0
	btn_normal.content_margin_top = 8.0
	btn_normal.content_margin_bottom = 8.0

	var btn_hover: StyleBoxFlat = make_ebony_box(Color(0.21, 0.18, 0.15, 0.98), COL_BRONZE_GOLD, 2, 4)
	btn_hover.content_margin_left = 16.0
	btn_hover.content_margin_right = 16.0
	btn_hover.content_margin_top = 8.0
	btn_hover.content_margin_bottom = 8.0

	var btn_pressed: StyleBoxFlat = make_ebony_box(Color(0.10, 0.09, 0.08, 1.0), COL_JADE_GREEN, 2, 4)
	btn_pressed.content_margin_left = 16.0
	btn_pressed.content_margin_right = 16.0
	btn_pressed.content_margin_top = 8.0
	btn_pressed.content_margin_bottom = 8.0

	var btn_disabled: StyleBoxFlat = make_ebony_box(Color(0.11, 0.10, 0.10, 0.65), Color(0.32, 0.28, 0.24, 0.5), 1, 4)
	btn_disabled.content_margin_left = 16.0
	btn_disabled.content_margin_right = 16.0
	btn_disabled.content_margin_top = 8.0
	btn_disabled.content_margin_bottom = 8.0

	th.set_stylebox("normal", "Button", btn_normal)
	th.set_stylebox("hover", "Button", btn_hover)
	th.set_stylebox("pressed", "Button", btn_pressed)
	th.set_stylebox("focus", "Button", btn_hover)
	th.set_stylebox("disabled", "Button", btn_disabled)
	th.set_color("font_color", "Button", COL_XUAN_WARM)
	th.set_color("font_hover_color", "Button", COL_BRONZE_GOLD)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.55, 0.52, 0.48, 0.8))
	th.set_font_size("font_size", "Button", FS_BODY)

	th.set_color("font_color", "Label", COL_XUAN_WARM)
	th.set_font_size("font_size", "Label", FS_BODY)
	th.set_font_size("normal_font_size", "RichTextLabel", FS_BODY)
	th.set_font_size("bold_font_size", "RichTextLabel", FS_BODY)

	var panel_sb: StyleBoxFlat = make_ebony_box(Color(0.11, 0.10, 0.09, 0.95), COL_BRONZE_DIM, 2, 6)
	th.set_stylebox("panel", "PanelContainer", panel_sb)

	return th


static func make_ebony_box(bg: Color, border: Color, border_w: int = 2, radius: int = 4) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.shadow_size = 6
	return sb


static func make_xuan_paper_box(border_col: Color = Color("#8C7352"), border_w: int = 2) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COL_XUAN_PAPER
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	sb.shadow_size = 8
	return sb


## 五行矿物色 + 无障碍双编码古篆徽章符号
static func get_element_color(elem: String) -> Color:
	match elem:
		"metal":
			return COL_BRONZE_GOLD
		"wood":
			return COL_JADE_GREEN
		"water":
			return Color("#6EA5C4")
		"fire":
			return COL_CINNABAR_RED
		"earth":
			return COL_EARTH_AMBER
		_:
			return COL_XUAN_WARM


static func get_element_dual_badge(elem: String) -> String:
	match elem:
		"metal":
			return "◇金"
		"wood":
			return "❖木"
		"water":
			return "≈水"
		"fire":
			return "▲火"
		"earth":
			return "■土"
		_:
			return "·凡"


const COL_BOSS_EBONY: Color = Color("#181513")
const COL_CARVED_EBONY: Color = Color("#292620")
const COL_HP_VERMILION: Color = Color("#B03A2E")
const COL_MP_CELADON: Color = Color("#3D7696")
const COL_CAST_AMBER: Color = Color("#D6A244")
const COL_CAST_LOCKED: Color = Color("#8E2822")
const COL_GILT_BRIGHT: Color = Color("#FCE088")


static func make_texture_or_ebony_box(
	tex_path: String,
	margin_l: int,
	margin_t: int,
	margin_r: int,
	margin_b: int,
	fallback_bg: Color,
	fallback_border: Color,
	border_w: int = 2,
	radius: int = 5
) -> StyleBox:
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		if tex != null:
			var sbt: StyleBoxTexture = StyleBoxTexture.new()
			sbt.texture = tex
			sbt.texture_margin_left = float(margin_l)
			sbt.texture_margin_top = float(margin_t)
			sbt.texture_margin_right = float(margin_r)
			sbt.texture_margin_bottom = float(margin_b)
			sbt.content_margin_left = float(margin_l)
			sbt.content_margin_top = float(margin_t)
			sbt.content_margin_right = float(margin_r)
			sbt.content_margin_bottom = float(margin_b)
			return sbt
	return make_ebony_box(fallback_bg, fallback_border, border_w, radius)

