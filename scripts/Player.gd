extends CharacterBody2D
class_name Player

# === CONFIG VARIABLES ===
@export var gravity = 500.0
@export var airbone_tap_speed = 1200.0
@export var min_drag_distance = 50.0
@export var max_drag_distance = 300.0
@export var drag_power_multiplier = 2.0
@export var arrow_line_width = 3
@export var arrow_line_color = Color.RED
@export var trajectory_dot_count = 15
@export var trajectory_dot_size = Vector2(6, 6)
@export var airborne_rotation_spins = 1.0 # Number of full spins per jump
@export var airborne_rotation_ease = 0.5 # 0.5 = ease out, 1.0 = linear
@export var rotation_reset_speed = 1
@export var squash_stretch_max_stretch_x = 0.2
@export var squash_stretch_max_squash_y = 0.2
@export var max_hp := 3
@export var fall_damage_threshold := 370.0 # velocity.y threshold for fall damage
@export var fall_damage_amount := 1
@export var sfx_volume := 0.7 # Master SFX volume (0.0 - 1.0)
@export var sfx_volume_jump := 0.7
@export var sfx_volume_land := 0.7
@export var sfx_volume_tap := 0.7
@export var sfx_volume_coin := 0.7
@export var sfx_volume_hurt := 0.7

# Add a sensitivity setting for trajectory preview
@export var trajectory_sensitivity := 1.0 # 1.0 = default, >1 = longer, <1 = shorter
@export var trajectory_offset := Vector2(0, -24) # Offset for first dot (e.g. top of player)

# === INTERNAL VARS ===
var is_airborne = false
var drag_start_pos = Vector2.ZERO
var dragging = false
var input_enabled := true
var hp := 3
var fall_start_y := 0.0
var tap_air_used = false

signal died

@onready var arrow_line = Line2D.new()
@onready var trajectory_dots = []
@onready var jump_sounds = [
	preload("res://sounds/hjump1.ogg")
]
@onready var coin_sound = preload("res://sounds/coin.wav")
@onready var tap_air_sounds = [
	preload("res://sounds/tap.ogg")
]
@onready var land_sounds = [
	preload("res://sounds/land.ogg")
]
@onready var sfx_player_jump = AudioStreamPlayer.new()
@onready var sfx_player_land = AudioStreamPlayer.new()
@onready var sfx_player_tap = AudioStreamPlayer.new()
@onready var sfx_player_coin = AudioStreamPlayer.new()
@onready var sfx_player_hurt = AudioStreamPlayer.new()
@onready var debug_label = get_node_or_null("../CanvasLayer/HBoxContainer/DebugLabel")

var debug_enabled := false
var last_platform = null

func some_trigger():
	emit_signal("exploded", global_position)


func _ready():
	# Setup arrow line
	arrow_line.width = arrow_line_width
	arrow_line.default_color = arrow_line_color
	arrow_line.visible = false
	add_child(arrow_line)

	# Create trajectory dots
	for i in range(trajectory_dot_count):
		var dot = ColorRect.new()
		dot.color = Color.WHITE
		dot.size = trajectory_dot_size
		dot.visible = false
		add_child(dot)
		trajectory_dots.append(dot)
	add_child(sfx_player_jump)
	add_child(sfx_player_land)
	add_child(sfx_player_tap)
	add_child(sfx_player_coin)
	add_child(sfx_player_hurt)

	if not debug_label:
		var lbl = Label.new()
		lbl.name = "DebugLabel"
		lbl.text = ""
		lbl.visible = false
		var hbox = get_node("../HBoxContainer")
		hbox.add_child(lbl)
		debug_label = lbl

	sfx_player_jump.volume_db = linear_to_db(sfx_volume_jump)
	sfx_player_land.volume_db = linear_to_db(sfx_volume_land)
	sfx_player_tap.volume_db = linear_to_db(sfx_volume_tap)
	sfx_player_coin.volume_db = linear_to_db(sfx_volume_coin)
	sfx_player_hurt.volume_db = linear_to_db(sfx_volume_hurt)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		debug_enabled = !debug_enabled
		if debug_enabled:
			print("[DEBUG] HP:", hp, "/", max_hp, "Airborne:", is_airborne, "Fall Start Y:", fall_start_y, "Fall Dist:", abs(global_position.y - fall_start_y), "Input Enabled:", input_enabled, "Dragging:", dragging)
	
	if not input_enabled:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_airborne:
				velocity.y = airbone_tap_speed  # Tap to drop faster
				velocity.x = 0
				tap_air_used = true
				input_enabled = false # Disable all input after tap-air
				if get_tree().current_scene.has_method("camera_flash"):
					get_tree().current_scene.camera_flash() # Flash when tap in air
				play_tap_air_sound()
				if get_tree().current_scene.has_method("camera_zoom"):
					get_tree().current_scene.camera_zoom(Vector2(1.8, 1.9), 0.15) # Zoom in on airborne tap
				# Airborne tap: set camera follow speed high
				var main_node = get_tree().get_root().get_node_or_null("World")
				if main_node and main_node.has_method("set_camera_fast_follow"):
					main_node.set_camera_fast_follow()
			else:
				drag_start_pos = get_global_mouse_position()
				dragging = true
				arrow_line.visible = true
				for dot in trajectory_dots:
					dot.visible = true

		elif not event.pressed and dragging:
			var drag_end_pos = get_global_mouse_position()
			var direction = drag_end_pos.direction_to(drag_start_pos).normalized()  # reversed direction
			var distance = clamp(drag_start_pos.distance_to(drag_end_pos), min_drag_distance, max_drag_distance)
			velocity = direction * (distance * drag_power_multiplier)
			is_airborne = true
			fall_start_y = global_position.y
			dragging = false
			arrow_line.visible = false
			for dot in trajectory_dots:
				dot.visible = false

			# Reset scale and rotation when launching
			$Polygon2D.scale = Vector2.ONE
			$Polygon2D.rotation = 0
			if get_tree().current_scene.has_method("start_camera_shake"):
				get_tree().current_scene.start_camera_shake(8, 0.08) # Shake a bit after jumping
			play_jump_sound()

func _process(_delta):
	if debug_enabled:
		if debug_label:
			debug_label.visible = true
			# Calculate fall distance and if damage will be taken
			var fall_dist = abs(global_position.y - fall_start_y)
			var will_take_damage = is_airborne and fall_dist > fall_damage_threshold
			var damage_str = "NO"
			if will_take_damage:
				damage_str = "YES!"
			debug_label.text = "[DEBUG]\nHP:%d/%d\nAirborne:%s\nFallY:%.1f\nFallDist:%.1f\nInput:%s\nDragging:%s\nFallDmgThresh:%.1f\nWillTakeDmg: %s" % [hp, max_hp, is_airborne, fall_start_y, fall_dist, input_enabled, dragging, fall_damage_threshold, damage_str]
	else:
		if debug_label:
			debug_label.visible = false
	
	if dragging:
		var drag_current = get_global_mouse_position()
		var drag_vector = drag_current - drag_start_pos

		arrow_line.clear_points()
		arrow_line.add_point(to_local(drag_start_pos))
		arrow_line.add_point(to_local(drag_current))

		var direction = drag_current.direction_to(drag_start_pos).normalized()
		var distance = clamp(drag_start_pos.distance_to(drag_current), min_drag_distance, max_drag_distance)
		update_trajectory_preview(direction, distance * drag_power_multiplier)

		update_aiming_animation(drag_vector)

	# Airborne rotation: complete full spins or stop at a fixed angle
	if is_airborne:
		if not has_meta("jump_rotation_start"):
			set_meta("jump_rotation_start", $Polygon2D.rotation)
			set_meta("jump_y_start", global_position.y)
			set_meta("jump_y_end", global_position.y - (max_drag_distance * drag_power_multiplier))

		var jump_y_start = get_meta("jump_y_start")
		var jump_y_end = get_meta("jump_y_end")
		if global_position.y <= jump_y_start and global_position.y >= jump_y_end:
			var t = clamp((jump_y_start - global_position.y) / (jump_y_start - jump_y_end), 0.0, 1.0)
			# --- To complete N spins, set airborne_rotation_spins to N (e.g., 2 for 720°)
			# --- To stop at a fixed angle, set airborne_rotation_spins to 0.5 for 180°, 1 for 360°, etc.
			var total_rot = 2 * PI * airborne_rotation_spins
			var ease_t = pow(sin(t * PI * 1), airborne_rotation_ease)
			$Polygon2D.rotation = lerp(get_meta("jump_rotation_start"), get_meta("jump_rotation_start") + total_rot, ease_t)
		else:
			# Snap to upright (0) or full spin (2*PI), depending on your preference
			if airborne_rotation_spins >= 1.0:
				$Polygon2D.rotation = 2*PI # or use 2*PI for a full spin
			else:
				$Polygon2D.rotation = 0.0
	else:
		# On ground, always reset to upright
		$Polygon2D.rotation = lerp_angle($Polygon2D.rotation, 0.0, rotation_reset_speed)
		if has_meta("jump_rotation_start"):
			remove_meta("jump_rotation_start")
			remove_meta("jump_y_start")
			remove_meta("jump_y_end")

	# print($"../CameraAnchor/Camera2D".zoom)

func update_trajectory_preview(direction: Vector2, power: float):
	# Start from the top of the player (offset)
	var pos = global_position + trajectory_offset
	var vel = direction * power * trajectory_sensitivity
	for i in range(trajectory_dots.size()):
		var t = i * 0.1
		var x = pos.x + vel.x * t
		var y = pos.y + vel.y * t + 0.5 * gravity * t * t
		trajectory_dots[i].global_position = Vector2(x, y)

func _physics_process(delta):
	if is_airborne:
		velocity.y += gravity * delta

	var collision = move_and_collide(velocity * delta)
	if collision and velocity.y > 0:
		# Fall damage based on distance fallen
		var fall_distance = abs(global_position.y - fall_start_y)
		var will_take_damage = fall_distance > fall_damage_threshold
		if will_take_damage:
			hp -= fall_damage_amount
			if hp <= 0:
				emit_signal("died")
			else:
				if get_tree().current_scene.has_method("start_camera_shake"):
					get_tree().current_scene.start_camera_shake(12, 0.12)
		is_airborne = false
		input_enabled = true # Re-enable input on landing
		velocity = Vector2.ZERO
		play_squash()
		if get_tree().current_scene.has_method("start_camera_shake"):
			get_tree().current_scene.start_camera_shake(4, 0.08) # Shake a bit after landing
		play_land_sound_with_damage(will_take_damage)
		if get_tree().current_scene.has_method("camera_zoom"):
			get_tree().current_scene.camera_zoom(Vector2(1.5, 1.5), 0.5) # Reset zoom on land

		# --- Platform following logic ---
		if collision.get_collider().has_method("is_moving_platform") and collision.get_collider().is_moving_platform():
			last_platform = collision.get_collider()
		else:
			last_platform = null
	else:	
		# If standing on a moving platform, follow its movement (only if not airborne)
		if not is_airborne and last_platform and last_platform._moving:
			# Only update _last_player_x when first landing on the platform
			if not last_platform.has_meta("player_on"):
				last_platform._last_player_x = last_platform.position.x
				last_platform.set_meta("player_on", true)
			# Always use the stored offset to maintain relative position
			if not last_platform.has_meta("player_offset_x") or typeof(last_platform.get_meta("player_offset_x")) != TYPE_FLOAT:
				last_platform.set_meta("player_offset_x", global_position.x - last_platform.position.x)
			var offset_x = last_platform.get_meta("player_offset_x")
			global_position.x = last_platform.position.x + offset_x
			last_platform._last_player_x = last_platform.position.x
		else:
			if last_platform and last_platform.has_meta("player_on"):
				last_platform.set_meta("player_on", false)
				if last_platform.has_meta("player_offset_x"):
					last_platform.remove_meta("player_offset_x")
			last_platform = null

	# --- Screen wrap logic (Snake-style, with padding) ---
	var viewport = get_viewport()
	var screen_size = viewport.get_visible_rect().size
	var cam = get_tree().current_scene.camera if get_tree().current_scene.has_node("camera") else null
	var cam_pos = cam.global_position if cam else Vector2.ZERO
	var cam_zoom = cam.zoom if cam else Vector2.ONE
	var half_width = (screen_size.x * 0.33 * cam_zoom.x)
	var padding = 10
	var min_x = cam_pos.x - half_width - padding
	var max_x = cam_pos.x + half_width + padding
	if global_position.x < min_x:
		global_position.x = max_x
	elif global_position.x > max_x:
		global_position.x = min_x

func play_jump_sound():
	var pitch = randf_range(0.85, 1.25)
	sfx_player_jump.stream = jump_sounds[0]
	sfx_player_jump.pitch_scale = pitch
	sfx_player_jump.play()

func play_coin_sound():
	var pitch = randf_range(1.1, 1.25)
	sfx_player_coin.stream = coin_sound
	sfx_player_coin.pitch_scale = pitch
	sfx_player_coin.play()

func play_tap_air_sound():
	var idx = randi() % tap_air_sounds.size()
	var pitch = randf_range(1.0, 1.2)
	sfx_player_tap.stream = tap_air_sounds[idx]
	sfx_player_tap.pitch_scale = pitch
	sfx_player_tap.play()
	var main = get_tree().get_root().get_node("World")
	main.play_explosion(global_position)

func play_land_sound():
	var pitch = randf_range(0.8, 1.3)
	sfx_player_land.stream = land_sounds[0]
	sfx_player_land.pitch_scale = pitch
	sfx_player_land.play()
	#$LandParticles.emitting = true
	$LandParticles/MultiParticleExample2.burst()

func play_hurt_sound():
	var pitch = randf_range(0.85, 1.05)
	sfx_player_hurt.stream = preload("res://sounds/hurt.ogg")
	sfx_player_hurt.pitch_scale = pitch
	sfx_player_hurt.play()
	# Trigger strong camera shake on damage
	var main = get_tree().get_root().get_node("World")
	if main and main.has_method("strong_camera_shake"):
		main.strong_camera_shake()

# In play_land_sound, play_hurt_sound if needed
func play_land_sound_with_damage(did_hurt: bool):
	if did_hurt:
		play_hurt_sound()
	else:
		play_land_sound()

func update_aiming_animation(drag_vector: Vector2):
	var drag_length = clamp(drag_vector.length(), 0, max_drag_distance)
	var strength_ratio = drag_length / max_drag_distance

	# Squash/stretch: stretch X by up to +max_stretch_x, squash Y by up to -max_squash_y
	var stretch_x = 1.0 + strength_ratio * squash_stretch_max_stretch_x
	var stretch_y = 1.0 - strength_ratio * squash_stretch_max_squash_y
	$Polygon2D.scale = Vector2(stretch_x, stretch_y)

	# Remove tilt while aiming (do not set rotation here)
	# $Polygon2D.rotation = drag_vector.angle() + PI

func play_squash():
	var tween = get_tree().create_tween()
	tween.tween_property(self, "scale", Vector2(1.2, 0.8), 0.1)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)

func _draw():
	pass # Debug info now shown in label

# If you want to allow changing volume at runtime, add this helper:
func set_sfx_volume(vol: float):
	sfx_volume = clamp(vol, 0.0, 1.0)
	sfx_player_jump.volume_db = linear_to_db(sfx_volume_jump)
	sfx_player_land.volume_db = linear_to_db(sfx_volume_land)
	sfx_player_tap.volume_db = linear_to_db(sfx_volume_tap)
	sfx_player_coin.volume_db = linear_to_db(sfx_volume_coin)
	sfx_player_hurt.volume_db = linear_to_db(sfx_volume_hurt)

func set_sfx_volume_jump(vol: float):
	sfx_volume_jump = clamp(vol, 0.0, 1.0)
	sfx_player_jump.volume_db = linear_to_db(sfx_volume_jump)

func set_sfx_volume_land(vol: float):
	sfx_volume_land = clamp(vol, 0.0, 1.0)
	sfx_player_land.volume_db = linear_to_db(sfx_volume_land)

func set_sfx_volume_tap(vol: float):
	sfx_volume_tap = clamp(vol, 0.0, 1.0)
	sfx_player_tap.volume_db = linear_to_db(sfx_volume_tap)

func set_sfx_volume_coin(vol: float):
	sfx_volume_coin = clamp(vol, 0.0, 1.0)
	sfx_player_coin.volume_db = linear_to_db(sfx_volume_coin)

func set_sfx_volume_hurt(vol: float):
	sfx_volume_hurt = clamp(vol, 0.0, 1.0)
	sfx_player_hurt.volume_db = linear_to_db(sfx_volume_hurt)
