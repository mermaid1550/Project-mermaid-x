# 🎨 Section A – ComfyUI / AI Texture & Mesh Prompts (Lóng Chéng)

Vollständige Prompts für die freie Pipeline: Konzept 2D → Geometrie 3D →
4K-PBR-Texturen. Alle Modelle untereinander austauschbar (SDXL, FLUX.1-dev,
TRELLIS, Hunyuan3D-2, TripoSR) – keine davon braucht API-Keys.

**Stilanker (in JEDEM Prompt wiederholen, damit die Serie konsistent bleibt):**
```
stylized cyberpunk anime aesthetic, neon magenta and cyan accents,
clean hard-surface design, cozy futuristic Hong Kong street style,
game asset, real-time ready
```

---

## A1. 2D-Konzepte (Stable Diffusion XL / FLUX.1-dev)

**Sampler-Basis für alle Konzept-Generierungen:**
`DPM++ 2M Karras`, 28 Steps, CFG 6.5 (SDXL) / Guidance 3.5 (FLUX),
1024×1024, Seed festhalten (Seriensprachlichkeit!).

### A1.1 Cyberpunk Vending Machine (Ziel-Asset)

**Positive:**
```
stylized cyberpunk vending machine, full-body product shot, front three-quarter view,
transparent glass front with glowing drink canisters, holographic chinese neon signage
reading ドリンク, brushed dark metal body with magenta panel lines, cyan edge lighting,
anime game prop, clean silhouette, centered on plain light gray studio background,
soft even lighting, no cast shadow, 8k game concept art, stylized cyberpunk anime aesthetic,
neon magenta and cyan accents, clean hard-surface design, real-time ready
```

**Negative:**
```
photorealistic, photo, cluttered background, ground, street, people, hands, text watermark,
logo, lowres, jpeg artifacts, blurry, deformed, extra legs, warped proportions,
asymmetric controls, harsh shadows, motion blur, cropped top, cropped bottom
```

### A1.2 AI-Pet Companion (Drachen-Pet)

**Positive:**
```
cute small dragon cyber-pet companion, floating pose, round chibi proportions,
glossy white and cyan body panels, glowing magenta eyes, holographic data wings,
t-posing facing camera, full body visible, plain light gray studio background,
soft even lighting, no cast shadow, anime mascot game character, 8k concept sheet,
stylized cyberpunk anime aesthetic, neon accents, real-time ready
```

**Negative:**
```
photorealistic, fur, scales texture photo, wings spread wide, dynamic action pose,
cropped, background scenery, text, watermark, signature, deformed, extra limbs,
blurry, lowres, ugly, bad anatomy, human, humanoid, arms, legs
```

### A1.3 Street-Assets (Serie: Laterne, Bank, Müllcontainer, Signet)

**Positive:**
```
modular cyberpunk street prop set, [SUBJEKT: e.g. glowing street lantern / park bench
with holo screen / waste bin with neon trim], front three-quarter view, consistent
scale reference, plain light gray studio background, soft even lighting, no cast shadow,
stylized game asset concept, 8k, stylized cyberpunk anime aesthetic,
neon magenta and cyan accents, clean hard-surface design, real-time ready
```
(`[SUBJEKT]` pro Datei ersetzen, Prompt sonst identisch → einheitliche Serie.)

**Negative:** wie A1.1.

### A1.4 FLUX.1-Hinweis
FLUX kennt kein CFG/Negative-IF-Layout: Negative als Ausschlüsse **in den
positiven Prompt schreiben**:
```
... plain light gray studio background, no shadow, no people, no text,
no watermark, entire object visible, centered
```

---

## A2. Konzept → 3D-Geometrie (TRELLIS 2 / Hunyuan3D-2 / TripoSR)

### A2.1 TRELLIS 2 (Text- oder Bild-zu-3D) – Struktur-Prompt

**Text-zu-3D (falls kein Konzeptbild vorhanden):**
```
a stylized cyberpunk vending machine, game-ready hard-surface prop,
symmetrical, boxy body with rounded corners, glass front panel,
four front buttons, low to medium polycount, clean manifold topology,
white untextured clay render, studio turntable lighting
```

**Bild-zu-3D (empfohlen: das A1.1-Konzept nehmen):**
- Input: A1.1 PNG, **Hintergrund entfernen** (ComfyUI `rembg`-Node oder BiRefNet),
  Object-Fit auf 80 % des Frames, Weißraum gleichmäßig.
- TRELLIS-Struktur-Params: `ss_guidance_strength=7.5`, `ss_steps=12`,
  `ms_guidance_strength=1.5`, `ms_steps=12`, `vrm_postprocess=True` aus,
  Output `mesh` Format **GLB**.

### A2.2 Hunyuan3D-2 (über ComfyUI-Node)
- Image-Conditioning: freigestelltes A1.1-Konzept (RGBA).
- Text-Prompt: derselbe wie A2.1, `negative`: `organic, deformed, asymmetric, open bottom`.
- Params: `steps=20`, `guidance=5.0`, Texture-Flag an (liefert ALBEDO + ROUGHNESS),
  Output GLB → `tools/ai3d/inbox/`.

### A2.3 TripoSR (Bild-zu-3D, MIT-Lizenz, 8 GB VRAM)
TripoSR ist **rein bildbasiert**, es gibt keinen Text-Prompt. Eingabe ist das
A1.1-Konzept (freigestellt, quadratisch, 768–1024 px, Objekt zentriert).
Modell-Flag: Standard-Checkpoint `stabilityai/TripoSR`.
CLI (siehe README):
```bash
python run.py konzept_vending.png -o output/ --device cuda
```
→ Export `output/*.obj` → `auto_prep_asset.py` konvertiert nach `.gltf`.

### A2.4 Nachbearbeitungs-Reihenfolge (Gilt für alle drei!)
1. Konzept bereinigen (freistellen, zentrieren)
2. Geometrie generieren (TRELLIS/Hunyuan/TripoSR)
3. `auto_prep_asset.py` ausführen (Cleanup, UV, Decimate, Export)
4. PBR-Texturen aus A3 erzeugen und im Skript zuordnen
5. GLB/GLTF nach `assets/models/` → Godot lädt per `ModelAndAILoader`

---

## A3. 4K-PBR-Texturen via ControlNet (Depth/Normal-geführt)

**Grund-Workflow (ComfyUI):**
`LoadImage` (A1.1-Konzept) → `Depth Anything V2`/`MiDaS` → `ControlNetLoader
control_v11f1p_sd15_depth` → `ControlNetApplyAdvanced (strength 0.75,
start 0.0, end 0.85)` → `KSampler` → `VAEDecode` → `SaveImage`.
Basis-Modell: **SDXL-base + dDetailer/epiCRealism-LoRA optional**.
2048×2048 (4K-Tiling), 32 Steps, CFG 7.0, DPM++ 2M Karras.

**Tipp „seamless":** `Tiled Diffusion`-Node (MZ) mit `tiles 4×4`,
`overlap 32`, `pool algorithm: split` ODER Prompt-Wort `seamless tiling,
texture map, orthographic top view` + `Offset VAE`-Node.

### A3.1 ALBEDO (BaseColor)

**Positive:**
```
seamless tileable pbr albedo map, flat color only, no shadows, no highlights,
no lighting, no baked ao, vending machine panel texture, brushed dark metal
with magenta panel lines, cyan decal accents, subtle wear, anime style,
4k texture, top-down orthographic, stylized cyberpunk anime aesthetic
```

**Negative:**
```
shadows, highlights, specular, glare, lighting, gradient, perspective,
3d render, photo, people, text, watermark, vignette, depth of field
```

### A3.2 ROUGHNESS

**Positive:**
```
seamless tileable pbr roughness map, grayscale, matte metal base value 0.55,
polished glass panel value 0.15, glossy painted edges value 0.3,
no color, no text, 4k, top-down orthographic, flat
```

**Negative:** `color, hue, text, watermark, shadows, perspective, blur`

Werte als Graustufen kontrollieren: via `Curve`-Node die Histogramm-Bereiche
auf 0.15 / 0.30 / 0.55 ziehen (rechts = glatt).

### A3.3 NORMAL MAP (tangent space)

**Positive:**
```
seamless tileable pbr normal map, tangent space, bluish purple base color,
panel gaps, rivets, vents, button relief, subtle surface dents,
flat background normal, 4k, top-down orthographic
```

**Negative:** `albedo, color shading, red green tint beyond tangent encoding,
text, watermark, perspective, baked shadows`

**Alternative ohne Generierung:** Depth-Map aus A2 als Eingabe nehmen,
`ControlNet Depth → KSampler (denoise 1.0)` mit **leerem Prompt** +
`Canny`-Detail-Pfad → als `normal` speichern (auch als `depth→normal`-Node
in ComfyUI-Utils verfügbar).

### A3.4 EMISSION (Leucht-Maske, Schwarz = aus)

**Positive:**
```
seamless tileable emission mask, pure black background,
bright white glowing outlines of panel lines and screen area,
crisp neon strip geometry, no gradients, no midtones, high contrast,
4k, top-down orthographic, no text
```

**Negative:** `gray background, dim glow, blur, text, watermark, perspective, color`

In Godot: als `emission_texture` + `emission_energy_multiplier = 2.5` auf
`StandardMaterial3D.emission_enabled = true`.

### A3.5 METALLIC (meist generisch – Standard-Werte statt KI)

Metallkarten sind bei Stylized-Assets fast immer 0/1-Masken:
In `auto_prep_asset.py` wird sie pro Material gesetzt
(Glas/Metall-Schild = 1, Lack/Plastik = 0) statt zu generieren.
Optional-Prompt für gemischte Flächen:
```
seamless tileable pbr metallic mask, binary black and white,
white = bare metal panels, black = painted plastic, crisp edges,
4k, top-down orthographic, no text
```

### A3.6 ControlNet-Zuordnung je Map

| Map | ControlNet | Strength | Denoise |
|---|---|---|---|
| Albedo | Depth (V2) | 0.75 | 0.65 |
| Roughness | Normal (MiDaS-Depth umgerechnet) | 0.45 | 0.90 |
| Normal | Depth (V2), Output als Normal-Bake | 0.90 | 1.00 |
| Emission | Canny (Kanten des Konzepts) | 0.80 | 0.55 |

Alle Maps mit gleichem Seed + gleichem Konzept-Input rendern → decken sich
pixelgenau, kein UV-Versatz im Shader.

---

## A4. Prompt-Parameter-Übersicht (Quick Copy)

```yaml
concept_2d:    { model: SDXL-base / FLUX.1-dev, sampler: DPM++2M Karras,
                 steps: 28, cfg: 6.5, size: 1024x1024 }
geometry_3d:   { model: TRELLIS2 / Hunyuan3D-2 / TripoSR, output: GLB,
                 texture: false  # Texturen kommen aus A3, präziser }
pbr_albedo:    { control: depth_v2, strength: 0.75, denoise: 0.65, steps: 32, size: 2048 }
pbr_roughness: { control: normal,   strength: 0.45, denoise: 0.90, steps: 32, size: 2048 }
pbr_normal:    { control: depth_v2, strength: 0.90, denoise: 1.00, steps: 32, size: 2048 }
pbr_emission:  { control: canny,    strength: 0.80, denoise: 0.55, steps: 32, size: 2048 }
pbr_metallic:  { source: auto_prep_asset.py defaults  # 0/1-Maske pro Material }
tiling:        { node: Tiled Diffusion (MZ), tiles: 4x4, overlap: 32, algorithm: split }
```

Die PBR-Workflows als importierbare JSONs liegen neben dieser Datei:
`texture_workflow.json` (Basis) – ControlNet-Varianten werden durch
Einsetzen der obigen Parameter in denselben Graphen erzeugt.
