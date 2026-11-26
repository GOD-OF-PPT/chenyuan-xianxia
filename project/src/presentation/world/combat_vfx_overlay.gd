class_name CombatVfxOverlay
extends Node2D
## 第三层战场地面朱砂危招预警阵纹、战术凝时走位路径线与克制水墨法术特效渲染层
## 分为地面层（GroundVfxLayer，位于角色脚下）与空中层（SkyVfxLayer，位于角色上方）。

var is_ground_layer: bool = true

## 地面危招预警列表：{type: "circle"|"cone", origin: Vector2, dir: Vector2, radius: float, angle_deg: float, progress: float}
var active_telegraphs: Array[Dictionary] = []

## 战术凝时队员走位预览路径：[{from: Vector2, to: Vector2, label: String}]
var move_previews: Array[Dictionary] = []

## 战术凝时预排技能连线：[{from: Vector2, to: Vector2, skill_name: String, color: Color}]
var queued_skill_lines: Array[Dictionary] = []

## 瞬态水墨剑气/法术爆发环：[{kind: String, pos: Vector2, target_pos: Vector2, radius: float, color: Color, timer: float, duration: float}]
var transient_fx: Array[Dictionary] = []


func step_fx(combat_delta: float) -> void:
	if combat_delta > 0.0:
		for i: int in range(transient_fx.size() - 1, -1, -1):
			var fx: Dictionary = transient_fx[i]
			var rem: float = float(fx.get("timer", 0.0)) - combat_delta
			if rem <= 0.0:
				transient_fx.remove_at(i)
			else:
				fx["timer"] = rem
	queue_redraw()


func spawn_ring_burst(pos: Vector2, radius: float, col: Color, duration: float = 0.45) -> void:
	transient_fx.append({
		"kind": "ring",
		"pos": pos,
		"radius": radius,
		"color": col,
		"timer": duration,
		"duration": duration,
	})
	queue_redraw()


func spawn_beam_slash(from_pos: Vector2, to_pos: Vector2, col: Color, duration: float = 0.28) -> void:
	transient_fx.append({
		"kind": "beam",
		"pos": from_pos,
		"target_pos": to_pos,
		"color": col,
		"timer": duration,
		"duration": duration,
	})
	queue_redraw()


func _draw() -> void:
	var font: Font = UIThemeBuilder.get_bold_font()
	if font == null:
		font = ThemeDB.fallback_font

	if is_ground_layer:
		# 1. 绘制暗红朱砂八卦危招圆环 / 扇形阵纹（外框高亮，内圈按读条进度向外充盈，不遮挡脚底！）
		for tele: Dictionary in active_telegraphs:
			var kind: String = str(tele.get("type", "circle"))
			var orig: Vector2 = tele.get("origin", Vector2.ZERO) as Vector2
			var rad: float = float(tele.get("radius", 140.0))
			var prog: float = clampf(float(tele.get("progress", 0.0)), 0.0, 1.0)
			if kind == "cone":
				var dir: Vector2 = (tele.get("dir", Vector2.RIGHT) as Vector2).normalized()
				var half_rad: float = deg_to_rad(float(tele.get("angle_deg", 95.0)) * 0.5)
				var base_ang: float = dir.angle()
				_draw_telegraph_cone(orig, rad, base_ang - half_rad, base_ang + half_rad, prog)
			else:
				_draw_telegraph_circle(orig, rad, prog)

		# 2. 绘制右键/战术凝时走位路径线与青玉落点标
		for mp: Dictionary in move_previews:
			var p_from: Vector2 = mp.get("from", Vector2.ZERO) as Vector2
			var p_to: Vector2 = mp.get("to", Vector2.ZERO) as Vector2
			draw_dashed_line(p_from, p_to, Color(0.46, 0.86, 0.72, 0.85), 2.5, 10.0)
			draw_circle(p_to, 7.0, Color(0.32, 0.78, 0.62, 0.90))
			draw_arc(p_to, 13.0, 0.0, TAU, 24, Color(0.84, 0.94, 0.88, 0.85), 2.0)
			var lbl: String = str(mp.get("label", ""))
			if lbl != "":
				draw_string(font, p_to + Vector2(12.0, 5.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.84, 0.96, 0.90))
		return

	# ==================== 空中剑气与预排连线层 ====================
	for ql: Dictionary in queued_skill_lines:
		var q_from: Vector2 = ql.get("from", Vector2.ZERO) as Vector2
		var q_to: Vector2 = ql.get("to", Vector2.ZERO) as Vector2
		var q_col: Color = ql.get("color", UIThemeBuilder.COL_BRONZE_GOLD) as Color
		draw_dashed_line(q_from + Vector2(0.0, -56.0), q_to + Vector2(0.0, -56.0), q_col, 2.2, 8.0)
		var sname: String = str(ql.get("skill_name", ""))
		if sname != "":
			var mid: Vector2 = (q_from + q_to) * 0.5 + Vector2(-30.0, -64.0)
			draw_string(font, mid, "预排·" + sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, q_col)

	for fx: Dictionary in transient_fx:
		var fkind: String = str(fx.get("kind", "ring"))
		var dur: float = maxf(0.05, float(fx.get("duration", 0.4)))
		var rem: float = float(fx.get("timer", 0.0))
		var t: float = 1.0 - (rem / dur)
		var base_c: Color = fx.get("color", UIThemeBuilder.COL_BRONZE_GOLD) as Color
		var alpha: float = (1.0 - t) * 0.82
		if fkind == "ring":
			var center: Vector2 = fx.get("pos", Vector2.ZERO) as Vector2
			var max_r: float = float(fx.get("radius", 120.0))
			var cur_r: float = lerpf(max_r * 0.25, max_r, t)
			draw_arc(center, cur_r, 0.0, TAU, 36, Color(base_c.r, base_c.g, base_c.b, alpha), 4.5)
			draw_circle(center, cur_r * 0.85, Color(base_c.r, base_c.g, base_c.b, alpha * 0.18))
		elif fkind == "beam":
			var a_pt: Vector2 = (fx.get("pos", Vector2.ZERO) as Vector2) + Vector2(0.0, -54.0)
			var b_pt: Vector2 = (fx.get("target_pos", Vector2.ZERO) as Vector2) + Vector2(0.0, -54.0)
			draw_line(a_pt, b_pt, Color(0.12, 0.11, 0.10, alpha * 0.7), 8.0)
			draw_line(a_pt, b_pt, Color(base_c.r, base_c.g, base_c.b, alpha), 4.0)


func _draw_telegraph_circle(center: Vector2, radius: float, progress: float) -> void:
	# 35° 斜俯视椭圆压扁比 0.56，贴合青石地面透视！
	var ry_scale: float = 0.58
	var bg_pts: PackedVector2Array = _make_ellipse_poly(center, radius, radius * ry_scale, 32)
	draw_colored_polygon(bg_pts, Color(0.72, 0.22, 0.16, 0.16))
	if progress > 0.02:
		var fill_r: float = radius * progress
		var fill_pts: PackedVector2Array = _make_ellipse_poly(center, fill_r, fill_r * ry_scale, 32)
		draw_colored_polygon(fill_pts, Color(0.78, 0.24, 0.18, 0.30))
	# 八卦内刻度线与高对比朱砂亮边
	var ring_pts: PackedVector2Array = _make_ellipse_poly(center, radius, radius * ry_scale, 36)
	ring_pts.append(ring_pts[0])
	draw_polyline(ring_pts, Color(0.92, 0.32, 0.24, 0.92), 2.8, true)
	for i: int in range(8):
		var ang: float = (TAU * float(i)) / 8.0
		var p1: Vector2 = center + Vector2(cos(ang) * radius * 0.72, sin(ang) * radius * ry_scale * 0.72)
		var p2: Vector2 = center + Vector2(cos(ang) * radius * 0.92, sin(ang) * radius * ry_scale * 0.92)
		draw_line(p1, p2, Color(0.92, 0.36, 0.26, 0.65), 2.0)


func _draw_telegraph_cone(origin: Vector2, radius: float, a_start: float, a_end: float, progress: float) -> void:
	var steps: int = 24
	var outer_poly: PackedVector2Array = PackedVector2Array([origin])
	for i: int in range(steps + 1):
		var a: float = lerpf(a_start, a_end, float(i) / float(steps))
		outer_poly.append(origin + Vector2(cos(a) * radius, sin(a) * radius * 0.72))
	draw_colored_polygon(outer_poly, Color(0.72, 0.22, 0.16, 0.18))

	if progress > 0.02:
		var fill_r: float = radius * progress
		var fill_poly: PackedVector2Array = PackedVector2Array([origin])
		for i2: int in range(steps + 1):
			var a2: float = lerpf(a_start, a_end, float(i2) / float(steps))
			fill_poly.append(origin + Vector2(cos(a2) * fill_r, sin(a2) * fill_r * 0.72))
		draw_colored_polygon(fill_poly, Color(0.82, 0.25, 0.18, 0.34))

	var outline: PackedVector2Array = outer_poly.duplicate()
	outline.append(origin)
	draw_polyline(outline, Color(0.94, 0.34, 0.24, 0.94), 2.8, true)


func _make_ellipse_poly(c: Vector2, rx: float, ry: float, segs: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(segs):
		var a: float = (TAU * float(i)) / float(segs)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
