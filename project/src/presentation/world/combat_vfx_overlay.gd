class_name CombatVfxOverlay
extends Node2D
## 第三层战场地面朱砂八卦危招阵纹、战术凝时走位路径线与宋明工笔水墨/矿物法术特效渲染层
## 分为地面层（GroundVfxLayer，z_index = 0，位于角色脚下）与空中层（SkyVfxLayer，z_index = 4，位于精灵之上且低于头顶 z=6 读条）。
## 严格遵循：
## - 全层与子粒子/刀光统一 UNSHADED（不受场景 CanvasModulate 压暗；水墨飞白采用 BLEND_MODE_MIX 保留浓墨笔触）
## - Space 战术凝时、Hitstop 顿帧与模态界面期间 GPUParticles2D（interpolate=false, fixed_fps=0, speed_scale=0）100% 零漂移定格。

const PERSPECTIVE_Y_RATIO: float = 0.44
const CONE_Y_RATIO: float = 0.46
const PROJECTILE_POOL_SIZE: int = 24
const SLASH_POOL_SIZE: int = 20
const RIBBON_POOL_SIZE: int = 16
const SHOCKWAVE_POOL_SIZE: int = 14
const PARTICLE_POOL_SIZE: int = 16

var is_ground_layer: bool = true

## 地面危招预警列表：{type: "circle"|"cone", origin: Vector2, dir: Vector2, radius: float, angle_deg: float, progress: float, interruptible: bool}
var active_telegraphs: Array[Dictionary] = []

## 战术凝时队员走位预览路径：[{from: Vector2, to: Vector2, label: String}]
var move_previews: Array[Dictionary] = []

## 战术凝时预排技能连线：[{from: Vector2, to: Vector2, skill_name: String, color: Color}]
var queued_skill_lines: Array[Dictionary] = []

## 兼容旧字段（不再绘制简陋直线/圆环）
var transient_fx: Array[Dictionary] = []

## 地面青玉水波点击落点（由实时 ui_delta 驱动，Space 战术凝时期间依然灵动扩散）
var _move_ripples: Array[Dictionary] = []
var _last_ripple_frame: int = -1
var _jade_ripple_tex: Texture2D = null
var _telegraph_pulse_clock: float = 0.0
var _stepped_combat_this_frame: bool = false

## 空中特效对象池与活跃槽位
var _pools_initialized: bool = false
var _projectile_pool: Array[Dictionary] = []
var _slash_pool: Array[Dictionary] = []
var _ribbon_pool: Array[Dictionary] = []
var _shockwave_pool: Array[Dictionary] = []
var _particle_pool: Array[Dictionary] = []
var _pending_spawns: Array[Dictionary] = []

var _mat_unshaded_mix: CanvasItemMaterial = null
var _mat_unshaded_add: CanvasItemMaterial = null
var _slash_shader: Shader = null
var _trail_width_curve: Curve = null
var _tex_cache: Dictionary = {}
var _ppm_cache: Dictionary = {}


func _ready() -> void:
	process_priority = 10
	material = _get_unshaded_mix_material()
	if is_ground_layer and ResourceLoader.exists("res://assets/ui/icons/casket_jade_ripple.png"):
		_jade_ripple_tex = load("res://assets/ui/icons/casket_jade_ripple.png") as Texture2D
	if not is_ground_layer:
		z_index = 4
		_init_sky_pools()


func _process(delta: float) -> void:
	if is_ground_layer and not _move_ripples.is_empty():
		_advance_move_ripples(delta)
		queue_redraw()


func _physics_process(_delta: float) -> void:
	if not is_ground_layer and _pools_initialized:
		if not _stepped_combat_this_frame:
			for slot: Dictionary in _particle_pool:
				if bool(slot.get("active", false)):
					var gp: GPUParticles2D = slot["node"] as GPUParticles2D
					if gp.speed_scale != 0.0:
						gp.speed_scale = 0.0
		_stepped_combat_this_frame = false


func _get_unshaded_mix_material() -> CanvasItemMaterial:
	if _mat_unshaded_mix == null:
		_mat_unshaded_mix = CanvasItemMaterial.new()
		_mat_unshaded_mix.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_mat_unshaded_mix.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	return _mat_unshaded_mix


func _get_unshaded_add_material() -> CanvasItemMaterial:
	if _mat_unshaded_add == null:
		_mat_unshaded_add = CanvasItemMaterial.new()
		_mat_unshaded_add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_mat_unshaded_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _mat_unshaded_add


func _get_slash_shader() -> Shader:
	if _slash_shader == null and ResourceLoader.exists("res://src/presentation/shaders/vfx_slash_wipe.gdshader"):
		_slash_shader = load("res://src/presentation/shaders/vfx_slash_wipe.gdshader") as Shader
	return _slash_shader


func _get_trail_width_curve() -> Curve:
	if _trail_width_curve == null:
		_trail_width_curve = Curve.new()
		_trail_width_curve.add_point(Vector2(0.0, 0.14))
		_trail_width_curve.add_point(Vector2(0.65, 0.72))
		_trail_width_curve.add_point(Vector2(1.0, 1.0))
	return _trail_width_curve


func _get_vfx_tex(rel_name: String) -> Texture2D:
	if _tex_cache.has(rel_name):
		return _tex_cache[rel_name] as Texture2D
	var full_p: String = "res://assets/vfx/" + rel_name
	if ResourceLoader.exists(full_p):
		var t: Texture2D = load(full_p) as Texture2D
		if t != null:
			_tex_cache[rel_name] = t
			return t
	return null


func _init_sky_pools() -> void:
	if _pools_initialized:
		return
	_pools_initialized = true
	var mix_mat: CanvasItemMaterial = _get_unshaded_mix_material()
	var trail_tex: Texture2D = _get_vfx_tex("vfx_sword_trail_ribbon.png")
	var w_curve: Curve = _get_trail_width_curve()
	var sl_sh: Shader = _get_slash_shader()

	# 1. Projectiles + Line2D wake ribbons
	for _i: int in range(PROJECTILE_POOL_SIZE):
		var line: Line2D = Line2D.new()
		line.visible = false
		line.material = mix_mat
		line.width = 20.0
		line.width_curve = w_curve
		line.texture = trail_tex
		line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(line)

		var spr: Sprite2D = Sprite2D.new()
		spr.visible = false
		spr.material = mix_mat
		add_child(spr)

		_projectile_pool.append({
			"active": false,
			"sprite": spr,
			"trail": line,
			"from_pos": Vector2.ZERO,
			"to_pos": Vector2.ZERO,
			"elapsed": 0.0,
			"duration": 0.18,
			"arc_height": 16.0,
			"elem": "metal",
			"spawn_impact_arc": false,
			"trail_pts": [],
		})

	# 2. Curved calligraphic & blazing-fire slash arcs (individual ShaderMaterial per slot)
	for _j: int in range(SLASH_POOL_SIZE):
		var s_spr: Sprite2D = Sprite2D.new()
		s_spr.visible = false
		var smat: ShaderMaterial = ShaderMaterial.new()
		smat.resource_local_to_scene = true
		if sl_sh != null:
			smat.shader = sl_sh
		s_spr.material = smat
		add_child(s_spr)

		_slash_pool.append({
			"active": false,
			"sprite": s_spr,
			"mat": smat,
			"elapsed": 0.0,
			"duration": 0.25,
			"base_scale": Vector2.ONE,
		})

	# 3. Swirling celadon/elemental silk qi ribbons
	var rib_tex: Texture2D = _get_vfx_tex("vfx_wood_qi_ribbon.png")
	for _k: int in range(RIBBON_POOL_SIZE):
		var r_spr: Sprite2D = Sprite2D.new()
		r_spr.visible = false
		r_spr.material = mix_mat
		r_spr.texture = rib_tex
		add_child(r_spr)

		_ribbon_pool.append({
			"active": false,
			"sprite": r_spr,
			"anchor": null,
			"base_pos": Vector2.ZERO,
			"elapsed": 0.0,
			"duration": 0.55,
			"rot_speed": 3.4,
			"rise_px": 28.0,
			"base_scale": 0.85,
			"base_col": Color.WHITE,
		})

	# 4. Calligraphic foreshortened shockwave brush rings
	var sw_tex: Texture2D = _get_vfx_tex("vfx_shockwave_ink_ring.png")
	for _m: int in range(SHOCKWAVE_POOL_SIZE):
		var w_spr: Sprite2D = Sprite2D.new()
		w_spr.visible = false
		w_spr.material = mix_mat
		w_spr.texture = sw_tex
		add_child(w_spr)

		_shockwave_pool.append({
			"active": false,
			"sprite": w_spr,
			"elapsed": 0.0,
			"duration": 0.42,
			"max_radius": 140.0,
			"base_col": Color.WHITE,
		})

	# 5. Pooled GPUParticles2D (100% deterministic pause freeze: interpolate=false, fixed_fps=0)
	for _p: int in range(PARTICLE_POOL_SIZE):
		var gp: GPUParticles2D = GPUParticles2D.new()
		gp.visible = false
		gp.emitting = false
		gp.one_shot = true
		gp.explosiveness = 0.88
		gp.preprocess = 0.03
		gp.local_coords = false
		gp.interpolate = false
		gp.fixed_fps = 0
		gp.material = mix_mat
		add_child(gp)

		_particle_pool.append({
			"active": false,
			"node": gp,
			"remaining": 0.0,
		})


func clear_all_fx() -> void:
	active_telegraphs.clear()
	move_previews.clear()
	queued_skill_lines.clear()
	transient_fx.clear()
	_move_ripples.clear()
	_pending_spawns.clear()

	if _pools_initialized:
		for p_slot: Dictionary in _projectile_pool:
			p_slot["active"] = false
			(p_slot["sprite"] as Sprite2D).visible = false
			var tr_l: Line2D = p_slot["trail"] as Line2D
			tr_l.clear_points()
			tr_l.visible = false
		for s_slot: Dictionary in _slash_pool:
			s_slot["active"] = false
			(s_slot["sprite"] as Sprite2D).visible = false
		for r_slot: Dictionary in _ribbon_pool:
			r_slot["active"] = false
			r_slot["anchor"] = null
			(r_slot["sprite"] as Sprite2D).visible = false
		for w_slot: Dictionary in _shockwave_pool:
			w_slot["active"] = false
			(w_slot["sprite"] as Sprite2D).visible = false
		for gp_slot: Dictionary in _particle_pool:
			gp_slot["active"] = false
			gp_slot["remaining"] = 0.0
			var gp: GPUParticles2D = gp_slot["node"] as GPUParticles2D
			gp.emitting = false
			gp.speed_scale = 0.0
			gp.visible = false
	queue_redraw()


func _advance_move_ripples(dt: float) -> void:
	if dt <= 0.0 or _move_ripples.is_empty():
		return
	var cur_pf: int = Engine.get_process_frames()
	if cur_pf == _last_ripple_frame:
		return
	_last_ripple_frame = cur_pf
	var step_dt: float = clampf(dt, 0.022, 0.042)
	for i: int in range(_move_ripples.size() - 1, -1, -1):
		var rp: Dictionary = _move_ripples[i]
		var next_e: float = float(rp.get("elapsed", 0.0)) + step_dt
		if next_e >= float(rp.get("duration", 0.52)):
			_move_ripples.remove_at(i)
		else:
			rp["elapsed"] = next_e


func step_fx(combat_delta: float, ui_delta: float = 0.0) -> void:
	if is_ground_layer:
		if ui_delta > 0.0:
			_advance_move_ripples(ui_delta)
		if combat_delta > 0.0:
			_telegraph_pulse_clock += combat_delta
		queue_redraw()
		return

	_init_sky_pools()
	_stepped_combat_this_frame = (combat_delta > 0.0)

	# 1. Step GPUParticles2D freeze/speed_scale & combat_delta lifetime
	var p_speed: float = 1.0 if combat_delta > 0.0 else 0.0
	for gp_slot: Dictionary in _particle_pool:
		if not bool(gp_slot.get("active", false)):
			continue
		var gp: GPUParticles2D = gp_slot["node"] as GPUParticles2D
		if gp.speed_scale != p_speed:
			gp.speed_scale = p_speed
		if combat_delta > 0.0:
			var rem: float = float(gp_slot.get("remaining", 0.0)) - combat_delta
			if rem <= 0.0:
				gp_slot["active"] = false
				gp.emitting = false
				gp.speed_scale = 0.0
				gp.visible = false
			else:
				gp_slot["remaining"] = rem

	if combat_delta > 0.0:
		# 2. Step delayed multi-sword / flurry spawns
		for d_i: int in range(_pending_spawns.size() - 1, -1, -1):
			var pend: Dictionary = _pending_spawns[d_i]
			var d_rem: float = float(pend.get("delay", 0.0)) - combat_delta
			if d_rem <= 0.0:
				var p_copy: Dictionary = pend.duplicate()
				_pending_spawns.remove_at(d_i)
				_dispatch_pending_spawn(p_copy)
			else:
				pend["delay"] = d_rem

		# 3. Step flying swords / needles / elemental bolts + Line2D wake ribbons
		for p_slot: Dictionary in _projectile_pool:
			if not bool(p_slot.get("active", false)):
				continue
			var el: float = float(p_slot.get("elapsed", 0.0)) + combat_delta
			var dur: float = maxf(0.05, float(p_slot.get("duration", 0.18)))
			var t: float = clampf(el / dur, 0.0, 1.0)
			var spr: Sprite2D = p_slot["sprite"] as Sprite2D
			var tr_line: Line2D = p_slot["trail"] as Line2D
			var p0: Vector2 = p_slot["from_pos"] as Vector2
			var p1: Vector2 = p_slot["to_pos"] as Vector2
			var arc_h: float = float(p_slot.get("arc_height", 16.0))

			var cur_pos: Vector2 = p0.lerp(p1, t) + Vector2(0.0, -arc_h * sin(t * PI))
			var prev_t: float = maxf(0.0, t - 0.06)
			var prev_pos: Vector2 = p0.lerp(p1, prev_t) + Vector2(0.0, -arc_h * sin(prev_t * PI))
			var tang: Vector2 = cur_pos - prev_pos
			if tang.length_squared() < 0.001:
				tang = p1 - p0
			spr.position = cur_pos
			spr.rotation = tang.angle()

			var pts: Array = p_slot["trail_pts"] as Array
			pts.append(cur_pos)
			if pts.size() > 10:
				pts.pop_front()
			tr_line.clear_points()
			for pt_v: Variant in pts:
				tr_line.add_point(pt_v as Vector2)

			if el >= dur:
				var elem_s: String = str(p_slot.get("elem", "metal"))
				if bool(p_slot.get("spawn_impact_arc", false)):
					var imp_style: String = "fire_blade" if elem_s == "fire" else ("water_frost" if elem_s == "water" else ("wood_gale" if elem_s == "wood" else "ink_cyan"))
					spawn_slash_arc(p1, tang, imp_style, 82.0, 0.20, false)
				spawn_particle_burst(p1, _hit_preset_for_elem(elem_s), 7)
				p_slot["active"] = false
				spr.visible = false
				tr_line.clear_points()
				tr_line.visible = false
			else:
				p_slot["elapsed"] = el

		# 4. Step curved slash arcs (sweep_progress uniform driven by combat_delta)
		for s_slot: Dictionary in _slash_pool:
			if not bool(s_slot.get("active", false)):
				continue
			var s_el: float = float(s_slot.get("elapsed", 0.0)) + combat_delta
			var s_dur: float = maxf(0.06, float(s_slot.get("duration", 0.25)))
			var s_spr: Sprite2D = s_slot["sprite"] as Sprite2D
			var smat: ShaderMaterial = s_slot["mat"] as ShaderMaterial
			if s_el >= s_dur:
				s_slot["active"] = false
				s_spr.visible = false
			else:
				s_slot["elapsed"] = s_el
				var prog_s: float = clampf(s_el / s_dur, 0.0, 1.0)
				smat.set_shader_parameter("sweep_progress", prog_s)
				var b_sc: Vector2 = s_slot["base_scale"] as Vector2
				s_spr.scale = b_sc * lerpf(0.88, 1.08, prog_s)

		# 5. Step swirling wood/elemental qi ribbons
		for r_slot: Dictionary in _ribbon_pool:
			if not bool(r_slot.get("active", false)):
				continue
			var r_el: float = float(r_slot.get("elapsed", 0.0)) + combat_delta
			var r_dur: float = maxf(0.10, float(r_slot.get("duration", 0.55)))
			var r_spr: Sprite2D = r_slot["sprite"] as Sprite2D
			if r_el >= r_dur:
				r_slot["active"] = false
				r_slot["anchor"] = null
				r_spr.visible = false
			else:
				r_slot["elapsed"] = r_el
				var rt: float = clampf(r_el / r_dur, 0.0, 1.0)
				var anch_raw: Variant = r_slot.get("anchor", null)
				var base_p: Vector2 = r_slot["base_pos"] as Vector2
				if anch_raw != null and is_instance_valid(anch_raw):
					var ba: BattleActor = anch_raw as BattleActor
					base_p = ba.get_vfx_origin_world("chest")
				r_spr.position = base_p + Vector2(0.0, -float(r_slot.get("rise_px", 28.0)) * rt)
				r_spr.rotation += float(r_slot.get("rot_speed", 3.4)) * combat_delta
				var sc_r: float = float(r_slot.get("base_scale", 0.85)) * lerpf(0.82, 1.14, rt)
				r_spr.scale = Vector2(sc_r, sc_r * 0.72)
				var env_r: float = sin(rt * PI)
				var bc: Color = r_slot["base_col"] as Color
				r_spr.modulate = Color(bc.r, bc.g, bc.b, clampf(bc.a * env_r * 1.25, 0.0, 1.0))

		# 6. Step foreshortened calligraphic shockwave rings
		for w_slot: Dictionary in _shockwave_pool:
			if not bool(w_slot.get("active", false)):
				continue
			var w_el: float = float(w_slot.get("elapsed", 0.0)) + combat_delta
			var w_dur: float = maxf(0.08, float(w_slot.get("duration", 0.42)))
			var w_spr: Sprite2D = w_slot["sprite"] as Sprite2D
			if w_el >= w_dur:
				w_slot["active"] = false
				w_spr.visible = false
			else:
				w_slot["elapsed"] = w_el
				var wt: float = clampf(w_el / w_dur, 0.0, 1.0)
				var ease_w: float = 1.0 - pow(1.0 - wt, 2.4)
				var cur_rad: float = lerpf(float(w_slot.get("max_radius", 140.0)) * 0.24, float(w_slot.get("max_radius", 140.0)), ease_w)
				var sx: float = (cur_rad * 2.0) / 236.0
				w_spr.scale = Vector2(sx, sx * 0.46)
				var wc: Color = w_slot["base_col"] as Color
				w_spr.modulate = Color(wc.r, wc.g, wc.b, clampf((1.0 - wt) * wc.a * 0.92, 0.0, 1.0))

	queue_redraw()


func _dispatch_pending_spawn(pend: Dictionary) -> void:
	var kind: String = str(pend.get("kind", ""))
	if kind == "sword":
		spawn_sword_projectile(
			pend["from_pos"] as Vector2,
			pend["to_pos"] as Vector2,
			str(pend.get("elem", "metal")),
			float(pend.get("duration", 0.17)),
			float(pend.get("arc_height", 18.0)),
			float(pend.get("sword_scale", 0.92)),
			0.0,
			bool(pend.get("spawn_impact_arc", true))
		)
	elif kind == "needle":
		spawn_needle_projectile(
			pend["from_pos"] as Vector2,
			pend["to_pos"] as Vector2,
			str(pend.get("elem", "wood")),
			float(pend.get("duration", 0.16)),
			0.0
		)
	elif kind == "slash":
		spawn_slash_arc(
			pend["origin_pos"] as Vector2,
			pend["dir"] as Vector2,
			str(pend.get("style", "ink_cyan")),
			float(pend.get("radius_px", 108.0)),
			float(pend.get("duration", 0.25)),
			bool(pend.get("flip_v", false)),
			0.0
		)


## ==================== 公开特效生成接口（全类型安全） ====================
func spawn_move_ripple(world_pos: Vector2) -> void:
	if _move_ripples.size() >= 8:
		_move_ripples.pop_front()
	_move_ripples.append({
		"pos": world_pos,
		"elapsed": 0.0,
		"duration": 0.52,
	})
	queue_redraw()


func spawn_sword_projectile(
	from_pos: Vector2,
	to_pos: Vector2,
	elem: String = "metal",
	duration: float = 0.17,
	arc_height: float = 18.0,
	sword_scale: float = 0.92,
	delay_sec: float = 0.0,
	spawn_impact_arc: bool = true
) -> void:
	if is_ground_layer:
		return
	if delay_sec > 0.001:
		_pending_spawns.append({
			"kind": "sword",
			"delay": delay_sec,
			"from_pos": from_pos,
			"to_pos": to_pos,
			"elem": elem,
			"duration": duration,
			"arc_height": arc_height,
			"sword_scale": sword_scale,
			"spawn_impact_arc": spawn_impact_arc,
		})
		return

	_init_sky_pools()
	var slot: Dictionary = _acquire_pool_slot(_projectile_pool)
	var spr: Sprite2D = slot["sprite"] as Sprite2D
	var tr_l: Line2D = slot["trail"] as Line2D
	spr.texture = _get_vfx_tex("vfx_flying_sword_qi.png")
	spr.scale = Vector2(sword_scale, sword_scale)
	spr.modulate = _projectile_tint_for_elem(elem)
	spr.position = from_pos
	spr.rotation = (to_pos - from_pos).angle()
	spr.visible = true

	tr_l.width = 22.0 * sword_scale
	tr_l.default_color = _trail_color_for_elem(elem)
	tr_l.clear_points()
	tr_l.add_point(from_pos)
	tr_l.visible = true

	slot["active"] = true
	slot["from_pos"] = from_pos
	slot["to_pos"] = to_pos
	slot["elapsed"] = 0.0
	slot["duration"] = maxf(0.08, duration)
	slot["arc_height"] = arc_height
	slot["elem"] = elem
	slot["spawn_impact_arc"] = spawn_impact_arc
	slot["trail_pts"] = [from_pos]


func spawn_needle_projectile(
	from_pos: Vector2,
	to_pos: Vector2,
	elem: String = "wood",
	duration: float = 0.16,
	delay_sec: float = 0.0
) -> void:
	if is_ground_layer:
		return
	if delay_sec > 0.001:
		_pending_spawns.append({
			"kind": "needle",
			"delay": delay_sec,
			"from_pos": from_pos,
			"to_pos": to_pos,
			"elem": elem,
			"duration": duration,
		})
		return

	_init_sky_pools()
	var slot: Dictionary = _acquire_pool_slot(_projectile_pool)
	var spr: Sprite2D = slot["sprite"] as Sprite2D
	var tr_l: Line2D = slot["trail"] as Line2D
	spr.texture = _get_vfx_tex("vfx_silver_needle.png")
	spr.scale = Vector2(0.88, 0.88)
	spr.modulate = _projectile_tint_for_elem(elem)
	spr.position = from_pos
	spr.rotation = (to_pos - from_pos).angle()
	spr.visible = true

	tr_l.width = 12.0
	tr_l.default_color = _trail_color_for_elem(elem)
	tr_l.clear_points()
	tr_l.add_point(from_pos)
	tr_l.visible = true

	slot["active"] = true
	slot["from_pos"] = from_pos
	slot["to_pos"] = to_pos
	slot["elapsed"] = 0.0
	slot["duration"] = maxf(0.08, duration)
	slot["arc_height"] = 10.0
	slot["elem"] = elem
	slot["spawn_impact_arc"] = false
	slot["trail_pts"] = [from_pos]


func spawn_element_bolt(from_pos: Vector2, to_pos: Vector2, elem: String = "fire", duration: float = 0.20) -> void:
	if is_ground_layer:
		return
	_init_sky_pools()
	var slot: Dictionary = _acquire_pool_slot(_projectile_pool)
	var spr: Sprite2D = slot["sprite"] as Sprite2D
	var tr_l: Line2D = slot["trail"] as Line2D
	spr.texture = _get_vfx_tex("vfx_particle_ink_drop.png" if elem == "miasma" else "vfx_particle_spark.png")
	spr.scale = Vector2(0.72, 0.46)
	spr.modulate = _projectile_tint_for_elem(elem)
	spr.position = from_pos
	spr.rotation = (to_pos - from_pos).angle()
	spr.visible = true

	tr_l.width = 16.0
	tr_l.default_color = _trail_color_for_elem(elem)
	tr_l.clear_points()
	tr_l.add_point(from_pos)
	tr_l.visible = true

	slot["active"] = true
	slot["from_pos"] = from_pos
	slot["to_pos"] = to_pos
	slot["elapsed"] = 0.0
	slot["duration"] = maxf(0.09, duration)
	slot["arc_height"] = 14.0
	slot["elem"] = elem
	slot["spawn_impact_arc"] = (elem == "fire")
	slot["trail_pts"] = [from_pos]


func spawn_slash_arc(
	origin_pos: Vector2,
	dir: Vector2,
	style: String = "ink_cyan",
	radius_px: float = 108.0,
	duration: float = 0.25,
	flip_v: bool = false,
	delay_sec: float = 0.0
) -> void:
	if is_ground_layer:
		return
	if delay_sec > 0.001:
		_pending_spawns.append({
			"kind": "slash",
			"delay": delay_sec,
			"origin_pos": origin_pos,
			"dir": dir,
			"style": style,
			"radius_px": radius_px,
			"duration": duration,
			"flip_v": flip_v,
		})
		return

	_init_sky_pools()
	var slot: Dictionary = _acquire_pool_slot(_slash_pool)
	var s_spr: Sprite2D = slot["sprite"] as Sprite2D
	var smat: ShaderMaterial = slot["mat"] as ShaderMaterial

	var use_fire_tex: bool = (style == "fire_blade" or style == "feral_claw")
	s_spr.texture = _get_vfx_tex("vfx_slash_fire_arc.png" if use_fire_tex else "vfx_slash_ink_arc.png")
	var tint: Color = Color(1.0, 1.0, 1.0, 0.98)
	match style:
		"metal_gold":
			tint = Color(1.06, 0.98, 0.84, 0.97)
		"water_frost":
			tint = Color(0.78, 0.94, 1.05, 0.96)
		"wood_gale":
			tint = Color(0.76, 1.04, 0.88, 0.96)
		"earth_heavy":
			tint = Color(1.04, 0.84, 0.56, 0.97)
		"feral_claw":
			tint = Color(0.86, 0.36, 0.62, 0.94)
		_:
			tint = Color(1.0, 1.0, 1.0, 0.98)

	var d_norm: Vector2 = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	var sc_val: float = clampf(radius_px / 118.0, 0.55, 2.25)
	var b_scale: Vector2 = Vector2(sc_val, sc_val * 0.86)
	s_spr.position = origin_pos + d_norm * (radius_px * 0.24)
	s_spr.rotation = d_norm.angle()
	s_spr.flip_v = flip_v
	s_spr.scale = b_scale * 0.92
	smat.set_shader_parameter("tint_color", tint)
	smat.set_shader_parameter("sweep_progress", 0.22)
	s_spr.visible = true

	slot["active"] = true
	slot["elapsed"] = 0.04
	slot["duration"] = maxf(0.12, duration)
	slot["base_scale"] = b_scale


func spawn_qi_ribbon(
	anchor_actor: BattleActor,
	world_pos: Vector2,
	elem: String = "wood",
	scale_mult: float = 1.0,
	duration: float = 0.55
) -> void:
	if is_ground_layer:
		return
	_init_sky_pools()
	var slot: Dictionary = _acquire_pool_slot(_ribbon_pool)
	var r_spr: Sprite2D = slot["sprite"] as Sprite2D
	var col: Color = _ribbon_color_for_elem(elem)
	r_spr.position = world_pos
	r_spr.rotation = float(_ribbon_pool.find(slot)) * 0.9
	r_spr.scale = Vector2(scale_mult * 0.82, scale_mult * 0.58)
	r_spr.modulate = Color(col.r, col.g, col.b, 0.88)
	r_spr.visible = true

	slot["active"] = true
	slot["anchor"] = anchor_actor
	slot["base_pos"] = world_pos
	slot["elapsed"] = 0.05
	slot["duration"] = maxf(0.20, duration)
	slot["rot_speed"] = 3.2
	slot["rise_px"] = 24.0
	slot["base_scale"] = scale_mult * 0.85
	slot["base_col"] = col


func spawn_heal_ribbons(target_actor: BattleActor, elem: String = "wood", intensity: float = 1.0) -> void:
	if is_ground_layer or target_actor == null:
		return
	var base_p: Vector2 = target_actor.get_vfx_origin_world("chest")
	spawn_qi_ribbon(target_actor, base_p, elem, 0.88 * intensity, 0.62)
	_init_sky_pools()
	var slot2: Dictionary = _acquire_pool_slot(_ribbon_pool)
	var r_spr2: Sprite2D = slot2["sprite"] as Sprite2D
	var col2: Color = _ribbon_color_for_elem(elem)
	r_spr2.position = base_p + Vector2(0.0, 10.0)
	r_spr2.rotation = PI * 0.85
	r_spr2.scale = Vector2(0.72 * intensity, 0.50 * intensity)
	r_spr2.modulate = Color(col2.r, col2.g, col2.b, 0.80)
	r_spr2.visible = true
	slot2["active"] = true
	slot2["anchor"] = target_actor
	slot2["base_pos"] = base_p + Vector2(0.0, 10.0)
	slot2["elapsed"] = 0.04
	slot2["duration"] = 0.68
	slot2["rot_speed"] = -2.8
	slot2["rise_px"] = 36.0
	slot2["base_scale"] = 0.72 * intensity
	slot2["base_col"] = col2
	spawn_particle_burst(base_p, "heal_motes", int(round(14.0 * intensity)))


func spawn_shockwave_ring(world_pos: Vector2, radius_px: float, col: Color, duration: float = 0.42) -> void:
	if is_ground_layer:
		return
	_init_sky_pools()
	var slot: Dictionary = _acquire_pool_slot(_shockwave_pool)
	var w_spr: Sprite2D = slot["sprite"] as Sprite2D
	var start_s: float = (radius_px * 0.5) / 236.0
	w_spr.position = world_pos
	w_spr.scale = Vector2(start_s, start_s * 0.46)
	w_spr.modulate = Color(col.r, col.g, col.b, 0.90)
	w_spr.visible = true

	slot["active"] = true
	slot["elapsed"] = 0.02
	slot["duration"] = maxf(0.14, duration)
	slot["max_radius"] = maxf(48.0, radius_px)
	slot["base_col"] = col


func spawn_particle_burst(world_pos: Vector2, preset_id: String, amount_override: int = -1) -> void:
	if is_ground_layer:
		return
	_init_sky_pools()
	var cfg: Dictionary = _get_or_build_particle_preset(preset_id)
	var slot: Dictionary = _acquire_pool_slot(_particle_pool)
	var gp: GPUParticles2D = slot["node"] as GPUParticles2D

	gp.emitting = false
	gp.position = world_pos
	gp.process_material = cfg["ppm"] as ParticleProcessMaterial
	gp.texture = cfg["tex"] as Texture2D
	gp.material = _get_unshaded_add_material() if bool(cfg.get("additive", true)) else _get_unshaded_mix_material()
	var def_amt: int = int(cfg.get("amount", 22))
	gp.amount = maxi(4, amount_override if amount_override > 0 else def_amt)
	gp.amount_ratio = 0.45 if SaveManager.reduced_motion else 1.0
	gp.lifetime = float(cfg.get("lifetime", 0.68))
	gp.interpolate = false
	gp.fixed_fps = 0
	gp.speed_scale = 1.0
	gp.visible = true
	gp.restart()
	gp.emitting = true

	slot["active"] = true
	slot["remaining"] = gp.lifetime + 0.12


func spawn_synergy_burst(
	world_pos: Vector2,
	syn_id: String,
	tank_actor: BattleActor = null,
	attacker_actor: BattleActor = null
) -> void:
	if is_ground_layer:
		return
	var chest_pos: Vector2 = world_pos + Vector2(0.0, -46.0)
	match syn_id:
		"wood_fire":
			spawn_shockwave_ring(world_pos, 168.0, UIThemeBuilder.COL_CINNABAR_RED, 0.50)
			spawn_slash_arc(chest_pos, Vector2(0.92, -0.38), "fire_blade", 132.0, 0.30, false)
			spawn_slash_arc(chest_pos, Vector2(-0.92, 0.38), "fire_blade", 124.0, 0.30, true, 0.04)
			spawn_particle_burst(chest_pos, "syn_wood_fire", 32)
		"fire_earth":
			spawn_shockwave_ring(world_pos, 152.0, UIThemeBuilder.COL_EARTH_AMBER, 0.52)
			spawn_particle_burst(chest_pos, "syn_fire_earth", 26)
			if tank_actor != null:
				spawn_qi_ribbon(tank_actor, tank_actor.get_vfx_origin_world("chest"), "earth", 1.0, 0.62)
		"earth_metal":
			spawn_shockwave_ring(world_pos, 156.0, UIThemeBuilder.COL_BRONZE_GOLD, 0.48)
			spawn_sword_projectile(chest_pos + Vector2(-130.0, -90.0), chest_pos + Vector2(30.0, 12.0), "metal", 0.14, 6.0, 1.15, 0.0, true)
			spawn_sword_projectile(chest_pos + Vector2(130.0, -90.0), chest_pos + Vector2(-30.0, 12.0), "metal", 0.14, 6.0, 1.15, 0.03, false)
			spawn_particle_burst(chest_pos, "syn_earth_metal", 30)
		"metal_water":
			spawn_shockwave_ring(world_pos, 150.0, UIThemeBuilder.COL_WATER_BLUE, 0.50)
			spawn_particle_burst(chest_pos, "syn_metal_water", 28)
			if attacker_actor != null:
				spawn_needle_projectile(chest_pos, attacker_actor.get_vfx_origin_world("chest"), "water", 0.22)
		"water_wood":
			spawn_shockwave_ring(world_pos, 160.0, UIThemeBuilder.COL_JADE_GREEN, 0.54)
			spawn_particle_burst(chest_pos, "syn_water_wood", 28)
			if tank_actor != null:
				spawn_heal_ribbons(tank_actor, "wood", 1.15)
		_:
			spawn_shockwave_ring(world_pos, 150.0, UIThemeBuilder.COL_BRONZE_GOLD, 0.45)
			spawn_particle_burst(chest_pos, "syn_wood_fire", 24)


## 兼容聚合转发（彻底废除裸直线/单圆环占位）
func spawn_ring_burst(pos: Vector2, radius: float, col: Color, duration: float = 0.45) -> void:
	spawn_shockwave_ring(pos, radius, col, duration)
	spawn_particle_burst(pos + Vector2(0.0, -34.0), _infer_preset_from_color(col), 14)


func spawn_beam_slash(from_pos: Vector2, to_pos: Vector2, col: Color, duration: float = 0.28) -> void:
	var elem: String = _infer_elem_from_color(col)
	spawn_sword_projectile(
		from_pos + Vector2(0.0, -52.0),
		to_pos + Vector2(0.0, -52.0),
		elem,
		clampf(duration * 0.65, 0.12, 0.22),
		16.0,
		0.90,
		0.0,
		true
	)


## 兼容便捷重载（供截图测试脚本或外部快速调用）
func spawn_projectile(
	kind: String,
	from_pos: Vector2,
	to_pos: Vector2,
	_col: Color = Color.WHITE,
	duration: float = 0.20
) -> void:
	if kind == "silver_needle":
		spawn_needle_projectile(from_pos, to_pos, "wood", duration)
	elif kind == "element_bolt":
		spawn_element_bolt(from_pos, to_pos, _infer_elem_from_color(_col), duration)
	else:
		spawn_sword_projectile(from_pos, to_pos, _infer_elem_from_color(_col), duration)


func spawn_wood_qi_ribbon(from_pos: Vector2, to_pos: Vector2) -> void:
	spawn_qi_ribbon(null, from_pos, "wood", 0.95, 0.68)
	spawn_needle_projectile(from_pos, to_pos, "wood", 0.24)


## ==================== 地面八卦危招阵纹与走位线绘制 ====================
func _draw() -> void:
	var font: Font = UIThemeBuilder.get_bold_font()
	if font == null:
		font = ThemeDB.fallback_font

	if is_ground_layer:
		# 1. 绘制 2.27:1 斜向透视朱砂八卦危招圆环 / 裂爪扇形阵纹（严格位于角色 FeetOrigin 之下！）
		for tele: Dictionary in active_telegraphs:
			var kind: String = str(tele.get("type", "circle"))
			var orig: Vector2 = tele.get("origin", Vector2.ZERO) as Vector2
			var rad: float = float(tele.get("radius", 140.0))
			var prog: float = clampf(float(tele.get("progress", 0.0)), 0.0, 1.0)
			var intr: bool = bool(tele.get("interruptible", false))
			if kind == "cone":
				var dir: Vector2 = (tele.get("dir", Vector2.RIGHT) as Vector2).normalized()
				var half_rad: float = deg_to_rad(float(tele.get("angle_deg", 95.0)) * 0.5)
				var base_ang: float = dir.angle()
				_draw_telegraph_cone(orig, rad, base_ang - half_rad, base_ang + half_rad, prog)
			else:
				_draw_telegraph_circle(orig, rad, prog, intr)

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

		# 3. 右键青玉水波落点（UNSHADED + 实时 ui_delta 驱动，置于走位线顶层以在战术凝时框选落点处清晰绽放同心涟漪！）
		for rp: Dictionary in _move_ripples:
			var r_pos: Vector2 = rp.get("pos", Vector2.ZERO) as Vector2
			var r_t: float = clampf(float(rp.get("elapsed", 0.0)) / maxf(0.05, float(rp.get("duration", 0.52))), 0.0, 1.0)
			var ease_main: float = 1.0 - pow(1.0 - r_t, 1.85)
			draw_set_transform(r_pos, 0.0, Vector2(1.0, 0.52))
			if _jade_ripple_tex != null:
				var tex_rad: float = lerpf(8.0, 41.0, ease_main)
				draw_texture_rect(
					_jade_ripple_tex,
					Rect2(-tex_rad, -tex_rad, tex_rad * 2.0, tex_rad * 2.0),
					false,
					Color(1.0, 1.0, 1.0, 0.82 * pow(1.0 - r_t, 1.05))
				)
			# Layer A: 青玉灵泉扩散波谷（初段亮玉心 -> 中段墨绿深谷衬底）
			var core_flash: float = clampf(1.0 - r_t * 3.2, 0.0, 1.0)
			if core_flash > 0.01:
				draw_circle(Vector2.ZERO, lerpf(15.0, 5.0, 1.0 - core_flash), Color(0.82, 0.93, 0.89, 0.78 * core_flash))
			draw_circle(Vector2.ZERO, lerpf(10.0, 39.0, ease_main), Color(0.18, 0.48, 0.40, 0.34 * pow(1.0 - r_t, 1.25)))
			# Layer B: 三重错落同心水波（深墨波谷 + 宋明石绿主波峰 + 白玉高光脊）
			for ring_i: int in range(3):
				var delay_f: float = float(ring_i) * 0.13
				var ring_raw: float = clampf((r_t - delay_f) / maxf(0.25, 1.0 - delay_f), 0.0, 1.0)
				if ring_raw > 0.005:
					var ease_r: float = 1.0 - pow(1.0 - ring_raw, 1.75)
					var rad_rp: float = lerpf(5.0, 41.0 - float(ring_i) * 5.5, ease_r)
					var a_ring: float = pow(1.0 - ring_raw, 0.85) * (0.98 - float(ring_i) * 0.18)
					draw_arc(Vector2.ZERO, rad_rp + 1.8, 0.0, TAU, 40, Color(0.06, 0.16, 0.14, a_ring * 0.72), 4.6)
					draw_arc(Vector2.ZERO, rad_rp, 0.0, TAU, 40, Color(0.45, 0.83, 0.72, a_ring), 3.4 - float(ring_i) * 0.45)
					draw_arc(Vector2.ZERO, maxf(2.0, rad_rp - 0.8), -PI * 0.92, -PI * 0.08, 20, Color(0.88, 0.95, 0.91, a_ring * 0.94), 2.1)
			# Layer C: 中心坠水回弹青玉珠（恢复竖直屏幕比例绘制）
			if r_t < 0.42:
				var drop_t: float = r_t / 0.42
				draw_set_transform(r_pos, 0.0, Vector2.ONE)
				var drop_p: Vector2 = Vector2(0.0, -sin(drop_t * PI) * 14.0)
				var drop_r: float = lerpf(5.8, 2.2, drop_t)
				draw_circle(drop_p, drop_r + 1.4, Color(0.14, 0.38, 0.31, 0.88 * (1.0 - drop_t)))
				draw_circle(drop_p, drop_r, Color(0.86, 0.94, 0.90, 0.95 * (1.0 - drop_t)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	# ==================== 空中预排技能连线层 ====================
	for ql: Dictionary in queued_skill_lines:
		var q_from: Vector2 = ql.get("from", Vector2.ZERO) as Vector2
		var q_to: Vector2 = ql.get("to", Vector2.ZERO) as Vector2
		var q_col: Color = ql.get("color", UIThemeBuilder.COL_BRONZE_GOLD) as Color
		draw_dashed_line(q_from + Vector2(0.0, -56.0), q_to + Vector2(0.0, -56.0), q_col, 2.2, 8.0)
		var sname: String = str(ql.get("skill_name", ""))
		if sname != "":
			var mid: Vector2 = (q_from + q_to) * 0.5 + Vector2(-30.0, -64.0)
			draw_string(font, mid, "预排·" + sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, q_col)


func _draw_telegraph_circle(center: Vector2, radius: float, progress: float, interruptible: bool) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, PERSPECTIVE_Y_RATIO))

	# 1. 半透明朱砂基底与由内向外充盈进度盘
	draw_circle(Vector2.ZERO, radius * 0.95, Color(0.68, 0.22, 0.17, 0.14))
	if progress > 0.015:
		var fill_r: float = radius * 0.94 * progress
		draw_circle(Vector2.ZERO, fill_r, Color(0.76, 0.25, 0.19, 0.30))
		draw_arc(Vector2.ZERO, fill_r, 0.0, TAU, 48, Color(0.96, 0.58, 0.36, 0.76), 2.4)

	# 2. 乾兑离震巽坎艮坤双环朱砂八卦贴图（贴合 master_b 2.27:1 透视椭圆）
	var bagua_tex: Texture2D = _get_vfx_tex("vfx_bagua_telegraph.png")
	if bagua_tex != null:
		draw_texture_rect(
			bagua_tex,
			Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0)),
			false,
			Color(1.0, 1.0, 1.0, 0.92)
		)
	else:
		draw_arc(Vector2.ZERO, radius * 0.94, 0.0, TAU, 48, Color(0.86, 0.30, 0.22, 0.92), 3.0)
		draw_arc(Vector2.ZERO, radius * 0.87, 0.0, TAU, 48, Color(0.86, 0.30, 0.22, 0.78), 2.0)

	# 3. 无障碍双编码：可打断危招在外圈叠加琥珀金四象断法方位标，不可打断叠加暗红双镇角
	var mark_col: Color = Color(0.94, 0.74, 0.36, 0.88) if interruptible else Color(0.76, 0.20, 0.18, 0.88)
	for i: int in range(8 if interruptible else 4):
		var ang: float = (TAU * float(i)) / float(8 if interruptible else 4)
		var p_in: Vector2 = Vector2(cos(ang), sin(ang)) * (radius * 0.95)
		var p_out: Vector2 = Vector2(cos(ang), sin(ang)) * (radius * 1.02)
		draw_line(p_in, p_out, mark_col, 2.6)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_telegraph_cone(origin: Vector2, radius: float, a_start: float, a_end: float, progress: float) -> void:
	var steps: int = 28
	var outer_poly: PackedVector2Array = PackedVector2Array([origin])
	var outer_rim: PackedVector2Array = PackedVector2Array()
	var inner_rim: PackedVector2Array = PackedVector2Array()
	for i: int in range(steps + 1):
		var a: float = lerpf(a_start, a_end, float(i) / float(steps))
		var pt_o: Vector2 = origin + Vector2(cos(a) * radius, sin(a) * radius * CONE_Y_RATIO)
		var pt_i: Vector2 = origin + Vector2(cos(a) * radius * 0.93, sin(a) * radius * 0.93 * CONE_Y_RATIO)
		outer_poly.append(pt_o)
		outer_rim.append(pt_o)
		inner_rim.append(pt_i)

	draw_colored_polygon(outer_poly, Color(0.70, 0.22, 0.17, 0.18))

	if progress > 0.015:
		var fill_r: float = radius * progress
		var fill_poly: PackedVector2Array = PackedVector2Array([origin])
		var fill_arc: PackedVector2Array = PackedVector2Array()
		for i2: int in range(steps + 1):
			var a2: float = lerpf(a_start, a_end, float(i2) / float(steps))
			var fp: Vector2 = origin + Vector2(cos(a2) * fill_r, sin(a2) * fill_r * CONE_Y_RATIO)
			fill_poly.append(fp)
			fill_arc.append(fp)
		draw_colored_polygon(fill_poly, Color(0.80, 0.25, 0.19, 0.34))
		if fill_arc.size() >= 2:
			draw_polyline(fill_arc, Color(0.96, 0.56, 0.36, 0.78), 2.2, true)

	# 双层朱砂墨线外框 + 锯齿危招刻度
	var full_outline: PackedVector2Array = PackedVector2Array([origin])
	full_outline.append_array(outer_rim)
	full_outline.append(origin)
	draw_polyline(full_outline, Color(0.15, 0.07, 0.06, 0.82), 4.8, true)
	draw_polyline(full_outline, Color(0.86, 0.28, 0.20, 0.94), 2.8, true)
	if inner_rim.size() >= 2:
		draw_polyline(inner_rim, Color(0.84, 0.32, 0.22, 0.72), 1.8, true)

	# 扇面中央叠加三道凶兽朱砂爪痕贴图
	var claw_tex: Texture2D = _get_vfx_tex("vfx_claw_marks_cone.png")
	if claw_tex != null:
		var mid_a: float = (a_start + a_end) * 0.5
		var mid_pt: Vector2 = origin + Vector2(cos(mid_a) * radius * 0.55, sin(mid_a) * radius * 0.55 * CONE_Y_RATIO)
		var c_sc: float = clampf(radius / 250.0, 0.55, 1.45)
		draw_set_transform(mid_pt, mid_a, Vector2(c_sc, c_sc * 0.52))
		draw_texture_rect(claw_tex, Rect2(Vector2(-128.0, -128.0), Vector2(256.0, 256.0)), false, Color(1.0, 1.0, 1.0, 0.85))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## ==================== 内部对象池与粒子预设工厂 ====================
func _acquire_pool_slot(pool: Array[Dictionary]) -> Dictionary:
	for slot: Dictionary in pool:
		if not bool(slot.get("active", false)):
			return slot
	return pool[0]


static func _projectile_tint_for_elem(elem: String) -> Color:
	match elem:
		"fire":
			return Color(1.08, 0.74, 0.42, 0.98)
		"water":
			return Color(0.78, 0.95, 1.08, 0.98)
		"wood":
			return Color(0.80, 1.04, 0.88, 0.98)
		"earth":
			return Color(1.04, 0.88, 0.62, 0.98)
		"miasma":
			return Color(0.66, 0.38, 0.74, 0.96)
		_:
			return Color(1.0, 1.0, 1.0, 0.98)


static func _trail_color_for_elem(elem: String) -> Color:
	match elem:
		"fire":
			return Color(0.95, 0.48, 0.24, 0.88)
		"water":
			return Color(0.54, 0.82, 0.96, 0.88)
		"wood":
			return Color(0.46, 0.84, 0.66, 0.86)
		"earth":
			return Color(0.84, 0.66, 0.38, 0.86)
		"miasma":
			return Color(0.56, 0.32, 0.64, 0.84)
		_:
			return Color(0.82, 0.95, 1.0, 0.88)


static func _ribbon_color_for_elem(elem: String) -> Color:
	match elem:
		"fire":
			return Color(1.08, 0.56, 0.34, 0.92)
		"water":
			return Color(0.68, 0.90, 1.06, 0.92)
		"metal":
			return Color(1.04, 0.92, 0.68, 0.92)
		"earth":
			return Color(0.96, 0.78, 0.48, 0.90)
		"miasma":
			return Color(0.68, 0.42, 0.76, 0.88)
		_:
			return Color(1.0, 1.0, 1.0, 0.94)


static func _hit_preset_for_elem(elem: String) -> String:
	match elem:
		"fire":
			return "hit_fire"
		"water":
			return "hit_water"
		"wood":
			return "hit_wood"
		"earth":
			return "hit_earth"
		"miasma":
			return "hit_miasma"
		_:
			return "hit_metal"


static func _infer_elem_from_color(col: Color) -> String:
	if col.r > 0.68 and col.g < 0.42:
		return "fire"
	if col.g > 0.45 and col.g > col.r * 1.15 and col.b < 0.65:
		return "wood"
	if col.b > col.r * 1.25:
		return "water"
	if col.r > 0.45 and col.b > 0.45 and col.g < 0.40:
		return "miasma"
	return "metal"


static func _infer_preset_from_color(col: Color) -> String:
	return _hit_preset_for_elem(_infer_elem_from_color(col))


static func _make_color_ramp(c0: Color, c1: Color, c2: Color) -> GradientTexture1D:
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	grad.colors = PackedColorArray([c0, c1, Color(c2.r, c2.g, c2.b, 0.0)])
	var gtex: GradientTexture1D = GradientTexture1D.new()
	gtex.gradient = grad
	gtex.width = 64
	return gtex


static func _make_scale_curve(s0: float, s_mid: float, s1: float) -> CurveTexture:
	var c: Curve = Curve.new()
	c.add_point(Vector2(0.0, s0))
	c.add_point(Vector2(0.35, s_mid))
	c.add_point(Vector2(1.0, s1))
	var ct: CurveTexture = CurveTexture.new()
	ct.curve = c
	return ct


func _get_or_build_particle_preset(preset_id: String) -> Dictionary:
	if _ppm_cache.has(preset_id):
		return _ppm_cache[preset_id] as Dictionary

	var ppm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	ppm.particle_flag_disable_z = true
	ppm.direction = Vector3(0.0, -1.0, 0.0)
	ppm.spread = 180.0
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 18.0
	ppm.damping_min = 45.0
	ppm.damping_max = 95.0
	ppm.scale_curve = _make_scale_curve(0.55, 1.0, 0.15)

	var tex_name: String = "vfx_particle_spark.png"
	var additive: bool = true
	var amount: int = 22
	var lifetime: float = 0.68

	match preset_id:
		"syn_wood_fire":
			tex_name = "vfx_particle_spark.png"
			additive = true
			amount = 32
			lifetime = 0.72
			ppm.initial_velocity_min = 105.0
			ppm.initial_velocity_max = 215.0
			ppm.gravity = Vector3(0.0, -72.0, 0.0)
			ppm.scale_min = 0.36
			ppm.scale_max = 0.78
			ppm.color_ramp = _make_color_ramp(Color("#FFF2B2"), Color("#E45A28"), Color("#9E2418"))
		"syn_fire_earth":
			tex_name = "vfx_particle_rock_shard.png"
			additive = false
			amount = 26
			lifetime = 0.78
			ppm.initial_velocity_min = 95.0
			ppm.initial_velocity_max = 185.0
			ppm.gravity = Vector3(0.0, 210.0, 0.0)
			ppm.angular_velocity_min = -220.0
			ppm.angular_velocity_max = 220.0
			ppm.scale_min = 0.30
			ppm.scale_max = 0.62
			ppm.color_ramp = _make_color_ramp(Color("#FFD27D"), Color("#B58942"), Color("#4A3B31"))
		"syn_earth_metal":
			tex_name = "vfx_particle_rock_shard.png"
			additive = true
			amount = 30
			lifetime = 0.64
			ppm.initial_velocity_min = 145.0
			ppm.initial_velocity_max = 255.0
			ppm.gravity = Vector3(0.0, 24.0, 0.0)
			ppm.angular_velocity_min = -260.0
			ppm.angular_velocity_max = 260.0
			ppm.scale_min = 0.28
			ppm.scale_max = 0.58
			ppm.color_ramp = _make_color_ramp(Color("#FFFDF2"), Color("#E8C06E"), Color("#9E7B3E"))
		"syn_metal_water":
			tex_name = "vfx_particle_jade_mote.png"
			additive = true
			amount = 28
			lifetime = 0.74
			ppm.initial_velocity_min = 88.0
			ppm.initial_velocity_max = 175.0
			ppm.gravity = Vector3(0.0, 32.0, 0.0)
			ppm.scale_min = 0.34
			ppm.scale_max = 0.68
			ppm.color_ramp = _make_color_ramp(Color("#ECFBFF"), Color("#7EC8E3"), Color("#2E5984"))
		"syn_water_wood":
			tex_name = "vfx_particle_petal_leaf.png"
			additive = false
			amount = 28
			lifetime = 0.84
			ppm.initial_velocity_min = 68.0
			ppm.initial_velocity_max = 145.0
			ppm.gravity = Vector3(0.0, -48.0, 0.0)
			ppm.angular_velocity_min = -140.0
			ppm.angular_velocity_max = 140.0
			ppm.scale_min = 0.34
			ppm.scale_max = 0.66
			ppm.color_ramp = _make_color_ramp(Color("#ECFFF4"), Color("#68C896"), Color("#3E7B67"))
		"ward_break":
			tex_name = "vfx_particle_rock_shard.png"
			additive = true
			amount = 30
			lifetime = 0.72
			ppm.initial_velocity_min = 135.0
			ppm.initial_velocity_max = 250.0
			ppm.gravity = Vector3(0.0, 120.0, 0.0)
			ppm.angular_velocity_min = -280.0
			ppm.angular_velocity_max = 280.0
			ppm.scale_min = 0.30
			ppm.scale_max = 0.64
			ppm.color_ramp = _make_color_ramp(Color("#FFF8E0"), Color("#E8B858"), Color("#8C6230"))
		"interrupt_shatter":
			tex_name = "vfx_particle_spark.png"
			additive = true
			amount = 22
			lifetime = 0.56
			ppm.initial_velocity_min = 115.0
			ppm.initial_velocity_max = 215.0
			ppm.gravity = Vector3(0.0, 15.0, 0.0)
			ppm.scale_min = 0.32
			ppm.scale_max = 0.66
			ppm.color_ramp = _make_color_ramp(Color("#FFFFFF"), Color("#FCE088"), Color("#C87A32"))
		"bond_qinglian":
			tex_name = "vfx_particle_petal_leaf.png"
			additive = false
			amount = 36
			lifetime = 0.88
			ppm.emission_sphere_radius = 36.0
			ppm.initial_velocity_min = 95.0
			ppm.initial_velocity_max = 205.0
			ppm.gravity = Vector3(0.0, -55.0, 0.0)
			ppm.angular_velocity_min = -180.0
			ppm.angular_velocity_max = 180.0
			ppm.scale_min = 0.36
			ppm.scale_max = 0.72
			ppm.color_ramp = _make_color_ramp(Color("#F0FFF8"), Color("#74E0B8"), Color("#3E7B67"))
		"heal_motes":
			tex_name = "vfx_particle_jade_mote.png"
			additive = true
			amount = 16
			lifetime = 0.76
			ppm.emission_sphere_radius = 24.0
			ppm.direction = Vector3(0.0, -1.0, 0.0)
			ppm.spread = 75.0
			ppm.initial_velocity_min = 38.0
			ppm.initial_velocity_max = 88.0
			ppm.gravity = Vector3(0.0, -52.0, 0.0)
			ppm.scale_min = 0.26
			ppm.scale_max = 0.54
			ppm.color_ramp = _make_color_ramp(Color("#F2FFF8"), Color("#78DCA8"), Color("#3E7B67"))
		"hit_fire":
			tex_name = "vfx_particle_spark.png"
			additive = true
			amount = 12
			lifetime = 0.46
			ppm.initial_velocity_min = 75.0
			ppm.initial_velocity_max = 155.0
			ppm.gravity = Vector3(0.0, -45.0, 0.0)
			ppm.scale_min = 0.24
			ppm.scale_max = 0.52
			ppm.color_ramp = _make_color_ramp(Color("#FFF4C2"), Color("#E4642C"), Color("#9E281B"))
		"hit_water":
			tex_name = "vfx_particle_ink_drop.png"
			additive = false
			amount = 12
			lifetime = 0.48
			ppm.initial_velocity_min = 70.0
			ppm.initial_velocity_max = 140.0
			ppm.gravity = Vector3(0.0, 90.0, 0.0)
			ppm.scale_min = 0.22
			ppm.scale_max = 0.46
			ppm.color_ramp = _make_color_ramp(Color("#EAF8FF"), Color("#6EA5C4"), Color("#2E5984"))
		"hit_wood":
			tex_name = "vfx_particle_petal_leaf.png"
			additive = false
			amount = 10
			lifetime = 0.54
			ppm.initial_velocity_min = 60.0
			ppm.initial_velocity_max = 125.0
			ppm.gravity = Vector3(0.0, -28.0, 0.0)
			ppm.angular_velocity_min = -140.0
			ppm.angular_velocity_max = 140.0
			ppm.scale_min = 0.24
			ppm.scale_max = 0.48
			ppm.color_ramp = _make_color_ramp(Color("#EAFFF2"), Color("#66C494"), Color("#3E7B67"))
		"hit_earth":
			tex_name = "vfx_particle_rock_shard.png"
			additive = false
			amount = 12
			lifetime = 0.52
			ppm.initial_velocity_min = 75.0
			ppm.initial_velocity_max = 150.0
			ppm.gravity = Vector3(0.0, 185.0, 0.0)
			ppm.angular_velocity_min = -200.0
			ppm.angular_velocity_max = 200.0
			ppm.scale_min = 0.22
			ppm.scale_max = 0.46
			ppm.color_ramp = _make_color_ramp(Color("#F6DFB0"), Color("#B58942"), Color("#524032"))
		"hit_miasma":
			tex_name = "vfx_particle_ink_drop.png"
			additive = false
			amount = 18
			lifetime = 0.62
			ppm.initial_velocity_min = 68.0
			ppm.initial_velocity_max = 148.0
			ppm.gravity = Vector3(0.0, -32.0, 0.0)
			ppm.scale_min = 0.26
			ppm.scale_max = 0.56
			ppm.color_ramp = _make_color_ramp(Color("#C89CE0"), Color("#6E3B78"), Color("#28182E"))
		_: # "hit_metal" / "hit_ink"
			tex_name = "vfx_particle_spark.png"
			additive = true
			amount = 10
			lifetime = 0.42
			ppm.initial_velocity_min = 85.0
			ppm.initial_velocity_max = 165.0
			ppm.gravity = Vector3(0.0, 20.0, 0.0)
			ppm.scale_min = 0.24
			ppm.scale_max = 0.48
			ppm.color_ramp = _make_color_ramp(Color("#F2FCFF"), Color("#8CD4EC"), Color("#3B6E84"))

	var out: Dictionary = {
		"ppm": ppm,
		"tex": _get_vfx_tex(tex_name),
		"additive": additive,
		"amount": amount,
		"lifetime": lifetime,
	}
	_ppm_cache[preset_id] = out
	return out
