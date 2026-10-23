extends CharacterBody2D
## A small controller for testing tile collision and traversal in the whitebox.
## The node origin is at the player's feet; the body occupies 12 x 22 pixels.

@export var run_speed: float = 110.0
@export var jump_speed: float = -260.0
@export var gravity: float = 800.0
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.1
@export var climb_speed: float = 72.0
@export var drop_through_time: float = 0.22

var spawn_position: Vector2 = Vector2.ZERO
var current_behavior: String = "normal"
var respawn_count: int = 0
var _tile_layers: Array[TileMapLayer] = []
var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _drop_through_left: float = 0.0
var _previous_jump: bool = false
var _previous_reset: bool = false
var _climbing: bool = false
var _facing: float = 1.0
var _has_spawn: bool = false


func _ready() -> void:
	if not _has_spawn:
		spawn_position = global_position
	refresh_tile_layers()
	queue_redraw()


func initialize_spawn(position: Vector2) -> void:
	spawn_position = position
	_has_spawn = true
	reset_to_spawn()


func refresh_tile_layers(world: Node = null) -> void:
	_tile_layers.clear()
	var root: Node = world
	if root == null:
		root = get_tree().current_scene
	if root == null:
		root = get_parent()
	if root != null:
		_collect_tile_layers(root)


func _collect_tile_layers(node: Node) -> void:
	if node is TileMapLayer:
		_tile_layers.append(node as TileMapLayer)
	for child: Node in node.get_children():
		_collect_tile_layers(child)


func reset_to_spawn(position: Vector2 = spawn_position) -> void:
	global_position = position
	velocity = Vector2.ZERO
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_drop_through_left = 0.0
	_climbing = false
	current_behavior = "normal"
	set_collision_mask_value(2, true)
	respawn_count += 1
	queue_redraw()


func _physics_process(delta: float) -> void:
	var reset_down: bool = Input.is_physical_key_pressed(KEY_R)
	if reset_down and not _previous_reset:
		reset_to_spawn()
	_previous_reset = reset_down
	var jump_down: bool = Input.is_action_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_SPACE)
	var jump_pressed: bool = jump_down and not _previous_jump
	_previous_jump = jump_down
	var move_x: float = _horizontal_axis()
	var move_y: float = _vertical_axis()
	if not is_zero_approx(move_x):
		_facing = signf(move_x)
	var behaviors: Dictionary = _sample_behaviors()
	if bool(behaviors.get("hazard", false)):
		reset_to_spawn()
		return
	var on_ladder: bool = bool(behaviors.get("climb", false))
	var in_liquid: bool = bool(behaviors.get("liquid", false))
	current_behavior = "liquid" if in_liquid else ("climb" if on_ladder else "normal")
	_drop_through_left = maxf(0.0, _drop_through_left - delta)
	set_collision_mask_value(2, _drop_through_left <= 0.0)
	_coyote_left = coyote_time if is_on_floor() else maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = jump_buffer_time if jump_pressed else maxf(0.0, _jump_buffer_left - delta)
	if jump_pressed and move_y > 0.5:
		_drop_through_left = drop_through_time
		set_collision_mask_value(2, false)
		_coyote_left = 0.0
		_jump_buffer_left = 0.0
		velocity.y = maxf(velocity.y, 36.0)
		position.y += 1.0
		_climbing = false
	elif _jump_buffer_left > 0.0 and (_coyote_left > 0.0 or _climbing):
		velocity.y = jump_speed
		_coyote_left = 0.0
		_jump_buffer_left = 0.0
		_climbing = false
		on_ladder = false
	if on_ladder and not is_zero_approx(move_y) and not jump_pressed:
		_climbing = true
	if not on_ladder:
		_climbing = false
	velocity.x = move_x * run_speed * (0.65 if in_liquid else 1.0)
	if _climbing:
		velocity.y = move_y * climb_speed
	else:
		velocity.y += gravity * delta * (0.35 if in_liquid else 1.0)
		velocity.y = minf(velocity.y, 110.0 if in_liquid else 480.0)
	move_and_slide()
	if _jump_buffer_left > 0.0 and is_on_floor() and _drop_through_left <= 0.0:
		velocity.y = jump_speed
		_coyote_left = 0.0
		_jump_buffer_left = 0.0
	# Samples after motion catch thin hazards crossed during the current frame.
	if bool(_sample_behaviors().get("hazard", false)):
		reset_to_spawn()
	elif global_position.y > spawn_position.y + 1600.0:
		reset_to_spawn()
	queue_redraw()


func _horizontal_axis() -> float:
	var left: bool = Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A)
	var right: bool = Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D)
	return float(int(right) - int(left))


func _vertical_axis() -> float:
	var up: bool = Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W)
	var down: bool = Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S)
	return float(int(down) - int(up))


func _sample_behaviors() -> Dictionary:
	var found: Dictionary = {}
	var offsets: Array[Vector2] = [Vector2(0.0, -11.0), Vector2(0.0, -20.0), Vector2(0.0, -2.0), Vector2(-5.0, -11.0), Vector2(5.0, -11.0)]
	for layer: TileMapLayer in _tile_layers:
		if not is_instance_valid(layer) or not layer.enabled or layer.tile_set == null:
			continue
		if layer.tile_set.get_custom_data_layer_by_name("behavior") < 0:
			continue
		for offset: Vector2 in offsets:
			var cell: Vector2i = layer.local_to_map(layer.to_local(global_position + offset))
			var tile_data: TileData = layer.get_cell_tile_data(cell)
			if tile_data == null:
				continue
			var behavior: String = str(tile_data.get_custom_data("behavior")).to_lower()
			for token: String in behavior.replace(";", ",").replace("|", ",").split(",", false):
				var tag: String = token.strip_edges()
				if not tag.is_empty():
					found[tag] = true
	return found


func _draw() -> void:
	var body_color: Color = Color("f6dfa5")
	if _climbing:
		body_color = Color("8fe0c9")
	elif current_behavior == "liquid":
		body_color = Color("8ac8f5")
	draw_rect(Rect2(-6.0, -22.0, 12.0, 22.0), Color("172333"))
	draw_rect(Rect2(-5.0, -21.0, 10.0, 20.0), body_color)
	draw_rect(Rect2(_facing * 2.0 - 1.0, -18.0, 2.0, 3.0), Color("172333"))
	draw_line(Vector2(-3.0, -2.0), Vector2(3.0, -2.0), Color("172333"), 1.0)
