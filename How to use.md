# How to Use the 2D DIC GUI

A step-by-step tutorial for the `dic2d_gui_vic2d_like.m` MATLAB app (modeled after Vic-2D).

---

## Requirements

| Requirement | Notes |
|---|---|
| MATLAB R2019b or newer | Tested with R2021a+ |
| Image Processing Toolbox | Required for `drawpolygon`, `drawpoint`, `poly2mask`, `imgaussfilt` |

---

## Launching the App

1. Open MATLAB.
2. Set the working directory to the folder containing `dic2d_gui_vic2d_like.m`.
3. In the Command Window, type:
   ```matlab
   dic2d_gui_vic2d_like
   ```
4. The GUI window opens with a **Controls** panel on the left and a **Display** panel on the right containing three axes:
   - **Top:** Reference / current deformed image with ROI overlay
   - **Bottom-left:** Average displacement vs. frame number
   - **Bottom-right:** Strain contour inside the ROI

---

## Step 1 -- Load a Folder of Images

1. Click **Load Folder...**
2. Browse to and select the folder containing your image sequence (e.g., `dummytest/`).
3. The app accepts `.tif`, `.tiff`, `.png`, `.jpg`, `.jpeg`, and `.bmp` files.
4. Images are sorted alphabetically. The **first image** becomes the reference frame; all remaining images are treated as deformed frames.
5. The reference image appears in the top display panel. The info label updates to show the folder path and frame count.

> **Tip:** Use zero-padded filenames (e.g., `frame_001.tif`, `frame_002.tif`) so alphabetical sort matches acquisition order.

---

## Step 2 -- Set DIC Parameters

Adjust these fields in the Controls panel before selecting the ROI:

| Parameter | Description | Typical Value |
|---|---|---|
| **Subset radius (R)** | Half-width of the correlation subset in pixels | 10-25 |
| **Step (px)** | Spacing between grid points inside the ROI | 8-20 |
| **Search radius (px)** | Integer search range for the coarse seed step | 5-15 |
| **Max iters** | Maximum IC-GN iterations per point | 20-50 |
| **Tol** | Convergence tolerance (displacement update norm) | 1e-3 |
| **Min texture std** | Minimum grayscale std-dev to keep a subset. Images loaded via `im2double` have values in [0,1], so this should be small (e.g., 0.01). | 0.01 |
| **Interp** | Interpolation method (`linear` or `cubic`) | cubic |
| **ROI densify (pts/edge)** | Points inserted between each polygon vertex for the boundary | 10 |
| **Strain smooth sigma** | Gaussian smoothing applied before strain differentiation | 0.5-2.0 |
| **Strain component** | Which strain field to display (`exx`, `eyy`, `gxy`, `evm`) | exx |
| **Disp direction** | Which displacement component to plot (`U (horizontal)` or `V (vertical)`) | U (horizontal) |

---

## Step 3 -- Select the Region of Interest (ROI)

1. Click **Select ROI (polygon)**.
2. The reference image fills the display. Click to place polygon vertices around the area you want to analyze.
3. **Double-click** on the last point to close the polygon.
4. The boundary is densified and a green polygon outline is drawn.
5. The image panel zooms to the ROI bounding box automatically.

> **Tip:** Select a region with good speckle contrast. Avoid very smooth areas where the texture threshold filter will reject subsets.

---

## Step 4 -- Build the Correlation Grid

1. Click **Build grid in ROI**.
2. Red dots appear on the reference image, showing every grid point whose subset center falls inside the ROI mask.
3. The status bar reports how many points were placed.

> **Tip:** If too few points are generated, reduce **Step (px)** or **Subset radius (R)**, then click Build again.

---

## Step 5 (Optional) -- Calibrate Pixel Scale

This step converts pixel displacements into physical units (mm, cm, m, or inches). Without calibration, all displacements are displayed in pixels.

1. Click **Calibrate (pick 2 points)**.
2. The reference image is shown at full resolution.
3. **Click on the first calibration point** on the image (e.g., one end of a scale bar or known feature). A cyan marker appears. Double-click or move the point to confirm its position.
4. **Click on the second calibration point** (e.g., the other end of the scale bar). A magenta marker appears.
5. A **dialog box** pops up showing the pixel distance between the two points. Enter:
   - The **real-world distance** between the two points (e.g., `25.4`)
   - The **unit** (e.g., `mm`)
6. Click **OK**. The app computes the scale factor:
   ```
   Scale (px/unit) = pixel distance / real-world distance
   ```
7. The **Scale** label updates (e.g., `Scale: 12.6000 px/mm`).

Once calibrated, the displacement plot displays values in physical units.

> **Tip:** Pick two points as far apart as possible to minimize the effect of pixel-picking error on the scale factor.

---

## Step 6 -- Run the DIC Analysis

1. Click **Run (realtime)**.
2. The app processes each deformed frame in sequence:
   - **Coarse integer search** seeds each grid point with the best integer pixel displacement.
   - **IC-GN** (Inverse Compositional Gauss-Newton) refines each point to sub-pixel accuracy.
3. After each frame, all three display panels update **in real time**:

### Top Panel -- Deformed Image with Tracked ROI
- Shows the current deformed frame.
- The **ROI boundary moves and deforms** with the specimen -- it is interpolated from the computed displacement field, so it follows the material exactly (just like Vic-2D).
- The displaced grid points (red dots) show where each tracked point has moved to in the current frame.

### Bottom-Left -- Average Displacement vs. Frame Number
- Plots the **mean displacement** of all converged grid points against the frame number.
- Use the **Disp direction** dropdown to switch between:
  - `U (horizontal)` -- average horizontal displacement
  - `V (vertical)` -- average vertical displacement
- If calibrated, the y-axis is in physical units; otherwise in pixels.

### Bottom-Right -- Strain Contour
- Shows the selected strain component (`exx`, `eyy`, `gxy`, or `evm`) as a filled color contour.
- Only the ROI interior is colored; the area outside the polygon is transparent.
- The ROI boundary is drawn in black.
- A colorbar shows the strain scale.

4. The progress gauge fills as frames complete. The status bar shows the current frame name and how many points converged.
5. To abort early, click **Stop**.

---

## Step 7 -- Inspect Results

- **Switch strain component:** Change the **Strain component** dropdown and re-run to view different strain fields.
- **Switch displacement direction:** Change the **Disp direction** dropdown -- the plot updates on the next frame (or re-run to see the full history).
- **Adjust smoothing:** Change **Strain smooth sigma** and re-run if strain contours are too noisy. Larger values smooth more aggressively.

---

## Step 8 -- Save Results

1. Click **Save MAT**.
2. A file browser opens. Choose a filename and location.
3. A `.mat` file is written containing:

| Variable | Contents |
|---|---|
| `folder` | Path to the image folder |
| `refName` | Filename of the reference image |
| `defNames` | Cell array of deformed frame filenames |
| `gridPts` | Nx2 array of grid point coordinates [x y] in pixels (reference configuration) |
| `roiPoly` | Polygon vertices as drawn |
| `roiPolyDense` | Densified boundary points |
| `U` | Horizontal displacement matrix (N points x M frames) in pixels |
| `V` | Vertical displacement matrix (N points x M frames) in pixels |
| `avgU` | Mean horizontal displacement per frame (1 x M) |
| `avgV` | Mean vertical displacement per frame (1 x M) |
| `calScale` | Calibration scale (px per physical unit), or `NaN` if not calibrated |
| `calUnit` | Physical unit string (e.g., `'mm'`) |

To convert saved pixel displacements to physical units after loading:
```matlab
load('DIC_results.mat');
U_mm = U / calScale;   % if calScale is not NaN
V_mm = V / calScale;
```

---

## Verification Test

To confirm the DIC pipeline is working correctly without opening the GUI:

```matlab
verify_dic
```

This script:
1. Loads the `dummytest` image sequence (101 frames)
2. Creates a centered rectangular ROI
3. Builds a correlation grid and runs DIC on 5 deformed frames
4. Verifies all 4 strain metrics produce valid output
5. Tests the deformed ROI boundary computation
6. Validates average displacement tracking
7. Checks calibration arithmetic

All 11 checks should pass with output like:
```
RESULT: 11 / 11 tests PASSED
All checks passed. DIC pipeline is functional.
```

---

## Workflow Summary

```
Launch app
    |
    v
Load Folder          <-- select image folder
    |
    v
Set Parameters       <-- subset size, step, search radius, etc.
    |
    v
Select ROI           <-- draw polygon on reference image
    |
    v
Build Grid           <-- generate correlation points inside ROI
    |
    v
Calibrate (optional) <-- pick 2 points, enter known distance
    |
    v
Run                  <-- real-time tracked ROI + strain contour
    |                    + avg displacement vs frame plot
    v
Save MAT             <-- export results for post-processing
```

---

## How It Works (Brief Technical Summary)

This app implements a standard **subset-based DIC** workflow similar to commercial tools like Vic-2D:

1. **Reference subsets:** Small square image patches (size = 2R+1) are extracted around each grid point on the reference image.
2. **Coarse search:** For each deformed frame, an integer-pixel exhaustive search finds the best match within the search radius using zero-mean normalized sum of squared differences (ZNSSD).
3. **Sub-pixel refinement:** The IC-GN (Inverse Compositional Gauss-Newton) algorithm refines each displacement to sub-pixel accuracy using image gradients.
4. **Strain computation:** The scattered displacement field is interpolated onto a regular grid inside the ROI, optionally smoothed, and differentiated to produce engineering strain fields.
5. **ROI tracking:** The ROI boundary on the deformed image is updated by interpolating the displacement field at the boundary points, so the outline moves and deforms with the specimen.

---

## Troubleshooting

| Issue | Likely Cause | Fix |
|---|---|---|
| "drawpolygon requires Image Processing Toolbox" | Toolbox not installed or licensed | Install the Image Processing Toolbox |
| "No grid points have sufficient texture" | Min texture std is too high for the image value range | Lower **Min texture std** (e.g., to `0.01` for `im2double` images in [0,1]) |
| Very few grid points converge | Low image texture or search radius too small | Increase **Search radius** or reduce **Min texture std** |
| Strain contour is blank / shows "No strain data" | Fewer than 4 converged points | Lower **Min texture std**, choose a more textured ROI, or reduce **Step** |
| Calibration dialog does not appear | Point picking cancelled or failed | Click directly on the image; double-click or move the point to confirm |
| Display does not zoom to ROI | ROI not selected before running | Click **Select ROI** and **Build grid** before clicking **Run** |
| App is slow | Many grid points + large search radius | Increase **Step (px)**, reduce **Search radius**, or use fewer frames |
| ROI boundary looks wrong on deformed frames | Grid points too sparse near boundary | Reduce **Step (px)** so more grid points are near the ROI edges |
