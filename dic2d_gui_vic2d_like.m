function dic2d_gui_vic2d_like()
% DIC 2D GUI (Vic2D-like) with:
% - folder load
% - polygon ROI selection (enclosure)
% - densified boundary points by interpolation between selected points
% - parameter panel (subset radius, step, search radius, etc.)
% - real-time plot while processing frames
% - strain contour plot inside ROI (zoomed to ROI bounding box)
% - 2-point pixel calibration for physical displacement units
%
% Requirements: Image Processing Toolbox (drawpolygon, drawline, poly2mask).
%
% Author: ChatGPT / Updated

%% ---------------- State ----------------
S = struct();
S.folder    = "";
S.files     = [];
S.Iref      = [];
S.refName   = "";
S.defNames  = {};
S.currentFrame = 0;

% ROI
S.roiPoly      = [];
S.roiPolyDense = [];
S.roiMask      = [];
S.gridPts      = [];
S.gridIJ       = [];
S.gridSize     = [];

% DIC results (current frame only for realtime UI)
S.U      = [];
S.V      = [];
S.strain = struct();

% Calibration
S.calScale = nan;   % pixels per physical unit (px / unit)
S.calUnit  = 'mm';  % physical unit label
S.calPts   = [];    % [x1 y1; x2 y2] of the calibration line in pixels

% UI handles
H = struct();

%% ---------------- UI Layout ----------------
H.fig = uifigure('Name','2D DIC (Vic2D-like) - GUI','Position',[100 100 1350 780]);

gl = uigridlayout(H.fig,[1 2]);
gl.ColumnWidth = {370,'1x'};
gl.RowHeight   = {'1x'};

% Left panel: controls
H.left = uipanel(gl,'Title','Controls');
H.left.Layout.Row = 1; H.left.Layout.Column = 1;
glL = uigridlayout(H.left,[22 2]);
glL.RowHeight  = repmat({30},1,22);
glL.ColumnWidth = {165,'1x'};

% Right panel: plots
H.right = uipanel(gl,'Title','Display');
H.right.Layout.Row = 1; H.right.Layout.Column = 2;
glR = uigridlayout(H.right,[2 2]);
glR.RowHeight  = {'1x','1x'};
glR.ColumnWidth = {'1x','1x'};

H.axImg = uiaxes(glR); H.axImg.Layout.Row = 1; H.axImg.Layout.Column = [1 2];
title(H.axImg,'Reference / Current frame + ROI');
axis(H.axImg,'image'); H.axImg.XTick=[]; H.axImg.YTick=[];

H.axDisp = uiaxes(glR); H.axDisp.Layout.Row = 2; H.axDisp.Layout.Column = 1;
title(H.axDisp,'Displacement (quiver)');
axis(H.axDisp,'ij'); grid(H.axDisp,'on');

H.axStrain = uiaxes(glR); H.axStrain.Layout.Row = 2; H.axStrain.Layout.Column = 2;
title(H.axStrain,'Strain contour');
axis(H.axStrain,'ij'); grid(H.axStrain,'on');

%% ---------------- Control Widgets ----------------
% Row 1-2: Folder / load
H.btnLoad = uibutton(glL,'Text','Load Folder...','ButtonPushedFcn',@onLoadFolder);
H.btnLoad.Layout.Row = 1; H.btnLoad.Layout.Column = [1 2];

H.lblInfo = uilabel(glL,'Text','No folder loaded.','WordWrap','on');
H.lblInfo.Layout.Row = 2; H.lblInfo.Layout.Column = [1 2];

% Rows 3-9: DIC Parameters
row = 3;
H.edSubset = labeledEdit(glL,row,'Subset radius (R)',  '15');  row=row+1;
H.edStep   = labeledEdit(glL,row,'Step (px)',           '10');  row=row+1;
H.edSearch = labeledEdit(glL,row,'Search radius (px)',  '10');  row=row+1;
H.edIters  = labeledEdit(glL,row,'Max iters',           '25');  row=row+1;
H.edTol    = labeledEdit(glL,row,'Tol',                '1e-3'); row=row+1;
H.edMinTex = labeledEdit(glL,row,'Min texture std',     '5');   row=row+1;
H.ddInterp = labeledDropdown(glL,row,'Interp', {'linear','cubic'}, 'cubic'); row=row+1;

% Rows 10-12: ROI
H.btnROI = uibutton(glL,'Text','Select ROI (polygon)','ButtonPushedFcn',@onSelectROI);
H.btnROI.Layout.Row = row; H.btnROI.Layout.Column = [1 2]; row=row+1;

H.edDense = labeledEdit(glL,row,'ROI densify (pts/edge)','10'); row=row+1;

H.btnBuildGrid = uibutton(glL,'Text','Build grid in ROI','ButtonPushedFcn',@onBuildGrid);
H.btnBuildGrid.Layout.Row = row; H.btnBuildGrid.Layout.Column = [1 2]; row=row+1;

% Row 13: Run / Stop
H.btnRun  = uibutton(glL,'Text','Run (realtime)','ButtonPushedFcn',@onRun);
H.btnRun.Layout.Row  = row; H.btnRun.Layout.Column  = 1;
H.btnStop = uibutton(glL,'Text','Stop','ButtonPushedFcn',@onStop);
H.btnStop.Layout.Row = row; H.btnStop.Layout.Column = 2;
H.btnStop.Enable = 'off';
row=row+1;

% Row 14: Progress
H.prog = uigauge(glL,'linear','Limits',[0 1],'Value',0);
H.prog.Layout.Row = row; H.prog.Layout.Column = [1 2]; row=row+1;

% Rows 15-16: Strain display
H.ddStrain = labeledDropdown(glL,row,'Strain to show', {'exx','eyy','gxy','evm'}, 'exx'); row=row+1;
H.edSmooth = labeledEdit(glL,row,'Strain smooth sigma','1.0'); row=row+1;

% ---- Rows 17-20: Calibration section ----
H.btnCal = uibutton(glL,'Text','Calibrate pixels (2-point)','ButtonPushedFcn',@onCalibrate);
H.btnCal.Layout.Row = row; H.btnCal.Layout.Column = [1 2]; row=row+1;

H.edCalDist = labeledEdit(glL,row,'Known distance','1.0'); row=row+1;

H.ddCalUnit = labeledDropdown(glL,row,'Unit', {'mm','cm','m','in'}, 'mm'); row=row+1;

H.lblScale = uilabel(glL,'Text','Scale: not calibrated','WordWrap','on');
H.lblScale.Layout.Row = row; H.lblScale.Layout.Column = [1 2]; row=row+1;
% ---- End calibration section ----

% Row 21: Save
H.btnSave = uibutton(glL,'Text','Save MAT','ButtonPushedFcn',@onSave);
H.btnSave.Layout.Row = row; H.btnSave.Layout.Column = [1 2]; row=row+1;

% Row 22: Status
H.lblStatus = uilabel(glL,'Text','Status: idle','WordWrap','on');
H.lblStatus.Layout.Row = 22; H.lblStatus.Layout.Column = [1 2];

% Stop flag
S.stopFlag = false;

%% ---------------- Callbacks ----------------
    function onLoadFolder(~,~)
        folder = uigetdir(pwd,'Select folder with images');
        if isequal(folder,0), return; end

        exts = {'*.tif','*.tiff','*.png','*.jpg','*.jpeg','*.bmp'};
        allFiles = [];
        for i=1:numel(exts)
            allFiles = [allFiles; dir(fullfile(folder, exts{i}))]; %#ok<AGROW>
        end
        if isempty(allFiles)
            uialert(H.fig,'No images found in that folder.','Load error');
            return;
        end

        [~,idx] = sort({allFiles.name});
        allFiles = allFiles(idx);

        S.folder   = folder;
        S.files    = allFiles;
        S.refName  = allFiles(1).name;
        S.defNames = {allFiles(2:end).name};

        S.Iref = readGray(fullfile(folder,S.refName));
        cla(H.axImg); imshow(S.Iref,'Parent',H.axImg); hold(H.axImg,'on');

        S.currentFrame = 0;
        S.roiPoly      = [];
        S.roiPolyDense = [];
        S.roiMask      = [];
        S.gridPts      = [];

        H.lblInfo.Text = sprintf("Folder: %s  |  Ref: %s  |  Frames: %d", ...
            folder, S.refName, numel(S.defNames));
        H.lblStatus.Text = "Status: folder loaded";
    end

    function onSelectROI(~,~)
        if isempty(S.Iref)
            uialert(H.fig,'Load images first.','ROI');
            return;
        end
        cla(H.axImg); imshow(S.Iref,'Parent',H.axImg); hold(H.axImg,'on');
        title(H.axImg,'Draw polygon ROI — double-click to finish');

        try
            hpoly = drawpolygon(H.axImg,'LineWidth',2);
        catch
            uialert(H.fig,'drawpolygon requires the Image Processing Toolbox.','ROI');
            return;
        end
        pos = hpoly.Position;
        if size(pos,1) < 3
            uialert(H.fig,'ROI needs at least 3 points.','ROI');
            delete(hpoly);
            return;
        end

        nPerEdge = max(1, round(str2double(H.edDense.Value)));
        dense = densifyPolygon(pos, nPerEdge);

        S.roiPoly      = pos;
        S.roiPolyDense = dense;

        [Hh,Ww] = size(S.Iref);
        S.roiMask = poly2mask(dense(:,1), dense(:,2), Hh, Ww);

        cla(H.axImg); imshow(S.Iref,'Parent',H.axImg); hold(H.axImg,'on');
        plot(H.axImg, [dense(:,1); dense(1,1)], [dense(:,2); dense(1,2)], 'g-','LineWidth',2);
        plot(H.axImg, pos(:,1), pos(:,2), 'go','MarkerFaceColor','g');
        title(H.axImg,'ROI selected (green boundary)');
        zoomToROI(H.axImg, dense);

        H.lblStatus.Text = sprintf("Status: ROI selected (%d vertices, %d dense pts)", ...
            size(pos,1), size(dense,1));
    end

    function onBuildGrid(~,~)
        if isempty(S.roiMask)
            uialert(H.fig,'Select ROI first.','Grid');
            return;
        end

        R    = round(str2double(H.edSubset.Value));
        step = round(str2double(H.edStep.Value));
        [Hh,Ww] = size(S.Iref);

        xv = (1+R):step:(Ww-R);
        yv = (1+R):step:(Hh-R);
        [Xg,Yg] = meshgrid(xv,yv);
        pts = [Xg(:), Yg(:)];

        lin    = sub2ind([Hh,Ww], round(pts(:,2)), round(pts(:,1)));
        inside = S.roiMask(lin);

        S.gridPts  = pts(inside,:);
        S.gridSize = [numel(yv), numel(xv)];

        cla(H.axImg); imshow(S.Iref,'Parent',H.axImg); hold(H.axImg,'on');
        plot(H.axImg, [S.roiPolyDense(:,1); S.roiPolyDense(1,1)], ...
                      [S.roiPolyDense(:,2); S.roiPolyDense(1,2)], 'g-','LineWidth',2);
        plot(H.axImg, S.gridPts(:,1), S.gridPts(:,2), 'r.','MarkerSize',10);
        title(H.axImg, sprintf('Grid: %d points inside ROI', size(S.gridPts,1)));
        zoomToROI(H.axImg, S.roiPolyDense);

        H.lblStatus.Text = sprintf("Status: grid built (%d points)", size(S.gridPts,1));
    end

    function onCalibrate(~,~)
        if isempty(S.Iref)
            uialert(H.fig,'Load images first.','Calibrate');
            return;
        end

        % Show full reference image so user can pick two well-separated points
        cla(H.axImg);
        imshow(S.Iref,'Parent',H.axImg); hold(H.axImg,'on');
        if ~isempty(S.roiPolyDense)
            plot(H.axImg, [S.roiPolyDense(:,1); S.roiPolyDense(1,1)], ...
                          [S.roiPolyDense(:,2); S.roiPolyDense(1,2)], 'g-','LineWidth',2);
        end
        % Reset zoom so user sees the full image for accurate point selection
        axis(H.axImg,'image');
        title(H.axImg,'Calibration: draw a line between two points of known distance — right-click to confirm');
        H.lblStatus.Text = "Status: draw calibration line on image...";
        drawnow;

        try
            hLine = drawline(H.axImg,'Color','cyan','LineWidth',2.5);
            wait(hLine);  % block until the user right-clicks / presses Escape
        catch
            uialert(H.fig,'drawline requires the Image Processing Toolbox.','Calibrate');
            return;
        end

        if ~isvalid(hLine)
            H.lblStatus.Text = "Status: calibration cancelled";
            return;
        end

        pts = hLine.Position;  % [x1 y1; x2 y2]
        if size(pts,1) < 2
            uialert(H.fig,'Could not read line endpoints.','Calibrate');
            return;
        end

        pixelDist = norm(pts(2,:) - pts(1,:));
        if pixelDist < 1
            uialert(H.fig,'Points too close — pick two well-separated points.','Calibrate');
            delete(hLine);
            return;
        end

        realDist = str2double(H.edCalDist.Value);
        if isnan(realDist) || realDist <= 0
            uialert(H.fig,'Enter a valid positive known distance in the "Known distance" field.','Calibrate');
            delete(hLine);
            return;
        end

        S.calUnit  = string(H.ddCalUnit.Value);
        S.calScale = pixelDist / realDist;   % px per physical unit
        S.calPts   = pts;

        H.lblScale.Text = sprintf("Scale: %.4f px/%s  (%.1f px = %.4g %s)", ...
            S.calScale, S.calUnit, pixelDist, realDist, S.calUnit);
        H.lblStatus.Text = sprintf("Status: calibrated — %.4f px/%s", S.calScale, S.calUnit);

        % Restore ROI zoom after calibration if ROI exists
        if ~isempty(S.roiPolyDense)
            zoomToROI(H.axImg, S.roiPolyDense);
        end
    end

    function onRun(~,~)
        if isempty(S.Iref) || isempty(S.defNames)
            uialert(H.fig,'Load a folder with at least 2 images.','Run');
            return;
        end
        if isempty(S.gridPts)
            uialert(H.fig,'Build grid in ROI first.','Run');
            return;
        end

        % Read params
        R            = round(str2double(H.edSubset.Value));
        searchR      = round(str2double(H.edSearch.Value));
        maxIters     = round(str2double(H.edIters.Value));
        tol          = str2double(H.edTol.Value);
        minTex       = str2double(H.edMinTex.Value);
        interpMethod = string(H.ddInterp.Value);
        smoothSigma  = str2double(H.edSmooth.Value);

        % Precompute reference gradients / interpolants
        Iref = S.Iref;
        [Ix_ref, Iy_ref] = gradient(Iref);
        Fref = griddedInterpolant(Iref,   interpMethod, "nearest");
        Fx   = griddedInterpolant(Ix_ref, interpMethod, "nearest");
        Fy   = griddedInterpolant(Iy_ref, interpMethod, "nearest");

        % Subset local offsets
        [dx, dy] = meshgrid(-R:R, -R:R);
        dx = dx(:); dy = dy(:);

        nPts    = size(S.gridPts,1);
        nFrames = numel(S.defNames);

        H.btnRun.Enable  = 'off';
        H.btnStop.Enable = 'on';
        S.stopFlag = false;

        Uall = nan(nPts, nFrames);
        Vall = nan(nPts, nFrames);

        % Precompute per-point reference data
        refData = cell(nPts,1);
        valid   = false(nPts,1);
        for p = 1:nPts
            x0 = S.gridPts(p,1); y0 = S.gridPts(p,2);
            X  = x0 + dx; Y  = y0 + dy;
            T  = Fref(Y, X);
            sT = std(T);
            if sT < minTex, continue; end
            Tn = (T - mean(T)) / sT;
            Gx = Fx(Y, X);
            Gy = Fy(Y, X);
            SD   = [Gx, Gy];
            Hmat = SD.'*SD + 1e-8*eye(2);
            refData{p} = struct("x0",x0,"y0",y0,"Tn",Tn,"SD",SD,"invH",inv(Hmat));
            valid(p) = true;
        end

        cla(H.axDisp); cla(H.axStrain);

        % Main loop
        for k = 1:nFrames
            if S.stopFlag, break; end
            S.currentFrame = k;

            Idef = readGray(fullfile(S.folder, S.defNames{k}));
            Fdef = griddedInterpolant(Idef, interpMethod, "nearest");

            U = nan(nPts,1); V = nan(nPts,1);
            for p = 1:nPts
                if ~valid(p), continue; end
                rd  = refData{p};
                uv0 = coarseIntegerSeed(Fref, Fdef, rd.x0, rd.y0, R, searchR);
                if any(isnan(uv0)), continue; end
                [pOpt, ok] = icgn_translation(rd, Fdef, dx, dy, maxIters, tol, uv0(:));
                if ok
                    U(p) = pOpt(1);
                    V(p) = pOpt(2);
                end
            end

            Uall(:,k) = U;
            Vall(:,k) = V;

            updateRealtimePlots(Idef, U, V, smoothSigma);

            H.prog.Value    = k / max(1,nFrames);
            H.lblStatus.Text = sprintf("Status: frame %d/%d — %s", k, nFrames, S.defNames{k});
            drawnow;
        end

        S.U = Uall;
        S.V = Vall;

        H.btnRun.Enable  = 'on';
        H.btnStop.Enable = 'off';
        H.lblStatus.Text = "Status: done";
    end

    function onStop(~,~)
        S.stopFlag = true;
        H.lblStatus.Text = "Status: stopping...";
    end

    function onSave(~,~)
        if isempty(S.U) || isempty(S.V)
            uialert(H.fig,'No results to save yet. Run DIC first.','Save');
            return;
        end
        out.folder       = S.folder;
        out.refName      = S.refName;
        out.defNames     = S.defNames;
        out.gridPts      = S.gridPts;
        out.roiPoly      = S.roiPoly;
        out.roiPolyDense = S.roiPolyDense;
        out.U            = S.U;
        out.V            = S.V;
        out.calScale     = S.calScale;
        out.calUnit      = S.calUnit;

        [file,path] = uiputfile('DIC_results.mat','Save results as');
        if isequal(file,0), return; end
        save(fullfile(path,file),'-struct','out','-v7.3');
        H.lblStatus.Text = sprintf("Status: saved — %s", fullfile(path,file));
    end

%% ---------------- Real-time plot update ----------------
    function updateRealtimePlots(Idef, U, V, smoothSigma)
        %-- Image panel: show deformed frame + ROI overlay, zoomed to ROI --
        cla(H.axImg);
        imshow(Idef,'Parent',H.axImg); hold(H.axImg,'on');
        if ~isempty(S.roiPolyDense)
            plot(H.axImg, [S.roiPolyDense(:,1); S.roiPolyDense(1,1)], ...
                          [S.roiPolyDense(:,2); S.roiPolyDense(1,2)], 'g-','LineWidth',2);
        end
        plot(H.axImg, S.gridPts(:,1), S.gridPts(:,2), 'r.','MarkerSize',8);
        title(H.axImg, sprintf("Frame %d: %s", S.currentFrame, S.defNames{S.currentFrame}));
        % Zoom image to ROI bounding box
        if ~isempty(S.roiPolyDense)
            zoomToROI(H.axImg, S.roiPolyDense);
        end

        %-- Displacement quiver, scaled to physical units if calibrated --
        good = ~isnan(U) & ~isnan(V);
        if ~isnan(S.calScale) && S.calScale > 0
            Uplot    = U / S.calScale;
            Vplot    = V / S.calScale;
            dispUnit = S.calUnit;
        else
            Uplot    = U;
            Vplot    = V;
            dispUnit = 'px';
        end

        cla(H.axDisp); hold(H.axDisp,'on');
        quiver(H.axDisp, S.gridPts(good,1), S.gridPts(good,2), ...
               Uplot(good), Vplot(good), 0);
        set(H.axDisp,'YDir','reverse');
        grid(H.axDisp,'on');
        xlabel(H.axDisp,'X (px)');
        ylabel(H.axDisp,'Y (px)');
        title(H.axDisp, sprintf('Displacement  [%s]', dispUnit));
        % Zoom quiver to ROI bounding box
        if ~isempty(S.roiPolyDense)
            zoomToROI(H.axDisp, S.roiPolyDense);
        end

        %-- Strain contour, zoomed to ROI --
        metric = string(H.ddStrain.Value);
        [Z, Xq, Yq, maskQ] = computeStrainGrid(S.gridPts, U, V, ...
                                                S.roiPolyDense, smoothSigma, metric);
        cla(H.axStrain);
        imagesc(H.axStrain, Xq(1,:), Yq(:,1), Z); hold(H.axStrain,'on');
        set(H.axStrain,'YDir','reverse');
        colorbar(H.axStrain);
        if ~isempty(S.roiPolyDense)
            plot(H.axStrain, [S.roiPolyDense(:,1); S.roiPolyDense(1,1)], ...
                             [S.roiPolyDense(:,2); S.roiPolyDense(1,2)], 'k-','LineWidth',1.5);
            zoomToROI(H.axStrain, S.roiPolyDense);
        end
        title(H.axStrain, sprintf('Strain contour: %s', metric));

        % Apply transparency mask outside polygon
        hImg = findobj(H.axStrain,'Type','Image');
        if ~isempty(hImg)
            alpha = double(maskQ);
            set(hImg(1),'AlphaData',alpha);
        end
    end

%% ---------------- Axes zoom helper ----------------
    function zoomToROI(ax, polyDense)
        % Zoom an axes to the ROI bounding box with 5% padding.
        xmin = min(polyDense(:,1)); xmax = max(polyDense(:,1));
        ymin = min(polyDense(:,2)); ymax = max(polyDense(:,2));
        pad  = max(5, 0.05 * max(xmax-xmin, ymax-ymin));
        xlim(ax, [xmin-pad, xmax+pad]);
        ylim(ax, [ymin-pad, ymax+pad]);
    end

%% ---------------- GUI widget helpers ----------------
    function ed = labeledEdit(parent, row, label, defaultVal)
        lab = uilabel(parent,'Text',label,'HorizontalAlignment','left');
        lab.Layout.Row    = row;
        lab.Layout.Column = 1;
        ed = uieditfield(parent,'text','Value',defaultVal);
        ed.Layout.Row    = row;
        ed.Layout.Column = 2;
    end

    function dd = labeledDropdown(parent, row, label, items, defaultVal)
        lab = uilabel(parent,'Text',label,'HorizontalAlignment','left');
        lab.Layout.Row    = row;
        lab.Layout.Column = 1;
        dd = uidropdown(parent,'Items',items,'Value',defaultVal);
        dd.Layout.Row    = row;
        dd.Layout.Column = 2;
    end

end % end of main function

% ======================================================================
%                              DIC Core
% ======================================================================

function I = readGray(path)
    I = im2double(imread(path));
    if ndims(I)==3, I = rgb2gray(I); end
end

function dense = densifyPolygon(pos, nPerEdge)
% Interpolate nPerEdge points between each consecutive pair of polygon vertices.
    N     = size(pos,1);
    dense = [];
    for i = 1:N
        a   = pos(i,:);
        b   = pos(mod(i,N)+1,:);
        t   = linspace(0,1,nPerEdge+2).';
        seg = a + (b-a).*t;
        if i < N
            seg = seg(1:end-1,:);
        end
        dense = [dense; seg]; %#ok<AGROW>
    end
    [~,ia] = unique(round(dense,6),'rows','stable');
    dense  = dense(ia,:);
end

function uv = coarseIntegerSeed(Fref, Fdef, x0, y0, R, searchR)
    [dx, dy] = meshgrid(-R:R, -R:R);
    Xr = x0 + dx; Yr = y0 + dy;
    T  = Fref(Yr, Xr);
    sT = std(T(:));
    if sT < 1e-9, uv = [nan nan]; return; end
    Tn = (T - mean(T(:))) / sT;

    best   = inf;
    bestuv = [0 0];
    for du = -searchR:searchR
        for dv = -searchR:searchR
            I  = Fdef(Yr+dv, Xr+du);
            sI = std(I(:));
            if sI < 1e-9, continue; end
            In  = (I - mean(I(:))) / sI;
            sse = sum((Tn(:)-In(:)).^2);
            if sse < best
                best   = sse;
                bestuv = [du dv];
            end
        end
    end
    uv = bestuv;
end

function [p, ok] = icgn_translation(rd, Fdef, dxv, dyv, maxIters, tol, p0)
% Translation-only IC-GN with ZNSSD residual.
    p  = p0(:);
    ok = false;

    x0   = rd.x0; y0 = rd.y0;
    Tn   = rd.Tn;
    SD   = rd.SD;
    invH = rd.invH;

    for it = 1:maxIters
        Xw = x0 + dxv + p(1);
        Yw = y0 + dyv + p(2);
        I  = Fdef(Yw, Xw);

        sI = std(I);
        if sI < 1e-9, return; end
        In = (I - mean(I)) / sI;

        e  = Tn - In;
        dp = invH * (SD.' * e);
        p  = p + dp;

        if norm(dp) < tol
            ok = true;
            return;
        end
    end
    ok = true;
end

% ======================================================================
%                         Strain Post-Processing
% ======================================================================

function [Z, Xq, Yq, maskQ] = computeStrainGrid(pts, U, V, polyDense, smoothSigma, metric)
% Interpolate scattered displacements to a regular grid covering the ROI
% bounding box, then compute engineering strains by finite differences.

    good = ~isnan(U) & ~isnan(V);
    pts  = pts(good,:);
    U    = U(good);
    V    = V(good);

    if isempty(pts)
        Z    = nan(10);
        Xq   = linspace(0,1,10);
        Yq   = linspace(0,1,10).';
        maskQ = false(10);
        return;
    end

    xmin = min(polyDense(:,1)); xmax = max(polyDense(:,1));
    ymin = min(polyDense(:,2)); ymax = max(polyDense(:,2));

    nx = 120; ny = 120;
    xq = linspace(xmin, xmax, nx);
    yq = linspace(ymin, ymax, ny);
    [Xq, Yq] = meshgrid(xq, yq);

    % Build mask in the query-grid's local integer coordinates
    maskQ = poly2mask(polyDense(:,1)-xmin+1, polyDense(:,2)-ymin+1, ny, nx);

    % Scattered interpolation of U and V onto the regular grid
    Fu = scatteredInterpolant(pts(:,1), pts(:,2), U, 'natural','none');
    Fv = scatteredInterpolant(pts(:,1), pts(:,2), V, 'natural','none');
    Ug = Fu(Xq, Yq);
    Vg = Fv(Xq, Yq);

    % Optional Gaussian smoothing to reduce noise before strain differentiation
    if smoothSigma > 0
        fsz = max(3, 2*ceil(3*smoothSigma)+1);
        Ug  = imgaussfilt(Ug, smoothSigma, 'FilterSize', fsz);
        Vg  = imgaussfilt(Vg, smoothSigma, 'FilterSize', fsz);
    end

    % Spatial gradients (first-order finite differences via gradient())
    dx = mean(diff(xq));
    dy = mean(diff(yq));
    [dUdy, dUdx] = gradient(Ug, dy, dx);
    [dVdy, dVdx] = gradient(Vg, dy, dx);

    exx = dUdx;
    eyy = dVdy;
    gxy = dUdy + dVdx;
    evm = sqrt(exx.^2 - exx.*eyy + eyy.^2 + 3*(gxy/2).^2);

    switch lower(metric)
        case "exx",  Z = exx;
        case "eyy",  Z = eyy;
        case "gxy",  Z = gxy;
        case "evm",  Z = evm;
        otherwise,   Z = exx;
    end

    Z(~maskQ) = nan;
end
