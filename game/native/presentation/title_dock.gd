extends Node3D
## Asset-free title background. The game's original logo is imported by the UI.
var camera := Camera3D.new()
var environment := WorldEnvironment.new()
var dock_environment: Environment
func _ready() -> void:
	dock_environment=Environment.new()
	dock_environment.background_mode=Environment.BG_COLOR
	dock_environment.background_color=Color("030a10")
	environment.environment=dock_environment;add_child(environment)
	add_child(camera);camera.current=true
