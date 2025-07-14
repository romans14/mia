function runInteractiveTireCurves
% runInteractiveTireCurves  Interactive TTC visualization with real-time filters
% and separate-window fit. This version allows two MAT files to be loaded and
% visualised simultaneously.

clear; clc;

% --- 1) Select TTC run files ---
[files, pathname] = uigetfile('*.mat','Select two TTC run .mat files', ...
    'MultiSelect','on');
if isequal(files,0)
    disp('Selection cancelled.');
    return;
end
if ischar(files)
    files = {files};
end
if numel(files) < 2
    error('Please select two MAT files.');
end
fullpaths = fullfile(pathname, files);

% --- 2) Load data ---
data1 = load(fullpaths{1}, 'AMBTMP', 'ET', 'MX', 'N', 'NFX', 'NFY', 'RE', 'RL', ...
    'RST', 'RUN', 'SA', 'SL', 'SR','FZ','FX','FY','MZ','P','IA','TSTI','TSTC', ...
    'TSTO', 'V');
data2 = load(fullpaths{2}, 'AMBTMP', 'ET', 'MX', 'N', 'NFX', 'NFY', 'RE', 'RL', ...
    'RST', 'RUN', 'SA', 'SL', 'SR','FZ','FX','FY','MZ','P','IA','TSTI','TSTC', ...
    'TSTO', 'V');
%TSTmed1 = (data1.TSTI + data1.TSTC + data1.TSTO)/3;
%TSTmed2 = (data2.TSTI + data2.TSTC + data2.TSTO)/3;

datasetNames = files;  % used for legend

% --- 3) Define axis options and ranges ---
% Dynamically get all data fields except the 'range' variables (assuming same
% fields in both MAT files)
allFields = fieldnames(data1);
exclude   = {'IA'};                                 % Fields to exclude from X axis options
xOptions  = setdiff(allFields, exclude, 'stable');         % Available X axis variables
xLabels   = xOptions;    % Labels for X popup (modify for prettier text if desired)

% Y axis options, dynamically get all data fields except the 'range' variables:
allFields = fieldnames(data1);
exclude   = {'IA'};
yOptions  = setdiff(allFields, exclude, 'stable');
yLabels   = yOptions;

% Preserve original ranges for FZ, P, IA sliders using both datasets
range.FZ  = [min([data1.FZ; data2.FZ]), max([data1.FZ; data2.FZ])];
range.P   = [min([data1.P;  data2.P ]), max([data1.P;  data2.P ])];
range.IA  = [min([data1.IA; data2.IA]), max([data1.IA; data2.IA])];

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
        set(hFZmin,'Enable','off'); set(hFZmax,'Enable','off');
        fzMin = range.FZ(1); fzMax = range.FZ(2);
    else
        set(hFZmin,'Enable','on'); set(hFZmax,'Enable','on');
        fzMin = get(hFZmin,'Value'); fzMax = get(hFZmax,'Value');
    end
    pMin  = get(hPmin,'Value'); pMax = get(hPmax,'Value');
    iaMin = get(hImin,'Value'); iaMax = get(hImax,'Value');
    if pMin>pMax, tmp=pMin; pMin=pMax; pMax=tmp; end
    if iaMin>iaMax, tmp=iaMin; iaMin=iaMax; iaMax=tmp; end

    % Dataset 1
    X1 = data1.(xVar); Y1 = data1.(yVar);
    mask1 = (data1.FZ>=fzMin & data1.FZ<=fzMax) & (data1.P>=pMin & data1.P<=pMax) & ...
            (data1.IA>=iaMin & data1.IA<=iaMax);
    xF1 = X1(mask1); yF1 = Y1(mask1); %T1 = TSTmed1(mask1);
    [xF1, idx] = sort(xF1); yF1 = yF1(idx); %T1 = T1(idx);

    % Dataset 2
    X2 = data2.(xVar); Y2 = data2.(yVar);
    mask2 = (data2.FZ>=fzMin & data2.FZ<=fzMax) & (data2.P>=pMin & data2.P<=pMax) & ...
            (data2.IA>=iaMin & data2.IA<=iaMax);
    xF2 = X2(mask2); yF2 = Y2(mask2); %T2 = TSTmed2(mask2);
    [xF2, idx] = sort(xF2); yF2 = yF2(idx); %T2 = T2(idx);

    cla(hAx);
    hold(hAx,'on');
    scatter(hAx, xF1, yF1, 36, 'filled','Marker','o');
    scatter(hAx, xF2, yF2, 36, 'filled','Marker','^');
    %colormap(hAx,'jet'); colorbar(hAx);
    %caxis(hAx,[min([T1;T2]) max([T1;T2])]);
    hold(hAx,'off');
    xlabel(hAx, xLabel,'Interpreter','none');
    ylabel(hAx, yLabel,'Interpreter','none');
    title(hAx, sprintf('%s vs %s',yLabel,xLabel),'Interpreter','none');
    grid(hAx,'on');
    legend(hAx,datasetNames,'Interpreter','none','Location','best');
end

% --- Nested function: doFit ---
function doFit(~,~)
    selX = get(hPopupX,'Value'); selY = get(hPopupY,'Value');
    xVar = xOptions{selX}; yVar = yOptions{selY};
    if strcmp(xVar,'FZ')
        fzMin = range.FZ(1); fzMax = range.FZ(2);
    else
        fzMin = get(hFZmin,'Value'); fzMax = get(hFZmax,'Value');
    end
    pMin  = get(hPmin,'Value');  pMax  = get(hPmax,'Value');
    iaMin = get(hImin,'Value');  iaMax = get(hImax,'Value');

    % Dataset 1
    X1 = data1.(xVar); Y1 = data1.(yVar);
    mask1 = (data1.FZ>=fzMin & data1.FZ<=fzMax) & (data1.P>=pMin & data1.P<=pMax) & ...
            (data1.IA>=iaMin & data1.IA<=iaMax);
    xF1 = X1(mask1); yF1 = Y1(mask1);

    % Dataset 2
    X2 = data2.(xVar); Y2 = data2.(yVar);
    mask2 = (data2.FZ>=fzMin & data2.FZ<=fzMax) & (data2.P>=pMin & data2.P<=pMax) & ...
            (data2.IA>=iaMin & data2.IA<=iaMax);
    xF2 = X2(mask2); yF2 = Y2(mask2);

    % Combine
    xF = [xF1; xF2];
    yF = [yF1; yF2];

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