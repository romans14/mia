function plotTTCTimeHistory()
% plotTTCTimeHistoryInteractive  Interactive Time history of TTC data with FZ, P, IA always shown and temperature gradient
%   Load a TTC .mat file with ET (time), FX, FY, MZ, FZ, P, IA, TSTI, TSTC, TSTO
%   and select FX, FY, or MZ to overlay, with color-coded temperature average.

    % 1) Prompt for .mat file
    [fn, pn] = uigetfile('*.mat', 'Select TTC .mat file with ET, FX, FY, MZ, FZ, P, IA, TSTI, TSTC, TSTO');
    if isequal(fn,0)
        disp('File selection cancelled.');
        return;
    end
    S = load(fullfile(pn, fn), 'ET', 'FX', 'FY', 'MZ', 'FZ', 'P', 'IA', 'TSTI', 'TSTC', 'TSTO');

    % 2) Verify variables
    req = {'ET','FX','FY','MZ','FZ','P','IA','TSTI','TSTC','TSTO'};
    for k = 1:numel(req)
        if ~isfield(S,req{k})
            error('The .mat file must contain %s.', strjoin(req, ', '));
        end
    end

    % 3) Compute temperature average
    Tmed = (S.TSTI + S.TSTC + S.TSTO)/3;

    % 4) Create GUI
    hFig = figure('Name','TTC Time History Interactive','NumberTitle','off','Position',[200 200 800 500]);
    hAx  = axes('Parent',hFig,'Position',[0.07 0.15 0.65 0.80]);

    % 5) Dropdown for main force selection (overlaid on always-present series)
    yVars   = {'FY','FX','MZ'};
    yLabels = {'Lateral force (FY)','Longitudinal force (FX)','Aligning torque (MZ)'};
    x0 = 0.78; w = 0.20; h = 0.05; y0 = 0.85;
    uicontrol('Style','text','Parent',hFig,'Units','normalized',...
        'Position',[x0 y0 w h],'String','Overlay Force:','HorizontalAlignment','left');
    hPopup = uicontrol('Style','popupmenu','Parent',hFig,'Units','normalized',...
        'Position',[x0 y0-h w h],'String',yLabels,'Value',1,'Callback',@updatePlot);

    % 6) Initial plot
    updatePlot();

    % Nested: updatePlot callback
    function updatePlot(~,~)
        idx   = get(hPopup,'Value');
        tData = S.ET;
        mainY = S.(yVars{idx});
        % Always-present series:
        fzData = S.FZ;
        pData  = S.P;
        iaData = S.IA;

        cla(hAx);
        hold(hAx,'on');
        % Plot FZ, P, IA as scatter. I numeri tra parentesi servono a modificare i colori in RGB
        scatter(hAx, tData, fzData, 24, 's', 'MarkerEdgeColor', [1.00 0.00 0.00], 'DisplayName','Vertical load (FZ)');
        scatter(hAx, tData, pData,  24, 'd', 'MarkerEdgeColor', [1.00 0.50 0.00], 'DisplayName','Pressure (P)');
        scatter(hAx, tData, iaData, 24, '^', 'MarkerEdgeColor', [1.00 0.00 1.00], 'DisplayName','Camber angle (IA)');
        % Plot main selected force colored by temperature
        scatter(hAx, tData, mainY, 36, Tmed, 'filled', 'DisplayName', yLabels{idx});
        hold(hAx,'off');

        % Colormap and colorbar for temperature
        colormap(hAx,'jet');
        cb = colorbar(hAx);
        cb.Label.String = 'Tread Temp. (avg)';

        grid(hAx,'on');
        xlabel(hAx,'Time (s)','Interpreter','none');
        ylabel(hAx,'Value','Interpreter','none');
        title(hAx,sprintf('%s and TTC parameters vs Time', yLabels{idx}),'Interpreter','none');
        legend(hAx,'Location','best');
    end
end