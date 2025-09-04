extends StaticBody2D

@export var min_width: float = 0.5
@export var max_width: float = 1.0

var _move_dir := 1
var _move_range := 80.0
var _move_speed := 50.0
var _move_origin := 0.0
var _move_time := 0.0
var _moving := false
var _last_player_x := 0.0

func make_thin():
	if has_node("Polygon2D"):
		var scale = randf_range(min_width, max_width)
		get_node("Polygon2D").scale.x = scale

func make_moving():
	_move_dir = randf() < 0.5 and 1 or -1
	_move_range = randf_range(40, 120)
	_move_speed = randf_range(30, 80)
	_move_origin = position.x
	_move_time = 0.0
	_moving = true
	_last_player_x = position.x
	set_process(true)

func _process(delta):
	if _moving:
		_move_time += delta
		position.x = _move_origin + sin(_move_time * _move_speed * 0.01) * _move_range * _move_dir

func is_moving_platform():
	return _moving
