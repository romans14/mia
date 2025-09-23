function compareTires_FyCamber_GUI()
    % ======================================================================
    % 1) Load .tir files
    % ======================================================================
    [file1,path1] = uigetfile('*.tir','Seleziona il primo file .tir');
    if ~file1, return; end
    [file2,path2] = uigetfile('*.tir','Seleziona il secondo file .tir');
    if ~file2, return; end
    tirFile1 = fullfile(path1,file1);
    tirFile2 = fullfile(path2,file2);

    % ======================================================================
    % 2) read parameters
    % ======================================================================
    [~,name1,~] = fileparts(file1);
    [~,name2,~] = fileparts(file2);
    p1 = readTirParameters(tirFile1);
    p2 = readTirParameters(tirFile2);
    tireName1 = getParam(p1,'tireName',name1);
    tireName2 = getParam(p2,'tireName',name2);

    % vectors
    camberDeg = -4:0.5:4;
    defaultAlphaMax = 15;  % [deg]

    % ======================================================================
    % 3) GUI creation
    % ======================================================================
    h.fig = figure('Name','Fy max vs Camber','NumberTitle','off', ...
                   'Position',[100 100 1000 500]);
    h.ax = axes('Parent',h.fig,'Units','normalized', ...
                'Position',[0.07 0.15 0.6 0.75]);
    h.panel = uipanel('Parent',h.fig,'Title','Controlli','Units','normalized', ...
                      'Position',[0.72 0.05 0.26 0.9]);
    h.chk1 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
                       'Position',[0.1 0.92 0.8 0.05],'String',tireName1,'Value',1);
    h.chk2 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
                       'Position',[0.1 0.86 0.8 0.05],'String',tireName2,'Value',1);
    h.edFz = createLabeledEdit(h.panel,[0.1 0.76 0.4 0.06],'Fz [N]:','1000');
    h.edP  = createLabeledEdit(h.panel,[0.1 0.66 0.4 0.06],'Pressione [Pa]:', ...
                               num2str(getParam(p1,'IP_NOM',1e5)));
    h.edAlpha = createLabeledEdit(h.panel,[0.1 0.56 0.4 0.06], ...
        'Slip Angle ± [deg]:',num2str(defaultAlphaMax));
    h.btnUpdate = uicontrol('Parent',h.panel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.1 0.15 0.35 0.08],'String','Aggiorna', ...
                'FontWeight','bold','Callback',@updatePlot);
    h.btnHold = uicontrol('Parent',h.panel,'Style','togglebutton','Units','normalized', ...
                'Position',[0.55 0.15 0.35 0.08],'String','HOLD','Callback',@toggleHold);
    h.txt = uicontrol('Parent',h.panel,'Style','text','Units','normalized', ...
                'Position',[0.1 0.03 0.8 0.1],'HorizontalAlignment','left');

    holdState = false;

    updatePlot();

    function toggleHold(src,~)
        holdState = logical(src.Value);
    end

    function updatePlot(~,~)
        if ~holdState
            cla(h.ax);
        end
        userFz = max(0,str2double(h.edFz.String));
        userP  = max(0,str2double(h.edP.String));
        p1.userPressure = userP; p2.userPressure = userP;
        userAlphaMax = str2double(h.edAlpha.String);
        if isnan(userAlphaMax)
            userAlphaMax = defaultAlphaMax;
            h.edAlpha.String = num2str(defaultAlphaMax);
        end
        userAlphaMax = abs(userAlphaMax);
        alphaVec = deg2rad(linspace(-userAlphaMax,userAlphaMax,400));
        gammaVec = deg2rad(camberDeg);
        Fy1 = zeros(size(gammaVec));
        Fy2 = zeros(size(gammaVec));
        for ii = 1:length(gammaVec)
            g = gammaVec(ii);
            if h.chk1.Value
                Fy = arrayfun(@(a) MF_PAC2002_Fy_pure(0,a,userFz,g,p1),alphaVec);
                Fy1(ii) = max(abs(Fy));
            end
            if h.chk2.Value
                Fy = arrayfun(@(a) MF_PAC2002_Fy_pure(0,a,userFz,g,p2),alphaVec);
                Fy2(ii) = max(abs(Fy));
            end
        end
        axes(h.ax); hold on;
        if h.chk1.Value
            plot(h.ax,camberDeg,Fy1,'b-','LineWidth',1.5,'DisplayName',tireName1);
        end
        if h.chk2.Value
            plot(h.ax,camberDeg,Fy2,'r--','LineWidth',1.5,'DisplayName',tireName2);
        end
        grid(h.ax,'on');
        xlabel(h.ax,'Camber [deg]');
        ylabel(h.ax,'|F_y|_{max} [N]');
        legend(h.ax,'-DynamicLegend','Location','best','Interpreter','none');
        h.txt.String = sprintf('Fz=%.0f N | P=%.0f Pa | |α|≤%.1f°', ...
                               userFz,userP,userAlphaMax);
        if ~holdState
            hold(h.ax,'off');
        end
    end
end

% ============================================================================
% helper for edit boxes
% ============================================================================
function hEdit = createLabeledEdit(parent,pos,label,initTag)
    uicontrol('Parent',parent,'Style','text','Units','normalized', ...
        'Position',pos,'String',label,'HorizontalAlignment','left');
    hEdit = uicontrol('Parent',parent,'Style','edit','Units','normalized', ...
        'Position',[pos(1)+pos(3) pos(2) pos(3) pos(4)],'String',initTag);
end

% ============================================================================
% read .tir parameters
% ============================================================================
function params = readTirParameters(tirFilename)
    fid = fopen(tirFilename,'r');
    if fid < 0
        error('Impossibile aprire il file: %s',tirFilename);
    end
    params = struct();
    while ~feof(fid)
        line = fgetl(fid);
        if ~ischar(line), break; end
        tokensNum = regexp(line,'^\s*(\S+)\s*=\s*([-+]?\d+(\.\d+)?([eE][+-]?\d+)?)','tokens');
        if ~isempty(tokensNum)
            name = tokensNum{1}{1};
            val = str2double(tokensNum{1}{2});
            if ~isnan(val), params.(name) = val; end
        end
        if contains(line,'% : COMMENT : Tire')
            t = regexp(line,'% : COMMENT : Tire\s+(.*)','tokens');
            params.tireName = strtrim(t{1}{1});
        end
    end
    fclose(fid);
end

% ============================================================================
% helper: return field value or default
% ============================================================================
function val = getParam(s,field,def)
    if isfield(s,field)
        val = s.(field);
    else
        val = def;
    end
end

% ============================================================================
% PAC2002 pure slip Fy formulation
% ============================================================================
function Fy = MF_PAC2002_Fy_pure(~,alpha,Fz,gamma,p)
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
    py1 = getParam(p,'PPY1',0); py2 = getParam(p,'PPY2',0); py3 = getParam(p,'PPY3',0);
    py4 = getParam(p,'PPY4',0);

    mu = (Dy1 + Dy2*dfz) * (1 + py3*dpi + py4*dpi^2) * (1 - Dy3*gamma^2);
    D = mu * Fz;
    C = Cy1;
    Ky0 = Ky1 * Fz0 * (1 + py1*dpi) * sin(2*atan(Fz/(Ky2*Fz0*(1 + py2*dpi))));
    K = Ky0 * (1 - Ky3*abs(gamma));
    B = K/(C*D + eps);
    SH = (Hy1 + Hy2*dfz) + Hy3*gamma;
    a = alpha + SH;
    E = (Ey1 + Ey2*dfz) * (1 - (Ey3 + Ey4*gamma)*sign(a));
    SV = Fz * (Vy1 + Vy2*dfz + (Vy3 + Vy4*dfz)*gamma);
    Fy0 = D * sin(C*atan(B*a - E*(B*a - atan(B*a))));
    Fy = Fy0 + SV;
end
