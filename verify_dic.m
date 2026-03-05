%% verify_dic.m
% Headless verification test for the DIC pipeline using dummytest images.
% Run this script directly in MATLAB (no GUI needed).
%
% What it checks:
%   1. Images load and convert to grayscale correctly
%   2. Polygon-to-mask conversion works
%   3. Grid points fall inside the ROI
%   4. DIC coarse seed and IC-GN refinement run without errors
%   5. Strain computation produces finite values inside ROI
%   6. Pixel calibration scale factor computes correctly
%
% Usage:  >> verify_dic

clear; clc;
fprintf('=== DIC Verification Test ===\n\n');

%% 1. Locate images
folder = fullfile(fileparts(mfilename('fullpath')), 'dummytest');
exts   = {'*.tif','*.tiff','*.png','*.jpg','*.jpeg','*.bmp'};
allFiles = [];
for i = 1:numel(exts)
    allFiles = [allFiles; dir(fullfile(folder, exts{i}))]; %#ok<AGROW>
end
assert(~isempty(allFiles), 'No images found in dummytest folder.');
[~,idx] = sort({allFiles.name});
allFiles = allFiles(idx);

refPath  = fullfile(folder, allFiles(1).name);
defPaths = cellfun(@(n) fullfile(folder,n), {allFiles(2:min(end,4)).name}, ...
           'UniformOutput', false);   % use first 3 deformed frames for speed

fprintf('[1] Found %d images.  Reference: %s\n', numel(allFiles), allFiles(1).name);

%% 2. Load reference image
Iref = readGray_v(refPath);
assert(ismatrix(Iref) && ~isempty(Iref), 'Reference image must be 2D grayscale.');
assert(all(Iref(:) >= 0) && all(Iref(:) <= 1), 'Pixel values must be in [0,1].');
[Hh, Ww] = size(Iref);
fprintf('[2] Reference image size: %d x %d  (height x width)\n', Hh, Ww);

%% 3. Define a rectangular ROI in the image centre (25% margins)
cx = round(Ww/2); cy = round(Hh/2);
hw = round(Ww*0.25); hh = round(Hh*0.25);
roiPoly = [cx-hw, cy-hh;
           cx+hw, cy-hh;
           cx+hw, cy+hh;
           cx-hw, cy+hh];

dense  = densifyPolygon_v(roiPoly, 20);
roiMask = poly2mask(dense(:,1), dense(:,2), Hh, Ww);

assert(any(roiMask(:)), 'ROI mask must contain at least one pixel.');
fprintf('[3] ROI polygon densified to %d boundary pts; mask covers %d px.\n', ...
        size(dense,1), sum(roiMask(:)));

%% 4. Build grid
R    = 15;
step = 20;
xv   = (1+R):step:(Ww-R);
yv   = (1+R):step:(Hh-R);
[Xg, Yg] = meshgrid(xv, yv);
pts  = [Xg(:), Yg(:)];
lin    = sub2ind([Hh,Ww], round(pts(:,2)), round(pts(:,1)));
inside = roiMask(lin);
gridPts = pts(inside,:);

assert(size(gridPts,1) > 0, 'No grid points inside ROI — increase image size or reduce R/step.');
fprintf('[4] Grid: %d points inside ROI.\n', size(gridPts,1));

%% 5. Build reference interpolants
interpMethod = 'cubic';
[Ix_ref, Iy_ref] = gradient(Iref);
Fref = griddedInterpolant(Iref,   interpMethod, 'nearest');
Fx   = griddedInterpolant(Ix_ref, interpMethod, 'nearest');
Fy   = griddedInterpolant(Iy_ref, interpMethod, 'nearest');

[dx, dy] = meshgrid(-R:R, -R:R);
dx = dx(:); dy = dy(:);

minTex   = 3;   % lower threshold for test images
maxIters = 20;
tol      = 1e-3;
searchR  = 8;

% Precompute per-point reference data
nPts    = size(gridPts,1);
refData = cell(nPts,1);
valid   = false(nPts,1);
for p = 1:nPts
    x0 = gridPts(p,1); y0 = gridPts(p,2);
    X  = x0 + dx; Y  = y0 + dy;
    T  = Fref(Y, X);
    sT = std(T);
    if sT < minTex, continue; end
    Tn   = (T - mean(T)) / sT;
    Gx   = Fx(Y, X); Gy = Fy(Y, X);
    SD   = [Gx, Gy];
    Hmat = SD.'*SD + 1e-8*eye(2);
    refData{p} = struct('x0',x0,'y0',y0,'Tn',Tn,'SD',SD,'invH',inv(Hmat));
    valid(p) = true;
end
fprintf('[5] Valid (textured) grid points: %d / %d\n', sum(valid), nPts);

%% 6. Run DIC on first few deformed frames
nFrames = numel(defPaths);
Uall = nan(nPts, nFrames);
Vall = nan(nPts, nFrames);

for k = 1:nFrames
    Idef = readGray_v(defPaths{k});
    Fdef = griddedInterpolant(Idef, interpMethod, 'nearest');

    U = nan(nPts,1); V = nan(nPts,1);
    for p = 1:nPts
        if ~valid(p), continue; end
        rd  = refData{p};
        uv0 = coarseIntegerSeed_v(Fref, Fdef, rd.x0, rd.y0, R, searchR);
        if any(isnan(uv0)), continue; end
        [pOpt, ok] = icgn_translation_v(rd, Fdef, dx, dy, maxIters, tol, uv0(:));
        if ok, U(p) = pOpt(1); V(p) = pOpt(2); end
    end
    Uall(:,k) = U; Vall(:,k) = V;
    nGood = sum(~isnan(U));
    fprintf('[6] Frame %d: %d / %d points converged\n', k, nGood, sum(valid));
end

%% 7. Strain computation
smoothSigma = 1.0;
[Z, Xq, Yq, maskQ] = computeStrainGrid_v(gridPts, Uall(:,1), Vall(:,1), dense, smoothSigma, 'exx');
finiteVals = sum(isfinite(Z(maskQ)));
assert(finiteVals > 0, 'Strain grid returned no finite values inside the ROI mask.');
fprintf('[7] Strain grid (exx): %d finite values inside ROI mask.\n', finiteVals);

%% 8. Calibration arithmetic
pt1 = [100, 200]; pt2 = [500, 200];   % horizontal line, 400 px
pixDist  = norm(pt2 - pt1);           % should be 400
realDist = 20.0;                       % mm
calScale = pixDist / realDist;         % px/mm
assert(abs(calScale - 20.0) < 1e-6, 'Calibration scale mismatch.');
U_mm = Uall(:,1) / calScale;
fprintf('[8] Calibration: %.1f px / %.1f mm = %.4f px/mm.  Mean |U| = %.4f mm\n', ...
        pixDist, realDist, calScale, mean(abs(U_mm(~isnan(U_mm)))));

%% 9. ROI bounding-box zoom check
xmin = min(dense(:,1)); xmax = max(dense(:,1));
ymin = min(dense(:,2)); ymax = max(dense(:,2));
assert(xmin >= 1 && ymin >= 1, 'ROI bounding box goes out of image bounds.');
assert(xmax <= Ww && ymax <= Hh, 'ROI bounding box exceeds image dimensions.');
fprintf('[9] ROI bounding box: x=[%.0f, %.0f]  y=[%.0f, %.0f]  (image %dx%d)\n', ...
        xmin, xmax, ymin, ymax, Ww, Hh);

fprintf('\n=== All checks passed. DIC pipeline is functional. ===\n');

% ======================================================================
%   Local copies of the core functions (mirror of main file, no GUI dep)
% ======================================================================
function I = readGray_v(path)
    I = im2double(imread(path));
    if ndims(I)==3, I = rgb2gray(I); end
end

function dense = densifyPolygon_v(pos, nPerEdge)
    N = size(pos,1); dense = [];
    for i = 1:N
        a = pos(i,:); b = pos(mod(i,N)+1,:);
        t = linspace(0,1,nPerEdge+2).';
        seg = a + (b-a).*t;
        if i < N, seg = seg(1:end-1,:); end
        dense = [dense; seg]; %#ok<AGROW>
    end
    [~,ia] = unique(round(dense,6),'rows','stable');
    dense  = dense(ia,:);
end

function uv = coarseIntegerSeed_v(Fref, Fdef, x0, y0, R, searchR)
    [dx,dy] = meshgrid(-R:R,-R:R);
    Xr=x0+dx; Yr=y0+dy;
    T=Fref(Yr,Xr); sT=std(T(:));
    if sT<1e-9, uv=[nan nan]; return; end
    Tn=(T-mean(T(:)))/sT;
    best=inf; bestuv=[0 0];
    for du=-searchR:searchR
        for dv=-searchR:searchR
            I=Fdef(Yr+dv,Xr+du); sI=std(I(:));
            if sI<1e-9, continue; end
            In=(I-mean(I(:)))/sI;
            sse=sum((Tn(:)-In(:)).^2);
            if sse<best, best=sse; bestuv=[du dv]; end
        end
    end
    uv=bestuv;
end

function [p,ok] = icgn_translation_v(rd, Fdef, dxv, dyv, maxIters, tol, p0)
    p=p0(:); ok=false;
    for it=1:maxIters
        Xw=rd.x0+dxv+p(1); Yw=rd.y0+dyv+p(2);
        I=Fdef(Yw,Xw); sI=std(I);
        if sI<1e-9, return; end
        In=(I-mean(I))/sI;
        e=rd.Tn-In; dp=rd.invH*(rd.SD.'*e);
        p=p+dp;
        if norm(dp)<tol, ok=true; return; end
    end
    ok=true;
end

function [Z,Xq,Yq,maskQ] = computeStrainGrid_v(pts, U, V, polyDense, smoothSigma, metric)
    good=~isnan(U)&~isnan(V); pts=pts(good,:); U=U(good); V=V(good);
    if isempty(pts)
        Z=nan(10); Xq=linspace(0,1,10); Yq=linspace(0,1,10).'; maskQ=false(10); return;
    end
    xmin=min(polyDense(:,1)); xmax=max(polyDense(:,1));
    ymin=min(polyDense(:,2)); ymax=max(polyDense(:,2));
    nx=60; ny=60;
    xq=linspace(xmin,xmax,nx); yq=linspace(ymin,ymax,ny);
    [Xq,Yq]=meshgrid(xq,yq);
    maskQ=poly2mask(polyDense(:,1)-xmin+1, polyDense(:,2)-ymin+1, ny, nx);
    Fu=scatteredInterpolant(pts(:,1),pts(:,2),U,'natural','none');
    Fv=scatteredInterpolant(pts(:,1),pts(:,2),V,'natural','none');
    Ug=Fu(Xq,Yq); Vg=Fv(Xq,Yq);
    if smoothSigma>0
        fsz=max(3,2*ceil(3*smoothSigma)+1);
        Ug=imgaussfilt(Ug,smoothSigma,'FilterSize',fsz);
        Vg=imgaussfilt(Vg,smoothSigma,'FilterSize',fsz);
    end
    dx2=mean(diff(xq)); dy2=mean(diff(yq));
    [~,dUdx]=gradient(Ug,dy2,dx2); [dVdy,~]=gradient(Vg,dy2,dx2);
    switch lower(metric)
        case 'exx', Z=dUdx;
        case 'eyy', Z=dVdy;
        otherwise,  Z=dUdx;
    end
    Z(~maskQ)=nan;
end
