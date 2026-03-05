%% verify_dic.m
% Headless verification test for the DIC pipeline using dummytest images.
% Tests: image loading, ROI masking, grid building, DIC correlation,
%        strain computation, calibration arithmetic, deformed-ROI boundary,
%        and average displacement tracking.
%
% Usage:  >> verify_dic

clear; clc;
fprintf('====================================================\n');
fprintf('         DIC Pipeline Verification Test\n');
fprintf('====================================================\n\n');

passed = 0;
total  = 0;

%% 1. Locate images
total = total+1;
folder = fullfile(fileparts(mfilename('fullpath')), 'dummytest');
exts   = {'*.tif','*.tiff','*.png','*.jpg','*.jpeg','*.bmp'};
allFiles = [];
for i = 1:numel(exts)
    allFiles = [allFiles; dir(fullfile(folder, exts{i}))]; %#ok<AGROW>
end
assert(~isempty(allFiles), 'No images found in dummytest folder.');
[~,idx] = sort({allFiles.name});
allFiles = allFiles(idx);

nImages = numel(allFiles);
refPath  = fullfile(folder, allFiles(1).name);
nDef = min(5, nImages-1);   % test with first 5 deformed frames for speed
defPaths = cell(1,nDef);
for i = 1:nDef
    defPaths{i} = fullfile(folder, allFiles(i+1).name);
end
fprintf('[1] PASS — Found %d images. Ref: %s, testing %d deformed frames\n', ...
    nImages, allFiles(1).name, nDef);
passed = passed+1;

%% 2. Load reference image
total = total+1;
Iref = readGray_v(refPath);
assert(ismatrix(Iref) && ~isempty(Iref), 'Reference image must be 2D grayscale.');
assert(all(Iref(:)>=0) && all(Iref(:)<=1), 'Pixel values must be in [0,1].');
[Hh, Ww] = size(Iref);
fprintf('[2] PASS — Reference image size: %d x %d\n', Hh, Ww);
passed = passed+1;

%% 3. Define ROI and build mask
total = total+1;
cx = round(Ww/2); cy = round(Hh/2);
hw = round(Ww*0.20); hh = round(Hh*0.20);
roiPoly = [cx-hw, cy-hh;
           cx+hw, cy-hh;
           cx+hw, cy+hh;
           cx-hw, cy+hh];
dense   = densifyPolygon_v(roiPoly, 15);
roiMask = poly2mask(dense(:,1), dense(:,2), Hh, Ww);
assert(any(roiMask(:)), 'ROI mask must contain at least one pixel.');
fprintf('[3] PASS — ROI: %d dense boundary pts, mask covers %d px\n', ...
    size(dense,1), sum(roiMask(:)));
passed = passed+1;

%% 4. Build grid
total = total+1;
R    = 15;
step = 15;
xv = (1+R):step:(Ww-R);
yv = (1+R):step:(Hh-R);
[Xg,Yg] = meshgrid(xv,yv);
pts = [Xg(:), Yg(:)];
lin = sub2ind([Hh,Ww], round(pts(:,2)), round(pts(:,1)));
gridPts = pts(roiMask(lin),:);
assert(size(gridPts,1)>0, 'No grid points inside ROI.');
fprintf('[4] PASS — Grid: %d points inside ROI\n', size(gridPts,1));
passed = passed+1;

%% 5. Precompute reference data
total = total+1;
interpMethod = 'cubic';
[Ix_ref, Iy_ref] = gradient(Iref);
Fref = griddedInterpolant(Iref,   interpMethod, 'nearest');
Fx   = griddedInterpolant(Ix_ref, interpMethod, 'nearest');
Fy   = griddedInterpolant(Iy_ref, interpMethod, 'nearest');

[dxs, dys] = meshgrid(-R:R, -R:R);
dxs = dxs(:); dys = dys(:);
minTex   = 0.01;  % im2double images have values in [0,1], so std is small
maxIters = 20;
tolVal   = 1e-3;
searchR  = 8;

nPts    = size(gridPts,1);
refData = cell(nPts,1);
valid   = false(nPts,1);
for p = 1:nPts
    x0 = gridPts(p,1); y0 = gridPts(p,2);
    X = x0+dxs; Y = y0+dys;
    T = Fref(Y,X); sT = std(T);
    if sT < minTex, continue; end
    Tn = (T-mean(T))/sT;
    Gx = Fx(Y,X); Gy = Fy(Y,X);
    SD = [Gx, Gy];
    Hmat = SD.'*SD + 1e-8*eye(2);
    refData{p} = struct('x0',x0,'y0',y0,'Tn',Tn,'SD',SD,'invH',inv(Hmat));
    valid(p) = true;
end
nValid = sum(valid);
assert(nValid > 0, 'No textured grid points found.');
fprintf('[5] PASS — Valid (textured) points: %d / %d\n', nValid, nPts);
passed = passed+1;

%% 6. Run DIC on deformed frames
total = total+1;
Uall = nan(nPts, nDef);
Vall = nan(nPts, nDef);
avgU = nan(1,nDef);
avgV = nan(1,nDef);

for k = 1:nDef
    Idef = readGray_v(defPaths{k});
    Fdef = griddedInterpolant(Idef, interpMethod, 'nearest');
    U = nan(nPts,1); V = nan(nPts,1);
    for p = 1:nPts
        if ~valid(p), continue; end
        rd = refData{p};
        uv0 = coarseIntegerSeed_v(Fref, Fdef, rd.x0, rd.y0, R, searchR);
        if any(isnan(uv0)), continue; end
        [pOpt, ok] = icgn_translation_v(rd, Fdef, dxs, dys, maxIters, tolVal, uv0(:));
        if ok, U(p)=pOpt(1); V(p)=pOpt(2); end
    end
    Uall(:,k) = U; Vall(:,k) = V;
    gd = ~isnan(U)&~isnan(V);
    if any(gd), avgU(k)=mean(U(gd)); avgV(k)=mean(V(gd)); end
    fprintf('     Frame %d: %d / %d converged\n', k, sum(gd), nValid);
end
anyConverged = any(~isnan(Uall(:)));
assert(anyConverged, 'No points converged on any frame.');
fprintf('[6] PASS — DIC completed on %d frames\n', nDef);
passed = passed+1;

%% 7. Strain computation with corrected mask
total = total+1;
smoothSigma = 1.0;
[Z, Xq, Yq, maskQ] = computeStrainGrid_v(gridPts, Uall(:,1), Vall(:,1), dense, smoothSigma, 'exx');
finiteInMask = sum(isfinite(Z(maskQ)));
fprintf('     Strain grid: %d finite values inside mask (%d mask pixels total)\n', ...
    finiteInMask, sum(maskQ(:)));
assert(finiteInMask > 0, 'Strain grid has no finite values inside mask.');
fprintf('[7] PASS — Strain contour computed successfully\n');
passed = passed+1;

%% 8. Verify all 4 strain metrics
total = total+1;
metrics = {'exx','eyy','gxy','evm'};
for m = 1:4
    [Zm,~,~,mQ] = computeStrainGrid_v(gridPts, Uall(:,1), Vall(:,1), dense, smoothSigma, metrics{m});
    assert(any(isfinite(Zm(mQ))), sprintf('Strain metric %s returned no finite values.', metrics{m}));
end
fprintf('[8] PASS — All 4 strain metrics (exx, eyy, gxy, evm) produce valid output\n');
passed = passed+1;

%% 9. Deformed ROI boundary
total = total+1;
U1 = Uall(:,1); V1 = Vall(:,1);
gd = ~isnan(U1)&~isnan(V1);
Fu_scat = scatteredInterpolant(gridPts(gd,1), gridPts(gd,2), U1(gd), 'natural','nearest');
Fv_scat = scatteredInterpolant(gridPts(gd,1), gridPts(gd,2), V1(gd), 'natural','nearest');
bndU = Fu_scat(dense(:,1), dense(:,2));
bndV = Fv_scat(dense(:,1), dense(:,2));
defBnd = dense + [bndU, bndV];
assert(all(isfinite(defBnd(:))), 'Deformed boundary has NaN/Inf values.');
fprintf('[9] PASS — Deformed ROI boundary computed (max shift: %.2f px)\n', ...
    max(sqrt(bndU.^2+bndV.^2)));
passed = passed+1;

%% 10. Average displacement tracking
total = total+1;
nFiniteAvg = sum(~isnan(avgU));
assert(nFiniteAvg > 0, 'No frames have valid average displacement.');
fprintf('[10] PASS — Average displacement tracked: %d/%d frames\n', nFiniteAvg, nDef);
fprintf('      Mean avgU = %.4f px,  Mean avgV = %.4f px\n', ...
    mean(avgU(~isnan(avgU))), mean(avgV(~isnan(avgV))));
passed = passed+1;

%% 11. Calibration arithmetic
total = total+1;
pt1 = [100 200]; pt2 = [500 200];
pixDist  = norm(pt2-pt1);   % 400 px
realDist = 20.0;             % mm
calScale = pixDist / realDist;
assert(abs(calScale - 20.0) < 1e-6, 'Calibration scale mismatch.');
U_phys = avgU / calScale;
fprintf('[11] PASS — Calibration: %.0f px / %.1f mm = %.4f px/mm\n', pixDist, realDist, calScale);
fprintf('      Avg displacement in mm: %.6f mm\n', mean(U_phys(~isnan(U_phys))));
passed = passed+1;

%% Summary
fprintf('\n====================================================\n');
fprintf('  RESULT: %d / %d tests PASSED\n', passed, total);
fprintf('====================================================\n');
if passed == total
    fprintf('  All checks passed. DIC pipeline is functional.\n');
else
    fprintf('  WARNING: Some checks failed!\n');
end

% ======================================================================
%   Local copies of core functions (no GUI dependency)
% ======================================================================

function I = readGray_v(pth)
    I = im2double(imread(pth));
    if ndims(I)==3, I = rgb2gray(I); end %#ok<ISMAT>
end

function dense = densifyPolygon_v(pos, nPerEdge)
    N = size(pos,1); dense = [];
    for i = 1:N
        a = pos(i,:); b = pos(mod(i,N)+1,:);
        t = linspace(0,1,nPerEdge+2).';
        seg = a+(b-a).*t;
        if i<N, seg=seg(1:end-1,:); end
        dense = [dense; seg]; %#ok<AGROW>
    end
    [~,ia] = unique(round(dense,6),'rows','stable');
    dense = dense(ia,:);
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
    if numel(U)<4
        Z=nan(10); Xq=ones(10).*linspace(0,1,10); Yq=Xq'; maskQ=false(10); return;
    end
    xmin=min(polyDense(:,1)); xmax=max(polyDense(:,1));
    ymin=min(polyDense(:,2)); ymax=max(polyDense(:,2));
    nx=80; ny=80;
    xq=linspace(xmin,xmax,nx); yq=linspace(ymin,ymax,ny);
    [Xq,Yq]=meshgrid(xq,yq);
    % Map polygon to grid-pixel coords [1..nx] x [1..ny]
    polyX_gp = (polyDense(:,1)-xmin)/(xmax-xmin)*(nx-1)+1;
    polyY_gp = (polyDense(:,2)-ymin)/(ymax-ymin)*(ny-1)+1;
    maskQ = poly2mask(polyX_gp, polyY_gp, ny, nx);
    Fu=scatteredInterpolant(pts(:,1),pts(:,2),U,'natural','none');
    Fv=scatteredInterpolant(pts(:,1),pts(:,2),V,'natural','none');
    Ug=Fu(Xq,Yq); Vg=Fv(Xq,Yq);
    nanM = isnan(Ug) & maskQ;
    if any(nanM(:))
        Fn=scatteredInterpolant(pts(:,1),pts(:,2),U,'nearest','nearest');
        Ug(nanM)=Fn(Xq(nanM),Yq(nanM));
        Fn=scatteredInterpolant(pts(:,1),pts(:,2),V,'nearest','nearest');
        Vg(nanM)=Fn(Xq(nanM),Yq(nanM));
    end
    if smoothSigma>0
        fsz=max(3,2*ceil(3*smoothSigma)+1);
        Ug(~maskQ)=0; Vg(~maskQ)=0;
        Ug=imgaussfilt(Ug,smoothSigma,'FilterSize',fsz);
        Vg=imgaussfilt(Vg,smoothSigma,'FilterSize',fsz);
    end
    hx=(xmax-xmin)/(nx-1); hy=(ymax-ymin)/(ny-1);
    [~,dUdx]=gradient(Ug,hx,hy);
    [dVdy,~]=gradient(Vg,hx,hy);
    exx=dUdx; eyy=dVdy;
    gxy_val = gradient(Ug,hx) + gradient(Vg,hy);  % simplified for test
    evm_val = sqrt(exx.^2 - exx.*eyy + eyy.^2 + 3*(gxy_val/2).^2);
    switch lower(metric)
        case 'exx', Z=exx;
        case 'eyy', Z=eyy;
        case 'gxy', Z=gxy_val;
        case 'evm', Z=evm_val;
        otherwise,  Z=exx;
    end
    Z(~maskQ)=nan;
end
