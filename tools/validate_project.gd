extends SceneTree
## Read-only resource and physics verification. Writes only docs/validation_report.json.
## Run with Godot --headless --path <project> --script res://tools/validate_project.gd

const EXPECTED_ORIGINALS: int = 387
const EXPECTED_TOTAL: int = 395
const EXPECTED_ANIMATIONS: int = 8
const EXPECTED_TERRAINS: int = 12
const EXPECTED_LAYERS: Array[String] = [
	"00_Background_背景墙", "10_BackDecor_后景装饰", "20_Solid_实体地形",
	"30_OneWay_单向平台", "40_Climb_梯子藤蔓", "50_Liquids_液体",
	"60_Hazards_危险物", "70_Interactables_交互标记", "80_Foreground_前景装饰"
]
const LAYER_TILESET_KEYS: Dictionary = {
	"00_Background_背景墙": "background", "10_BackDecor_后景装饰": "decoration",
	"20_Solid_实体地形": "terrain", "30_OneWay_单向平台": "platforms",
	"40_Climb_梯子藤蔓": "climb", "50_Liquids_液体": "liquids",
	"60_Hazards_危险物": "hazards", "70_Interactables_交互标记": "interactables",
	"80_Foreground_前景装饰": "decoration", "Catalog_全部素材": "all"
}

var _index: Dictionary = {}
var _manifest: Dictionary = {}
var _sets: Dictionary = {}
var _errors: Array[Dictionary] = []
var _assertion_count: int = 0
var _resource_summary: Dictionary = {}
var _scene_summary: Dictionary = {}
var _runtime_summary: Dictionary = {}
var _raw_images: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_index = _read_json("res://data/tile_index.json")
	_manifest = _read_json("res://data/asset_manifest.json")
	if _index.is_empty() or _manifest.is_empty():
		_finish()
		return
	_validate_index()
	_validate_tilesets()
	_validate_scenes()
	await _validate_runtime()
	await _validate_other_scene_runtime()
	_finish()


func _read_json(path: String) -> Dictionary:
	_expect(FileAccess.file_exists(path), path, "JSON file exists")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(parsed is Dictionary, path, "Valid JSON dictionary")
	return parsed as Dictionary if parsed is Dictionary else {}


func _expect(condition: bool, scope: String, message: String) -> void:
	_assertion_count += 1
	if not condition:
		_errors.append({"scope": scope, "message": message})
		push_error("VALIDATION: %s: %s" % [scope, message])


func _load_png(path: String) -> Image:
	if _raw_images.has(path):
		return _raw_images[path] as Image
	var image: Image = Image.new()
	var result: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	_expect(result == OK, path, "PNG decodes without using editor import warnings")
	if result != OK:
		return null
	_raw_images[path] = image
	return image


func _same_visible_pixels(first: Image, second: Image) -> bool:
	if first.get_size() != second.get_size():
		return false
	# Godot's fix_alpha_border legitimately changes RGB where alpha is zero.
	for y: int in range(first.get_height()):
		for x: int in range(first.get_width()):
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			if a.a != b.a or (a.a > 0.0 and a != b):
				return false
	return true


func _validate_index() -> void:
	var sprites: Dictionary = _index.get("sprites", {})
	var originals: Array = _manifest.get("sprites", [])
	var original_keys: Dictionary = {}
	for entry: Dictionary in originals:
		var key: String = str(entry.get("key", ""))
		_expect(not key.is_empty() and not original_keys.has(key), "manifest", "Original key is unique: " + key)
		original_keys[key] = true
		_expect(sprites.has(key), key, "Original appears in tile index")
	var animated_count: int = 0
	var multi_cell_count: int = 0
	for key: String in sprites:
		var entry: Dictionary = sprites[key]
		_expect(str(entry.get("key", "")) == key, key, "Dictionary key matches asset key")
		var animated: bool = bool(entry.get("animated", false))
		animated_count += int(animated)
		if not animated:
			_expect(original_keys.has(key), key, "Native key is present in original manifest")
		var expected_size: Vector2i = Vector2i(int(entry.width), int(entry.height))
		var cells: Vector2i = Vector2i(int(entry.atlas_w), int(entry.atlas_h))
		_expect(expected_size == cells * 16, key, "Original dimensions retained as complete multi-cell tile")
		multi_cell_count += int(cells != Vector2i.ONE)
		var path: String = str(entry.texture_path)
		_expect(FileAccess.file_exists(path), key, "Source crop or animation texture exists")
		if FileAccess.file_exists(path):
			var image: Image = _load_png(path)
			_expect(image != null and not image.is_empty(), key, "Texture pixels are readable")
			if image != null and not image.is_empty():
				var image_size: Vector2i = image.get_size()
				_expect(image_size.y == expected_size.y, key, "Texture height matches indexed dimensions")
				_expect(image_size.x == expected_size.x * (int(entry.get("frames", 1)) if animated else 1), key, "Texture width matches native crop or animation strip")
	_expect(originals.size() == EXPECTED_ORIGINALS and original_keys.size() == EXPECTED_ORIGINALS, "manifest", "Exactly 387 unique original assets")
	_expect(sprites.size() == EXPECTED_TOTAL, "index", "Exactly 395 indexed tiles")
	_expect(animated_count == EXPECTED_ANIMATIONS, "index", "Exactly 8 animation tiles")
	_expect(int(_index.get("tile_size", 0)) == 16, "index", "Native tile grid is 16 px")
	_resource_summary["original_unique_keys"] = original_keys.size()
	_resource_summary["indexed_tiles"] = sprites.size()
	_resource_summary["animated_tiles"] = animated_count
	_resource_summary["multi_cell_tiles"] = multi_cell_count


func _included(set_key: String, entry: Dictionary) -> bool:
	var behavior: String = str(entry.behavior)
	match set_key:
		"all": return true
		"terrain": return behavior == "solid"
		"platforms": return behavior == "one_way"
		"background": return str(entry.category) in ["terrain", "background", "sky", "clouds_sky", "castle", "ruins", "cave"]
		"decoration": return behavior == "decoration"
		"climb": return behavior == "climb"
		"liquids": return behavior == "liquid"
		"hazards": return behavior == "hazard"
		"interactables": return behavior == "marker"
	return false


func _validate_tilesets() -> void:
	var paths: Dictionary = _index.get("tilesets", {})
	var sprites: Dictionary = _index.get("sprites", {})
	var sources: Dictionary = _index.get("sources", {})
	_expect(paths.size() == 9, "tilesets", "Nine categorized resources")
	var summaries: Dictionary = {}
	for set_key: String in paths:
		var path: String = str(paths[set_key])
		var tileset: TileSet = load(path) as TileSet
		_expect(tileset != null, path, "TileSet resource loads")
		if tileset == null:
			continue
		_sets[set_key] = tileset
		_expect(tileset.tile_size == Vector2i(16, 16), path, "16 px tile size")
		_expect(tileset.get_physics_layers_count() == 3, path, "Three physics channels")
		for physics: int in range(mini(3, tileset.get_physics_layers_count())):
			_expect(tileset.get_physics_layer_collision_layer(physics) == [1, 2, 8][physics], path, "Solid / one-way / hazard layer bits")
			_expect(tileset.get_physics_layer_collision_mask(physics) == 4, path, "Physics channels target player bit 4")
		for field: String in ["asset_key", "display_name", "category", "behavior", "pack"]:
			_expect(tileset.get_custom_data_layer_by_name(field) >= 0, path, "Custom field: " + field)
		var actual_keys: Dictionary = {}
		var total_tiles: int = 0
		var animations: int = 0
		var polygons: int = 0
		for source_index: int in range(tileset.get_source_count()):
			var source_id: int = tileset.get_source_id(source_index)
			var atlas: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
			_expect(atlas != null, path, "Source is a usable texture atlas")
			if atlas == null:
				continue
			_expect(atlas.texture != null, path, "Atlas texture loads")
			if atlas.texture == null:
				continue
			var atlas_size: Vector2i = atlas.texture.get_size()
			var atlas_image: Image = atlas.texture.get_image()
			var raw_atlas: Image = null
			if atlas.texture.resource_path.ends_with(".png"):
				raw_atlas = _load_png(atlas.texture.resource_path)
			_expect(atlas.texture_region_size == Vector2i(16, 16), path, "Atlas slicing remains 16 px")
			for tile_index: int in range(atlas.get_tiles_count()):
				total_tiles += 1
				var coords: Vector2i = atlas.get_tile_id(tile_index)
				var data: TileData = atlas.get_tile_data(coords, 0)
				var key: String = str(data.get_custom_data("asset_key"))
				var scope: String = set_key + ":" + key
				_expect(not actual_keys.has(key), scope, "Unique tile key in resource")
				actual_keys[key] = true
				_expect(sprites.has(key), scope, "Every resource tile is indexed")
				if not sprites.has(key):
					continue
				var entry: Dictionary = sprites[key]
				_expect(_included(set_key, entry), scope, "Tile belongs to its category")
				_expect(source_id == int(sources[entry.source_key]), scope, "Stable source ID matches index")
				_expect(coords == Vector2i(int(entry.atlas_x), int(entry.atlas_y)), scope, "Atlas coordinates match index")
				_expect(atlas.get_tile_size_in_atlas(coords) == Vector2i(int(entry.atlas_w), int(entry.atlas_h)), scope, "Complete multi-cell object retained")
				var origin: Vector2i = -Vector2i((int(entry.width) - 16) / 2, (int(entry.height) - 16) / 2)
				_expect(data.texture_origin == origin, scope, "Multi-cell object anchors at upper-left placement cell")
				var frames: int = atlas.get_tile_animation_frames_count(coords)
				animations += int(frames > 1)
				_expect(frames == int(entry.get("frames", 1)), scope, "Animation frame count matches index")
				for frame: int in range(frames):
					var region: Rect2i = atlas.get_tile_texture_region(coords, frame)
					_expect(region.position.x >= 0 and region.position.y >= 0 and region.end.x <= atlas_size.x and region.end.y <= atlas_size.y, scope, "All frame regions stay inside texture")
				if not bool(entry.get("animated", false)) and atlas_image != null:
					var original: Image = _load_png(str(entry.texture_path))
					var region: Rect2i = atlas.get_tile_texture_region(coords)
					var atlas_crop: Image = atlas_image.get_region(region)
					original.convert(Image.FORMAT_RGBA8)
					atlas_crop.convert(Image.FORMAT_RGBA8)
					_expect(_same_visible_pixels(original, atlas_crop), scope, "Imported atlas preserves every visible original pixel and alpha")
					if raw_atlas != null:
						var raw_crop: Image = raw_atlas.get_region(region)
						raw_crop.convert(Image.FORMAT_RGBA8)
						_expect(original.get_size() == raw_crop.get_size() and original.get_data() == raw_crop.get_data(), scope, "Raw atlas preserves every original RGBA pixel")
				var behavior: String = "decoration" if set_key == "background" else str(entry.behavior)
				_expect(str(data.get_custom_data("behavior")) == behavior, scope, "Gameplay behavior matches category")
				for physics: int in range(tileset.get_physics_layers_count()):
					var count: int = data.get_collision_polygons_count(physics)
					polygons += count
					var expected: bool = (behavior == "solid" and physics == 0) or (behavior == "one_way" and physics == 1) or (behavior == "hazard" and physics == 2)
					_expect(count > 0 if expected else count == 0, scope, "Correct collision polygons on physics channel %d" % physics)
					for polygon: int in range(count):
						_expect(data.get_collision_polygon_points(physics, polygon).size() >= 3, scope, "Collision polygon is usable")
						_expect(data.is_collision_polygon_one_way(physics, polygon) == (behavior == "one_way"), scope, "One-way flag is limited to platform polygons")
		for key: String in sprites:
			_expect(actual_keys.has(key) == _included(set_key, sprites[key]), set_key + ":" + key, "Indexed tile category coverage")
		var terrains: int = tileset.get_terrain_sets_count()
		_expect(terrains == (EXPECTED_TERRAINS if set_key in ["all", "terrain", "background"] else 0), path, "Expected 12 terrain themes in terrain-capable sets")
		var terrain_names: Dictionary = {}
		for terrain: int in range(terrains):
			_expect(tileset.get_terrains_count(terrain) == 1, path, "Each theme has one terrain")
			var terrain_name: String = tileset.get_terrain_name(terrain, 0)
			_expect(not terrain_names.has(terrain_name), path, "Terrain theme names are unique")
			terrain_names[terrain_name] = true
		var pattern_cells: int = 0
		for pattern_index: int in range(tileset.get_patterns_count()):
			var pattern: TileMapPattern = tileset.get_pattern(pattern_index)
			var pattern_scope: String = "%s:pattern[%d]" % [set_key, pattern_index]
			_expect(pattern != null, pattern_scope, "Saved pattern loads")
			if pattern == null:
				continue
			var cells: Array[Vector2i] = pattern.get_used_cells()
			_expect(not cells.is_empty(), pattern_scope, "Saved painting pattern contains cells")
			for cell: Vector2i in cells:
				pattern_cells += 1
				var scope: String = pattern_scope + ":cell " + str(cell)
				var source_id: int = pattern.get_cell_source_id(cell)
				_expect(tileset.has_source(source_id), scope, "Pattern source ID exists in its TileSet")
				if not tileset.has_source(source_id):
					continue
				var atlas: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
				_expect(atlas != null, scope, "Pattern source is an atlas")
				if atlas == null:
					continue
				var coords: Vector2i = pattern.get_cell_atlas_coords(cell)
				_expect(atlas.has_tile(coords), scope, "Pattern references an existing atlas tile")
				if not atlas.has_tile(coords):
					continue
				# TileMapPattern.set_cell defaults to -1; persisted uint16 65535 is invalid.
				var alternative: int = pattern.get_cell_alternative_tile(cell)
				_expect(alternative >= 0 and atlas.has_alternative_tile(coords, alternative), scope, "Pattern alternative ID exists; no invalid -1 / 65535 references")
		summaries[set_key] = {"tiles": total_tiles, "atlas_sources": tileset.get_source_count(), "animated_tiles": animations, "collision_polygons": polygons, "terrain_themes": terrains, "patterns": tileset.get_patterns_count(), "pattern_cells": pattern_cells}
	_resource_summary["tilesets"] = summaries


func _validate_scenes() -> void:
	for path: String in ["res://scenes/levels/whitebox_test.tscn", "res://scenes/levels/whitebox_template.tscn", "res://scenes/reference/asset_catalog.tscn", "res://scenes/actors/test_player.tscn"]:
		var packed: PackedScene = load(path) as PackedScene
		_expect(packed != null, path, "Packed scene loads")
		if packed == null:
			continue
		var scene: Node = packed.instantiate()
		_expect(scene != null, path, "Scene instantiates with scripts and resources")
		if scene == null:
			continue
		var layer_count: int = 0
		var bindings: Dictionary = {}
		for child: Node in scene.get_children():
			if child is TileMapLayer:
				layer_count += 1
				var layer: TileMapLayer = child as TileMapLayer
				var scope: String = path + ":" + str(layer.name)
				_expect(layer.tile_set != null, scope, "Scene layer has a TileSet")
				if layer.tile_set != null:
					var resource_path: String = layer.tile_set.resource_path
					var expected_key: String = str(LAYER_TILESET_KEYS.get(str(layer.name), ""))
					var expected_path: String = str(_index.tilesets.get(expected_key, ""))
					_expect(not resource_path.is_empty(), scope, "TileSet has an external resource path")
					_expect(not expected_path.is_empty() and resource_path == expected_path, scope, "External TileSet path matches the indexed category resource")
					_expect(_sets.has(expected_key) and layer.tile_set == _sets.get(expected_key), scope, "Layer shares the loaded project TileSet instead of embedding a duplicate")
					bindings[str(layer.name)] = resource_path
		if path.contains("/levels/"):
			_expect(layer_count == 9, path, "Nine separate editing layers")
			var previous_z: int = -1000
			for layer_name: String in EXPECTED_LAYERS:
				var layer: TileMapLayer = scene.get_node_or_null(NodePath(layer_name)) as TileMapLayer
				_expect(layer != null, path, "Named editing layer: " + layer_name)
				if layer != null:
					_expect(layer.z_index > previous_z, path, "Layer visual stacking order")
					previous_z = layer.z_index
			_expect(scene.get_node_or_null("Spawn") is Marker2D, path, "Spawn marker is present")
			_expect(scene.get_node_or_null("Player") is CharacterBody2D, path, "Playable test character is present")
		elif path.contains("/reference/"):
			var catalog_layer: TileMapLayer = scene.get_node_or_null("Catalog_全部素材") as TileMapLayer
			_expect(catalog_layer != null and not catalog_layer.collision_enabled, path, "Catalog is safe to inspect without collisions")
		_scene_summary[path] = {"loaded": true, "instantiated": true, "tilemap_layers": layer_count, "external_tileset_bindings": bindings}
		scene.free()


func _wait_physics(frames: int) -> void:
	for frame: int in range(frames):
		await physics_frame
	await process_frame


func _validate_runtime() -> void:
	var packed: PackedScene = load("res://scenes/levels/whitebox_test.tscn") as PackedScene
	if packed == null:
		return
	var level: Node2D = packed.instantiate() as Node2D
	root.add_child(level)
	current_scene = level
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var spawn: Marker2D = level.get_node("Spawn") as Marker2D
	await _wait_physics(12)
	var landed: bool = player.is_on_floor() and absf(player.global_position.y - 288.0) < 1.0
	_expect(landed, "runtime", "Main scene player lands on the authored solid floor")
	_runtime_summary["main_scene_landing"] = {"passed": landed, "feet": _vector_json(player.global_position), "on_floor": player.is_on_floor()}
	var start_x: float = player.global_position.x
	Input.action_press("ui_right")
	await _wait_physics(12)
	Input.action_release("ui_right")
	var moved_right: bool = player.global_position.x > start_x + 18.0
	Input.action_press("ui_left")
	await _wait_physics(12)
	Input.action_release("ui_left")
	var moved_left: bool = absf(player.global_position.x - start_x) < 4.0
	_expect(moved_right and moved_left, "runtime", "Simulated left/right inputs move the real main-scene player")
	_runtime_summary["movement"] = {"passed": moved_right and moved_left, "run_speed": player.get("run_speed")}
	Input.action_press("ui_accept")
	await _wait_physics(2)
	Input.action_release("ui_accept")
	var jumped: bool = player.velocity.y < -200.0 and player.global_position.y < 288.0
	_expect(jumped, "runtime", "Simulated jump leaves the solid floor")
	_runtime_summary["jump"] = {"passed": jumped, "vertical_velocity": player.velocity.y}
	player.call("reset_to_spawn")
	await _wait_physics(2)
	var platforms: TileMapLayer = level.get_node("30_OneWay_单向平台") as TileMapLayer
	var platform_cell: Vector2i = Vector2i(8, 0)
	for used_cell: Vector2i in platforms.get_used_cells():
		if used_cell.x == 8:
			platform_cell = used_cell
			break
	var platform_data: TileData = platforms.get_cell_tile_data(platform_cell)
	if platform_data != null:
		var polygon: PackedVector2Array = platform_data.get_collision_polygon_points(1, 0)
		var top_y: float = INF
		for point: Vector2 in polygon:
			top_y = minf(top_y, point.y)
		var center: Vector2 = platforms.to_global(platforms.map_to_local(platform_cell))
		var platform_top: float = center.y + top_y
		player.call("reset_to_spawn", Vector2(center.x, platform_top + 30.0))
		player.velocity = Vector2(0.0, -260.0)
		await _wait_physics(16)
		var passed_up: bool = player.global_position.y < platform_top - 2.0
		_expect(passed_up, "runtime", "Player passes upward through the authored one-way platform")
		await _wait_physics(35)
		var stood: bool = player.is_on_floor() and absf(player.global_position.y - platform_top) < 1.0
		_expect(stood, "runtime", "Player lands and stands on the one-way platform")
		Input.action_press("ui_down")
		Input.action_press("ui_accept")
		await _wait_physics(6)
		Input.action_release("ui_accept")
		Input.action_release("ui_down")
		var dropped: bool = player.global_position.y > platform_top + 6.0 and not player.get_collision_mask_value(2)
		_expect(dropped, "runtime", "Down plus jump passes downward through one-way collision")
		await _wait_physics(20)
		_expect(player.get_collision_mask_value(2), "runtime", "One-way collision mask is restored after drop-through")
		_runtime_summary["one_way"] = {"passed_upward": passed_up, "stood_on_top": stood, "dropped_downward": dropped, "restored_mask": player.get_collision_mask_value(2), "platform_top_y": platform_top}
	else:
		_expect(false, "runtime", "Authored one-way test platform exists")
	player.call("reset_to_spawn", Vector2(344.0, 272.0))
	Input.action_press("ui_up")
	await _wait_physics(12)
	Input.action_release("ui_up")
	var climbed: bool = str(player.get("current_behavior")) == "climb" and player.global_position.y < 260.0
	_expect(climbed, "runtime", "Authored ladder custom data enables climbing")
	_runtime_summary["climb"] = {"passed": climbed, "feet_y": player.global_position.y, "state": player.get("current_behavior")}
	player.call("reset_to_spawn", Vector2(568.0, 288.0))
	await _wait_physics(3)
	var liquid: bool = str(player.get("current_behavior")) == "liquid"
	_expect(liquid, "runtime", "Authored animated liquid is detected")
	_runtime_summary["liquid"] = {"passed": liquid, "state": player.get("current_behavior")}
	var previous_respawns: int = int(player.get("respawn_count"))
	player.global_position = Vector2(408.0, 288.0)
	player.velocity = Vector2.ZERO
	await _wait_physics(3)
	var hazard: bool = int(player.get("respawn_count")) > previous_respawns and player.global_position.distance_to(spawn.global_position) < 2.0
	_expect(hazard, "runtime", "Authored spike custom data respawns player without blocking hazard physics")
	_runtime_summary["hazard_respawn"] = {"passed": hazard, "feet": _vector_json(player.global_position), "spawn": _vector_json(spawn.global_position)}
	var hud: Node = level.get_node_or_null("TestHUD")
	_expect(hud is CanvasLayer, "runtime", "Test HUD is created successfully")
	_scene_summary["res://scenes/levels/whitebox_test.tscn"]["ran_in_tree"] = true
	_scene_summary["res://scenes/actors/test_player.tscn"]["ran_in_tree"] = true
	level.queue_free()
	await process_frame


func _validate_other_scene_runtime() -> void:
	for path: String in ["res://scenes/levels/whitebox_template.tscn", "res://scenes/reference/asset_catalog.tscn"]:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var scene: Node = packed.instantiate()
		root.add_child(scene)
		current_scene = scene
		await _wait_physics(8)
		if path.contains("whitebox_template"):
			var player: CharacterBody2D = scene.get_node("Player") as CharacterBody2D
			var spawn: Marker2D = scene.get_node("Spawn") as Marker2D
			var landed: bool = player.is_on_floor() and player.global_position.distance_to(spawn.global_position) < 1.0
			_expect(landed, "runtime", "Blank template also runs and lands on its removable starting floor")
			_runtime_summary["template_landing"] = {"passed": landed, "feet": _vector_json(player.global_position)}
		else:
			var layer: TileMapLayer = scene.get_node("Catalog_全部素材") as TileMapLayer
			_expect(layer.get_used_cells().size() == EXPECTED_ORIGINALS, "runtime", "Running catalog presents every original asset once")
		_scene_summary[path]["ran_in_tree"] = true
		scene.queue_free()
		await process_frame


func _vector_json(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _finish() -> void:
	var report: Dictionary = {
		"passed": _errors.is_empty(),
		"generated_at_utc": Time.get_datetime_string_from_system(true) + "Z",
		"godot_version": str(Engine.get_version_info().get("string", "")),
		"assertions": _assertion_count,
		"resources": _resource_summary,
		"scenes": _scene_summary,
		"runtime": _runtime_summary,
		"errors": _errors
	}
	DirAccess.make_dir_recursive_absolute("res://docs")
	var file: FileAccess = FileAccess.open("res://docs/validation_report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	else:
		push_error("Unable to write validation report")
	print("WHITEBOX_VALIDATION_RESULT ", JSON.stringify({"passed": _errors.is_empty(), "assertions": _assertion_count, "errors": _errors.size(), "report": "res://docs/validation_report.json"}))
	quit(0 if _errors.is_empty() else 1)
