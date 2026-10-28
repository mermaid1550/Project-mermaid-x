#!/usr/bin/env python3
"""triposr_cpu.py – Bild → 3D über TripoSR (MIT) auf der CPU, ohne GPU.

Warum ein eigener Wrapper statt run.py:
  1. oneDNN/mkldnn crasht in vielen VMs mit SIGFPE in Conv-Layern
     (derselbe Fehler wie bei Coqui-VITS) → vor dem Import deaktivieren.
  2. Niedrigere Marching-Cubes-Auflösung als Default für CPU-Tempo.
  3. Export als .glb, damit unser ModelLoader3D/Blender-Skript es frisst.

    python3 tools/ai3d/triposr_cpu.py --image renders/machine.png \
        --out tools/ai3d/inbox --name street_asset --mc-resolution 128

Läuft auf CPU; GPU wird automatisch genutzt, wenn cuda verfügbar ist.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import time
from pathlib import Path

# --- SIGFPE-Workaround: muss VOR torch/tsr-Import passieren ---------------
import torch

torch.backends.mkldnn.enabled = False
if not torch.cuda.is_available():
    torch.set_num_threads(max(2, (os.cpu_count() or 2)))


def main() -> int:
    parser = argparse.ArgumentParser(description="TripoSR Bild→3D (CPU-tauglich)")
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--out", type=Path, default=Path("tools/ai3d/inbox"))
    parser.add_argument("--name", default="ai_asset")
    parser.add_argument("--mc-resolution", type=int, default=128,
                        help="Marching-Cubes-Auflösung (256 = Standard, 128 = 8× schneller auf CPU)")
    parser.add_argument("--foreground-ratio", type=float, default=0.85)
    parser.add_argument("--no-remove-bg", action="store_true")
    args = parser.parse_args()

    if not args.image.exists():
        print(f"FEHLER: Bild nicht gefunden: {args.image}")
        return 1

    logging.basicConfig(format="%(asctime)s %(levelname)s %(message)s", level=logging.INFO)

    # tsr erst JETZT importieren (nach mkldnn-Deaktivierung)
    sys.path.insert(0, os.environ.get("TRIPOSR_PATH", str(Path.home() / "TripoSR")))
    import rembg
    from PIL import Image

    from tsr.system import TSR
    from tsr.utils import resize_foreground, remove_background

    device = "cuda:0" if torch.cuda.is_available() else "cpu"
    started = time.time()

    print(f"[1/4] Modell laden ({device}) ...")
    model = TSR.from_pretrained("stabilityai/TripoSR", config_name="config.yaml",
                                weight_name="model.ckpt")
    model.renderer.set_chunk_size(8192)
    model.to(device)
    print(f"      Modell bereit ({time.time() - started:.0f}s)")

    print("[2/4] Bild vorbereiten ...")
    if args.no_remove_bg:
        image = Image.open(args.image).convert("RGB")
    else:
        session = rembg.new_session()
        image = remove_background(Image.open(args.image), session)
        image = resize_foreground(image, args.foreground_ratio)
        import numpy as np

        arr = np.array(image).astype(np.float32) / 255.0
        arr = arr[:, :, :3] * arr[:, :, 3:4] + (1 - arr[:, :, 3:4]) * 0.5
        image = Image.fromarray((arr * 255.0).astype(np.uint8))

    print(f"[3/4] Inference ({args.mc_resolution}³ Marching Cubes) ...")
    infer_start = time.time()
    with torch.no_grad():
        scene_codes = model([image], device=device)
    print(f"      Inference fertig ({time.time() - infer_start:.0f}s)")

    print("[4/4] Mesh extrahieren + exportieren ...")
    meshes = model.extract_mesh(scene_codes, True, resolution=args.mc_resolution)

    args.out.mkdir(parents=True, exist_ok=True)
    out_path = args.out / f"{args.name}.obj"
    meshes[0].export(str(out_path))

    verts = len(meshes[0].vertices)
    faces = len(meshes[0].faces)
    print(f"✅ {out_path}: {verts} Vertices, {faces} Faces, gesamt {time.time() - started:.0f}s")
    print(f"   -> weiter: auto_prep_asset.py --file {out_path} --output assets/models")
    return 0


if __name__ == "__main__":
    sys.exit(main())
