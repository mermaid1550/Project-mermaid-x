#!/usr/bin/env python3
"""auto_prep_asset.py – Blender Headless Asset-Pipeline für Lóng Chéng.

Kapitel-4/6 Bible: AI-generierte Rohteile (TRELLIS/Hunyuan3D/TripoSR,
.gltf/.glb/.obj) werden automatisch bereinigt, geglättet, entpackt,
ge-Decimated, mit PBR-Texturen belegt und als optimiertes glTF nach
der Godot-4-Projektstruktur exportiert.

Aufruf (Blender 4.x, komplett headless):

    blender --background --python tools/ai3d/blender/auto_prep_asset.py -- \
        --input  tools/ai3d/inbox \
        --output assets/models \
        --max-tris 12000

    # Einzeldatei:
    blender --background --python auto_prep_asset.py -- \
        --file tools/ai3d/inbox/machine.glb --output assets/models

Optionen:
    --input DIR      Ordner mit AI-Rohteilen (verarbeitet neue Dateien)
    --file FILE      einzelne Datei verarbeiten
    --output DIR     Zielordner relativ zum Projektroot (Default: assets/models)
    --max-tris N     Ziel-Oberflächenzahl; darüber wird dekrementiert
    --bake           PBR-Maps aus dem Material bake sonst nur zuordnen
    --bake-res N     Auflösung der Bakes (Default 2048)
    --no-uv          Smart-UV-Projektion unterdrücken
    --dry-run        alles außer Export ausführen

Läuft NICHT in Blender: das Skript prüft das selbst und bricht mit
Fehlermeldung ab (damit CI-Tests ohne Blender sauber fehlschlagen).
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Blender-Guard: import bpy erst nach Argumentparse, damit `--self-test`
# ohne Blender lauffähig ist (prüft Pipeline-Logik ohne bpy).
# ---------------------------------------------------------------------------
SELF_TEST = "--self-test" in sys.argv

try:
    import bpy  # type: ignore
    from mathutils import Vector  # type: ignore

    HAVE_BPY = True
except ImportError:
    bpy = None  # type: ignore
    Vector = None  # type: ignore
    HAVE_BPY = False

AI_EXTENSIONS = {".gltf", ".glb", ".obj"}
PROCESSED_TAG = "_game"  # verhindert Doppelverarbeitung eigener Outputs

# PBR-Rollen für die Texturen-Zuordnung. Reihenfolge = Zuordnungsprinzip.
TEXTURE_SLOTS = {
    "albedo": ["albedo", "basecolor", "base_color", "diffuse", "diff", "color"],
    "roughness": ["roughness", "rough", "orm_r", "r_rough"],
    "normal": ["normal", "nor", "nmap", "nrm"],
    "emission": ["emission", "emissive", "emit", "glow"],
    "metallic": ["metallic", "metalness", "metal"],
}


# --------------------------------------------------------------------- CLI
def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Lóng Chéng Blender Asset-Prep")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--input", type=Path, help="Ordner mit AI-Rohteilen")
    group.add_argument("--file", type=Path, help="einzelne Eingabedatei")
    parser.add_argument("--output", type=Path, default=Path("assets/models"))
    parser.add_argument("--max-tris", type=int, default=12000)
    parser.add_argument("--bake", action="store_true")
    parser.add_argument("--bake-res", type=int, default=2048)
    parser.add_argument("--no-uv", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true", help="Pipeline-Logik ohne bpy testen")
    return parser.parse_args(argv)


def blender_argv() -> list[str]:
    """Argumente nach dem `--`-Trenner von Blender."""
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1:]


# ------------------------------------------------------- Projekt-Ermittlung
def find_project_root(start: Path) -> Path:
    """Findest den Ordner mit project.godot – Ausgabe geht immer dorthin."""
    for candidate in [start] + list(start.parents):
        if (candidate / "project.godot").exists():
            return candidate
    raise SystemExit("FEHLER: project.godot nicht gefunden – bitte im Projekt ausführen.")


def collect_inputs(args: argparse.Namespace) -> list[Path]:
    if args.file:
        files = [args.file]
    else:
        files = sorted(
            p for p in args.input.iterdir()
            if p.suffix.lower() in AI_EXTENSIONS and PROCESSED_TAG not in p.stem
        )
    missing = [p for p in files if not p.exists()]
    if missing:
        raise SystemExit(f"FEHLER: Eingabedatei(en) nicht gefunden: {missing}")
    return files


def find_textures(source: Path) -> dict[str, Path]:
    """Sucht Begleit-Texturen gleichen Stammes (z.B. machine_albedo.png)."""
    directory = source.parent if source.is_file() else source
    found: dict[str, Path] = {}
    for path in sorted(directory.iterdir()):
        if path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".tga", ".exr"}:
            continue
        stem = path.stem.lower()
        for slot, keywords in TEXTURE_SLOTS.items():
            if slot in found:
                continue
            if any(keyword in stem for keyword in keywords):
                found[slot] = path
    return found


# ------------------------------------------------------------ bpy-Pipeline
def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path: Path) -> list:
    suffix = path.suffix.lower()
    if suffix == ".obj":
        # Blender 4.1+: wm.obj_import, älter: import_scene.obj
        try:
            bpy.ops.wm.obj_import(filepath=str(path))
        except AttributeError:
            bpy.ops.import_scene.obj(filepath=str(path))
    else:
        bpy.ops.import_scene.gltf(filepath=str(path))
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def cleanup_mesh(objects: list) -> dict:
    """Merge by distance, Loose Parts, triangulieren, Normals konsistent."""
    stats = {"merged_verts": 0, "removed_faces": 0}
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    before_verts = _vert_count()
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    stats["merged_verts"] = before_verts - _vert_count()

    before_faces = _face_count()
    bpy.ops.mesh.delete_loose()
    stats["removed_faces"] = before_faces - _face_count()

    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return stats


def _vert_count() -> int:
    return sum(len(obj.data.vertices) for obj in bpy.context.selected_objects if obj.type == "MESH")


def _face_count() -> int:
    return sum(len(obj.data.polygons) for obj in bpy.context.selected_objects if obj.type == "MESH")


def smooth_normals(objects: list) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.shade_smooth()
    # Auto Smooth über Modifier (Blender 4.1+): 30° – harte Kanten bleiben hart.
    for obj in objects:
        if not any(m.name == "Smooth by Angle" for m in obj.modifiers):
            bpy.context.view_layer.objects.active = obj
            try:
                bpy.ops.object.shade_auto_smooth(angle=0.523599)  # 30°
            except RuntimeError:
                mod = obj.modifiers.new("Smooth by Angle", "NODES")
                mod.node_group = _ensure_smooth_by_angle_group()


def _ensure_smooth_by_angle_group():
    """Die von Blender mitgelieferte 'Smooth by Angle' NodeGroup nachbauen."""
    group = bpy.data.node_groups.get("Smooth by Angle") or bpy.data.node_groups.new(
        "Smooth by Angle", "ShaderNodeTree"
    )
    if not group.nodes:
        group.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
        group.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
        group.interface.new_socket("Shade Smooth", in_out="OUTPUT", socket_type="NodeSocketBool")
        nodes, links = group.nodes, group.links
        n_in = nodes.new("NodeGroupInput")
        n_out = nodes.new("NodeGroupOutput")
        n_split = nodes.new("GeometryNodeSplitEdges")
        n_smooth = nodes.new("GeometryNodeSetShadeSmooth")
        n_smooth.inputs["Shade Smooth"].default_value = True
        links.new(n_in.outputs[0], n_split.inputs["Mesh"])
        links.new(n_split.outputs["Mesh"], n_smooth.inputs["Geometry"])
        links.new(n_smooth.outputs["Geometry"], n_out.inputs[0])
    return group


def ensure_uvs(objects: list, skip: bool) -> dict:
    """Smart-UV-Projektion nur, wenn ein Mesh gar keine UVs hat."""
    stats = {"unwrapped": 0, "skipped": 0}
    if skip:
        stats["skipped"] = len(objects)
        return stats
    for obj in objects:
        if obj.data.uv_layers:
            stats["skipped"] += 1
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.02)  # 66°
        bpy.ops.object.mode_set(mode="OBJECT")
        stats["unwrapped"] += 1
    return stats


def decimate(objects: list, max_tris: int) -> dict:
    """Reduziert auf Ziel-Oberflächenzahl, falls das Rohteil zu schwer ist."""
    stats = {"before": 0, "after": 0, "decimated": 0}
    for obj in objects:
        obj.data.calc_loop_triangles()
        stats["before"] += len(obj.data.loop_triangles)
    if stats["before"] <= max_tris:
        stats["after"] = stats["before"]
        return stats
    per_object_budget = max(1, int(max_tris / max(1, len(objects))))
    for obj in objects:
        obj.data.calc_loop_triangles()
        current = len(obj.data.loop_triangles)
        if current <= per_object_budget:
            continue
        ratio = per_object_budget / current
        modifier = obj.modifiers.new("Decimate", "DECIMATE")
        modifier.ratio = ratio
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        stats["decimated"] += 1
    for obj in objects:
        obj.data.calc_loop_triangles()
        stats["after"] += len(obj.data.loop_triangles)
    return stats


def ensure_material(obj) -> object:
    if obj.data.materials:
        material = obj.data.materials[0]
    else:
        material = bpy.data.materials.new(name=f"MAT_{obj.name}")
        obj.data.materials.append(material)
    material.use_nodes = True
    return material


def assign_textures(obj, textures: dict[str, Path]) -> list[str]:
    """Hängt gefundene PBR-Maps an den Principled BSDF (Godot-kompatibel)."""
    if not textures:
        return []
    material = ensure_material(obj)
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        links.new(bsdf.outputs["BSDF"], next(n for n in nodes if n.type == "OUTPUT_MATERIAL").inputs["Surface"])

    assigned = []
    for slot, path in textures.items():
        texture_node = nodes.new("ShaderNodeTexImage")
        texture_node.name = f"TX_{slot}"
        texture_node.image = bpy.data.images.load(str(path), check_existing=True)
        texture_node.location = (-600, 100 - 250 * len(assigned))
        # Daten-Maps brauchen Non-Color, Albedo bleibt sRGB.
        if slot != "albedo":
            texture_node.image.colorspace_settings.name = "Non-Color"

        target = {
            "albedo": "Base Color",
            "roughness": "Roughness",
            "metallic": "Metallic",
            "emission": "Emission Color",
        }.get(slot)
        if slot == "normal":
            normal_map = nodes.new("ShaderNodeNormalMap")
            normal_map.location = (-300, -400)
            links.new(texture_node.outputs["Color"], normal_map.inputs["Color"])
            links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
        elif slot == "emission":
            links.new(texture_node.outputs["Color"], bsdf.inputs[target])
            bsdf.inputs["Emission Strength"].default_value = 2.5
        elif target:
            links.new(texture_node.outputs["Color"], bsdf.inputs[target])
        assigned.append(slot)
    return assigned


def bake_pbr(objects: list, textures_dir: Path, resolution: int) -> dict:
    """Bakt Albedo/Roughness/Emission aus den bestehenden Materialen (Cycles)."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1  # Farb-/Wertbakes brauchen keine Rays
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.image_settings.file_format = "PNG"
    scene.render.bake.margin = 16
    scene.render.bake.use_clear = True

    baked: dict[str, int] = {}
    passes = {"albedo": "DIFFUSE", "roughness": "ROUGHNESS", "emission": "EMIT"}
    for slot, bake_type in passes.items():
        images = []
        for obj in objects:
            material = ensure_material(obj)
            nodes = material.node_tree.nodes
            bake_node = nodes.new("ShaderNodeTexImage")
            bake_node.name = f"BAKE_{slot}"
            bake_node.location = (-600, -900)
            bake_image = bpy.data.images.new(
                f"BAKE_{obj.name}_{slot}", width=resolution, height=resolution
            )
            bake_node.image = bake_image
            nodes.active = bake_node
            images.append((obj, bake_node, bake_image))

        bpy.ops.object.select_all(action="DESELECT")
        for obj, _, _ in images:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]

        if bake_type == "DIFFUSE":
            # Nur die Farbe bakens, kein Licht (Sonst kommen Schatten in die Albedo).
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
        else:
            bpy.ops.object.bake(type=bake_type)

        for obj, node, image in images:
            target = textures_dir / f"{obj.name}_{slot}.png"
            image.filepath_raw = str(target)
            if slot != "albedo":
                image.colorspace_settings.name = "Non-Color"
            image.save()
            bpy.data.images.remove(image)
            node.image = None
            node.name = f"BAKE_{slot}_done"
        baked[slot] = len(images)
    return baked


def export_gltf(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",  # einzelne Datei, so wie ModelLoader3D sie lädt
        export_yup=True,
        export_apply=True,  # Modifier (Decimate/Smooth) einbacken
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )


# -------------------------------------------------------------- Pipeline
def process_file(source: Path, args: argparse.Namespace, root: Path) -> dict:
    started = time.time()
    reset_scene()

    objects = import_model(source)
    if not objects:
        raise RuntimeError(f"{source.name}: keine Mesh-Objekte importiert")

    cleanup = cleanup_mesh(objects)
    smooth_normals(objects)
    uvs = ensure_uvs(objects, args.no_uv)
    tris = decimate(objects, args.max_tris)

    textures = find_textures(source)
    assigned: list[str] = []
    for obj in objects:
        assigned = assign_textures(obj, textures) or assigned

    baked: dict[str, int] = {}
    if args.bake:
        baked = bake_pbr(objects, (root / args.output / "_bakes"), args.bake_res)

    out_file = root / args.output / f"{source.stem}{PROCESSED_TAG}.glb"
    if args.dry_run:
        exported = False
    else:
        export_gltf(out_file)
        exported = True

    report = {
        "source": str(source),
        "output": str(out_file) if exported else None,
        "objects": len(objects),
        "cleanup": cleanup,
        "uv": uvs,
        "tris": tris,
        "textures_assigned": assigned,
        "textures_baked": baked,
        "seconds": round(time.time() - started, 1),
    }
    return report


def self_test() -> int:
    """Testet die bpy-freie Logik (Argumente, Texturen-Finder, Root-Suche)."""
    import tempfile

    failures = 0

    def check(condition: bool, message: str) -> None:
        nonlocal failures
        if condition:
            print(f"OK {message}")
        else:
            print(f"FEHLER {message}")
            failures += 1

    args = parse_args(["--input", "inbox", "--max-tris", "5000", "--bake", "--bake-res", "1024"])
    check(args.max_tris == 5000 and args.bake and args.bake_res == 1024, "CLI-Parser")

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        for name in ["machine_albedo.png", "machine_rough.png", "machine_nor.png",
                     "machine_emissive.png", "machine_metal.png", "photo.jpg"]:
            (tmpdir / name).write_bytes(b"x")
        found = find_textures(tmpdir)
        check(set(found) == {"albedo", "roughness", "normal", "emission", "metallic"},
              f"Texturen-Rollen-Erkennung ({sorted(found)})")
        check(find_textures(tmpdir)["albedo"].name == "machine_albedo.png",
              "Slot-Reihenfolge: albedo schlägt 'color'-Keyword nicht doppelt")

        # Root-Suche braucht project.godot – hier prüfen wir den Abbruchpfad
        try:
            find_project_root(tmpdir)
            check(False, "find_project_root muss ohne project.godot scheitern")
        except SystemExit:
            check(True, "find_project_root scheitert sauber ohne project.godot")

        # collect_inputs mit Datei, die existiert
        f = tmpdir / "in.glb"
        f.write_bytes(b"glTF")
        args2 = parse_args(["--file", str(f)])
        check(collect_inputs(args2) == [f], "collect_inputs einzelne Datei")

    print("SELF-TEST BESTANDEN ✔" if failures == 0 else f"SELF-TEST {failures} FEHLER ✗")
    return 1 if failures else 0


def main() -> int:
    args = parse_args(blender_argv() if not SELF_TEST else ["--input", ".", "--self-test"])

    if SELF_TEST:
        return self_test()

    if not HAVE_BPY:
        print(
            "FEHLER: 'bpy' nicht importierbar – dieses Skript läuft NUR in Blender:\n"
            "  blender --background --python auto_prep_asset.py -- --input <ordner>",
            file=sys.stderr,
        )
        return 2

    root = find_project_root(Path.cwd())
    inputs = collect_inputs(args)
    if not inputs:
        print(f"Keine neuen Dateien in {args.input} – fertig.")
        return 0

    reports = []
    for source in inputs:
        try:
            report = process_file(source, args, root)
        except Exception as error:  # noqa: BLE001 – Pipeline soll weiterlaufen
            print(f"❌ {source.name}: {type(error).__name__}: {error}", file=sys.stderr)
            continue
        reports.append(report)
        print(f"✅ {source.name} -> {Path(report['output']).name if report['output'] else '(dry-run)'} "
              f"| {report['objects']} Obj | {report['tris']['after']} Tris "
              f"| UV: {report['uv']} | Texturen: {report['textures_assigned']} "
              f"| {report['seconds']}s")

    if reports:
        manifest = root / args.output / "pipeline_report.json"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps(reports, indent=2, ensure_ascii=False))
        print(f"📄 Report: {manifest}")
    return 0 if reports or not inputs else 1


if __name__ == "__main__":
    sys.exit(main())
