# 🐲 Lóng Chéng – AI-Asset-Pipeline (100 % frei & Open Source)

Alles hier kostet **0 €**, hat keine Royalties und keine Vendor-Lock-ins.
Zwei Ebenen:

| Ebene | Tool | Lizenz | Braucht GPU? | Status |
|---|---|---|---|---|
| **Prozedural (sofort)** | `generate_buildings.py` (reines Python) | MIT (dieses Repo) | nein | ✅ funktioniert hier |
| **AI Bild → 3D** | TripoSR | MIT | **nein, CPU reicht!** | ✅ **hier getestet: 55 s** |
| **AI Text → 3D** | Hunyuan3D-2 (ComfyUI-Node) | MIT | ja (empfohlen) | 🔧 |
| **AI Texturen** | ComfyUI + Stable Diffusion (SDXL-Turbo) | AGPL-3.0 / OpenRAIL | ja | 🔧 |
| **Rendern/Export** | Blender | GPL-3.0 | nein (Cycles CPU) | ✅ **hier getestet** |
| **Text-to-Speech** | Coqui TTS (de/thorsten/vits) | MIT | nein, CPU reicht | ✅ **hier getestet: 7,3 s/Satz** |

> **Wichtig – diese VM hat KEINE GPU, trotzdem lief alles:** echte Laufzeiten
> aus diesen Läufen: TripoSR Bild→3D **55 s** (Inference alone 7 s),
> Coqui TTS **7,3 s** pro Satz über den Live-Endpoint, Blender-Render
> 1280×720 **~55 s**. Die drei Stolperfallen stehen unter Abschnitt 2.

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

# CPU-Fall NUR mit --no-build-isolation (sonst findet pip torch nicht):
grep -v torchmcubes requirements.txt > /tmp/rest.txt
pip install -r /tmp/rest.txt
pip install scikit-build-core ninja onnxruntime
pip install --no-build-isolation "git+https://github.com/tatsy/torchmcubes.git"

# Eingabe: ein SAUBER freigestelltes Konzeptbild (Weißraum, Objekt zentriert)
python tools/ai3d/triposr_cpu.py --image konzept.png \
    --out tools/ai3d/inbox --name street_asset --mc-resolution 128
# -> tools/ai3d/inbox/street_asset.obj
```

**Die drei Stolperfallen, die wir hier ausgebessert haben (nachschlagen, bevor es bei dir hakt):**

1. **`torchmcubes` baut nur mit `--no-build-isolation`** und `scikit-build-core`+
   `ninja`+`cmake`. Sonst: `CMakeNotFoundError` bzw. „torch not found in build env".
2. **oneDNN/mkldnn crasht mit SIGFPE** in vielen VMs/Containern – mitten in der
   Convolution des VITS-Duration-Predictors (Coqui) bzw. der Netz-Layer.
   Fix: `torch.backends.mkldnn.enabled = False` **vor** dem Modell-Import
   (steht in `triposr_cpu.py` und im Backend `_load_tts()`).
3. **Coqui-Modellname** heißt in coqui-tts ≥ 0.24 nicht mehr `de/thorsten/v2`,
   sondern `tts_models/de/thorsten/vits` (Format: `typ/sprache/datensatz/modell`).
   Zusätzlich braucht es **`espeak-ng` als Binary im PATH** (Phonisierung) –
   ohne Root lokal bauen geht mit cmake aus dem Quellcode.

**Qualitätshinweis aus der Praxis:** TripoSR ist extrem eingabebild-abhängig.
Ein gedimmter Render mit dunklem Hintergrund gab ein lumpy, strukturloses
Mesh. Für brauchbare Assets zählt ein **sauber freigestelltes Konzeptbild**
mit Weißraum (siehe ComfyUI `rembg`-Node, Prompt-Bibliothek A1).

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
