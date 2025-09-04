extends Area2D

@export var pickup_sound: AudioStream

func _ready():
	# Godot 4 uses Callable instead of string method name
	self.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node):
	if body.is_in_group("PlayerSHAPE"):
		if pickup_sound:
			var sfx = AudioStreamPlayer.new()
			sfx.stream = pickup_sound
			add_child(sfx)
			sfx.play()
			await sfx.finished
		queue_free()
