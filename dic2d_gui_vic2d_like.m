function dic2d_gui_vic2d_like()
% DIC 2D GUI (Vic2D-like) with:
% - folder load
% - polygon ROI selection
% - densified boundary points
% - parameter panel (subset radius, step, search radius, etc.)
% - real-time strain contour plot inside ROI (zoomed to ROI)
% - ROI overlay that tracks/deforms with the specimen
% - average displacement vs frame number plot
% - 2-point pixel calibration via point picking + distance input dialog
%
% Requirements: Image Processing Toolbox (drawpolygon, drawpoint, poly2mask, imgaussfilt).

%% ---------------- State ----------------
S = struct();
S.folder       = "";
S.files        = [];
S.Iref         = [];
S.refName      = "";
S.defNames     = {};
S.currentFrame = 0;

% ROI
S.roiPoly      = [];   % user-drawn polygon vertices [x y]
S.roiPolyDense = [];   % densified boundary
S.roiMask      = [];   % binary mask on reference image
S.gridPts      = [];   % [x y] grid point coords (reference config)
S.gridIJ       = [];
S.gridSize     = [];

% DIC cumulative results
S.U      = [];   % nPts x nFrames
S.V      = [];
S.strain = struct();

% Calibration
S.calScale = nan;   % pixels per physical unit (px / unit)
S.calUnit  = 'mm';
S.calPts   = [];    % [x1 y1; x2 y2]

% UI handles
H = struct();

%% ---------------- UI Layout ----------------
H.fig = uifigure('Name','2D DIC (Vic2D-like) - GUI','Position',[100 100 1400 800]);

gl = uigridlayout(H.fig,[1 2]);
gl.ColumnWidth = {380,'1x'};
gl.RowHeight   = {'1x'};

% Left panel: controls
H.left = uipanel(gl,'Title','Controls');
H.left.Layout.Row = 1; H.left.Layout.Column = 1;
glL = uigridlayout(H.left,[22 2]);
glL.RowHeight   = repmat({30},1,22);
glL.ColumnWidth = {170,'1x'};

% Right panel: plots
H.right = uipanel(gl,'Title','Display');
H.right.Layout.Row = 1; H.right.Layout.Column = 2;
glR = uigridlayout(H.right,[2 2]);
glR.RowHeight   = {'1x','1x'};
glR.ColumnWidth = {'1x','1x'};

H.axImg = uiaxes(glR);
H.axImg.Layout.Row = 1; H.axImg.Layout.Column = [1 2];
title(H.axImg,'Reference / Current frame + ROI');
axis(H.axImg,'image'); H.axImg.XTick=[]; H.axImg.YTick=[];

H.axDisp = uiaxes(glR);
H.axDisp.Layout.Row = 2; H.axDisp.Layout.Column = 1;
title(H.axDisp,'Avg Displacement vs Frame');
grid(H.axDisp,'on'); xlabel(H.axDisp,'Frame'); ylabel(H.axDisp,'Displacement');

H.axStrain = uiaxes(glR);
H.axStrain.Layout.Row = 2; H.axStrain.Layout.Column = 2;
title(H.axStrain,'Strain contour');
axis(H.axStrain,'ij'); grid(H.axStrain,'on');

%% ---------------- Control Widgets ----------------
H.btnLoad = uibutton(glL,'Text','Load Folder...','ButtonPushedFcn',@onLoadFolder);
H.btnLoad.Layout.Row = 1; H.btnLoad.Layout.Column = [1 2];

H.lblInfo = uilabel(glL,'Text','No folder loaded.','WordWrap','on');
H.lblInfo.Layout.Row = 2; H.lblInfo.Layout.Column = [1 2];

row = 3;
H.edSubset = labeledEdit(glL,row,'Subset radius (R)',  '15');  row=row+1;
H.edStep   = labeledEdit(glL,row,'Step (px)',           '10');  row=row+1;
H.edSearch = labeledEdit(glL,row,'Search radius (px)',  '10');  row=row+1;
H.edIters  = labeledEdit(glL,row,'Max iters',           '25');  row=row+1;
H.edTol    = labeledEdit(glL,row,'Tol',                '1e-3'); row=row+1;
H.edMinTex = labeledEdit(glL,row,'Min texture std',     '0.01'); row=row+1;
H.ddInterp = labeledDropdown(glL,row,'Interp', {'linear','cubic'}, 'cubic'); row=row+1;

% ROI
H.btnROI = uibutton(glL,'Text','Select ROI (polygon)','ButtonPushedFcn',@onSelectROI);
H.btnROI.Layout.Row = row; H.btnROI.Layout.Column = [1 2]; row=row+1;

H.edDense = labeledEdit(glL,row,'ROI densify (pts/edge)','10'); row=row+1;

H.btnBuildGrid = uibutton(glL,'Text','Build grid in ROI','ButtonPushedFcn',@onBuildGrid);
H.btnBuildGrid.Layout.Row = row; H.btnBuildGrid.Layout.Column = [1 2]; row=row+1;

% Run / Stop
H.btnRun  = uibutton(glL,'Text','Run (realtime)','ButtonPushedFcn',@onRun);
H.btnRun.Layout.Row  = row; H.btnRun.Layout.Column = 1;
H.btnStop = uibutton(glL,'Text','Stop','ButtonPushedFcn',@onStop);
H.btnStop.Layout.Row = row; H.btnStop.Layout.Column = 2;
H.btnStop.Enable = 'off';
row=row+1;

H.prog = uigauge(glL,'linear','Limits',[0 1],'Value',0);
H.prog.Layout.Row = row; H.prog.Layout.Column = [1 2]; row=row+1;

% Strain + displacement display
H.ddStrain = labeledDropdown(glL,row,'Strain component', {'exx','eyy','gxy','evm'}, 'exx'); row=row+1;
H.edSmooth = labeledEdit(glL,row,'Strain smooth sigma','1.0'); row=row+1;
H.ddDispDir = labeledDropdown(glL,row,'Disp direction', {'U (horizontal)','V (vertical)'}, 'U (horizontal)'); row=row+1;

% Calibration
H.btnCal = uibutton(glL,'Text','Calibrate (pick 2 points)','ButtonPushedFcn',@onCalibrate);
H.btnCal.Layout.Row = row; H.btnCal.Layout.Column = [1 2]; row=row+1;

H.lblScale = uilabel(glL,'Text','Scale: not calibrated','WordWrap','on');
H.lblScale.Layout.Row = row; H.lblScale.Layout.Column = [1 2]; row=row+1;

% Save
H.btnSave = uibutton(glL,'Text','Save MAT','ButtonPushedFcn',@onSave);
H.btnSave.Layout.Row = row; H.btnSave.Layout.Column = [1 2]; row=row+1;

% Status
H.lblStatus = uilabel(glL,'Text','Status: idle','WordWrap','on');
H.lblStatus.Layout.Row = 22; H.lblStatus.Layout.Column = [1 2];

S.stopFlag = false;

% Storage for running avg-displacement plot
S.avgU = [];  % 1 x nFrames running vectors
S.avgV = [];

%% ================================================================
%%                          CALLBACKS
%% ================================================================

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
        S.U = []; S.V = [];
        S.avgU = []; S.avgV = [];

        H.lblInfo.Text = sprintf("Folder: %s  |  Ref: %s  |  Frames: %d", ...
            folder, S.refName, numel(S.defNames));
        H.lblStatus.Text = "Status: folder loaded";
    end

    function onSelectROI(~,~)
        if isempty(S.Iref)
            uialert(H.fig,'Load images first.','ROI'); return;
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
            delete(hpoly); return;
        end

        nPerEdge = max(1, round(str2double(H.edDense.Value)));
        dense = densifyPolygon(pos, nPerEdge);

        S.roiPoly      = pos;
        S.roiPolyDense = dense;

        [Hh,Ww] = size(S.Iref);
        S.roiMask = poly2mask(dense(:,1), dense(:,2), Hh, Ww);

        cla(H.axImg); imshow(S.Iref,'Parent',H.axImg); hold(H.axImg,'on');
        plot(H.axImg, [dense(:,1);dense(1,1)], [dense(:,2);dense(1,2)], 'g-','LineWidth',2);
        plot(H.axImg, pos(:,1), pos(:,2), 'go','MarkerFaceColor','g');
        title(H.axImg,'ROI selected');
        zoomToROI(H.axImg, dense);

        H.lblStatus.Text = sprintf("Status: ROI selected (%d vertices)", size(pos,1));
    end

    function onBuildGrid(~,~)
        if isempty(S.roiMask)
            uialert(H.fig,'Select ROI first.','Grid'); return;
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
        plot(H.axImg, [S.roiPolyDense(:,1);S.roiPolyDense(1,1)], ...
                      [S.roiPolyDense(:,2);S.roiPolyDense(1,2)], 'g-','LineWidth',2);
        plot(H.axImg, S.gridPts(:,1), S.gridPts(:,2), 'r.','MarkerSize',10);
        title(H.axImg, sprintf('Grid: %d points', size(S.gridPts,1)));
        zoomToROI(H.axImg, S.roiPolyDense);

        H.lblStatus.Text = sprintf("Status: grid built (%d points)", size(S.gridPts,1));
    end

    function onCalibrate(~,~)
        if isempty(S.Iref)
            uialert(H.fig,'Load images first.','Calibrate'); return;
        end

        % Show reference image at full zoom for point picking
        cla(H.axImg);
        imshow(S.Iref,'Parent',H.axImg); hold(H.axImg,'on');
        if ~isempty(S.roiPolyDense)
            plot(H.axImg, [S.roiPolyDense(:,1);S.roiPolyDense(1,1)], ...
                          [S.roiPolyDense(:,2);S.roiPolyDense(1,2)], 'g-','LineWidth',2);
        end
        axis(H.axImg,'image');
        title(H.axImg,'CALIBRATE: Click FIRST point, then double-click to confirm');
        H.lblStatus.Text = "Status: pick first calibration point...";
        drawnow;

        % Pick point 1
        try
            hp1 = drawpoint(H.axImg,'Color','cyan','MarkerSize',12);
        catch
            uialert(H.fig,'drawpoint requires the Image Processing Toolbox.','Calibrate');
            return;
        end
        pt1 = hp1.Position;  % [x1 y1]

        % Pick point 2
        title(H.axImg,'CALIBRATE: Click SECOND point, then double-click to confirm');
        H.lblStatus.Text = "Status: pick second calibration point...";
        drawnow;

        try
            hp2 = drawpoint(H.axImg,'Color','magenta','MarkerSize',12);
        catch
            delete(hp1);
            uialert(H.fig,'drawpoint failed.','Calibrate');
            return;
        end
        pt2 = hp2.Position;  % [x2 y2]

        % Draw line between the two points
        plot(H.axImg, [pt1(1) pt2(1)], [pt1(2) pt2(2)], 'c-','LineWidth',2);

        pixelDist = norm(pt2 - pt1);
        if pixelDist < 1
            uialert(H.fig,'Points too close — pick two well-separated points.','Calibrate');
            delete(hp1); delete(hp2);
            return;
        end

        % Ask user for the real distance via input dialog
        answer = inputdlg( ...
            {sprintf('Pixel distance = %.1f px.\nEnter the real-world distance:', pixelDist), ...
             'Unit (mm, cm, m, in):'}, ...
            'Calibration', [1 50], {'1.0','mm'});

        if isempty(answer)
            H.lblStatus.Text = "Status: calibration cancelled";
            delete(hp1); delete(hp2);
            return;
        end

        realDist = str2double(answer{1});
        unitStr  = strtrim(answer{2});
        if isnan(realDist) || realDist <= 0
            uialert(H.fig,'Enter a valid positive distance.','Calibrate');
            delete(hp1); delete(hp2);
            return;
        end

        S.calScale = pixelDist / realDist;   % px per physical unit
        S.calUnit  = unitStr;
        S.calPts   = [pt1; pt2];

        H.lblScale.Text = sprintf("Scale: %.4f px/%s\n(%.1f px = %.4g %s)", ...
            S.calScale, S.calUnit, pixelDist, realDist, S.calUnit);
        H.lblStatus.Text = sprintf("Status: calibrated — %.4f px/%s", S.calScale, S.calUnit);

        % Restore ROI zoom
        if ~isempty(S.roiPolyDense)
            zoomToROI(H.axImg, S.roiPolyDense);
        end
    end

    function onRun(~,~)
        if isempty(S.Iref) || isempty(S.defNames)
            uialert(H.fig,'Load a folder with at least 2 images.','Run'); return;
        end
        if isempty(S.gridPts)
            uialert(H.fig,'Build grid in ROI first.','Run'); return;
        end

        R            = round(str2double(H.edSubset.Value));
        searchR      = round(str2double(H.edSearch.Value));
        maxIters     = round(str2double(H.edIters.Value));
        tol          = str2double(H.edTol.Value);
        minTex       = str2double(H.edMinTex.Value);
        interpMethod = string(H.ddInterp.Value);
        smoothSigma  = str2double(H.edSmooth.Value);

        Iref = S.Iref;
        [Ix_ref, Iy_ref] = gradient(Iref);
        Fref = griddedInterpolant(Iref,   interpMethod, "nearest");
        Fx   = griddedInterpolant(Ix_ref, interpMethod, "nearest");
        Fy   = griddedInterpolant(Iy_ref, interpMethod, "nearest");

        [dxs, dys] = meshgrid(-R:R, -R:R);
        dxs = dxs(:); dys = dys(:);

        nPts    = size(S.gridPts,1);
        nFrames = numel(S.defNames);

        H.btnRun.Enable  = 'off';
        H.btnStop.Enable = 'on';
        S.stopFlag = false;

        Uall = nan(nPts, nFrames);
        Vall = nan(nPts, nFrames);

        % Precompute per-point reference subset data
        refData = cell(nPts,1);
        valid   = false(nPts,1);
        for p = 1:nPts
            x0 = S.gridPts(p,1); y0 = S.gridPts(p,2);
            X  = x0 + dxs; Y  = y0 + dys;
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

        nValid = sum(valid);
        if nValid == 0
            uialert(H.fig,'No grid points have sufficient texture. Lower "Min texture std" or select a different ROI.','Run');
            H.btnRun.Enable = 'on'; H.btnStop.Enable = 'off';
            return;
        end

        % Init running avg displacement arrays
        S.avgU = nan(1, nFrames);
        S.avgV = nan(1, nFrames);

        cla(H.axDisp); cla(H.axStrain);

        % Main DIC loop
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
                [pOpt, ok] = icgn_translation(rd, Fdef, dxs, dys, maxIters, tol, uv0(:));
                if ok
                    U(p) = pOpt(1);
                    V(p) = pOpt(2);
                end
            end

            Uall(:,k) = U;
            Vall(:,k) = V;

            % Compute running averages for displacement plot
            good = ~isnan(U) & ~isnan(V);
            if any(good)
                S.avgU(k) = mean(U(good));
                S.avgV(k) = mean(V(good));
            end

            % Update all real-time plots
            updateRealtimePlots(Idef, U, V, k, smoothSigma);

            H.prog.Value     = k / max(1,nFrames);
            H.lblStatus.Text = sprintf("Status: frame %d/%d — %s  (%d/%d converged)", ...
                k, nFrames, S.defNames{k}, sum(good), nValid);
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
            uialert(H.fig,'No results to save yet. Run DIC first.','Save'); return;
        end
        out.folder       = S.folder;
        out.refName      = S.refName;
        out.defNames     = S.defNames;
        out.gridPts      = S.gridPts;
        out.roiPoly      = S.roiPoly;
        out.roiPolyDense = S.roiPolyDense;
        out.U            = S.U;
        out.V            = S.V;
        out.avgU         = S.avgU;
        out.avgV         = S.avgV;
        out.calScale     = S.calScale;
        out.calUnit      = S.calUnit;

        [file,path] = uiputfile('DIC_results.mat','Save results as');
        if isequal(file,0), return; end
        save(fullfile(path,file),'-struct','out','-v7.3');
        H.lblStatus.Text = sprintf("Status: saved — %s", fullfile(path,file));
    end

%% ================================================================
%%                       REAL-TIME PLOT UPDATE
%% ================================================================

    function updateRealtimePlots(Idef, U, V, frameIdx, smoothSigma)
        good = ~isnan(U) & ~isnan(V);

        % ---- (1) IMAGE PANEL: deformed frame + displaced ROI overlay ----
        cla(H.axImg);
        imshow(Idef,'Parent',H.axImg); hold(H.axImg,'on');

        % Draw displaced grid points (reference position + displacement)
        if any(good)
            dispX = S.gridPts(good,1) + U(good);
            dispY = S.gridPts(good,2) + V(good);
            plot(H.axImg, dispX, dispY, 'r.','MarkerSize',8);
        end

        % Draw deformed ROI boundary using interpolated displacement field
        if ~isempty(S.roiPolyDense) && any(good)
            % Interpolate the displacement field at the dense boundary points
            Fu_scat = scatteredInterpolant(S.gridPts(good,1), S.gridPts(good,2), ...
                                           U(good), 'natural','nearest');
            Fv_scat = scatteredInterpolant(S.gridPts(good,1), S.gridPts(good,2), ...
                                           V(good), 'natural','nearest');
            bndU = Fu_scat(S.roiPolyDense(:,1), S.roiPolyDense(:,2));
            bndV = Fv_scat(S.roiPolyDense(:,1), S.roiPolyDense(:,2));
            defBnd = S.roiPolyDense + [bndU, bndV];
            plot(H.axImg, [defBnd(:,1);defBnd(1,1)], [defBnd(:,2);defBnd(1,2)], ...
                 'g-','LineWidth',2);
        elseif ~isempty(S.roiPolyDense)
            % Fallback: show undeformed boundary
            plot(H.axImg, [S.roiPolyDense(:,1);S.roiPolyDense(1,1)], ...
                          [S.roiPolyDense(:,2);S.roiPolyDense(1,2)], 'g-','LineWidth',2);
        end

        title(H.axImg, sprintf("Frame %d: %s", frameIdx, S.defNames{frameIdx}));
        if ~isempty(S.roiPolyDense)
            zoomToROI(H.axImg, S.roiPolyDense);
        end

        % ---- (2) DISPLACEMENT PANEL: avg displacement vs frame number ----
        % Determine direction from dropdown
        dirStr = string(H.ddDispDir.Value);
        if startsWith(dirStr,'U')
            avgData = S.avgU;
            dirLabel = 'U (horizontal)';
        else
            avgData = S.avgV;
            dirLabel = 'V (vertical)';
        end

        % Scale to physical units if calibrated
        if ~isnan(S.calScale) && S.calScale > 0
            plotData = avgData / S.calScale;
            dispUnit = S.calUnit;
        else
            plotData = avgData;
            dispUnit = 'px';
        end

        cla(H.axDisp); hold(H.axDisp,'on');
        frames = 1:numel(plotData);
        validFrames = ~isnan(plotData);
        if any(validFrames)
            plot(H.axDisp, frames(validFrames), plotData(validFrames), 'b.-','MarkerSize',12,'LineWidth',1.5);
        end
        xlabel(H.axDisp, 'Frame number');
        ylabel(H.axDisp, sprintf('Avg %s  [%s]', dirLabel, dispUnit));
        title(H.axDisp, sprintf('Avg Displacement — %s', dirLabel));
        grid(H.axDisp,'on');
        xlim(H.axDisp, [0.5, max(2,numel(plotData)+0.5)]);

        % ---- (3) STRAIN CONTOUR, zoomed to ROI ----
        metric = string(H.ddStrain.Value);
        [Z, Xq, Yq, maskQ] = computeStrainGrid(S.gridPts, U, V, ...
                                                 S.roiPolyDense, smoothSigma, metric);

        cla(H.axStrain);
        if ~all(isnan(Z(:)))
            imagesc(H.axStrain, Xq(1,:), Yq(:,1), Z, 'AlphaData', double(maskQ));
            hold(H.axStrain,'on');
            set(H.axStrain,'YDir','reverse');
            colorbar(H.axStrain);
            colormap(H.axStrain, 'jet');

            if ~isempty(S.roiPolyDense)
                plot(H.axStrain, [S.roiPolyDense(:,1);S.roiPolyDense(1,1)], ...
                                 [S.roiPolyDense(:,2);S.roiPolyDense(1,2)], 'k-','LineWidth',1.5);
                zoomToROI(H.axStrain, S.roiPolyDense);
            end
        else
            text(H.axStrain, 0.5, 0.5, 'No strain data', ...
                 'HorizontalAlignment','center','Units','normalized');
        end
        title(H.axStrain, sprintf('Strain: %s  (frame %d)', metric, frameIdx));
    end

%% ================================================================
%%                         HELPER FUNCTIONS
%% ================================================================

    function zoomToROI(ax, polyDense)
        xmin = min(polyDense(:,1)); xmax = max(polyDense(:,1));
        ymin = min(polyDense(:,2)); ymax = max(polyDense(:,2));
        pad  = max(5, 0.05 * max(xmax-xmin, ymax-ymin));
        xlim(ax, [xmin-pad, xmax+pad]);
        ylim(ax, [ymin-pad, ymax+pad]);
    end

    function ed = labeledEdit(parent, r, label, defaultVal)
        lab = uilabel(parent,'Text',label,'HorizontalAlignment','left');
        lab.Layout.Row = r; lab.Layout.Column = 1;
        ed = uieditfield(parent,'text','Value',defaultVal);
        ed.Layout.Row = r; ed.Layout.Column = 2;
    end

    function dd = labeledDropdown(parent, r, label, items, defaultVal)
        lab = uilabel(parent,'Text',label,'HorizontalAlignment','left');
        lab.Layout.Row = r; lab.Layout.Column = 1;
        dd = uidropdown(parent,'Items',items,'Value',defaultVal);
        dd.Layout.Row = r; dd.Layout.Column = 2;
    end

end  % end of main function

% ======================================================================
%                              DIC Core
% ======================================================================

function I = readGray(p)
    I = im2double(imread(p));
    if ndims(I)==3, I = rgb2gray(I); end %#ok<ISMAT>
end

function dense = densifyPolygon(pos, nPerEdge)
    N = size(pos,1);
    dense = [];
    for i = 1:N
        a = pos(i,:);
        b = pos(mod(i,N)+1,:);
        t = linspace(0,1,nPerEdge+2).';
        seg = a + (b-a).*t;
        if i < N, seg = seg(1:end-1,:); end
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
    best = inf; bestuv = [0 0];
    for du = -searchR:searchR
        for dv = -searchR:searchR
            I  = Fdef(Yr+dv, Xr+du);
            sI = std(I(:));
            if sI < 1e-9, continue; end
            In  = (I - mean(I(:))) / sI;
            sse = sum((Tn(:)-In(:)).^2);
            if sse < best, best = sse; bestuv = [du dv]; end
        end
    end
    uv = bestuv;
end

function [p, ok] = icgn_translation(rd, Fdef, dxv, dyv, maxIters, tol, p0)
    p  = p0(:); ok = false;
    x0 = rd.x0; y0 = rd.y0;
    for it = 1:maxIters
        Xw = x0 + dxv + p(1);
        Yw = y0 + dyv + p(2);
        I  = Fdef(Yw, Xw);
        sI = std(I);
        if sI < 1e-9, return; end
        In = (I - mean(I)) / sI;
        e  = rd.Tn - In;
        dp = rd.invH * (rd.SD.' * e);
        p  = p + dp;
        if norm(dp) < tol, ok = true; return; end
    end
    ok = true;
end

% ======================================================================
%                        Strain Post-Processing
% ======================================================================

function [Z, Xq, Yq, maskQ] = computeStrainGrid(pts, U, V, polyDense, smoothSigma, metric)
% Interpolate scattered displacement onto a regular grid inside the ROI
% bounding box, then compute strains via spatial gradients.

    good = ~isnan(U) & ~isnan(V);
    pts  = pts(good,:);
    U    = U(good);
    V    = V(good);

    if numel(U) < 4
        Z = nan(10); Xq = ones(10).*linspace(0,1,10);
        Yq = Xq'; maskQ = false(10);
        return;
    end

    xmin = min(polyDense(:,1)); xmax = max(polyDense(:,1));
    ymin = min(polyDense(:,2)); ymax = max(polyDense(:,2));

    nx = 120; ny = 120;
    xq = linspace(xmin, xmax, nx);
    yq = linspace(ymin, ymax, ny);
    [Xq, Yq] = meshgrid(xq, yq);

    % Build ROI mask on the query grid.
    % Map polygon world-coords to [1..nx] x [1..ny] grid-pixel coords.
    polyX_gp = (polyDense(:,1) - xmin) / (xmax - xmin) * (nx - 1) + 1;
    polyY_gp = (polyDense(:,2) - ymin) / (ymax - ymin) * (ny - 1) + 1;
    maskQ = poly2mask(polyX_gp, polyY_gp, ny, nx);

    % Scattered interpolation of U and V onto the regular grid
    Fu = scatteredInterpolant(pts(:,1), pts(:,2), U, 'natural','none');
    Fv = scatteredInterpolant(pts(:,1), pts(:,2), V, 'natural','none');
    Ug = Fu(Xq, Yq);
    Vg = Fv(Xq, Yq);

    % Replace NaNs inside the mask with nearest-neighbour to avoid gaps
    nanMask = isnan(Ug) & maskQ;
    if any(nanMask(:))
        Fn = scatteredInterpolant(pts(:,1), pts(:,2), U, 'nearest','nearest');
        Ug(nanMask) = Fn(Xq(nanMask), Yq(nanMask));
        Fn = scatteredInterpolant(pts(:,1), pts(:,2), V, 'nearest','nearest');
        Vg(nanMask) = Fn(Xq(nanMask), Yq(nanMask));
    end

    % Gaussian smoothing before differentiation
    if smoothSigma > 0
        fsz = max(3, 2*ceil(3*smoothSigma)+1);
        % Only smooth inside the mask to avoid boundary artifacts
        Ug(~maskQ) = 0;
        Vg(~maskQ) = 0;
        Ug = imgaussfilt(Ug, smoothSigma, 'FilterSize', fsz);
        Vg = imgaussfilt(Vg, smoothSigma, 'FilterSize', fsz);
    end

    % Spatial gradients (pixel spacing in world coordinates)
    hx = (xmax - xmin) / (nx - 1);
    hy = (ymax - ymin) / (ny - 1);
    [dUdy, dUdx] = gradient(Ug, hx, hy);
    [dVdy, dVdx] = gradient(Vg, hx, hy);

    exx = dUdx;
    eyy = dVdy;
    gxy = dUdy + dVdx;
    evm = sqrt(exx.^2 - exx.*eyy + eyy.^2 + 3*(gxy/2).^2);

    switch lower(metric)
        case "exx", Z = exx;
        case "eyy", Z = eyy;
        case "gxy", Z = gxy;
        case "evm", Z = evm;
        otherwise,  Z = exx;
    end

    Z(~maskQ) = nan;
end
