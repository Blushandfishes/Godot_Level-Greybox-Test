extends SceneTree
## Rebuild generated resources. Run only when intentionally resetting the demo.

var manifest: Dictionary
var sprites: Dictionary = {}
var source_ids: Dictionary = {}
var tile_sets: Dictionary = {}
var terrain_ids: Dictionary = {}
var errors: Array[String] = []

const SET_NAMES := {
	"all": "00_全部素材", "terrain": "01_实体地形", "platforms": "02_单向平台",
	"background": "03_背景墙", "decoration": "04_装饰", "climb": "05_攀爬",
	"liquids": "06_液体", "hazards": "07_危险物", "interactables": "08_交互标记"
}
const LAYERS := [
	["00_Background_背景墙", "background", -50],
	["10_BackDecor_后景装饰", "decoration", -30],
	["20_Solid_实体地形", "terrain", 0],
	["30_OneWay_单向平台", "platforms", 2],
	["40_Climb_梯子藤蔓", "climb", 4],
	["50_Liquids_液体", "liquids", 6],
	["60_Hazards_危险物", "hazards", 8],
	["70_Interactables_交互标记", "interactables", 10],
	["80_Foreground_前景装饰", "decoration", 30]
]

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	for path: String in ["res://tilesets", "res://scenes/levels", "res://scenes/reference", "res://docs", "res://data"]:
		DirAccess.make_dir_recursive_absolute(path)
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/asset_manifest.json"))
	for entry: Dictionary in manifest.sprites:
		entry.behavior = _behavior(entry)
		sprites[entry.key] = entry
	for i: int in range(manifest.sources.size()):
		source_ids[manifest.sources[i].key] = i
	for set_key: String in SET_NAMES:
		var ts := _new_tileset(str(SET_NAMES[set_key]))
		for source: Dictionary in manifest.sources:
			var included: Array[Dictionary] = []
			for key: String in source.sprite_keys:
				var entry: Dictionary = sprites[key]
				if _include(set_key, entry):
					included.append(entry)
			if included.is_empty():
				continue
			var atlas := TileSetAtlasSource.new()
			atlas.resource_name = source.label
			atlas.texture = load(source.texture_path)
			atlas.texture_region_size = Vector2i(16, 16)
			ts.add_source(atlas, int(source_ids[source.key]))
			for entry: Dictionary in included:
				var coords := Vector2i(entry.atlas_x, entry.atlas_y)
				atlas.create_tile(coords, Vector2i(entry.atlas_w, entry.atlas_h))
				var td := atlas.get_tile_data(coords, 0)
				# Godot subtracts texture_origin. Anchor the complete object at its upper-left cell.
				td.texture_origin = -Vector2i((int(entry.width) - 16) / 2, (int(entry.height) - 16) / 2)
				_configure_tile(ts, td, entry, set_key)
		if set_key in ["all", "terrain", "background"]:
			_add_terrain_patterns(ts)
		if set_key in ["all", "platforms"]:
			_add_platform_patterns(ts)
		tile_sets[set_key] = ts
		_save(ts, _set_path(set_key))
	_add_animations()
	# Save again after attaching animation sources.
	for set_key: String in tile_sets:
		_save(tile_sets[set_key], _set_path(set_key))
	var index := {"tile_size":16, "sources":source_ids, "sprites":sprites, "tilesets":{}}
	for key: String in SET_NAMES:
		index.tilesets[key] = _set_path(key)
	_write_json("res://data/tile_index.json", index)
	_make_level(false)
	_make_level(true)
	_make_catalog()
	var summary := {"sprites":sprites.size(), "atlas_sources":source_ids.size(), "tilesets":tile_sets.size(), "terrain_themes":terrain_ids.size(), "errors":errors}
	_write_json("res://docs/build_report.json", summary)
	print("TILESET_BUILD_RESULT ", JSON.stringify(summary))
	quit(0 if errors.is_empty() else 1)

func _new_tileset(label: String) -> TileSet:
	var ts := TileSet.new()
	ts.resource_name = label
	ts.tile_size = Vector2i(16,16)
	for mask: int in [1, 2, 8]:
		ts.add_physics_layer()
		var i := ts.get_physics_layers_count() - 1
		ts.set_physics_layer_collision_layer(i, mask)
		ts.set_physics_layer_collision_mask(i, 4)
	for field: String in ["asset_key", "display_name", "category", "behavior", "pack"]:
		ts.add_custom_data_layer()
		var i := ts.get_custom_data_layers_count() - 1
		ts.set_custom_data_layer_name(i, field)
		ts.set_custom_data_layer_type(i, TYPE_STRING)
	return ts

func _behavior(entry: Dictionary) -> String:
	var cat: String = entry.category
	var n: String = entry.name
	if cat == "terrain": return "solid"
	if cat == "ice" and n == "ice_block": return "solid"
	if cat == "platforms" or (cat == "moving_platform" and n != "chain") or n == "wood_bridge": return "one_way"
	if cat == "climb" or n in ["ladder", "vine"]: return "climb"
	if cat == "liquid": return "liquid"
	if cat == "hazards" or n == "spikes": return "hazard"
	if n in ["crate", "barrel", "metal_crate", "question_block", "used_block", "crumbling_block"]: return "solid"
	if cat in ["doors", "pickups", "collectibles", "gadgets", "hazards_gadgets"]: return "marker"
	return "decoration"

func _include(set_key: String, entry: Dictionary) -> bool:
	var b: String = entry.behavior
	match set_key:
		"all": return true
		"terrain": return b == "solid"
		"platforms": return b == "one_way"
		"background": return entry.category in ["terrain", "background", "sky", "clouds_sky", "castle", "ruins", "cave"]
		"decoration": return b == "decoration"
		"climb": return b == "climb"
		"liquids": return b == "liquid"
		"hazards": return b == "hazard"
		"interactables": return b == "marker"
	return false

func _configure_tile(ts: TileSet, td: TileData, entry: Dictionary, set_key: String) -> void:
	var b: String = "decoration" if set_key == "background" else str(entry.behavior)
	td.set_custom_data("asset_key", entry.key)
	td.set_custom_data("display_name", entry.name)
	td.set_custom_data("category", entry.category)
	td.set_custom_data("behavior", b)
	td.set_custom_data("pack", entry.pack)
	if b == "solid":
		_polygon(td, 0, Rect2(-8,-8,16,16))
	elif b == "one_way":
		# Match visible platform top, preserving hollow pixels underneath.
		var image: Image = (load(entry.texture_path) as Texture2D).get_image()
		var bounds := image.get_used_rect()
		_polygon(td, 1, Rect2(-8, float(bounds.position.y)-8, 16, 3))
		td.set_collision_polygon_one_way(1, 0, true)
		td.set_collision_polygon_one_way_margin(1, 0, 1.0)
	elif b == "hazard":
		var image: Image = (load(entry.texture_path) as Texture2D).get_image()
		var r := image.get_used_rect()
		_polygon(td, 2, Rect2(Vector2(r.position)-Vector2(8,8), Vector2(r.size)))
	if entry.category == "terrain":
		var theme: String = entry.pack + "/" + str(entry.name).get_slice("_",0)
		var terrain_set := _ensure_terrain(ts, theme)
		td.terrain_set = terrain_set
		td.terrain = 0
		var part: String = str(entry.name).trim_prefix(str(entry.name).get_slice("_",0) + "_")
		var sides := [true,true,true,true] # top,right,bottom,left
		match part:
			"tl": sides = [false,true,true,false]
			"top", "top_alt": sides = [false,true,true,true]
			"tr": sides = [false,false,true,true]
			"left": sides = [true,true,true,false]
			"right": sides = [true,false,true,true]
			"bl": sides = [true,true,false,false]
			"bottom": sides = [true,true,false,true]
			"br": sides = [true,false,false,true]
			"block": sides = [false,false,false,false]
		for i: int in range(4):
			td.set_terrain_peering_bit([TileSet.CELL_NEIGHBOR_TOP_SIDE,TileSet.CELL_NEIGHBOR_RIGHT_SIDE,TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,TileSet.CELL_NEIGHBOR_LEFT_SIDE][i], 0 if sides[i] else -1)
		if part in ["fill_a", "fill_b", "top_alt"]: td.probability = 0.2

func _ensure_terrain(ts: TileSet, key: String) -> int:
	for i: int in range(ts.get_terrain_sets_count()):
		if ts.get_terrain_name(i,0) == key: return i
	var i := ts.get_terrain_sets_count()
	ts.add_terrain_set()
	ts.set_terrain_set_mode(i, TileSet.TERRAIN_MODE_MATCH_SIDES)
	ts.add_terrain(i)
	ts.set_terrain_name(i,0,key)
	ts.set_terrain_color(i,0,Color.from_hsv(float(i)/12.0,0.5,0.8))
	terrain_ids[key] = i
	return i

func _polygon(td: TileData, physics: int, r: Rect2) -> void:
	td.set_collision_polygons_count(physics,1)
	td.set_collision_polygon_points(physics,0,PackedVector2Array([r.position, Vector2(r.end.x,r.position.y), r.end, Vector2(r.position.x,r.end.y)]))

func _add_terrain_patterns(ts: TileSet) -> void:
	for source: Dictionary in manifest.sources:
		if source.category != "terrain" or not ts.has_source(int(source_ids[source.key])): continue
		var lookup: Dictionary = {}
		for key: String in source.sprite_keys:
			var e: Dictionary = sprites[key]
			lookup[e.name] = e
		var prefix: String = str(source.theme)
		var pattern := TileMapPattern.new()
		for y: int in range(4):
			for x: int in range(6):
				var suffix: String = ("tl" if x==0 else "tr" if x==5 else "top") if y==0 else (("bl" if x==0 else "br" if x==5 else "bottom") if y==3 else ("left" if x==0 else "right" if x==5 else "center"))
				if lookup.has(prefix+"_"+suffix):
					var e: Dictionary = lookup[prefix+"_"+suffix]
					pattern.set_cell(Vector2i(x,y),int(source_ids[source.key]),Vector2i(e.atlas_x,e.atlas_y),0)
		ts.add_pattern(pattern)

func _add_platform_patterns(ts: TileSet) -> void:
	for source: Dictionary in manifest.sources:
		if source.category != "platforms" or not ts.has_source(int(source_ids[source.key])): continue
		var pattern := TileMapPattern.new()
		for key: String in source.sprite_keys:
			var e: Dictionary = sprites[key]
			var x: int = 0 if str(e.name).ends_with("left") else 2 if str(e.name).ends_with("right") else 1
			pattern.set_cell(Vector2i(x,0),int(source_ids[source.key]),Vector2i(e.atlas_x,e.atlas_y),0)
		ts.add_pattern(pattern)

func _add_animations() -> void:
	var specs: Array = []
	for pack: String in ["vol2", "vol3"]:
		specs.append([pack, "collectibles", "coin_spin", ["coin_spin_0","coin_spin_1","coin_spin_2","coin_spin_3"], 8.333333, "marker"])
		specs.append([pack, "gadgets", "spring_preview", ["spring_idle","spring_extended"], 5.0, "marker"])
		specs.append([pack, "gadgets", "checkpoint_preview", ["checkpoint_off","checkpoint_on"], 2.5, "marker"])
	specs.append(["vol2","liquid","lava_surface",["lava_top_a","lava_top_b"],3.333333,"liquid"])
	specs.append(["vol3","liquid","swamp_surface",["swamp_top_a","swamp_top_b"],3.333333,"liquid"])
	for i: int in range(specs.size()):
		var spec: Array = specs[i]
		var image := Image.create(16 * spec[3].size(),16,false,Image.FORMAT_RGBA8)
		for f: int in range(spec[3].size()):
			var entry: Dictionary = sprites[spec[0]+"/"+spec[1]+"/"+spec[3][f]]
			var frame: Image = (load(entry.texture_path) as Texture2D).get_image()
			image.blit_rect(frame,Rect2i(0,0,16,16),Vector2i(f*16,0))
		var file_path: String = "res://assets/atlases/animated_"+spec[0]+"_"+spec[2]+".png"
		image.save_png(file_path)
		var e := {"key":spec[0]+"/animated/"+spec[2],"name":spec[2],"category":spec[1],"pack":spec[0],"behavior":spec[5],"source_key":"animated_"+spec[0]+"_"+spec[2],"atlas_x":0,"atlas_y":0,"atlas_w":1,"atlas_h":1,"width":16,"height":16,"texture_path":file_path,"animated":true,"frames":spec[3].size()}
		var id: int = manifest.sources.size()+i
		source_ids[e.source_key] = id
		sprites[e.key] = e
		for set_key: String in tile_sets:
			if not _include(set_key,e): continue
			var ts: TileSet = tile_sets[set_key]
			var atlas := TileSetAtlasSource.new()
			atlas.resource_name = "动画 / " + spec[0] + " / " + spec[2]
			# Animation PNGs must be imported before this build step.
			atlas.texture = load(file_path)
			atlas.texture_region_size = Vector2i(16,16)
			ts.add_source(atlas,id)
			atlas.create_tile(Vector2i.ZERO)
			atlas.set_tile_animation_columns(Vector2i.ZERO,spec[3].size())
			atlas.set_tile_animation_frames_count(Vector2i.ZERO,spec[3].size())
			atlas.set_tile_animation_speed(Vector2i.ZERO,float(spec[4]))
			_configure_tile(ts,atlas.get_tile_data(Vector2i.ZERO,0),e,set_key)

func _set_path(key: String) -> String:
	return "res://tilesets/" + str(SET_NAMES[key]) + ".tres"

func _make_level(empty: bool) -> void:
	var world := Node2D.new()
	world.name = "WhiteboxTemplate" if empty else "WhiteboxTest"
	world.set_script(load("res://scripts/whitebox_world.gd"))
	world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var layers: Dictionary = {}
	for spec: Array in LAYERS:
		var layer := TileMapLayer.new()
		layer.name = spec[0]
		layer.tile_set = tile_sets[spec[1]]
		layer.z_index = spec[2]
		layer.add_to_group("whitebox_tiles")
		world.add_child(layer)
		layer.owner = world
		layers[spec[1]] = layer
		if spec[1]=="background": layer.modulate = Color(0.35,0.4,0.5,1)
	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = Vector2(56,288) if not empty else Vector2(56,160)
	spawn.gizmo_extents = 8
	world.add_child(spawn)
	spawn.owner = world
	var player: CharacterBody2D = load("res://scenes/actors/test_player.tscn").instantiate()
	player.name = "Player"
	player.position = spawn.position
	player.z_index = 20
	world.add_child(player)
	player.owner = world
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = Vector2(320,180)
	world.add_child(camera)
	camera.owner = world
	if not empty:
		_rect(layers.terrain,"forest","grass",Rect2i(0,18,40,5))
		_rect(layers.terrain,"vol2","cave",Rect2i(12,15,4,3))
		_rect(layers.terrain,"vol3","castle",Rect2i(30,12,4,6))
		_rect(layers.background,"vol2","cave",Rect2i(10,7,7,11))
		_rect(layers.background,"vol3","castle",Rect2i(28,6,8,12))
		_platform(layers.platforms,"forest","grass",6,16,5)
		_platform(layers.platforms,"vol2","cave",16,13,5)
		_platform(layers.platforms,"vol3","castle",23,10,5)
		for y: int in range(12,18): _put(layers.climb,"vol2/climb/ladder_mid",Vector2i(21,y))
		_put(layers.climb,"vol2/climb/ladder_top",Vector2i(21,11))
		for x: int in range(25,29): _put(layers.hazards,"vol2/hazards/spikes_up",Vector2i(x,17))
		for x: int in range(35,39): _put(layers.liquids,"vol2/animated/lava_surface",Vector2i(x,17))
		_put(layers.decoration,"forest/trees/tree_oak",Vector2i(0,15))
		_put(layers.decoration,"forest/nature/flower_blue",Vector2i(5,17))
		_put(layers.interactables,"vol3/doors/door_open",Vector2i(31,10))
		_put(layers.interactables,"vol2/animated/coin_spin",Vector2i(18,10))
	else:
		# A small removable starting floor keeps the template immediately runnable.
		_rect(layers.terrain,"forest","stone",Rect2i(0,10,12,3))
	var packed := PackedScene.new()
	packed.pack(world)
	_save(packed,"res://scenes/levels/"+("whitebox_template.tscn" if empty else "whitebox_test.tscn"))
	world.free()

func _rect(layer: TileMapLayer, pack: String, theme: String, rect: Rect2i) -> void:
	for y: int in range(rect.size.y):
		for x: int in range(rect.size.x):
			var suffix: String = ("tl" if x==0 else "tr" if x==rect.size.x-1 else "top") if y==0 else (("bl" if x==0 else "br" if x==rect.size.x-1 else "bottom") if y==rect.size.y-1 else ("left" if x==0 else "right" if x==rect.size.x-1 else "center"))
			_put(layer,pack+"/terrain/"+theme+"_"+suffix,rect.position+Vector2i(x,y))

func _platform(layer: TileMapLayer, pack: String, theme: String, x: int, y: int, width: int) -> void:
	for dx: int in range(width):
		var suffix: String = "left" if dx==0 else "right" if dx==width-1 else "mid"
		_put(layer,pack+"/platforms/"+theme+"_plat_"+suffix,Vector2i(x+dx,y))

func _put(layer: TileMapLayer, key: String, cell: Vector2i) -> void:
	if not sprites.has(key):
		errors.append("Missing demo sprite: "+key)
		return
	var e: Dictionary = sprites[key]
	layer.set_cell(cell,int(source_ids[e.source_key]),Vector2i(e.atlas_x,e.atlas_y))

func _make_catalog() -> void:
	var world := Node2D.new()
	world.name = "AssetCatalog"
	world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var layer := TileMapLayer.new()
	layer.name = "Catalog_全部素材"
	layer.tile_set = tile_sets.all
	layer.collision_enabled = false
	world.add_child(layer)
	layer.owner = world
	var row: int = 2
	for source: Dictionary in manifest.sources:
		var title := Label.new()
		title.text = source.label
		title.position = Vector2(0,(row-1)*16)
		title.add_theme_font_size_override("font_size",10)
		world.add_child(title)
		title.owner = world
		var x: int = 0
		var height: int = 1
		for key: String in source.sprite_keys:
			var e: Dictionary = sprites[key]
			_put(layer,key,Vector2i(x,row))
			x += int(e.atlas_w)+1
			height = maxi(height,int(e.atlas_h))
		row += height+3
	var packed := PackedScene.new()
	packed.pack(world)
	_save(packed,"res://scenes/reference/asset_catalog.tscn")
	world.free()

func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource,path)
	if err != OK:
		errors.append("Save failed %s: %s" % [path,err])
	else:
		# Packed scenes must reference the reusable external TileSets, rather than embedding copies.
		resource.take_over_path(path)

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t"))
