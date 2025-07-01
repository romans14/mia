function runInteractiveTireCurves
% runInteractiveTireCurves  Interactive TTC visualization with real-time filters and separate-window fit
clear; clc;

% --- 1) Select TTC run file ---
[filename, pathname] = uigetfile('*.mat','Select a TTC run .mat file');
if isequal(filename,0)
    disp('Selection cancelled.'); return;
end
fullpath = fullfile(pathname, filename);

% --- 2) Load data ---
data = load(fullpath,'AMBTMP', 'ET', 'MX', 'N', 'NFX', 'NFY', 'RE', 'RL', 'RST', 'RUN', 'SA', 'SL', 'SR','FZ','FX','FY','MZ','P','IA','TSTI','TSTC','TSTO', 'V');
TSTmed = (data.TSTI + data.TSTC + data.TSTO)/3;

% --- 3) Define axis options and ranges ---
% Dynamically get all data fields except the 'range' variables:
allFields = fieldnames(data);
exclude   = {'FZ','P','IA'};                                 % Fields to exclude from X axis options
xOptions  = setdiff(allFields, exclude, 'stable');         % Available X axis variables
xLabels   = xOptions;    % Labels for X popup (modify for prettier text if desired)

% Y axis options, dynamically get all data fields except the 'range' variables:
allFields = fieldnames(data);
exclude   = {'FZ','P','IA'};
yOptions  = setdiff(allFields, exclude, 'stable');
yLabels   = yOptions;

% Preserve original ranges for FZ, P, IA sliders
range.FZ  = [min(data.FZ), max(data.FZ)];
range.P   = [min(data.P),  max(data.P)];
range.IA  = [min(data.IA), max(data.IA)];

% --- 4) Create main GUI ---
hFig = figure('Name','Interactive Tire Curves','NumberTitle','off','Position',[200 200 800 600]);
hAx  = axes('Parent',hFig,'Position',[0.07 0.05 0.60 0.90]);

% --- 5) Layout controls on right ---
x0 = 0.70; ctrlW = 0.25; ctrlH = 0.04; yStart = 0.90; yStep = 0.05;
% X axis
uicontrol('Style','text','Parent',hFig,'Units','normalized','Position',[x0 yStart ctrlW ctrlH],...
    'String','X Axis:','HorizontalAlignment','left');
hPopupX = uicontrol('Style','popupmenu','Parent',hFig,'Units','normalized','Position',[x0 yStart-yStep ctrlW ctrlH],...
    'String',xLabels,'Value',1,'Callback',@updatePlot);
% Y axis
uicontrol('Style','text','Parent',hFig,'Units','normalized','Position',[x0 yStart-2*yStep ctrlW ctrlH],...
    'String','Y Axis:','HorizontalAlignment','left');
hPopupY = uicontrol('Style','popupmenu','Parent',hFig,'Units','normalized','Position',[x0 yStart-3*yStep ctrlW ctrlH],...
    'String',yLabels,'Value',1,'Callback',@updatePlot);
% FZ sliders
uicontrol('Style','text','Parent',hFig,'Units','normalized','Position',[x0 yStart-4*yStep ctrlW ctrlH],...
    'String','FZ min/max:','HorizontalAlignment','left');
hFZmin = uicontrol('Style','slider','Parent',hFig,'Units','normalized','Position',[x0 yStart-5*yStep ctrlW ctrlH],...
    'Min',range.FZ(1),'Max',range.FZ(2),'Value',range.FZ(1),'Callback',@updatePlot);
hFZmax = uicontrol('Style','slider','Parent',hFig,'Units','normalized','Position',[x0 yStart-6*yStep ctrlW ctrlH],...
    'Min',range.FZ(1),'Max',range.FZ(2),'Value',range.FZ(2),'Callback',@updatePlot);
% P sliders
uicontrol('Style','text','Parent',hFig,'Units','normalized','Position',[x0 yStart-7*yStep ctrlW ctrlH],...
    'String','P min/max:','HorizontalAlignment','left');
hPmin = uicontrol('Style','slider','Parent',hFig,'Units','normalized','Position',[x0 yStart-8*yStep ctrlW ctrlH],...
    'Min',range.P(1),'Max',range.P(2),'Value',range.P(1),'Callback',@updatePlot);
hPmax = uicontrol('Style','slider','Parent',hFig,'Units','normalized','Position',[x0 yStart-9*yStep ctrlW ctrlH],...
    'Min',range.P(1),'Max',range.P(2),'Value',range.P(2),'Callback',@updatePlot);
% IA sliders
uicontrol('Style','text','Parent',hFig,'Units','normalized','Position',[x0 yStart-10*yStep ctrlW ctrlH],...
    'String','IA min/max:','HorizontalAlignment','left');
hImin = uicontrol('Style','slider','Parent',hFig,'Units','normalized','Position',[x0 yStart-11*yStep ctrlW ctrlH],...
    'Min',range.IA(1),'Max',range.IA(2),'Value',range.IA(1),'Callback',@updatePlot);
hImax = uicontrol('Style','slider','Parent',hFig,'Units','normalized','Position',[x0 yStart-12*yStep ctrlW ctrlH],...
    'Min',range.IA(1),'Max',range.IA(2),'Value',range.IA(2),'Callback',@updatePlot);
% Fit button
uicontrol('Style','pushbutton','Parent',hFig,'Units','normalized','Position',[x0 yStart-13*yStep ctrlW ctrlH],...
    'String','Fit PAC2002','Callback',@doFit);

% --- 6) Initial plot ---
updatePlot();

% --- Nested function: updatePlot ---
function updatePlot(~,~)
    selX = get(hPopupX,'Value'); selY = get(hPopupY,'Value');
    xVar = xOptions{selX}; xLabel = xLabels{selX};
    yVar = yOptions{selY}; yLabel = yLabels{selY};
    if strcmp(xVar,'FZ')
        set(hFZmin,'Enable','off'); set(hFZmax,'Enable','off'); fzMin=range.FZ(1); fzMax=range.FZ(2);
    else
        set(hFZmin,'Enable','on'); set(hFZmax,'Enable','on'); fzMin=get(hFZmin,'Value'); fzMax=get(hFZmax,'Value');
    end
    pMin=get(hPmin,'Value'); pMax=get(hPmax,'Value'); iaMin=get(hImin,'Value'); iaMax=get(hImax,'Value');
    if pMin>pMax, tmp=pMin; pMin=pMax; pMax=tmp; end
    if iaMin>iaMax, tmp=iaMin; iaMin=iaMax; iaMax=tmp; end
    X = data.(xVar); Y = data.(yVar);
    mask = (data.FZ>=fzMin & data.FZ<=fzMax) & (data.P>=pMin & data.P<=pMax) & (data.IA>=iaMin & data.IA<=iaMax);
    xF = X(mask); yF = Y(mask); Tcol = TSTmed(mask);
    [xF, idx] = sort(xF); yF = yF(idx); Tcol = Tcol(idx);
    cla(hAx);
    scatter(hAx, xF, yF, 36, Tcol, 'filled'); colormap(hAx,'jet'); colorbar(hAx);
    xlabel(hAx, xLabel,'Interpreter','none'); ylabel(hAx, yLabel,'Interpreter','none');
    title(hAx, sprintf('%s vs %s',yLabel,xLabel),'Interpreter','none'); grid(hAx,'on');
end

% --- Nested function: doFit ---
function doFit(~,~)
    selX = get(hPopupX,'Value'); selY = get(hPopupY,'Value');
    xVar = xOptions{selX}; yVar = yOptions{selY};
    X = data.(xVar); Y = data.(yVar);
    fzMin = get(hFZmin,'Value'); fzMax = get(hFZmax,'Value');
    pMin  = get(hPmin,'Value');  pMax  = get(hPmax,'Value');
    iaMin = get(hImin,'Value');  iaMax = get(hImax,'Value');
    mask   = (data.FZ>=fzMin & data.FZ<=fzMax) & (data.P>=pMin & data.P<=pMax) & (data.IA>=iaMin & data.IA<=iaMax);
    xF    = X(mask); yF    = Y(mask);
    [xF, idx] = sort(xF); yF = yF(idx);
    % PAC2002 fit
    mfFun = @(p,x) p(3).*sin(p(2).*atan(p(1).*x - p(4).*(p(1).*x - atan(p(1).*x))));
    p0 = [10,1.9,max(yF),0.97]; lb=[0,0,0,-10]; ub=[Inf,Inf,Inf,10];
    opts = optimoptions('lsqcurvefit','Display','off');
    xFine = linspace(min(xF),max(xF),200);
    pOpt  = lsqcurvefit(mfFun,p0,xF,yF,lb,ub,opts);
    yFit  = mfFun(pOpt,xFine);
    figure('Name','PAC2002 Fit','NumberTitle','off','Color','w');
    plot(xFine,yFit,'k-','LineWidth',2); grid on;
    xlabel(xLabels{selX},'Interpreter','none'); ylabel(yLabels{selY},'Interpreter','none');
    title(sprintf('PAC2002 fit of %s vs %s',yLabels{selY},xLabels{selX}),'FontSize',14);
end
end
