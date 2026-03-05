# How to Use the 2D DIC GUI

A step-by-step tutorial for the `dic2d_gui_vic2d_like.m` MATLAB app.

---

## Requirements

| Requirement | Notes |
|---|---|
| MATLAB R2019b or newer | Tested with R2021a+ |
| Image Processing Toolbox | Required for `drawpolygon`, `drawline`, `poly2mask`, `imgaussfilt` |

---

## Launching the App

1. Open MATLAB.
2. Set the working directory to the folder containing `dic2d_gui_vic2d_like.m`.
3. In the Command Window, type:
   ```matlab
   dic2d_gui_vic2d_like
   ```
4. The GUI window opens. It has a **Controls** panel on the left and a **Display** panel on the right with three plot axes.

---

## Step 1 — Load a Folder of Images

1. Click **Load Folder…**
2. Browse to and select the folder containing your image sequence (e.g., `dummytest/`).
3. The app accepts `.tif`, `.tiff`, `.png`, `.jpg`, `.jpeg`, and `.bmp` files.
4. Images are sorted alphabetically. The **first image** becomes the reference frame; all remaining images are treated as deformed frames.
5. The reference image appears in the top display panel. The info label updates to show the folder path and frame count.

> **Tip:** Use zero-padded filenames (e.g., `frame_001.tif`, `frame_002.tif`) so alphabetical sort matches acquisition order.

---

## Step 2 — Set DIC Parameters

Adjust these fields in the Controls panel before selecting the ROI:

| Parameter | Description | Typical Value |
|---|---|---|
| **Subset radius (R)** | Half-width of the correlation subset in pixels | 10–25 |
| **Step (px)** | Spacing between grid points inside the ROI | 8–20 |
| **Search radius (px)** | Integer search range for the coarse seed step | 5–15 |
| **Max iters** | Maximum IC-GN iterations per point | 20–50 |
| **Tol** | Convergence tolerance (displacement update norm) | 1e-3 |
| **Min texture std** | Minimum grayscale std-dev to keep a subset | 3–8 |
| **Interp** | Interpolation method (`linear` or `cubic`) | cubic |
| **ROI densify (pts/edge)** | Points inserted between each polygon vertex for the boundary | 10 |
| **Strain smooth sigma** | Gaussian smoothing applied before strain differentiation | 0.5–2.0 |
| **Strain to show** | Which strain component to display | exx |

---

## Step 3 — Select the Region of Interest (ROI)

1. Click **Select ROI (polygon)**.
2. The reference image fills the display. Click to place polygon vertices around the area you want to analyse.
3. **Double-click** on the last point to close the polygon.
4. The boundary is densified (number of interpolated points per edge is set by **ROI densify**) and a green polygon outline is drawn.
5. All three display panels zoom to the ROI bounding box automatically.

> **Tip:** Select a region with good speckle contrast. Avoid very smooth areas where the texture threshold filter will reject subsets.

---

## Step 4 — Build the Correlation Grid

1. Click **Build grid in ROI**.
2. Red dots appear on the reference image, showing every grid point whose subset centre falls inside the ROI mask.
3. The status bar reports how many points were placed.

> **Tip:** If too few points are generated, reduce **Step (px)** or **Subset radius (R)**, then click Build again.

---

## Step 5 (Optional) — Calibrate Pixel Scale

This step converts pixel displacements into physical units (mm, cm, m, or inches).

1. Fill in the **Known distance** field with the real-world length of a reference feature visible in the image (e.g., `25.4` for a 25.4 mm ruler mark span).
2. Select the correct **Unit** from the dropdown (`mm`, `cm`, `m`, or `in`).
3. Click **Calibrate pixels (2-point)**.
4. The reference image is shown at full resolution. **Draw a line** between the two physical reference points:
   - Click once to place the first endpoint.
   - Click once more to place the second endpoint.
   - **Right-click** (or press **Escape**) to confirm the line.
5. The app computes the scale factor:
   ```
   Scale (px/unit) = pixel distance of line / known real distance
   ```
6. The **Scale** label updates to show the computed factor (e.g., `Scale: 12.6000 px/mm`).

Once calibrated, the **Displacement** quiver plot displays vectors in physical units. Without calibration, displacements are shown in pixels.

> **Tip:** Pick two points as far apart as possible (across the full image width or a scale bar) to minimise the effect of pixel-picking error on the scale factor.

---

## Step 6 — Run the DIC Analysis

1. Click **Run (realtime)**.
2. The app processes each deformed frame in sequence:
   - Coarse integer search seeds each point.
   - IC-GN (Inverse Compositional Gauss-Newton) sub-pixel refinement converges the translation vector.
3. After each frame, the three display panels update **in real time**:
   - **Top panel:** Current deformed frame with the ROI boundary and grid overlay, zoomed to the ROI.
   - **Bottom-left:** Displacement quiver plot (vectors in calibrated units or pixels), zoomed to the ROI.
   - **Bottom-right:** Strain contour (selected component) with a colour bar, zoomed to the ROI. Values outside the polygon are transparent.
4. The progress gauge fills as frames complete. The status bar shows the current frame name.
5. To abort early, click **Stop**.

---

## Step 7 — Inspect Strain Results

- Use the **Strain to show** dropdown to switch between components:
  - `exx` — horizontal normal strain
  - `eyy` — vertical normal strain
  - `gxy` — engineering shear strain
  - `evm` — von Mises equivalent strain
- Adjust **Strain smooth sigma** and re-run if contours are noisy. Larger values smooth more aggressively.

---

## Step 8 — Save Results

1. Click **Save MAT**.
2. A file browser opens. Choose a filename and location.
3. A `.mat` file is written containing:

| Variable | Contents |
|---|---|
| `folder` | Path to the image folder |
| `refName` | Filename of the reference image |
| `defNames` | Cell array of deformed frame filenames |
| `gridPts` | Nx2 array of grid point coordinates [x y] in pixels |
| `roiPoly` | Polygon vertices as drawn |
| `roiPolyDense` | Densified boundary points |
| `U` | Horizontal displacement matrix (N points × M frames) in pixels |
| `V` | Vertical displacement matrix (N points × M frames) in pixels |
| `calScale` | Calibration scale (px per physical unit), or `NaN` if not calibrated |
| `calUnit` | Physical unit string (e.g., `'mm'`) |

---

## Verification Test

To confirm the DIC pipeline is working correctly without opening the GUI:

```matlab
verify_dic
```

This script loads the `dummytest` image sequence, runs the full pipeline on a centred rectangular ROI, checks strain output and calibration arithmetic, and prints a pass/fail summary.

---

## Workflow Summary

```
Launch app
    │
    ▼
Load Folder          ← select image folder
    │
    ▼
Set Parameters       ← subset size, step, search radius, etc.
    │
    ▼
Select ROI           ← draw polygon on reference image
    │
    ▼
Build Grid           ← generate correlation points inside ROI
    │
    ▼
Calibrate (optional) ← draw 2-point line, enter known distance
    │
    ▼
Run                  ← real-time displacement + strain contour plots
    │
    ▼
Save MAT             ← export results for post-processing
```

---

## Troubleshooting

| Issue | Likely Cause | Fix |
|---|---|---|
| "drawpolygon requires Image Processing Toolbox" | Toolbox not installed / licensed | Install the Image Processing Toolbox |
| Very few grid points converge | Low image texture or search radius too small | Increase **Search radius** or reduce **Min texture std** |
| Strain contour is all NaN | No converged displacement points in the ROI | Lower **Min texture std** or choose a larger / more textured ROI |
| Calibration line appears then disappears | Image redrawn before reading the line | Right-click to confirm the line **before** clicking anything else |
| Display does not zoom to ROI | ROI not selected before running | Click **Select ROI** and **Build grid** before clicking **Run** |
| App is slow | Many grid points + large search radius | Increase **Step (px)**, reduce **Search radius**, or use fewer frames |
