function compareTires_MzSlip_GUI()
%COMPARETIRES_MZSLIP_GUI Plot self aligning moment Mz vs slip angle for two TIR files.
%   This GUI allows selecting two tire files and compares the aligning
%   moment as computed with the PAC2002 formula. A HOLD toggle button
%   keeps previous curves when parameters are updated.

%% Load TIR files
[file1,path1] = uigetfile('*.tir','Seleziona il primo file .tir'); if isequal(file1,0), return; end
[file2,path2] = uigetfile('*.tir','Seleziona il secondo file .tir'); if isequal(file2,0), return; end
p1 = readTirParameters(fullfile(path1,file1));
p2 = readTirParameters(fullfile(path2,file2));
[~,name1] = fileparts(file1); tireName1 = getParam(p1,'tireName',name1);
[~,name2] = fileparts(file2); tireName2 = getParam(p2,'tireName',name2);

alphaDeg = linspace(-15,15,500);             % slip angle range
alphaRad = deg2rad(alphaDeg);

%% Create GUI
h.fig = figure('Name','Mz vs Slip Angle','NumberTitle','off','Position',[100 100 800 600]);
h.panel = uipanel('Parent',h.fig,'Title','Controlli','Units','normalized','Position',[0.7 0.05 0.28 0.9]);

h.chk1 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
    'Position',[0.1 0.94 0.8 0.04],'String',tireName1,'Value',1);
h.chk2 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
    'Position',[0.1 0.90 0.8 0.04],'String',tireName2,'Value',1);

h.ax = axes('Parent',h.fig,'Units','normalized','Position',[0.08 0.15 0.58 0.75]);

h.edFz  = createLabeledEdit(h.panel,[0.1 0.84 0.35 0.05],'Fz [N]:','1000');
h.edP   = createLabeledEdit(h.panel,[0.1 0.78 0.35 0.05],'Pressione [Pa]:',num2str(getParam(p1,'IP_NOM',1e5)));
h.edCam = createLabeledEdit(h.panel,[0.1 0.72 0.35 0.05],'Camber [deg]:','0');

h.btnHold   = uicontrol('Parent',h.panel,'Style','togglebutton','Units','normalized', ...
    'Position',[0.1 0.20 0.35 0.06],'String','HOLD');
h.btnUpdate = uicontrol('Parent',h.panel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.1 0.14 0.35 0.06],'String','Aggiorna','FontWeight','bold','Callback',@updatePlot);

h.line1 = gobjects(0); h.line2 = gobjects(0);

h.txt = uicontrol('Parent',h.panel,'Style','text','Units','normalized', ...
    'Position',[0.1 0.02 0.8 0.10],'FontSize',10,'HorizontalAlignment','left');

updatePlot();

    function updatePlot(~,~)
        userFz  = max(0,str2double(h.edFz.String));
        userP   = max(0,str2double(h.edP.String));
        userCam = str2double(h.edCam.String); gamma = deg2rad(userCam);
        p1.userPressure = userP; p2.userPressure = userP;
        if ~get(h.btnHold,'Value')
            cla(h.ax);
            h.line1 = gobjects(0); h.line2 = gobjects(0);
        end
        axes(h.ax); hold on;
        if h.chk1.Value
            Mz1 = arrayfun(@(a) MF_PAC2002_Mz_pure(0,a,userFz,gamma,p1),alphaRad);
            ln = plot(alphaDeg,Mz1,'b--','LineWidth',1.5);
            h.line1(end+1) = ln;
        end
        if h.chk2.Value
            Mz2 = arrayfun(@(a) MF_PAC2002_Mz_pure(0,a,userFz,gamma,p2),alphaRad);
            ln = plot(alphaDeg,Mz2,'r-','LineWidth',1.5);
            h.line2(end+1) = ln;
        end
        grid on; xlabel('Slip Angle [deg]'); ylabel('M_z [Nm]');
        updateLegend();
        hold off;
        h.txt.String = sprintf('Fz=%.0f N | P=%.0f Pa | Cam=%.1f^o',userFz,userP,userCam);
    end

    function updateLegend()
        delete(findobj(h.ax,'Tag','legendDummy'));
        handles = [];
        entries = {};
        if h.chk1.Value && ~isempty(h.line1)
            handles(end+1) = plot(h.ax,nan,nan,'b--','LineWidth',1.5,'Tag','legendDummy');
            entries{end+1} = tireName1;
        end
        if h.chk2.Value && ~isempty(h.line2)
            handles(end+1) = plot(h.ax,nan,nan,'r-','LineWidth',1.5,'Tag','legendDummy');
            entries{end+1} = tireName2;
        end
        if ~isempty(handles)
            legend(h.ax,handles,entries,'Location','Best','Interpreter','none');
        else
            legend(h.ax,'off');
        end
    end
end

%% -----------------------------------------------------------------------------
% Helper to create labeled edit boxes
function hEdit = createLabeledEdit(parent,pos,label,initTag)
    uicontrol('Parent',parent,'Style','text','Units','normalized', ...
        'Position',pos,'String',label,'HorizontalAlignment','left');
    hEdit = uicontrol('Parent',parent,'Style','edit','Units','normalized', ...
        'Position',[pos(1)+pos(3) pos(2) pos(3) pos(4)],'String',initTag);
end

%% -----------------------------------------------------------------------------
% Read parameters from a .tir file
function params = readTirParameters(tirFilename)
    fid = fopen(tirFilename,'r');
    if fid < 0, error('Impossibile aprire il file: %s',tirFilename); end
    params = struct();
    while ~feof(fid)
        line = fgetl(fid);
        if ~ischar(line), break; end
        tokensNum = regexp(line,'^\s*(\S+)\s*=\s*([-+]?\d+(\.\d+)?([eE][+-]?\d+)?)','tokens');
        if ~isempty(tokensNum)
            name = tokensNum{1}{1};
            val  = str2double(tokensNum{1}{2});
            if ~isnan(val), params.(name) = val; end
        end
        if contains(line,'% : COMMENT : Tire')
            t = regexp(line,'% : COMMENT : Tire\s+(.*)','tokens');
            params.tireName = strtrim(t{1}{1});
        end
    end
    fclose(fid);
end

%% -----------------------------------------------------------------------------
% Return parameter value or default
function val = getParam(s,field,def)
    if isfield(s,field), val = s.(field); else, val = def; end
end

%% -----------------------------------------------------------------------------
% PAC2002 pure lateral force formulation
function Fy = MF_PAC2002_Fy_pure(~,alpha,Fz,userGamma,p)
    Fz0 = p.FNOMIN;
    dfz = (Fz - Fz0)/Fz0;
    pi0 = getParam(p,'IP_NOM',2e5);
    pi  = getParam(p,'userPressure',pi0);
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
    Fy  = Fy0 + SV;
end

%% -----------------------------------------------------------------------------
% PAC2002 pure aligning moment formulation
function Mz = MF_PAC2002_Mz_pure(~,alpha,Fz,userGamma,p)
    Fz0 = p.FNOMIN;
    dfz = (Fz - Fz0)/Fz0;
    pi0 = getParam(p,'IP_NOM',2e5);
    pi  = getParam(p,'userPressure',pi0);
    dpi = (pi - pi0)/pi0;
    Bz1 = getParam(p,'QBZ1',0.1); Bz2 = getParam(p,'QBZ2',0); Bz3 = getParam(p,'QBZ3',0);
    Bz4 = getParam(p,'QBZ4',0); Bz5 = getParam(p,'QBZ5',0); Cz1 = getParam(p,'QCZ1',1);
    Dz1 = getParam(p,'QDZ1',0.1); Dz2 = getParam(p,'QDZ2',0); Dz3 = getParam(p,'QDZ3',0);
    Dz4 = getParam(p,'QDZ4',0); Ez1 = getParam(p,'QEZ1',0.1); Ez2 = getParam(p,'QEZ2',0);
    Ez3 = getParam(p,'QEZ3',0); Ez4 = getParam(p,'QEZ4',0); Ez5 = getParam(p,'QEZ5',0);
    Hz1 = getParam(p,'QHZ1',0.1); Hz2 = getParam(p,'QHZ2',0); Hz3 = getParam(p,'QHZ3',0);
    Hz4 = getParam(p,'QHZ4',0); R0 = getParam(p,'UNLOADED_RADIUS',0.3); pz1 = getParam(p,'QPZ1',0);
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
