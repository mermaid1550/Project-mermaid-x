#!/usr/bin/env python3
"""render_asset.py – Blender Cycles CPU-Render für Lóng Chéng Marketing-Shots.

Braucht KEINE GPU: Cycles läuft komplett auf CPU (auch in dieser VM).
Exportiert PNG-Rendering(s) eines glTF-Modells aus assets/models/ –
für Steam-Seite, App-Store, Social oder Doku.

    blender --background --python tools/ai3d/blender/render_asset.py -- \
        --file assets/models/machine_game.glb \
        --out renders/machine.png \
        --resolution 1280x720 --samples 48

Optionen:
    --file PATH       zu renderndes glTF/GLB (Pflicht)
    --out PATH        Ziel-PNG (Default: renders/<stamm>.png)
    --resolution WxH  Auflösung (Default 1280x720)
    --samples N       Cycles-Samples (Default 48; niedrig = schnell)
    --turntable       8 Ansichten (0..315°) statt einer Kamera-Ansicht
    --dark            Cyberpunk-Nachtstimmung (Default) | --dark off = neutral
"""

from __future__ import annotations

import argparse
import math
import sys
import time
from pathlib import Path

try:
    import bpy  # type: ignore
    from mathutils import Vector  # type: ignore
except ImportError:
    print("FEHLER: nur in Blender ausführbar: blender --background --python render_asset.py -- ...")
    sys.exit(2)


def blender_argv() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Lóng Chéng Asset-Renderer (Cycles CPU)")
    p.add_argument("--file", required=True, type=Path)
    p.add_argument("--out", type=Path, default=None)
    p.add_argument("--resolution", default="1280x720")
    p.add_argument("--samples", type=int, default=48)
    p.add_argument("--turntable", action="store_true")
    p.add_argument("--dark", nargs="?", const="on", default="on", choices=["on", "off"])
    return p.parse_args(argv)


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path: Path) -> list:
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"FEHLER: keine Meshes in {path}")
    # Modell auf Ursatz ausrichten: minX/minZ auf 0, Grundfläche auf y=0
    min_corner = Vector((1e9, 1e9, 1e9))
    max_corner = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            min_corner = Vector(map(min, min_corner, world))
            max_corner = Vector(map(max, max_corner, world))
    offset = Vector((-min_corner.x, -min_corner.y, -min_corner.z))
    for obj in meshes:
        obj.location += offset
    size = max_corner - min_corner
    return meshes, size, offset


def setup_scene(dark: bool) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_percentage = 100

    # Boden (schwarzes Studio-Tablett mit leichtem Reflex)
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "StudioFloor"
    mat = bpy.data.materials.new("FloorMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.02, 0.02, 0.03, 1) if dark else (0.6, 0.6, 0.62, 1)
    bsdf.inputs["Roughness"].default_value = 0.35
    floor.data.materials.append(mat)

    # Umgebungs-Hintergrund
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    if dark:
        bg.inputs["Color"].default_value = (0.01, 0.008, 0.02, 1)
        bg.inputs["Strength"].default_value = 1.0
    else:
        bg.inputs["Color"].default_value = (0.35, 0.36, 0.4, 1)
        bg.inputs["Strength"].default_value = 1.0

    # Drei-Punkt-Beleuchtung: Key (warm), Fill (kühl), Rim (Neon-Magenta)
    def area(name, loc, rot, energy, size, color):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        obj.rotation_euler = rot
        bpy.context.collection.objects.link(obj)
        return obj

    area("Key", (4, 6, 5), (math.radians(-40), math.radians(25), math.radians(140)),
         700, 5.0, (1.0, 0.95, 0.88))
    area("Fill", (-5, 3, 3), (math.radians(-60), math.radians(-30), math.radians(-120)),
         250, 6.0, (0.75, 0.82, 1.0))
    area("Rim", (0, -5, 4), (math.radians(-55), 0, math.radians(180)),
         500, 4.0, (1.0, 0.25, 0.75) if dark else (1, 1, 1))


def place_camera(target: Vector, distance: float, height: float, angle_deg: float) -> None:
    camera_data = bpy.data.cameras.new("Cam")
    camera_data.lens = 50
    cam = bpy.data.objects.new("Cam", camera_data)
    bpy.context.collection.objects.link(cam)
    rad = math.radians(angle_deg)
    cam.location = Vector((
        target.x + distance * math.sin(rad),
        target.y - distance * math.cos(rad),
        height,
    ))
    direction = target + Vector((0, 0, 0.5)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam


def render(out: Path, samples: int) -> None:
    scene = bpy.context.scene
    scene.cycles.samples = samples
    out.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)


def main() -> int:
    args = parse_args(blender_argv())
    if not args.file.exists():
        print(f"FEHLER: {args.file} nicht gefunden")
        return 1

    width, height = (int(v) for v in args.resolution.lower().split("x"))
    width, height = int(width), int(height)
    started = time.time()
    reset()
    meshes, size, _ = import_model(args.file)
    setup_scene(dark=(args.dark == "on"))

    target = Vector((size.x / 2, size.y / 2, size.z / 2))
    distance = max(size.x, size.y, size.z) * 2.2
    cam_height = size.z * 1.1

    default_out = Path("renders") / f"{args.file.stem}.png"
    out = args.out or default_out

    if args.turntable:
        base = out.parent / out.stem
        for angle in range(0, 360, 45):
            place_camera(target, distance, cam_height, angle)
            render(Path(f"{base}_{angle:03d}.png"), args.samples)
            print(f"✅ {base}_{angle:03d}.png")
    else:
        bpy.context.scene.render.resolution_x = int(width)
        bpy.context.scene.render.resolution_y = int(height)
        place_camera(target, distance, cam_height, 35)
        render(out, args.samples)
        print(f"✅ {out}")

    print(f"⏱ {time.time() - started:.1f}s | {args.samples} Samples | CPU")
    return 0


if __name__ == "__main__":
    sys.exit(main())
