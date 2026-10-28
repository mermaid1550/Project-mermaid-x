#!/usr/bin/env python3
"""Lóng Chéng Asset-Generator: erzeugt spielbare GLB-Modelle ohne AI-GPU.

Dies ist der 0-Abhängigkeiten-Grundstein der Pipeline (Kapitel 4/6 Bible):
prozedurale Geometrie -> glTF 2.0 Binary (.glb), direkt ladbar über
ModelLoader3D. Für AI-generierte Assets ohne eigene Geometrie ersetzt man
die Teile-Definition unten durch einen TripoSR/Hunyuan3D-Output (siehe
README.md im selben Ordner).

    python3 tools/ai3d/generate_buildings.py

Ausgabe: assets/ai_models/house.glb, assets/ai_models/tower.glb
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "ai_models"

# --------------------------------------------------------------- sRGB -> linear
def lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(hex_str: str) -> tuple[float, float, float]:
    h = hex_str.lstrip("#")
    return tuple(lin(int(h[i : i + 2], 16) / 255) for i in (0, 2, 4))  # type: ignore[return-value]


# ----------------------------------------------------------------- Materialien
MATERIALS = [
    ("walls", "#E8DCC8", 0.0, 0.9, None),
    ("roof", "#E0246B", 0.1, 0.5, None),
    ("wood", "#5A3A22", 0.0, 0.8, None),
    ("glow_cyan", "#28E0FF", 0.0, 0.3, "#28E0FF"),
    ("concrete", "#9A9A9A", 0.0, 0.95, None),
    ("tower_body", "#1B2340", 0.2, 0.7, None),
    ("glow_magenta", "#FF3DC8", 0.0, 0.3, "#FF3DC8"),
    ("metal", "#C8C8C8", 0.9, 0.35, None),
]


class Part:
    """Ein Mesh-Teil: flache Polygone mit berechneten Normals, Weltkoordinaten."""

    def __init__(self, name: str, mat: int) -> None:
        self.name = name
        self.mat = mat
        self.pos: list[tuple[float, float, float]] = []
        self.nrm: list[tuple[float, float, float]] = []
        self.idx: list[int] = []

    @staticmethod
    def _normal(a, b, c):
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        length = math.sqrt(sum(c * c for c in n)) or 1.0
        return (n[0] / length, n[1] / length, n[2] / length)

    def quad(self, a, b, c, d) -> None:
        n = self._normal(a, b, c)
        base = len(self.pos)
        self.pos.extend((a, b, c, d))
        self.nrm.extend((n, n, n, n))
        self.idx.extend((base, base + 1, base + 2, base, base + 2, base + 3))

    def tri(self, a, b, c) -> None:
        n = self._normal(a, b, c)
        base = len(self.pos)
        self.pos.extend((a, b, c))
        self.nrm.extend((n, n, n))
        self.idx.extend((base, base + 1, base + 2))

    def box(self, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> None:
        # 6 Quads, CCW von außen gesehen (glTF-Standard)
        self.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))  # +z
        self.quad((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0))  # -z
        self.quad((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1))  # +x
        self.quad((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0))  # -x
        self.quad((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0))  # +y
        self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1))  # -y


# ------------------------------------------------------------------ GLB-Writer
def build_glb(parts: list[Part], path: Path) -> tuple[int, int]:
    binary = bytearray()
    accessors: list[dict] = []
    buffer_views: list[dict] = []
    meshes: list[dict] = []
    nodes: list[dict] = []

    def add_view(data: bytes, target: int) -> int:
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        binary.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(buffer_views) - 1

    total_tris = 0
    for part in parts:
        pos_bytes = b"".join(struct.pack("<3f", *p) for p in part.pos)
        nrm_bytes = b"".join(struct.pack("<3f", *n) for n in part.nrm)
        idx_bytes = struct.pack(f"<{len(part.idx)}I", *part.idx)

        pv = add_view(pos_bytes, 34962)
        nv = add_view(nrm_bytes, 34962)
        iv = add_view(idx_bytes, 34963)

        xs, ys, zs = zip(*part.pos)
        accessors.append(
            {
                "bufferView": pv,
                "componentType": 5126,
                "count": len(part.pos),
                "type": "VEC3",
                "min": [min(xs), min(ys), min(zs)],
                "max": [max(xs), max(ys), max(zs)],
            }
        )
        pos_acc = len(accessors) - 1
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(part.nrm), "type": "VEC3"})
        nrm_acc = len(accessors) - 1
        accessors.append({"bufferView": iv, "componentType": 5125, "count": len(part.idx), "type": "SCALAR"})
        idx_acc = len(accessors) - 1

        meshes.append(
            {
                "name": part.name,
                "primitives": [
                    {"attributes": {"POSITION": pos_acc, "NORMAL": nrm_acc}, "indices": idx_acc, "material": part.mat}
                ],
            }
        )
        nodes.append({"name": part.name, "mesh": len(meshes) - 1})
        total_tris += len(part.idx) // 3

    gltf_materials = []
    for name, color, metallic, roughness, emissive in MATERIALS:
        mat = {
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": [*rgb(color), 1.0],
                "metallicFactor": metallic,
                "roughnessFactor": roughness,
            },
        }
        if emissive:
            mat["emissiveFactor"] = list(rgb(emissive))
        gltf_materials.append(mat)

    gltf = {
        "asset": {"version": "2.0", "generator": "longcheng-generate_buildings"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": gltf_materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(binary)}],
    }

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    while len(binary) % 4:
        binary.append(0)

    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    blob = struct.pack("<III", 0x46546C67, 2, total)
    blob += struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    blob += struct.pack("<II", len(binary), 0x004E4942) + bytes(binary)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(blob)
    return len(nodes), total_tris


# ------------------------------------------------------------------- Modelle
def house() -> list[Part]:
    """Reihenhaus, Cyberpunk-Variante: Akademie/Apartments für Lóng Chéng."""
    walls, roof, door = Part("walls", 0), Part("roof", 1), Part("door", 2)
    glass, porch = Part("windows", 3), Part("porch", 4)
    chimney = Part("chimney", 4)

    walls.box(-2, 0, -2, 2, 3, 2)

    # Satteldach (First entlang Z), Überstand 0.2
    roof.quad((0, 4.4, -2.2), (0, 4.4, 2.2), (2.2, 3, 2.2), (2.2, 3, -2.2))
    roof.quad((0, 4.4, 2.2), (0, 4.4, -2.2), (-2.2, 3, -2.2), (-2.2, 3, 2.2))
    roof.tri((-2, 3, 2), (2, 3, 2), (0, 4.4, 2))
    roof.tri((2, 3, -2), (-2, 3, -2), (0, 4.4, -2))

    door.box(-0.5, 0, 2.0, 0.5, 2.1, 2.12)
    glass.box(-1.6, 1.2, 2.0, -0.9, 1.9, 2.1)
    glass.box(0.9, 1.2, 2.0, 1.6, 1.9, 2.1)
    glass.box(2.0, 1.2, -1.0, 2.1, 1.9, -0.3)
    glass.box(-1.0, 1.2, -2.1, -0.3, 1.9, -2.0)
    porch.box(-0.9, 0, 2.12, 0.9, 0.28, 2.9)
    chimney.box(1.2, 3.4, -1.0, 1.6, 4.6, -0.6)

    return [walls, roof, door, glass, porch, chimney]


def tower() -> list[Part]:
    """Wohn-Zochrom für den Open-World-Hub: 12 m, leuchtende Fensterbänder."""
    parts = [
        Part("body", 5),
        Part("trim", 6),
        Part("antenna", 7),
        Part("windows", 3),
    ]
    body, trim, antenna, windows = parts

    body.box(-3, 0, -3, 3, 12, 3)
    for floor in range(6):
        y = 1.0 + floor * 1.9
        windows.box(3.0, y, -2.6, 3.08, y + 1.0, 2.6)   # Ost
        windows.box(-3.08, y, -2.6, -3.0, y + 1.0, 2.6)  # West
        windows.box(-2.6, y, 3.0, 2.6, y + 1.0, 3.08)    # Süd
        windows.box(-2.6, y, -3.08, 2.6, y + 1.0, -3.0)  # Nord
    trim.box(-3.2, 12, -3.2, 3.2, 12.4, 3.2)
    antenna.box(-0.12, 12.4, -0.12, 0.12, 15.5, 0.12)

    return parts


def main() -> None:
    for name, builder in (("house", house), ("tower", tower)):
        parts = builder()
        nodes, tris = build_glb(parts, OUT_DIR / f"{name}.glb")
        size_kb = (OUT_DIR / f"{name}.glb").stat().st_size // 1024
        print(f"OK {name}.glb: {nodes} Teile, {tris} Dreiecke, {size_kb} KB")


if __name__ == "__main__":
    main()
