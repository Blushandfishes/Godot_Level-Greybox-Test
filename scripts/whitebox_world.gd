extends Node2D
## Attach to the level root. Spawn and Player may be assigned in the Inspector.

@export var spawn_node_path: NodePath = NodePath("Spawn")
@export var player_node_path: NodePath = NodePath("Player")
@export var show_test_hud: bool = true

var _player: CharacterBody2D
var _spawn: Marker2D
var _status_label: Label
var _hud_layer: CanvasLayer


func _ready() -> void:
	_player = get_node_or_null(player_node_path) as CharacterBody2D
	_spawn = get_node_or_null(spawn_node_path) as Marker2D
	if _player != null:
		if _player.has_method("refresh_tile_layers"):
			_player.call("refresh_tile_layers", self)
		if _spawn != null and _player.has_method("initialize_spawn"):
			_player.call("initialize_spawn", _spawn.global_position)
	if show_test_hud:
		_create_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var code: Key = key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	if code == KEY_F1:
		get_tree().debug_collisions_hint = not get_tree().debug_collisions_hint
		get_viewport().set_input_as_handled()
	elif code == KEY_F2:
		respawn_player()
		get_viewport().set_input_as_handled()


func respawn_player() -> void:
	if is_instance_valid(_player) and _player.has_method("reset_to_spawn"):
		_player.call("reset_to_spawn")


func _process(_delta: float) -> void:
	if not is_instance_valid(_status_label):
		return
	var debug_text: String = "ON" if get_tree().debug_collisions_hint else "OFF"
	var behavior_text: String = "normal"
	if is_instance_valid(_player):
		var value: Variant = _player.get("current_behavior")
		if value != null:
			behavior_text = str(value)
	_status_label.text = "State: %s   |   Collision debug: %s" % [behavior_text, debug_text]


func _create_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "TestHUD"
	_hud_layer.layer = 20
	add_child(_hud_layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(10.0, 10.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.085, 0.90)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	_hud_layer.add_child(panel)
	var lines: VBoxContainer = VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lines)
	var title: Label = Label.new()
	title.text = "WHITEBOX PLAYTEST | 16 px grid"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("f6dfa5"))
	lines.add_child(title)
	var help: Label = Label.new()
	help.text = "A D / Arrows: move   Space: jump   W S: climb\nDown + Space: drop   R / F2: respawn   F1: collision debug"
	help.add_theme_font_size_override("font_size", 13)
	lines.add_child(help)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color("a8c0d4"))
	lines.add_child(_status_label)
