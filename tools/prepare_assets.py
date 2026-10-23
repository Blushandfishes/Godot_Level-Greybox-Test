"""Import the original pixel-art packs and build lossless, category-based atlases.

Run from any directory. The original pack directory can be overridden with
--source-root; output stays in this Godot project unless --project-root is set.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import shutil

from PIL import Image


TILE_SIZE = 16
ATLAS_COLUMNS = 16
PACKS = {
    "forest": ("Pixel_Forest_Platformer_Tileset_v1.0", "森林", "Forest"),
    "vol2": ("Pixel_Platformer_Tileset_Vol2_v1.0", "洞穴与遗迹", "Vol. 2"),
    "vol3": ("Pixel_Platformer_Tileset_Vol3_v1.0", "城堡与沼泽", "Vol. 3"),
}
CATEGORIES = {
    "terrain": ("实体地形", "Terrain"),
    "platforms": ("单向平台", "Platforms"),
    "background": ("背景墙", "Background Walls"),
    "trees": ("树木", "Trees"),
    "bushes": ("灌木", "Bushes"),
    "clouds_sky": ("云与天空", "Clouds and Sky"),
    "nature": ("自然装饰", "Nature"),
    "props": ("场景道具", "Props"),
    "pickups": ("拾取物", "Pickups"),
    "hazards_gadgets": ("危险物与机关", "Hazards and Gadgets"),
    "liquid": ("液体", "Liquids"),
    "hazards": ("危险物", "Hazards"),
    "gadgets": ("机关状态", "Gadget States"),
    "moving_platform": ("移动平台组件", "Moving Platform Parts"),
    "collectibles": ("收集物", "Collectibles"),
    "climb": ("攀爬组件", "Climbing Parts"),
    "doors": ("门与出口", "Doors and Exits"),
    "cave": ("洞穴装饰", "Cave Decor"),
    "lava": ("火山装饰", "Lava Decor"),
    "ruins": ("遗迹装饰", "Ruins Decor"),
    "sky": ("天空装饰", "Sky Decor"),
    "castle": ("城堡装饰", "Castle Decor"),
    "swamp": ("沼泽装饰", "Swamp Decor"),
    "ice": ("冰雪装饰", "Ice Decor"),
    "desert": ("沙漠装饰", "Desert Decor"),
}
THEMES = {
    "grass": ("草地", "Grass"),
    "stone": ("岩石", "Stone"),
    "sand": ("沙地", "Sand"),
    "snow": ("雪地", "Snow"),
    "cave": ("洞穴", "Cave"),
    "lava": ("火山", "Lava"),
    "sky": ("天空", "Sky"),
    "ruins": ("遗迹", "Ruins"),
    "castle": ("城堡", "Castle"),
    "swamp": ("沼泽", "Swamp"),
    "ice": ("冰地", "Ice"),
    "desert": ("沙漠", "Desert"),
}
SOURCE_FILES = (
    "LICENSE.txt", "README.md", "spritesheet.json", "tileset.png",
    "spritesheet.png", "sample_scene.png", "sample_level.png",
)
ANIMATION_SPECS = (
    ("vol2", "collectibles", "coin_spin", ("coin_spin_0", "coin_spin_1", "coin_spin_2", "coin_spin_3")),
    ("vol3", "collectibles", "coin_spin", ("coin_spin_0", "coin_spin_1", "coin_spin_2", "coin_spin_3")),
    ("vol2", "gadgets", "spring_preview", ("spring_idle", "spring_extended")),
    ("vol3", "gadgets", "spring_preview", ("spring_idle", "spring_extended")),
    ("vol2", "gadgets", "checkpoint_preview", ("checkpoint_off", "checkpoint_on")),
    ("vol3", "gadgets", "checkpoint_preview", ("checkpoint_off", "checkpoint_on")),
    ("vol2", "liquid", "lava_surface", ("lava_top_a", "lava_top_b")),
    ("vol3", "liquid", "swamp_surface", ("swamp_top_a", "swamp_top_b")),
)


def read_rgba(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return image.convert("RGBA")


def resource_path(path: Path, project_root: Path) -> str:
    return "res://" + path.relative_to(project_root).as_posix()


def source_label(pack: str, category: str, theme: str) -> str:
    _, pack_cn, pack_en = PACKS[pack]
    category_cn, category_en = CATEGORIES.get(category, (category, category))
    if theme:
        theme_cn, theme_en = THEMES.get(theme, (theme, theme.title()))
        return f"{pack_cn} · {theme_cn}{category_cn} | {pack_en} / {theme_en} {category_en}"
    return f"{pack_cn} · {category_cn} | {pack_en} / {category_en}"


def prepare_animation_strips(project_root: Path) -> int:
    """Build importable animation PNGs without adding duplicate manifest sprites."""
    atlas_root = project_root / "assets" / "atlases"
    atlas_root.mkdir(parents=True, exist_ok=True)
    for pack, category, name, frame_names in ANIMATION_SPECS:
        frames = [
            read_rgba(project_root / "assets" / "tiles" / pack / "native" / category / f"{frame_name}.png")
            for frame_name in frame_names
        ]
        if any(frame.size != (TILE_SIZE, TILE_SIZE) for frame in frames):
            raise ValueError(f"Animation frames must be native 16x16 PNGs: {pack}/{name}")
        strip = Image.new("RGBA", (TILE_SIZE * len(frames), TILE_SIZE))
        for index, frame in enumerate(frames):
            strip.paste(frame, (index * TILE_SIZE, 0))
        destination = atlas_root / f"animated_{pack}_{name}.png"
        strip.save(destination, format="PNG", optimize=True)
        saved_strip = read_rgba(destination)
        for index, frame in enumerate(frames):
            reconstructed = saved_strip.crop((index * TILE_SIZE, 0, (index + 1) * TILE_SIZE, TILE_SIZE))
            if reconstructed.size != frame.size or reconstructed.tobytes() != frame.tobytes():
                raise ValueError(f"Animation strip changed native frame pixels: {pack}/{name}/{frame_names[index]}")
    return len(ANIMATION_SPECS)


def import_assets(source_root: Path, project_root: Path) -> dict:
    # Validate every input directory before writing output.
    for folder, _, _ in PACKS.values():
        native = source_root / folder / "PNG" / "native"
        if not native.is_dir():
            raise FileNotFoundError(f"Original native PNG folder does not exist: {native}")

    sprite_records: list[dict] = []
    groups: dict[str, list[dict]] = defaultdict(list)
    originals: dict[str, Image.Image] = {}
    pack_audits: dict[str, dict] = {}
    anomalies: list[dict] = []

    for pack, (folder, _, _) in PACKS.items():
        pack_root = source_root / folder
        native_root = pack_root / "PNG" / "native"
        destination_root = project_root / "assets" / "tiles" / pack
        source_destination = destination_root / "source"
        source_destination.mkdir(parents=True, exist_ok=True)
        (source_destination / ".gdignore").write_text("", encoding="utf-8")
        for filename in SOURCE_FILES:
            source = pack_root / filename
            if source.is_file():
                shutil.copy2(source, source_destination / filename)

        metadata = json.loads((pack_root / "spritesheet.json").read_text(encoding="utf-8"))
        frames = metadata["frames"]
        original_sheet = read_rgba(pack_root / "spritesheet.png")
        png_files = sorted(native_root.rglob("*.png"), key=lambda path: path.as_posix())
        category_counts: Counter = Counter()
        sizes: Counter = Counter()
        metadata_matches = 0

        for source in png_files:
            relative = source.relative_to(native_root)
            category = relative.parts[0]
            name = source.stem
            key = f"{pack}/{category}/{name}"
            image = read_rgba(source)
            width, height = image.size
            if width <= 0 or height <= 0 or width % TILE_SIZE or height % TILE_SIZE:
                raise ValueError(f"Native sprite is not aligned to the 16-pixel grid: {source}")
            if not image.getbbox():
                raise ValueError(f"Native sprite is empty: {source}")
            if width > TILE_SIZE * ATLAS_COLUMNS:
                raise ValueError(f"Sprite exceeds atlas width: {source}")
            if key in originals:
                raise ValueError(f"Duplicate asset key: {key}")

            destination = destination_root / "native" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

            theme = name.split("_", 1)[0] if category in {"terrain", "platforms"} else ""
            groupkey = "_".join(part for part in (pack, category, theme) if part)
            record = {
                "key": key,
                "pack": pack,
                "category": category,
                "name": name,
                "width": width,
                "height": height,
                "texture_path": resource_path(destination, project_root),
                "source_key": groupkey,
                "atlas_x": 0,
                "atlas_y": 0,
                "atlas_w": width // TILE_SIZE,
                "atlas_h": height // TILE_SIZE,
            }
            sprite_records.append(record)
            groups[groupkey].append(record)
            originals[key] = image
            category_counts[category] += 1
            sizes[f"{width}x{height}"] += 1

            frame = frames.get(name)
            if frame is None or frame.get("category") != category:
                anomaly = {
                    "type": "missing_or_conflicting_spritesheet_metadata",
                    "sprite_key": key,
                    "resolution": "Imported the original PNG by category and filename; no sprite was dropped.",
                }
                if pack == "vol3" and category == "terrain" and name == "ice_block":
                    anomaly["detail"] = "Two ice_block files share one JSON key; metadata points to ice/ice_block."
                    anomaly["recovered_original_sheet_rect"] = [240, 32, 16, 16]
                anomalies.append(anomaly)
            else:
                rect = (frame["x"], frame["y"], frame["x"] + frame["w"], frame["y"] + frame["h"])
                crop = original_sheet.crop(rect)
                if crop.size != image.size or crop.tobytes() != image.tobytes():
                    raise ValueError(f"Original spritesheet metadata differs from native PNG: {key}")
                metadata_matches += 1

        expected = metadata.get("meta", {}).get("count")
        if expected != len(frames):
            anomalies.append({
                "type": "metadata_count_mismatch",
                "pack": pack,
                "declared_sprite_count": expected,
                "json_frame_count": len(frames),
                "native_png_count": len(png_files),
            })
        pack_audits[pack] = {
            "original_folder": folder,
            "native_png_count": len(png_files),
            "json_frame_count": len(frames),
            "metadata_pixel_matches": metadata_matches,
            "category_counts": dict(sorted(category_counts.items())),
            "size_counts": dict(sorted(sizes.items())),
            "original_spritesheet_size": list(original_sheet.size),
            "original_tileset_size": list(read_rgba(pack_root / "tileset.png").size),
        }

    atlas_root = project_root / "assets" / "atlases"
    atlas_root.mkdir(parents=True, exist_ok=True)
    sources: list[dict] = []
    validated = 0
    for groupkey in sorted(groups):
        records = groups[groupkey]
        records.sort(key=lambda record: (-record["atlas_h"], -record["atlas_w"], record["name"]))
        cursor_x = cursor_y = shelf_height = 0
        for record in records:
            width, height = record["atlas_w"], record["atlas_h"]
            if cursor_x + width > ATLAS_COLUMNS:
                cursor_x = 0
                cursor_y += shelf_height
                shelf_height = 0
            record["atlas_x"] = cursor_x
            record["atlas_y"] = cursor_y
            cursor_x += width
            shelf_height = max(shelf_height, height)
        atlas = Image.new("RGBA", (ATLAS_COLUMNS * TILE_SIZE, (cursor_y + shelf_height) * TILE_SIZE))
        for record in records:
            # Paste RGBA pixels directly. Passing an alpha mask would alter semitransparent pixels.
            atlas.paste(originals[record["key"]], (record["atlas_x"] * TILE_SIZE, record["atlas_y"] * TILE_SIZE))
        atlas_path = atlas_root / f"{groupkey}.png"
        atlas.save(atlas_path, format="PNG", optimize=True)
        saved_atlas = read_rgba(atlas_path)
        for record in records:
            x, y = record["atlas_x"] * TILE_SIZE, record["atlas_y"] * TILE_SIZE
            reconstructed = saved_atlas.crop((x, y, x + record["width"], y + record["height"]))
            original = originals[record["key"]]
            copied = read_rgba(project_root / record["texture_path"].removeprefix("res://"))
            if reconstructed.size != original.size or reconstructed.tobytes() != original.tobytes():
                raise ValueError(f"Atlas changed sprite pixels: {record['key']}")
            if copied.size != original.size or copied.tobytes() != original.tobytes():
                raise ValueError(f"Copied native PNG changed sprite pixels: {record['key']}")
            validated += 1
        first = records[0]
        category = first["category"]
        theme = first["name"].split("_", 1)[0] if category in {"terrain", "platforms"} else ""
        sources.append({
            "key": groupkey,
            "label": source_label(first["pack"], category, theme),
            "pack": first["pack"],
            "category": category,
            "theme": theme,
            "texture_path": resource_path(atlas_path, project_root),
            "sprite_keys": [record["key"] for record in records],
        })

    # Write these before the first Godot import pass so its build script can load them.
    prepare_animation_strips(project_root)
    sprite_records.sort(key=lambda record: record["key"])
    manifest = {"tile_size": TILE_SIZE, "sprites": sprite_records, "sources": sources}
    audit = {
        "tile_size": TILE_SIZE,
        "atlas_columns": ATLAS_COLUMNS,
        "atlas_margin": 0,
        "atlas_separation": 0,
        "counts": {
            "packs": len(PACKS),
            "sprites": len(sprite_records),
            "atlas_sources": len(sources),
            "single_cell_sprites": sum(record["atlas_w"] == 1 and record["atlas_h"] == 1 for record in sprite_records),
            "multi_cell_sprites": sum(record["atlas_w"] != 1 or record["atlas_h"] != 1 for record in sprite_records),
            "native_and_atlas_pixel_validations": validated,
        },
        "packs": pack_audits,
        "anomalies": anomalies,
        "notes": [
            "All 387 original native PNGs are preserved, including both Vol. 3 ice_block files.",
            "Large objects keep their original full frame and transparency; no artwork is cropped or resized.",
            "Original source documents and reference sheets are stored under each pack's source/.gdignore.",
            "x4 PNGs duplicate native artwork; GIFs are enlarged previews, so neither are imported as extra sprites.",
            "Terrain packs provide outer corners and edges, but not all concave-corner or narrow-connection combinations.",
            "Animation atlases are prepared separately from these static categorized atlases.",
        ],
        "license": {
            "author": "reodesuxz",
            "personal_and_commercial_projects": True,
            "project_modifications": True,
            "attribution_required": False,
            "standalone_asset_redistribution": False,
            "ai_training": False,
            "original_license_preserved_for_each_pack": True,
        },
    }
    for path, content in ((project_root / "data" / "asset_manifest.json", manifest), (project_root / "docs" / "asset_audit.json", audit)):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return audit


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=Path(r"C:\Users\24569\Desktop\黑客松Jam\白盒素材"))
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    audit = import_assets(args.source_root.resolve(), args.project_root.resolve())
    print(json.dumps({"counts": audit["counts"], "anomalies": audit["anomalies"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
