extends Control

@onready var start_button = $MarginContainer/VBoxContainer/Play
@onready var quit_button = $MarginContainer/VBoxContainer/Quit

func _ready():
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_start_pressed():
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _on_quit_pressed():
	get_tree().quit()
