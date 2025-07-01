function compareTires_PAC2002_GUI()
    % ======================================================================
    % 1) caricamento file .tir
    % ======================================================================
    [file1,path1] = uigetfile('*.tir','Seleziona il primo file .tir'); if ~file1, return; end
    [file2,path2] = uigetfile('*.tir','Seleziona il secondo file .tir'); if ~file2, return; end
    tirFile1 = fullfile(path1,file1);
    tirFile2 = fullfile(path2,file2);

    % ======================================================================
    % 2) lettura parametri .tir
    % ======================================================================
    % Ricava i nomi dei file senza estensione come nome pneumatico
    [~,name1,~] = fileparts(file1);
    [~,name2,~] = fileparts(file2);

    p1 = readTirParameters(tirFile1);
    p2 = readTirParameters(tirFile2);

    % Se esiste nel file un campo 'tireName', usalo; altrimenti usa il nome file
    tireName1 = getParam(p1, 'tireName', name1);
    tireName2 = getParam(p2, 'tireName', name2);

    % ======================================================================
    % 3) vettori base
    % ======================================================================
    kappaVec = linspace(-1,1,500);
    alphaVec = deg2rad(linspace(-15,15,500));

    % labels Y dei grafici
    yLabels = {'F_x [N]','F_y [N]','M_z [Nm]'};
    % opzioni X: solo slip e Fz
    xOptions = {'Slip Angle','Longitudinal Slip','Fz'};

    % ======================================================================
    % 4) creazione GUI
    % ======================================================================
    h.fig = figure('Name','Confronto PAC2002','NumberTitle','off','Position',[100 100 1200 600]);
    h.panel = uipanel('Parent',h.fig,'Title','Controlli','Units','normalized', ...
                      'Position',[0.75 0.05 0.24 0.9]);
    % checkboxes per mostra/nascondi gomme
    h.chk1 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
        'Position',[0.1 0.94 0.8 0.04],'String',tireName1,'Value',1);
    h.chk2 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
        'Position',[0.1 0.90 0.8 0.04],'String',tireName2,'Value',1);
    % assi grafici
    h.ax(1) = axes('Parent',h.fig,'Units','normalized','Position',[0.05 0.73 0.65 0.23]);
    h.ax(2) = axes('Parent',h.fig,'Units','normalized','Position',[0.05 0.41 0.65 0.23]);
    h.ax(3) = axes('Parent',h.fig,'Units','normalized','Position',[0.05 0.09 0.65 0.23]);

    % campi edit
    h.edFz  = createLabeledEdit(h.panel,[0.1 0.84 0.35 0.05],'Fz [N]:','1000');
    h.edP   = createLabeledEdit(h.panel,[0.1 0.78 0.35 0.05],'Pressione [Pa]:',num2str(getParam(p1,'IP_NOM',1e5)));
    h.edCam = createLabeledEdit(h.panel,[0.1 0.72 0.35 0.05],'Camber [deg]:','0');
    h.edK   = createLabeledEdit(h.panel,[0.1 0.66 0.35 0.05],'Slip Ratio κ:','0');
    h.edA   = createLabeledEdit(h.panel,[0.1 0.60 0.35 0.05],'Slip Angle α [deg]:','0');

    % popup X-axis per ogni grafico
    for i=1:3
        yPos = 0.52 - 0.07*(i-1);
        uicontrol('Parent',h.panel,'Style','text','Units','normalized', ...
            'Position',[0.1 yPos+0.03 0.8 0.03], 'String',sprintf('Grafico %d X-axis:',i));
    
        % Imposta Longitudinal Slip (indice 2) solo per il primo grafico, altrimenti default (indice 1)
    defaultValue = 2 * (i == 1) + 1 * (i ~= 1);  % i==1 → 2, altrimenti 1    
        
        h.popup(i) = uicontrol('Parent',h.panel,'Style','popupmenu','Units','normalized', ...
            'Position',[0.1 yPos 0.8 0.04],'String',xOptions, 'Value', defaultValue);
    end

    % bottoni
    h.btnUpdate = uicontrol('Parent',h.panel,'Style','pushbutton','Units','normalized', ...
        'Position',[0.1 0.14 0.35 0.06],'String','Aggiorna','FontWeight','bold','Callback',@updatePlots);
    h.btnEllipse = uicontrol('Parent',h.panel,'Style','pushbutton','Units','normalized', ...
        'Position',[0.45 0.14 0.35 0.06],'String','Friction Ellipse','Callback',@showEllipse);

    % testo di stato
    h.txt = uicontrol('Parent',h.panel,'Style','text','Units','normalized', ...
        'Position',[0.1 0.02 0.8 0.10],'FontSize',10,'HorizontalAlignment','left');

    updatePlots();

    function updatePlots(~,~)
        userFz    = max(0,str2double(h.edFz.String));
        userP     = max(0,str2double(h.edP.String));
        userCam   = str2double(h.edCam.String); gamma = deg2rad(userCam);
        userKappa = str2double(h.edK.String);
        userAlpha = deg2rad(str2double(h.edA.String));
        p1.userPressure = userP;
        p2.userPressure = userP;
        for i=1:3
            sel = h.popup(i).Value;
            opt = xOptions{sel};
            outputType = yLabels{i};  % i = 1 → Fx, 2 → Fy, 3 → Mz
            [X1,Y1] = computeCurve(opt,userFz,gamma,userKappa,userAlpha,p1,outputType);
            [X2,Y2] = computeCurve(opt,userFz,gamma,userKappa,userAlpha,p2,outputType);

            axes(h.ax(i)); cla; hold on;
            if h.chk1.Value, plot(X1,Y1,'b-','LineWidth',1.5); 
            end
            if h.chk2.Value, plot(X2,Y2,'r-','LineWidth',1.5); 
            end
            grid on; xlabel(opt); ylabel(yLabels{i});
            legendEntries = {};
            if h.chk1.Value, legendEntries{end+1}=tireName1; 
            end
            if h.chk2.Value, legendEntries{end+1}=tireName2; 
            end
            if ~isempty(legendEntries), legend(legendEntries,'Location','Best','Interpreter','none'); end
            hold off;
        end
        h.txt.String = sprintf('Fz=%.0f N | P=%.0f Pa | Cam=%.1f° | κ=%.3f | α=%.1f°', ...
            userFz,userP,userCam,userKappa,rad2deg(userAlpha));
    end

    function showEllipse(~,~)   
    if ~h.chk1.Value && ~h.chk2.Value
        errordlg('Seleziona almeno una gomma!','Errore'); return;
    end

    userFz    = max(0,str2double(h.edFz.String));
    userP     = max(0,str2double(h.edP.String));
    userCam   = str2double(h.edCam.String); gamma = deg2rad(userCam);
    userKappa = str2double(h.edK.String);
    userAlpha = deg2rad(str2double(h.edA.String));

    kVec = linspace(-1,1,50);
    aVec = deg2rad(linspace(-15,15,50));

    % verifica coefficienti longitudinali e laterali validi
    hasLong1 = isfield(p1,'PDX1') && isfield(p1,'PCX1') && (p1.PDX1 ~= 0) && (p1.PCX1 ~= 0);
    hasLat1  = isfield(p1,'PDY1') && isfield(p1,'PCY1') && (p1.PDY1 ~= 0) && (p1.PCY1 ~= 0);
    hasLong2 = isfield(p2,'PDX1') && isfield(p2,'PCX1') && (p2.PDX1 ~= 0) && (p2.PCX1 ~= 0);
    hasLat2  = isfield(p2,'PDY1') && isfield(p2,'PCY1') && (p2.PDY1 ~= 0) && (p2.PCY1 ~= 0);


    % stampa messaggi nel Command Window
    if hasLong1
    fprintf('✅ Coefficienti longitudinali validi in: %s\n', tireName1);
    elseif isfield(p1,'PDX1') && isfield(p1,'PCX1')
    fprintf('⚠️ Coefficienti longitudinali nulli in: %s\n', tireName1);
    end

    if hasLat1
    fprintf('✅ Coefficienti laterali validi in: %s\n', tireName1);
    elseif isfield(p1,'PDY1') && isfield(p1,'PCY1')
    fprintf('⚠️ Coefficienti laterali nulli in: %s\n', tireName1);
    end

    if hasLong2
    fprintf('✅ Coefficienti longitudinali validi in: %s\n', tireName2);
    elseif isfield(p2,'PDX1') && isfield(p2,'PCX1')
    fprintf('⚠️ Coefficienti longitudinali nulli in: %s\n', tireName2);
    end

    if hasLat2
    fprintf('✅ Coefficienti laterali validi in: %s\n', tireName2);
    elseif isfield(p2,'PDY1') && isfield(p2,'PCY1')
    fprintf('⚠️ Coefficienti laterali nulli in: %s\n', tireName2);
    end


    % nuova figura e asse
    figE = figure('Name','Friction Ellipse','NumberTitle','off');
    axE = axes('Parent',figE); hold(axE,'on'); grid(axE,'on');
    hLine1 = []; hLine2 = [];

    % plottaggio per la gomma 1
    if h.chk1.Value
        p1.userPressure = userP;
        if hasLong1 && hasLat1
            for a = aVec
                Fx = arrayfun(@(k) MF_PAC2002_Fx_pure(k,0,userFz,a,p1),kVec);
                Fy = arrayfun(@(k) MF_PAC2002_Fy_pure(k,a,userFz,a,p1),kVec);
                hLine1(end+1) = plot(axE,Fx,Fy,'b-');
            end
            for k = kVec
                Fx = arrayfun(@(al) MF_PAC2002_Fx_pure(k,0,userFz,al,p1),aVec);
                Fy = arrayfun(@(al) MF_PAC2002_Fy_pure(k,al,userFz,al,p1),aVec);
                hLine1(end+1) = plot(axE,Fx,Fy,'b-');
            end
        else
            fprintf('⚠️ Coefficienti incompleti per %s: ellisse non tracciata.\n', tireName1);
        end
    end

    % plottaggio per la gomma 2
    if h.chk2.Value
        p2.userPressure = userP;
        if hasLong2 && hasLat2
            for a = aVec
                Fx = arrayfun(@(k) MF_PAC2002_Fx_pure(k,0,userFz,a,p2),kVec);
                Fy = arrayfun(@(k) MF_PAC2002_Fy_pure(k,a,userFz,a,p2),kVec);
                hLine2(end+1) = plot(axE,Fx,Fy,'r--');
            end
            for k = kVec
                Fx = arrayfun(@(al) MF_PAC2002_Fx_pure(k,0,userFz,al,p2),aVec);
                Fy = arrayfun(@(al) MF_PAC2002_Fy_pure(k,al,userFz,al,p2),aVec);
                hLine2(end+1) = plot(axE,Fx,Fy,'r--');
            end
        else
            fprintf('⚠️ Coefficienti incompleti per %s: ellisse non tracciata.\n', tireName2);
        end
    end

    xlabel(axE,'F_x [N]'); ylabel(axE,'F_y [N]');
    legendEntries = {};
    if h.chk1.Value && hasLong1 && hasLat1, legendEntries{end+1} = tireName1; end
    if h.chk2.Value && hasLong2 && hasLat2, legendEntries{end+1} = tireName2; end
    if ~isempty(legendEntries)
        legend(axE,legendEntries,'Location','Best','Interpreter','none');
    end

    % checkbox per show/hide
    if ~isempty(hLine1)
        uicontrol('Parent',figE,'Style','checkbox','String',tireName1, ...
            'Value',true,'Units','normalized','Position',[0.8 0.9 0.15 0.05], ...
            'Callback',@(src,~) set(hLine1,'Visible',src.Value*"on" + ~src.Value*"off"));
    end
    if ~isempty(hLine2)
        uicontrol('Parent',figE,'Style','checkbox','String',tireName2, ...
            'Value',true,'Units','normalized','Position',[0.8 0.84 0.15 0.05], ...
            'Callback',@(src,~) set(hLine2,'Visible',src.Value*"on" + ~src.Value*"off"));
    end

    hold(axE,'off');
    end
end

% helper compute curve generale
function [X,Y] = computeCurve(opt,Fz,gamma,kappa,alpha,p,outputType)
    switch opt
        case 'Slip Angle'
            X = linspace(-15,15,500);
            alphaVec = deg2rad(X);
            switch outputType
                case 'F_x [N]'
                    Y = arrayfun(@(a) MF_PAC2002_Fx_pure(0,0,Fz,gamma,p), alphaVec);  % opzionale
                case 'F_y [N]'
                    Y = arrayfun(@(a) MF_PAC2002_Fy_pure(0,a,Fz,gamma,p), alphaVec);
                case 'M_z [Nm]'
                    Y = arrayfun(@(a) MF_PAC2002_Mz_pure(0,a,Fz,gamma,p), alphaVec);
            end
        case 'Longitudinal Slip'
            X = linspace(-1,1,500);
            switch outputType
                case 'F_x [N]'
                    Y = arrayfun(@(k) MF_PAC2002_Fx_pure(k,0,Fz,gamma,p), X);
                case 'F_y [N]'
                    Y = arrayfun(@(k) MF_PAC2002_Fy_pure(k,0,Fz,gamma,p), X);
                case 'M_z [Nm]'
                    Y = arrayfun(@(k) MF_PAC2002_Mz_pure(k,0,Fz,gamma,p), X);
            end
        case 'Fz'
            X = linspace(0,3*p.FNOMIN,500);
            switch outputType
                case 'F_x [N]'
                    Y = arrayfun(@(fz) MF_PAC2002_Fx_pure(kappa,0,fz,gamma,p), X);
                case 'F_y [N]'
                    Y = arrayfun(@(fz) MF_PAC2002_Fy_pure(kappa,alpha,fz,gamma,p), X);
                case 'M_z [Nm]'
                    Y = arrayfun(@(fz) MF_PAC2002_Mz_pure(kappa,alpha,fz,gamma,p), X);
            end
        otherwise
            X = []; Y = [];
    end
end

% helper per edit box
function hEdit = createLabeledEdit(parent,pos,label,initTag)
    uicontrol('Parent',parent,'Style','text','Units','normalized', ...
        'Position',pos,'String',label,'HorizontalAlignment','left');
    hEdit = uicontrol('Parent',parent,'Style','edit','Units','normalized', ...
        'Position',[pos(1)+pos(3) pos(2) pos(3) pos(4)],'String',initTag);
end

% ============================================================================
% LETTURA PARAMETRI .tir
% ============================================================================
function params = readTirParameters(tirFilename)
    fid = fopen(tirFilename,'r'); if fid<0, error('Impossibile aprire il file: %s',tirFilename); end
    params = struct();
    while ~feof(fid)
        line = fgetl(fid); 
        if ~ischar(line), break; 
        end
        tokensNum = regexp(line,'^\s*(\S+)\s*=\s*([-+]?\d+(\.\d+)?([eE][+-]?\d+)?)','tokens');
        if ~isempty(tokensNum)
            name = tokensNum{1}{1}; val = str2double(tokensNum{1}{2}); if ~isnan(val), params.(name)=val; 
            end
        end
        if contains(line,'% : COMMENT : Tire')
            t = regexp(line,'% : COMMENT : Tire\s+(.*)','tokens'); params.tireName = strtrim(t{1}{1});
        end
    end
    fclose(fid);
end

% ============================================================================
% HELPER: restituisce parametro o default
% ============================================================================
function val = getParam(s,field,def)
    if isfield(s,field), val = s.(field); 
    else val = def; 
    end
end

% ============================================================================
% PURE SLIP PAC2002 FORMULATIONS
% ============================================================================
function Fx = MF_PAC2002_Fx_pure(kappa,~,Fz,userGamma,p)
    Fz0 = p.FNOMIN; 
    dfz = (Fz - Fz0)/Fz0;
    pi0 = getParam(p,'IP_NOM',2e5); 
    pi = getParam(p,'userPressure',pi0); 
    dpi = (pi - pi0)/pi0;
    Cx1 = getParam(p,'PCX1',1); Dx1 = getParam(p,'PDX1',1); Dx2 = getParam(p,'PDX2',0);
    Dx3 = getParam(p,'PDX3',0); Ex1 = getParam(p,'PEX1',0); Ex2 = getParam(p,'PEX2',0);
    Ex3 = getParam(p,'PEX3',0); Ex4 = getParam(p,'PEX4',0); Kx1 = getParam(p,'PKX1',10);
    Kx2 = getParam(p,'PKX2',0); Kx3 = getParam(p,'PKX3',0); Hx1 = getParam(p,'PHX1',0);
    Hx2 = getParam(p,'PHX2',0); Vx1 = getParam(p,'PVX1',0); Vx2 = getParam(p,'PVX2',0);
    px1 = getParam(p,'PPX1',0); px2 = getParam(p,'PPX2',0); px3 = getParam(p,'PPX3',0);
    px4 = getParam(p,'PPX4',0);
    
%formule per il calcolo
    mu = (Dx1 + Dx2*dfz)*(1 - Dx3*(userGamma^2))*(1 + px3*dpi + px4*dpi^2);
    D = mu * Fz; 
    C = Cx1; 
    K = Fz * (Kx1 + Kx2*dfz) * exp(Kx3*dfz) * (1 + px1*dpi + px2*dpi^2);
    B = K/(C*D + eps); 
    SH = Hx1 + Hx2*dfz;
    k = kappa + SH;
    E = (Ex1 + Ex2*dfz + Ex3*dfz^2) * (1 - Ex4*sign(k)); 
    SV = Fz * (Vx1 + Vx2*dfz);  
    Fx0 = D*sin(C*atan(B*k - E*(B*k - atan(B*k)))); 
    Fx = Fx0 + SV;
end

function Fy = MF_PAC2002_Fy_pure(~,alpha,Fz,userGamma,p)
    Fz0 = p.FNOMIN; 
    dfz = (Fz - Fz0)/Fz0;
    pi0 = getParam(p,'IP_NOM',2e5); 
    pi = getParam(p,'userPressure',pi0); 
    dpi = (pi - pi0)/pi0;
    Cy1 = getParam(p,'PCY1',1.1); Dy1 = getParam(p,'PDY1',1); Dy2 = getParam(p,'PDY2',0);
    Dy3 = getParam(p,'PDY3',0); Ey1 = getParam(p,'PEY1',0); Ey2 = getParam(p,'PEY2',0);
    Ey3 = getParam(p,'PEY3',0); Ey4 = getParam(p,'PEY4',0); Ky1 = getParam(p,'PKY1',20);
    Ky2 = getParam(p,'PKY2',0); Ky3 = getParam(p,'PKY3',0); Hy1 = getParam(p,'PHY1',0);
    Hy2 = getParam(p,'PHY2',0); Hy3 = getParam(p,'PHY3',0); Vy1 = getParam(p,'PVY1',0); 
    Vy2 = getParam(p,'PVY2',0); Vy3 = getParam(p,'PVY3',0); Vy4 = getParam(p,'PVY4',0); 
    py1 = getParam(p,'PPY1',0); py2 = getParam(p,'PPY2',0); py3 = getParam(p,'PPY3',0); py4 = getParam(p,'PPY4',0);

    %formule per il calcolo
    mu = (Dy1 + Dy2*dfz) * (1 + py3*dpi + py4*dpi^2)*(1 - Dy3*userGamma^2);
    D = mu * Fz;
    C = Cy1; 
    Ky0 = Ky1 * Fz0*(1 + py1*dpi)*sin(2*atan(Fz/(Ky2*Fz0*(1 + py2*dpi))));
    K = Ky0 * (1 - Ky3 * abs(userGamma)); 
    B = K/(C*D + eps);
    SH = (Hy1 + Hy2*dfz) + Hy3 * userGamma;
    a = alpha + SH;
    E = (Ey1 + Ey2*dfz) * (1 - (Ey3 + Ey4*userGamma)*sign(a)); 
    SV = Fz * (Vy1 + Vy2*dfz + (Vy3 + Vy4*dfz)*userGamma); 
    Fy0 = D*sin(C*atan(B*a - E*(B*a - atan(B*a)))); 
    Fy = Fy0 + SV;
end

function Mz = MF_PAC2002_Mz_pure(~,alpha,Fz,userGamma,p)
    Fz0 = p.FNOMIN; 
    dfz = (Fz - Fz0)/Fz0;
    pi0 = getParam(p,'IP_NOM',2e5);
    pi = getParam(p,'userPressure',pi0);
    dpi = (pi - pi0)/pi0;
    Bz1 = getParam(p,'QBZ1',0.1); Bz2 = getParam(p,'QBZ2',0); Bz3 = getParam(p,'QBZ3',0); 
    Bz4 = getParam(p,'QBZ4',0); Bz5 = getParam(p,'QBZ5',0); Cz1 = getParam(p,'QCZ1',1); 
    Dz1 = getParam(p,'QDZ1',0.1); Dz2 = getParam(p,'QDZ2',0); Dz3 = getParam(p,'QDZ3',0);
    Dz4 = getParam(p,'QDZ4',0); Ez1 = getParam(p,'QEZ1',0.1); Ez2 = getParam(p,'QEZ2',0); 
    Ez3 = getParam(p,'QEZ3',0); Ez4 = getParam(p,'QEZ4',0); Ez5 = getParam(p,'QEZ5',0);
    Hz1 = getParam(p,'QHZ1',0.1); Hz2 = getParam(p,'QHZ2',0); Hz3 = getParam(p,'QHZ3',0);
    Hz4 = getParam(p,'QHZ4',0); R0 = getParam(p,'UNLOADED_RADIUS',0.3); pz1 = getParam(p,'QPZ1',0);

    %formule per il calcolo
    D = Fz * (Dz1 + Dz2*dfz)*(1 - pz1*dpi)*(1 + Dz3*userGamma + Dz4*userGamma^2) * R0/ Fz0; 
    C = Cz1;
    SH = Hz1 + Hz2*dfz + (Hz3 + Hz4*dfz)*userGamma;
    a = alpha + SH;
    B = (Bz1 + Bz2*dfz + Bz3*dfz^2) * (1 + Bz4*userGamma + Bz5*abs(userGamma));
    E = (Ez1 + Ez2*dfz + Ez3*dfz^2)*(1 + (Ez4 + Ez5*userGamma)*((2/pi)*atan(B*C*a)));
    trail = D * cos(C*atan(B*a - E*(B*a - atan(B*a))))*cos(alpha); 
    Fy0 = MF_PAC2002_Fy_pure(0,alpha,Fz,userGamma,p);
    Mz = -trail * Fy0;
end 