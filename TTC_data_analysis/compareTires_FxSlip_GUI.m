function compareTires_FxSlip_GUI()
%COMPARETIRES_FXSLIP_GUI Compare Fx vs longitudinal slip for two TIR files using PAC2002.
%   This GUI is a simplified version of COMPARETIRES_PAC2002_GUI focused on
%   plotting the longitudinal force Fx as a function of the slip ratio. The interface
%   remains similar and asks for two TIR files at startup. An additional
%   toggle button "HOLD" allows keeping previous curves when parameters are
%   updated.

%% 1) Load .tir files
[file1,path1] = uigetfile('*.tir','Seleziona il primo file .tir'); if isequal(file1,0), return; end
[file2,path2] = uigetfile('*.tir','Seleziona il secondo file .tir'); if isequal(file2,0), return; end

p1 = readTirParameters(fullfile(path1,file1));
p2 = readTirParameters(fullfile(path2,file2));
[~,name1] = fileparts(file1); tireName1 = getParam(p1,'tireName',name1);
[~,name2] = fileparts(file2); tireName2 = getParam(p2,'tireName',name2);

%% 2) Create GUI
h.fig = figure('Name','Fx vs Slip Ratio','NumberTitle','off','Position',[100 100 800 600]);
h.panel = uipanel('Parent',h.fig,'Title','Controlli','Units','normalized','Position',[0.7 0.05 0.28 0.9]);

% checkboxes to show/hide each tire
h.chk1 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
    'Position',[0.1 0.94 0.8 0.04],'String',tireName1,'Value',1);
h.chk2 = uicontrol('Parent',h.panel,'Style','checkbox','Units','normalized', ...
    'Position',[0.1 0.90 0.8 0.04],'String',tireName2,'Value',1);

% axis for plot
h.ax = axes('Parent',h.fig,'Units','normalized','Position',[0.08 0.15 0.58 0.75]);

% edit fields
h.edFz  = createLabeledEdit(h.panel,[0.1 0.84 0.35 0.05],'Fz [N]:','1000');
h.edP   = createLabeledEdit(h.panel,[0.1 0.78 0.35 0.05],'Pressione [Pa]:',num2str(getParam(p1,'IP_NOM',1e5)));
h.edCam = createLabeledEdit(h.panel,[0.1 0.72 0.35 0.05],'Camber [deg]:','0');
h.edK   = createLabeledEdit(h.panel,[0.1 0.66 0.35 0.05],'Slip Ratio \kappa:','0');

% buttons
h.btnHold    = uicontrol('Parent',h.panel,'Style','togglebutton','Units','normalized', ...
    'Position',[0.1 0.20 0.35 0.06],'String','HOLD');
    h.btnUpdate  = uicontrol('Parent',h.panel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.1 0.14 0.35 0.06],'String','Aggiorna','FontWeight','bold','Callback',@updatePlot);

% store line handles for plotting
h.line1 = gobjects(0); h.line2 = gobjects(0);

% status text
h.txt = uicontrol('Parent',h.panel,'Style','text','Units','normalized', ...
    'Position',[0.1 0.02 0.8 0.10],'FontSize',10,'HorizontalAlignment','left');

updatePlot();

    function updatePlot(~,~)
        userFz  = max(0,str2double(h.edFz.String));
        userP   = max(0,str2double(h.edP.String));
        userCam = str2double(h.edCam.String); gamma = deg2rad(userCam);
        p1.userPressure = userP; p2.userPressure = userP;

        kappaVec = linspace(-0.2,0.2,500);
        if ~get(h.btnHold,'Value')
            cla(h.ax);
            h.line1 = gobjects(0); h.line2 = gobjects(0);
        end
        axes(h.ax); hold on;
        default1 = [0 0 1];  % blue
        default2 = [1 0 0];  % red
        if h.chk1.Value
            Fx1 = arrayfun(@(k) MF_PAC2002_Fx_pure(k,0,userFz,gamma,p1),kappaVec);
            ln = plot(kappaVec,Fx1,'--','Color',default1,'LineWidth',1.5);
            h.line1(end+1) = ln;
        end
        if h.chk2.Value
            Fx2 = arrayfun(@(k) MF_PAC2002_Fx_pure(k,0,userFz,gamma,p2),kappaVec);
            ln = plot(kappaVec,Fx2,'-','Color',default2,'LineWidth',1.5);
            h.line2(end+1) = ln;
        end
        grid on; xlabel('Slip Ratio \kappa'); ylabel('F_x [N]');
        updateLegend();
        hold off;
        h.txt.String = sprintf('Fz=%.0f N | P=%.0f Pa | Cam=%.1f^o',userFz,userP,userCam);
    end

    function updateLegend()
        delete(findobj(h.ax,'Tag','legendDummy'));
        handles = [];
        entries = {};
        if h.chk1.Value && ~isempty(h.line1)
            handles(end+1) = plot(h.ax,nan,nan,'k--','LineWidth',1.5,'Tag','legendDummy'); %#ok<AGROW>
            entries{end+1} = tireName1; %#ok<AGROW>
        end
        if h.chk2.Value && ~isempty(h.line2)
            handles(end+1) = plot(h.ax,nan,nan,'k-','LineWidth',1.5,'Tag','legendDummy'); %#ok<AGROW>
            entries{end+1} = tireName2; %#ok<AGROW>
        end
        tbcColors = [0 0 1; 0 1 0; 1 0 0];
        for ii = 1:size(tbcColors,1)
            handles(end+1) = plot(h.ax,nan,nan,'s','MarkerFaceColor',tbcColors(ii,:), ...
                'MarkerEdgeColor',tbcColors(ii,:),'Tag','legendDummy'); %#ok<AGROW>
            entries{end+1} = 'TBC'; %#ok<AGROW>
        end
        if ~isempty(handles)
            lgd = legend(h.ax,handles,entries,'Location','Best','Interpreter','none');
            set(lgd,'TextColor','k');
        end
    end
end

%% ---------------------------------------------------------------------------
% Helper to create labeled edit boxes
function hEdit = createLabeledEdit(parent,pos,label,initTag)
    uicontrol('Parent',parent,'Style','text','Units','normalized', ...
        'Position',pos,'String',label,'HorizontalAlignment','left');
    hEdit = uicontrol('Parent',parent,'Style','edit','Units','normalized', ...
        'Position',[pos(1)+pos(3) pos(2) pos(3) pos(4)],'String',initTag);
end

%% ---------------------------------------------------------------------------
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

%% ---------------------------------------------------------------------------
% Return parameter value or default
function val = getParam(s,field,def)
    if isfield(s,field), val = s.(field); else, val = def; end
end

%% ---------------------------------------------------------------------------
% PAC2002 pure longitudinal slip formulation
function Fx = MF_PAC2002_Fx_pure(kappa,~,Fz,userGamma,p)
    Fz0 = p.FNOMIN;
    dfz = (Fz - Fz0)/Fz0;
    pi0 = getParam(p,'IP_NOM',2e5);
    pi  = getParam(p,'userPressure',pi0);
    dpi = (pi - pi0)/pi0;
    Cx1 = getParam(p,'PCX1',1); Dx1 = getParam(p,'PDX1',1); Dx2 = getParam(p,'PDX2',0);
    Dx3 = getParam(p,'PDX3',0); Ex1 = getParam(p,'PEX1',0); Ex2 = getParam(p,'PEX2',0);
    Ex3 = getParam(p,'PEX3',0); Ex4 = getParam(p,'PEX4',0); Kx1 = getParam(p,'PKX1',10);
    Kx2 = getParam(p,'PKX2',0); Kx3 = getParam(p,'PKX3',0); Hx1 = getParam(p,'PHX1',0);
    Hx2 = getParam(p,'PHX2',0); Vx1 = getParam(p,'PVX1',0); Vx2 = getParam(p,'PVX2',0);
    px1 = getParam(p,'PPX1',0); px2 = getParam(p,'PPX2',0); px3 = getParam(p,'PPX3',0);
    px4 = getParam(p,'PPX4',0);

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
    Fx  = Fx0 + SV;
end
