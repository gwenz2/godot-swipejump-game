extends Node2D
class_name Main

# --- CONSTANTS ---
static var SPECIAL_BG_SPAWN_CHANCES := [
	{ "score": 20, "chance": 0.2 },
	{ "score": 50, "chance": 0.13 },
	{ "score": 54, "chance": 0.13 },
	{ "score": 100, "chance": 0.12 }
]
static var SPECIAL_BG_SPACING := 1300
static var SPECIAL_BG_X_RANGE := Vector2(-200, 200)
static var SPECIAL_BG_Y_OFFSET := Vector2(-600, -800)

# --- EXPORTS ---
@export var platform_scene: PackedScene
@export var coin_scene: PackedScene
@export var platform_buffer: int = 20
@export var platform_remove_distance: int = 400
@export var shake_intensity_default: float = 5.0
@export var shake_duration_default: float = 0.05
@export var flash_opacity: float = 0.6
@export var flash_fade_time: float = 0.2
@export var special_bg_images: Array[String] = [] # Array of image paths (strings)
@export var special_bg_min_scale: float = 0.09
@export var special_bg_max_scale: float = 0.9
@export var special_bg_allow_rotate: bool = true
@export var special_bg_allow_scale: bool = true
@export var special_bg_parallax_min: float = 0.2
@export var special_bg_parallax_max: float = 0.8
var special_bg_scales: Array[Vector2] = [Vector2(0.18, 0.18), Vector2(0.25, 0.25), Vector2(0.4, 0.4), Vector2(0.5, 0.5)] # asteroid, mini nebula, nebula, asteroid field
var special_bg_parallax: Array[float] = [0.3, 0.5, 0.7, 0.6 ] # asteroid, mini nebula, nebula, asteroid field # Per-image parallax, e.g. [0.3, 0.5, ...]

# --- NODES ---
@onready var player = $Player
@onready var camera_anchor = $CameraAnchor
@onready var camera = $CameraAnchor/Camera2D
@onready var score_label = $CanvasLayer/HBoxContainer/Score
@onready var hp_label = $CanvasLayer/HBoxContainer/HP
@onready var game_over_ui = $CanvasLayer/GameOverUI
@onready var try_again_button =$"CanvasLayer/GameOverUI/MarginContainer/VBoxContainer/Try Again"
@onready var quit_button = $CanvasLayer/GameOverUI/MarginContainer/VBoxContainer/Quit
@onready var highscore_label = $CanvasLayer/GameOverUI/MarginContainer/VBoxContainer/Highscore
@onready var world_env = $WorldEnvironment
@onready var starfield = $Starfield if has_node("Starfield") else null

# --- STATE VARS ---
var game_over = false
var platform_spacing = 200
var score = 0
var highscore = 0
var shake_time = 0.0
var shake_intensity = 0.0
var camera_follow_speed := 0.02 # Default slow follow
var camera_follow_speed_fast := 0.1 # Fast follow value
var camera_follow_speed_timer := 0.0
var camera_follow_speed_fast_duration := 0.20
var platforms = []
var last_platform_y = 0.0
var last_special_bg_y := 0.0
var special_bg_nodes := [] # Store info for parallax

# --- INITIALIZATION ---
func _ready():
	init_game()

func init_game():
	game_over_ui.visible = false
	# Load highscore from project settings
	highscore = ProjectSettings.get_setting("application/config/highscore", 0)
	highscore_label.text = "Highscore: " + str(highscore)
	# Connect Game Over UI buttons
	try_again_button.pressed.connect(_on_try_again_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	# Connect player HP/died signal
	player.died.connect(_on_player_died)
	hp_label.text = "HP: " + str(player.hp)
	# Spawn initial platforms
	for i in range(platform_buffer):
		var y = -i * platform_spacing
		spawn_platform(Vector2(randf_range(-150, 150), y))
		last_platform_y = y

# --- GAME LOGIC ---
func _process(delta):
	if game_over:
		var child = get_child(0)  # First child node
		child.velocity = Vector2.ZERO
		return  # Skip processing when game is over
	update_ui()
	update_camera()
	update_platforms()
	update_background_color(player.position.y)
	spawn_special_backgrounds()
	update_special_bg_parallax()

func update_ui():
	hp_label.text = "HP: " + str(player.hp)
	var new_score = int(-player.position.y / 10)
	if new_score > score:
		score = new_score
		score_label.text = "Score: " + str(score)

func update_camera():
	var cam_target_y = player.position.y - 100

	# Camera follow speed logic
	if camera_follow_speed_timer > 0.0:
		camera_follow_speed_timer -= get_process_delta_time()
		if camera_follow_speed_timer <= 0.0:
			camera_follow_speed = camera_follow_speed_fast * 0.2 # Ease back to slow
		else:
			camera_follow_speed = camera_follow_speed_fast
	else:
		camera_follow_speed = 0.02

	# Camera follows upward faster than downward, using camera_follow_speed
	if cam_target_y < camera_anchor.position.y:
		camera_anchor.position.y = lerp(camera_anchor.position.y, cam_target_y, camera_follow_speed_fast)
	else:
		camera_anchor.position.y = lerp(camera_anchor.position.y, cam_target_y, camera_follow_speed)
	camera_anchor.position.y = min(camera_anchor.position.y, player.position.y - 100)

	# Apply camera shake offset (temporary)
	if shake_time > 0:
		shake_time -= get_process_delta_time()
		var shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_intensity
		camera.position = shake_offset
	else:
		camera.position = Vector2.ZERO  # Reset to original position

	# --- Improved game over check: player below visible camera area ---
	var viewport = get_viewport()
	var screen_size = viewport.get_visible_rect().size
	var cam_zoom = camera.zoom
	var cam_bottom = camera.global_position.y + (screen_size.y * 0.5 * cam_zoom.y)
	if player.global_position.y > cam_bottom + 10: # 40px buffer
		if player.has_method("play_hurt_sound"):
			player.play_hurt_sound()
			show_game_over()

func update_platforms():
	# Spawn new platforms above player
	while last_platform_y > player.position.y - platform_buffer * platform_spacing:
		last_platform_y -= platform_spacing
		spawn_platform(Vector2(randf_range(-150, 150), last_platform_y))

	# Remove platforms below player
	for p in platforms.duplicate():
		if p.global_position.y > player.position.y + platform_remove_distance:
			platforms.erase(p)
			p.queue_free()

func spawn_platform(pos: Vector2):
	var p = platform_scene.instantiate()
	add_child(p)
	p.global_position = pos
	platforms.append(p)

	# Increase thin platform chance with score
	var thin_chance: float = clamp(0.2 + float(score) / 2000.0, 0.2, 0.8)
	if p.has_method("make_thin") and randf() < thin_chance:
		p.make_thin()

	# Make platform moving with some chance (scaling with score)
	var move_chance: float = clamp(0.1 + float(score) / 3000.0, 0.1, 0.5)
	if p.has_method("make_moving") and randf() < move_chance:
		p.make_moving()

	# Randomly spawn a coin above the platform
	if coin_scene and randf() < 0.4:
		var coin_pos = pos + Vector2(randf_range(-30, 30), -40)
		spawn_coin(coin_pos)

func spawn_coin(pos: Vector2):
	var c = coin_scene.instantiate()
	add_child(c)
	c.global_position = pos
	c.connect("collected", Callable(self, "_on_coin_collected"))

func _on_coin_collected(value: int):
	score += value
	score_label.text = "Score: " + str(score)
	start_camera_shake(shake_intensity_default, shake_duration_default)
	if player.has_method("play_coin_sound"):
		player.play_coin_sound()

func start_camera_shake(intensity: float, duration: float):
	shake_intensity = intensity
	shake_time = duration

func camera_flash():
	var flash = $CanvasLayer/Flash
	flash.visible = true
	flash.modulate.a = flash_opacity
	var tween = get_tree().create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, flash_fade_time).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(flash, "hide"))

func camera_zoom(target_zoom: Vector2, duration: float = 0.3):
	var tween = get_tree().create_tween()
	tween.tween_property(camera, "zoom", target_zoom, duration)

func play_explosion(pos: Vector2):
	$TapParticles.global_position = pos
	$TapParticles.emitting = false
	#$TapParticles.emitting = true
	$TapParticles/MultiParticleExample1.burst()


# --- Game Over UI functions ---
func show_game_over():
	game_over = true
	$CanvasLayer/HBoxContainer.visible = false
	player.input_enabled = false
	# Update highscore if needed
	if score > highscore:
		highscore = score
		ProjectSettings.set_setting("application/config/highscore", highscore)
		ProjectSettings.save()
	highscore_label.text = "Score: " + str(score) + "\nHighscore: " + str(highscore)
	game_over_ui.visible = true
	

func _on_try_again_pressed():
	get_tree().reload_current_scene()

func _on_quit_pressed():
	get_tree().quit()

func _on_player_died():
	show_game_over()

func set_camera_fast_follow():
	camera_follow_speed_timer = camera_follow_speed_fast_duration
	camera_follow_speed = camera_follow_speed_fast

func update_background_color(player_y: float):
	# Interpolate from blue (low) to purple (high)
	var min_y = 0.0
	var max_y = -4000.0 # Adjust for your game height range
	var t = clamp((player_y - min_y) / (max_y - min_y), 0.0, 1.0)
	var low_color = Color(0.2, 0.4, 0.8) # Blue
	var high_color = Color(0.7, 0.2, 0.7) # Purple
	var bg_color = low_color.lerp(high_color, t)


# Add a new method to allow strong camera shake from Player.gd
func strong_camera_shake():
	start_camera_shake(shake_intensity_default * 5.0, shake_duration_default * 4.0)

func spawn_special_bg(idx):
	if idx >= 0 and idx < special_bg_images.size():
		var sprite = Sprite2D.new()
		var tex = load(special_bg_images[idx])
		if tex:
			sprite.texture = tex
			add_child(sprite)
			# Calculate camera top
			var viewport = get_viewport()
			var screen_size = viewport.get_visible_rect().size
			var cam_zoom = camera.zoom
			var cam_top = camera.global_position.y - (screen_size.y * 0.5 * cam_zoom.y)
			var x = randf_range(-400, 400)
			# Adjust spawn height based on parallax: higher parallax = spawn further above
			var parallax = special_bg_parallax[idx] if idx < special_bg_parallax.size() else randf_range(special_bg_parallax_min, special_bg_parallax_max)
			var min_offset = 400
			var max_offset = 800
			# For high parallax, multiply offset (e.g., up to 2x for parallax near 1)
			var parallax_factor = lerp(1.0, 2.0, clamp(parallax, 0.0, 1.0))
			var y = cam_top - min_offset * parallax_factor - randf_range(0, (max_offset - min_offset) * parallax_factor)
			sprite.global_position = Vector2(x, y)
			sprite.z_index = -10
			# Per-image scale
			if special_bg_allow_scale:
				if idx < special_bg_scales.size():
					sprite.scale = special_bg_scales[idx]
				else:
					var scale = randf_range(special_bg_min_scale, special_bg_max_scale)
					sprite.scale = Vector2.ONE * scale
			# Random rotation
			if special_bg_allow_rotate:
				sprite.rotation = randf_range(0, TAU)
			# Per-image parallax
			parallax = special_bg_parallax[idx] if idx < special_bg_parallax.size() else randf_range(special_bg_parallax_min, special_bg_parallax_max)
			special_bg_nodes.append({"sprite": sprite, "base_y": y, "parallax": parallax})

func spawn_special_backgrounds():
	if special_bg_images.size() == 0:
		return
	for i in range(special_bg_images.size()):
		var spawn_info = SPECIAL_BG_SPAWN_CHANCES[min(i, SPECIAL_BG_SPAWN_CHANCES.size()-1)]
		if score >= spawn_info["score"] and player.position.y < last_special_bg_y - SPECIAL_BG_SPACING:
			if randf() < spawn_info["chance"]:
				spawn_special_bg(i)
				print(i)
				last_special_bg_y = player.position.y

func update_special_bg_parallax():
	# Do not apply shake to special backgrounds; only parallax
	for info in special_bg_nodes:
		if is_instance_valid(info.sprite):
			var base_y = info.base_y
			var factor = info.parallax
			var parallax_y = base_y + (camera_anchor.position.y - base_y) * factor
			var parallax_x = info.sprite.global_position.x # keep X as is (or add parallax if you want)
			info.sprite.global_position = Vector2(parallax_x, parallax_y)
