function compareTires_MxSlip_GUI()
    % ======================================================================
    % 1) load .tir files
    % ======================================================================
    [file1,path1] = uigetfile('*.tir','Seleziona il primo file .tir'); if ~file1, return; end
    [file2,path2] = uigetfile('*.tir','Seleziona il secondo file .tir'); if ~file2, return; end
    tirFile1 = fullfile(path1,file1);
    tirFile2 = fullfile(path2,file2);

    % ======================================================================
    % 2) read .tir parameters
    % ======================================================================
    [~,name1,~] = fileparts(file1);
    [~,name2,~] = fileparts(file2);

    p1 = readTirParameters(tirFile1);
    p2 = readTirParameters(tirFile2);

    tireName1 = getParam(p1,'tireName',name1);
    tireName2 = getParam(p2,'tireName',name2);

    % slip angle vector
    alphaVec = deg2rad(linspace(-15,15,500));

    % ======================================================================
    % 3) create GUI
    % ======================================================================
    h.fig = figure('Name','Mx vs Slip Angle','NumberTitle','off','Position',[100 100 1000 600]);
    h.panel = uipanel('Parent',h.fig,'Title','Controlli','Units','normalized','Position',[0.75 0.05 0.24 0.9]);

    h.chk1 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
        'Position',[0.1 0.94 0.8 0.04],'String',tireName1,'Value',1);
    h.chk2 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
        'Position',[0.1 0.90 0.8 0.04],'String',tireName2,'Value',1);

    h.ax = axes('Parent',h.fig,'Units','normalized','Position',[0.07 0.11 0.65 0.80]);
    hold(h.ax,'on');
    createLegendSquares();
    createLegendLines();
    hold(h.ax,'off');

    h.edFz  = createLabeledEdit(h.panel,[0.1 0.84 0.35 0.05],'Fz [N]:','1000');
    h.edP   = createLabeledEdit(h.panel,[0.1 0.78 0.35 0.05],'Pressione [Pa]:',num2str(getParam(p1,'IP_NOM',1e5)));
    h.edCam = createLabeledEdit(h.panel,[0.1 0.72 0.35 0.05],'Camber [deg]:','0');

    h.btnUpdate = uicontrol('Parent',h.panel,'Style','pushbutton','Units','normalized', ...
        'Position',[0.1 0.14 0.35 0.06],'String','Aggiorna','FontWeight','bold','Callback',@updatePlot);
    h.btnHold   = uicontrol('Parent',h.panel,'Style','togglebutton','Units','normalized', ...
        'Position',[0.55 0.14 0.35 0.06],'String','Hold Off','Callback',@toggleHold);

    h.txt = uicontrol('Parent',h.panel,'Style','text','Units','normalized', ...
        'Position',[0.1 0.02 0.8 0.10],'FontSize',10,'HorizontalAlignment','left');

    h.holdOn = false;
    h.lines1 = gobjects(0);
    h.lines2 = gobjects(0);
    updatePlot();

    function toggleHold(src,~)
        h.holdOn = logical(src.Value);
        if h.holdOn
            src.String = 'Hold On';
        else
            src.String = 'Hold Off';
        end
    end

    function createLegendSquares()
        h.squareB = plot(h.ax,NaN,NaN,'s','LineStyle','none', ...
            'MarkerFaceColor','b','MarkerEdgeColor','b','Visible','off');
        h.squareG = plot(h.ax,NaN,NaN,'s','LineStyle','none', ...
            'MarkerFaceColor','g','MarkerEdgeColor','g','Visible','off');
        h.squareR = plot(h.ax,NaN,NaN,'s','LineStyle','none', ...
            'MarkerFaceColor','r','MarkerEdgeColor','r','Visible','off');
    end

    function createLegendLines()
        h.dummy1  = plot(h.ax,NaN,NaN,'k-','LineWidth',1.5,'Visible','off');
        h.dummy2  = plot(h.ax,NaN,NaN,'k--','LineWidth',1.5,'Visible','off');
    end

    function updatePlot(~,~)
        userFz  = str2double(h.edFz.String);
        userP   = str2double(h.edP.String);
        userCam = deg2rad(str2double(h.edCam.String));
        p1.userPressure = userP;
        p2.userPressure = userP;

        if ~h.holdOn
            delete([h.lines1 h.lines2 h.squareB h.squareG h.squareR h.dummy1 h.dummy2]);
            h.lines1 = gobjects(0);
            h.lines2 = gobjects(0);
            cla(h.ax);
            createLegendSquares();
            createLegendLines();
        end
        hold(h.ax,'on'); grid(h.ax,'on');

        if h.chk1.Value
            Mx1 = arrayfun(@(a) MF_PAC2002_Mx_simple(a,userFz,userCam,p1),alphaVec);
            h.lines1(end+1) = plot(h.ax,rad2deg(alphaVec),Mx1,'k-','LineWidth',1.5);
        end
        if h.chk2.Value
            Mx2 = arrayfun(@(a) MF_PAC2002_Mx_simple(a,userFz,userCam,p2),alphaVec);
            h.lines2(end+1) = plot(h.ax,rad2deg(alphaVec),Mx2,'k--','LineWidth',1.5);
        end

        xlabel(h.ax,'Slip Angle [deg]');
        ylabel(h.ax,'M_x [Nm]');

        legendHandles = [];
        legendEntries = {};
        if ~isempty(h.lines1)
            legendHandles(end+1) = h.dummy1;
            legendEntries{end+1} = tireName1;
        end
        if ~isempty(h.lines2)
            legendHandles(end+1) = h.dummy2;
            legendEntries{end+1} = tireName2;
        end
        legendHandles = [legendHandles h.squareB h.squareG h.squareR];
        legendEntries = [legendEntries {'TBC','TBC','TBC'}];
        if ~isempty(legendHandles)
            legend(h.ax,legendHandles,legendEntries,'Location','Best','Interpreter','none');
        else
            legend(h.ax,'off');
        end
        hold(h.ax,'off');
        h.txt.String = sprintf('Fz=%.0f N | P=%.0f Pa | Cam=%.1f°',userFz,userP,rad2deg(userCam));
    end
end

function hEdit = createLabeledEdit(parent,pos,label,initTag)
    uicontrol('Parent',parent,'Style','text','Units','normalized', ...
        'Position',pos,'String',label,'HorizontalAlignment','left');
    hEdit = uicontrol('Parent',parent,'Style','edit','Units','normalized', ...
        'Position',[pos(1)+pos(3) pos(2) pos(3) pos(4)],'String',initTag);
end

function params = readTirParameters(tirFilename)
    fid = fopen(tirFilename,'r'); if fid<0, error('Impossibile aprire il file: %s',tirFilename); end
    params = struct();
    while ~feof(fid)
        line = fgetl(fid);
        if ~ischar(line), break; end
        tokensNum = regexp(line,'^\s*(\S+)\s*=\s*([-+]?\d+(\.\d+)?([eE][+-]?\d+)?)','tokens');
        if ~isempty(tokensNum)
            name = tokensNum{1}{1}; val = str2double(tokensNum{1}{2}); if ~isnan(val), params.(name)=val; end
        end
        if contains(line,'% : COMMENT : Tire')
            t = regexp(line,'% : COMMENT : Tire\s+(.*)','tokens'); params.tireName = strtrim(t{1}{1});
        end
    end
    fclose(fid);
end

function val = getParam(s,field,def)
    if isfield(s,field), val = s.(field); else val = def; end
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

function Mx = MF_PAC2002_Mx_simple(alpha,Fz,gamma,p)
    Fz0_p = p.FNOMIN;
    R0 = getParam(p,'UNLOADED_RADIUS',0.3);
    qsx1 = getParam(p,'QSX1',0); qsx2 = getParam(p,'QSX2',0); qsx3 = getParam(p,'QSX3',0);
    lambdaMx = getParam(p,'LVMX',1);
    Fy = MF_PAC2002_Fy_pure(0,alpha,Fz,gamma,p);
    Mx = Fz * R0 * ((qsx1 - qsx2)*gamma + qsx3*Fy/Fz0_p) * lambdaMx;
end
