# 🐲 Lóng Chéng – AI-Asset-Pipeline (100 % frei & Open Source)

Alles hier kostet **0 €**, hat keine Royalties und keine Vendor-Lock-ins.
Zwei Ebenen:

| Ebene | Tool | Lizenz | Braucht GPU? | Status |
|---|---|---|---|---|
| **Prozedural (sofort)** | `generate_buildings.py` (reines Python) | MIT (dieses Repo) | nein | ✅ funktioniert hier |
| **AI Bild → 3D** | TripoSR | MIT | ja (≥8 GB VRAM) | 🔧 auf deinem Rechner |
| **AI Text → 3D** | Hunyuan3D-2 (ComfyUI-Node) | MIT | ja | 🔧 auf deinem Rechner |
| **AI Texturen** | ComfyUI + Stable Diffusion (SDXL-Turbo) | AGPL-3.0 / OpenRAIL | ja | 🔧 auf deinem Rechner |
| **Rendern/Export** | Blender | GPL-3.0 | Optional | 🔧 auf deinem Rechner |

> Warum „hier“ und „bei dir“? Diese Cloud-VM hat **keine GPU**. Leichte
> prozedurale Generierung läuft sofort und ist getestet; schwere
> AI-Inference installierst und startest du lokal. Die Pipelines sind
> identisch – nur der Rechner wechselt.

## 1. Sofort nutzbar: prozedural erzeugen

```bash
python3 tools/ai3d/generate_buildings.py
# OK house.glb: 6 Teile, 102 Dreiecke, 10 KB
# OK tower.glb: 4 Teile, 324 Dreiecke, 22 KB
```

Ergibt `assets/ai_models/*.glb`, direkt ladbar über `ModelLoader3D`
inklusive automatischer Box-Kollision. Die Stadt im Hub
(`scripts/world_test_3d.gd`) lädt genau diese Dateien.

**Neues Modell erzeugen:** eigene `Part`-Funktion schreiben
(Boxen/Quads/Triangles) und in `main()` registrieren. Oder Abschnitt 2
nutzen und die AI-Datei nur in `assets/ai_models/` ablegen – gleicher
Dateiname, gleicher Ladeweg.

## 2. AI Bild → 3D mit TripoSR (lokal, MIT-Lizenz)

```bash
git clone https://github.com/VAST-AI-Research/TripoSR
cd TripoSR
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Testbild (Beispiel aus dem Repo):
python run.py example_data/1.png -o output/

# Ergebnis: output/*.obj  →  nach GLB konvertieren:
pip install trimesh
python -c "import trimesh,sys; trimesh.load(sys.argv[1]).export(sys.argv[2])" \
    output/1.obj output/house.glb

# In das Spiel:
cp output/house.glb /pfad/zu/lóng-chéng/assets/ai_models/
```

In Godot ändert nichts: `ModelLoader3D.load_ai_generated_3d_model()` lädt
die Datei, die Kollision entsteht automatisch aus der Bounding Box.

## 3. AI Text → 3D mit Hunyuan3D-2 über ComfyUI

1. [ComfyUI](https://github.com/comfyanonymous/ComfyUI) installieren
   (AGPL-3.0, gratis).
2. Den **Hunyuan3D-2-Node** installieren
   (z.B. `ComfyUI-Hunyuan3DWrapper` oder den offiziellen Node-Paket).
3. Prompt z.B. `cyberpunk townhouse with magenta roof, glowing cyan
   windows, anime style`, Sampler laufen lassen, GLB exportieren,
   nach `assets/ai_models/` kopieren.

## 4. Texturen & UI-Bilder mit ComfyUI + SDXL

`tools/ai3d/comfyui/texture_workflow.json` ist ein fertiger
ComfyUI-Workflow: Ladefenster für ein Referenzbild + KSampler +
Speichern. Nimm ein freies Modell, z.B.:

- **SDXL-Turbo** (OpenRAIL++): schnell, gut für Game-Texturen
- **Juggernaut XL** (OpenRAIL++): realistisch
- **Anything V5 / Anima** (CreativeML OpenRAIL): Anime-Look für Charaktere

Output als PNG nach `assets/textures/`, in Godot als `StandardMaterial3D.
albedo_texture` ziehen.

## 5. Rendern mit Blender (Promo-Shots, Trailer)

Blender (GPL-3.0) lädt jedes unserer `.glb` direkt. Headless-Render für
Screenshots/Steam-Tags:

```bash
blender --background --python-expr "
import bpy
bpy.ops.import_scene.gltf(filepath='assets/ai_models/house.glb')
bpy.context.scene.render.filepath = '/tmp/house.png'
bpy.ops.render.render(write_still=True)
"
```

## Lizenz-Check (alles frei, alles kommerziell nutzbar)

- **Dieses Repo** (Generator, Szenen, Skripte): MIT (siehe LICENSE)
- **Godot**: MIT
- **TripoSR**: MIT
- **Hunyuan3D-2 / ComfyUI**: MIT bzw. AGPL (Selbstnutzung & Modifikation frei)
- **Stable Diffusion**: CreativeML OpenRAIL-M (auch kommerziell erlaubt)
- **Blender**: GPL-3.0
- **Noto Sans SC Font**: SIL Open Font License 1.1

Nichts davon verlangt eine Umsatzbeteiligung. Kein Service, kein Abo,
kein API-Key nötig.
