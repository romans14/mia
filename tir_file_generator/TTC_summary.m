function TTC_summary(fname)

% TTC_summary(fname)
% fname: filename for file output, must be excel (.xls, .xlsx, .csv, etc)
%
% Searches given directory and subdirectories for .mat and .dat TTC files
% and parses the required information, calculates an estimate for friction
% parameters at 1000N load and outputs to a master table.
%
% Created by: Alex Schramm 24/11/2020
% v1.1 - 07/12/2020 - Alex Schramm

%% Test for licenses
if license('test','Distrib_Computing_Toolbox')
    if isempty(gcp('nocreate'))
        parpool; % start a default parallel pool if one doesn't exist
    end
else
    error('TTC_summary: Required toolbox license missing: Distrib_Computing_Toolbox')
end

%%
selpath = uigetdir(cd,'Select directory of all TTC test data to be analysed');
if isequal(selpath,0)
    error('TTC_summary: data path not selected')
end

oldpath = addpath(genpath(selpath));

if nargin == 0
    fname = [selpath '\TTC_Master_Tyre_Summary.xlsx'];
    i = 1;
    while exist(fname,'file') == 2
        fname = [selpath '\TTC_Master_Tyre_Summary_' num2str(i) '.xlsx'];
        i = i + 1;
    end
end

l = [dir([selpath '\**\*.dat']);dir([selpath '\**\*.mat'])];

header = {'Project','RunID','TireID','Manufacturer','Size','Item','TestID','W_rim','OD_rim','W_tyre','OD_tyre','mass','CORNERING','DRIVE_BRAKE','COMBINED','LOADED_RADIUS','TRANSIENT'};
units = {'','','','','','','','in','in','mm','mm','kg','','','','',''};
desc = {'','','','','','','','','','','','','','','','',''};
out = cell2table(cell(length(l),length(header)));
out.Properties.VariableNames = header;
out.Properties.VariableUnits = units;
out.Properties.VariableDescriptions = desc;

store = struct('TireID',[],'File',[],'TestID',[],'dataX',[],'dataY',[],'dataRE',[]);

spmd
    warning('off','all')
end
disp('Parsing through individual run files:')
fprintf([repmat('_',1,length(l)) '\n\n']);
parfor i = 1:length(l)
    rowout = cell(size(header));
    tok = regexp(l(i).name,'B([0-9]+)[^0-9.]+([0-9]+)\.(?:mat|dat)','tokens');
    if isempty(tok)
        warndlg('TTC_summary: File IDs are not recognized')
    end
    projectid = tok{1}{1};
    runid = tok{1}{2};
    tireidstruct = TTC_Project_Parse(l(i).name,l(i).folder);
    
    rowout{1} = str2double(projectid);
    rowout{2} = str2double(runid);
    item = strrep(tireidstruct.item,' ','');
    rowout{3} = ['B' projectid '_' tireidstruct.manuf '_' replace(tireidstruct.size,{'/','-','.0','.'},{'_','x','',''}) '_' item(1:min(10,length(item))) '_' sprintf('%.0f_in_rim',tireidstruct.w_rim)];
    rowout{4} = tireidstruct.manuf;
    rowout{5} = tireidstruct.size;
    rowout{6} = tireidstruct.item;
    rowout{7} = tireidstruct.testid;
    rowout{8} = tireidstruct.w_rim;
    rowout{9} = tireidstruct.od_rim;
    rowout{10} = tireidstruct.w_tire;
    rowout{11} = tireidstruct.od_tire;
    rowout{12} = tireidstruct.mass;
    
    store(i).File = l(i).name;
    store(i).TestID = tireidstruct.testid;
    store(i).TireID = rowout{3};
    
    [~,~,ext] = fileparts( l(i).name);
    if strcmp(ext,'.mat')
        test_data = load(l(i).name);
    else
        test_data = TTC_dat2mat(l(i).name,l(i).folder);
    end
    
    if ~isfield(test_data,'SL') % needed since early data files don't have SL
        SL_flag = true;
        test_data.SL = test_data.SR; % TODO: CHECK IF THIS IS CORRECT. IS RE TRUE EVEN DURING DRIVE/BRAKE/COMBINED TESTS?
    else
        SL_flag = false;
    end
    test_data.T = mean([test_data.TSTC,test_data.TSTI,test_data.TSTO],2); % mean tyre temperature
    
    %         figure
    %         a(1)=subplot(211);
    %         plot(test_data.ET,test_data.FX,'.-','displayname','FX')
    %         hold on
    %         plot(test_data.ET,test_data.FY,'.-','displayname','FY')
    %         legend
    %         a(2)=subplot(212);
    %         plot(test_data.ET,test_data.SA,'.-','displayname','SA')
    %         hold on
    %         plot(test_data.ET,test_data.IA,'.-','displayname','IA')
    %         plot(test_data.ET,test_data.RL,'.-','displayname','RL')
    %         plot(test_data.ET,test_data.SL*100,'.-','displayname','SL')
    %         plot(test_data.ET,test_data.V,'.-','displayname','V')
    %         plot(test_data.ET,test_data.P,'.-','displayname','P')
    %         legend
    %         linkaxes(a,'x')
    
    dt = mode(diff(test_data.ET));
    idx = [0; find(diff(test_data.ET)>2*dt); length(test_data.ET)];
    data=struct();
    for j = 1:length(idx)-1
        data(j).measurement = j;
        data(j).duration = test_data.ET(idx(j+1)) - test_data.ET(idx(j)+1);
        x = idx(j)+1:idx(j+1);
        % detect test
        if strcmp(test_data.testid,'Cornering')
            if max(test_data.SA(x))-min(test_data.SA(x)) > 11
                data(j).test_type = 'CORNERING';
            elseif all(test_data.V(x)<10) && any(abs(test_data.SA(x))>0.5) && any(test_data.V(x)>1)
                data(j).test_type = 'TRANSIENT';
            elseif all(abs(test_data.FX(x))<250) && all(abs(test_data.SA(x))<0.5) && max(test_data.IA(x))-min(test_data.IA(x)) < 0.5 && max(test_data.V(x))-min(test_data.V(x)) < 1 && max(test_data.RL(x))-min(test_data.RL(x)) < 0.1
                data(j).test_type = 'LOADED_RADIUS';
            else
                data(j).test_type = 'WARMUP';
            end
        else
            if all(abs(test_data.SA(x))<0.5) && max(test_data.FX(x))-min(test_data.FX(x)) > 1000
                data(j).test_type = 'DRIVE_BRAKE';
            elseif max(test_data.FX(x))-min(test_data.FX(x)) > 1000
                data(j).test_type = 'COMBINED';
            elseif all(abs(test_data.FX(x))<250) && all(abs(test_data.SA(x))<0.5) && max(test_data.IA(x))-min(test_data.IA(x)) < 0.5 && max(test_data.V(x))-min(test_data.V(x)) < 1 && max(test_data.RL(x))-min(test_data.RL(x)) < 0.1
                data(j).test_type = 'LOADED_RADIUS';
            elseif all(test_data.V(x)<10) && any(test_data.SA(x)>0.5) && any(test_data.V(x)>1)
                data(j).test_type = 'TRANSIENT';
            else
                data(j).test_type = 'WARMUP';
            end
        end
        
        %         if max(test_data.IA(x))-min(test_data.IA(x)) > 0.5 %|| (max(test_data.SA(x))-min(test_data.SA(x))>0.5 && abs(test_data.SA(x(1)))>0.5)
        %             data(j).test_type = 'WARMUP';
        %         else
        %             if all(test_data.FX(x)<250)
        %                 if all(abs(test_data.SA(x))<0.5)
        %                     data(j).test_type = 'LOADED_RADIUS';
        %                 elseif all(test_data.V(x)<10)
        %                     data(j).test_type = 'TRANSIENT';
        %                 elseif max(test_data.SA(x))-min(test_data.SA(x)) > 0.5
        %                     data(j).test_type = 'CORNERING';
        %                 else
        %                     data(j).test_type = 'WARMUP';
        %                 end
        %             else
        %                 if all(abs(test_data.SA(x))<0.5)
        %                     data(j).test_type = 'DRIVE_BRAKE';
        %                 elseif max(test_data.SA(x))-min(test_data.SA(x)) > 0.5 || max(test_data.FX(x))-min(test_data.FX(x)) > 500
        %                     data(j).test_type = 'COMBINED';
        %                 else
        %                     data(j).test_type = 'WARMUP';
        %                 end
        %             end
        %         end
        % test means
        data(j).V_mean = mean(test_data.V(x));
        data(j).P_mean = mean(test_data.P(x));
        data(j).FX_mean = mean(test_data.FX(x));
        data(j).FY_mean = mean(test_data.FY(x));
        data(j).FZ_mean = mean(test_data.FZ(x));
        data(j).IA_mean = mean(test_data.IA(x));
        data(j).SA_mean = mean(test_data.SA(x));
        data(j).T_mean = mean([test_data.TSTC(x);test_data.TSTI(x);test_data.TSTO(x)]);
        % test data
        data(j).ET = test_data.ET(x);
        data(j).FX = test_data.FX(x);
        data(j).FY = test_data.FY(x);
        data(j).FZ = test_data.FZ(x);
        data(j).IA = test_data.IA(x);
        data(j).N = test_data.N(x);
        data(j).P = test_data.P(x);
        data(j).SA = test_data.SA(x);
        data(j).SL = test_data.SL(x);
        data(j).V = test_data.V(x);
        data(j).T = test_data.T(x);
        data(j).RE = test_data.RE(x);
        data(j).RL = test_data.RL(x);
    end
    
    rowout{13} = sum(strcmp(extractfield(data,'test_type'),'CORNERING'));
    rowout{14} = sum(strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE'));
    rowout{15} = sum(strcmp(extractfield(data,'test_type'),'COMBINED'));
    rowout{16} = sum(strcmp(extractfield(data,'test_type'),'LOADED_RADIUS'));
    rowout{17} = sum(strcmp(extractfield(data,'test_type'),'TRANSIENT'));
    
    out{i,:} = rowout;
    
    store(i).dataX = data(strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') & abs(extractfield(data,'IA_mean')) < 0.5);
    store(i).dataY = data(strcmp(extractfield(data,'test_type'),'CORNERING') & abs(extractfield(data,'IA_mean')) < 0.5);
    if SL_flag
        store(i).dataRE = data(strcmp(extractfield(data,'test_type'),'LOADED_RADIUS'));
    end
    fprintf('\b|\n');
end
spmd
    warning('on','all')
end
clear data test_data

tires = unique(extractfield(store,'TireID'));
data_in = struct();
for i = 1:length(tires)
    % parfor loop prep
    data_in(i).dataX = [store(strcmp(extractfield(store,'TireID'),tires{i})).dataX];
    data_in(i).dataY = [store(strcmp(extractfield(store,'TireID'),tires{i})).dataY];
    data_in(i).dataRE = [store(strcmp(extractfield(store,'TireID'),tires{i})).dataRE];
    data_in(i).UNLOADED_RADIUS = out.OD_tyre{find(strcmp(tires{i},out.TireID),1)}/2/1000;
end
data_out = cell(length(tires),6);
disp('Calculating friction parameters:')
fprintf([repmat('_',1,length(tires)) '\n\n']);
parfor i = 1:length(tires)
    % parfor loop prep
    data_par = data_in(i);
    dataX = data_par.dataX;
    dataY = data_par.dataY;
    dataRE = data_par.dataRE;
    tire = struct();
    rowout = cell(1,6);
    
    if ~isempty([dataX,dataY])
        % required tyre nominal values:
        [p_bins,tire.IP_NOM] = sep_bin(extractfield([dataX,dataY],'P')*1000);
        i_p_nom = find(tire.IP_NOM>p_bins,1,'last');
        [~,tire.FNOMIN] = sep_bin(-extractfield([dataX,dataY],'FZ'));
        [~,tire.LONGVL] = sep_bin(extractfield([dataX,dataY],'V')/3.6);
        tire.UNLOADED_RADIUS = data_par.UNLOADED_RADIUS;
        
        % fit mu_x
        if ~isempty(dataX)
            % fit RE for proper SL if needed:
            if ~isempty(dataRE)
                [T_bins,Temp] = sep_bin(extractfield(dataRE,'T'),0.8);
                i_T_nom = find(Temp>T_bins,1,'last');
                % rho fitting eq 9
                rho = @(tire,data) max((tire.UNLOADED_RADIUS*(tire.QRE0+tire.QV1*((extractfield(data,'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL).^2)-extractfield(data,'RL')/100).*cos(deg2rad(extractfield(data,'IA'))) + tire.QRC1 * (1 - cos(deg2rad(extractfield(data,'IA')))),0);
                % QRE0 fit eq 9 (V=0,IA=0,P=nominal)
                idx = extractfield(dataRE,'T_mean') > T_bins(i_T_nom) & extractfield(dataRE,'T_mean') < T_bins(i_T_nom+1) & extractfield(dataRE,'V_mean') < 1 & extractfield(dataRE,'P_mean')*1000 > p_bins(i_p_nom) & extractfield(dataRE,'P_mean')*1000 < p_bins(i_p_nom+1) & abs(extractfield(dataRE,'IA_mean')) < 0.5;
                [~,b] = lin_orth_reg([-extractfield(dataRE(idx),'FZ')',tire.UNLOADED_RADIUS-extractfield(dataRE(idx),'RL')'/100]);
                tire.QRE0 = -b/tire.UNLOADED_RADIUS+1;
                % QV1 fit eq 9 (V>0,IA=0,P=nominal)
                idx = extractfield(dataRE,'T_mean') > T_bins(i_T_nom) & extractfield(dataRE,'T_mean') < T_bins(i_T_nom+1) & extractfield(dataRE,'P_mean')*1000 > p_bins(i_p_nom) & extractfield(dataRE,'P_mean')*1000 < p_bins(i_p_nom+1) & abs(extractfield(dataRE,'IA_mean')) < 0.5;
                if all(extractfield(dataRE(idx & extractfield(dataRE,'V_mean') > 1),'V')/3.6./extractfield(dataRE(idx & extractfield(dataRE,'V_mean') > 1),'N')/pi*30 < 2)
                    [~,b] = lin_orth_reg([-extractfield(dataRE(idx),'FZ')',tire.UNLOADED_RADIUS*tire.QRE0-extractfield(dataRE(idx),'RL')'/100]);
                    tire.QV1 = (tire.LONGVL/mean(extractfield(dataRE(idx),'N')*pi/30)/tire.UNLOADED_RADIUS)^2*(-b/tire.UNLOADED_RADIUS);
                else
                    warning('TyreFit_PAC2002: parameter QV1 skipped due to lack of N dataRE in CalSpan files.')
                end
                % NON ADAMS-CAR PARAMETER FIT (ADJUST RHO BASED ON CAMBER ANGLE):
                idx = extractfield(dataRE,'T_mean') > T_bins(i_T_nom) & extractfield(dataRE,'T_mean') < T_bins(i_T_nom+1) & extractfield(dataRE,'P_mean')*1000 > p_bins(i_p_nom) & extractfield(dataRE,'P_mean')*1000 < p_bins(i_p_nom+1) & abs(extractfield(dataRE,'IA_mean')) > 0.5;
                ia_bins = sep_bin(extractfield(dataRE(idx),'IA'));
                rc = zeros(1,length(ia_bins)-1);
                for j = 1:length(ia_bins)-1
                    jdx = idx & extractfield(dataRE,'IA_mean') > ia_bins(j) & extractfield(dataRE,'IA_mean') < ia_bins(j+1);
                    x = tire.UNLOADED_RADIUS*(tire.QRE0+tire.QV1*((extractfield(dataRE(jdx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL).^2)-extractfield(dataRE(jdx),'RL')/100;
                    y = -extractfield(dataRE(jdx),'FZ');
                    [~,b] = lin_orth_reg([y',x']);
                    rc(j) = -b/(1-cos(deg2rad(mean(extractfield(dataRE(jdx),'IA')))));
                end
                tire.QRC1 = mean(rc);
                
                % VERTICAL_STIFFNESS fit
                idx = extractfield(dataRE,'T_mean') > T_bins(i_T_nom) & extractfield(dataRE,'T_mean') < T_bins(i_T_nom+1);
                x = rho(tire,dataRE(idx));
                y = -extractfield(dataRE(idx),'FZ');
                tire.VERTICAL_STIFFNESS = y/x; % linear regression w/ no intercept TODO: implement an orthogonal/deming regression w/ no intercept
                
                % Effective Rolling Radius eq 11 fitting: DREFF BREFF FREFF
                idx = extractfield(dataRE,'V_mean')>5 & abs(extractfield(dataRE,'FX_mean'))<200 & extractfield(dataRE,'T_mean') > T_bins(i_T_nom) & extractfield(dataRE,'T_mean') < T_bins(i_T_nom+1);
                RE_data = (extractfield(dataRE(idx),'V')/3.6)./(extractfield(dataRE(idx),'N')*pi/30);
                rhoFz0 = tire.FNOMIN/tire.VERTICAL_STIFFNESS;
                x = rho(tire,dataRE(idx))/rhoFz0;
                y = -(RE_data - (tire.UNLOADED_RADIUS*tire.QRE0 + tire.QV1*tire.UNLOADED_RADIUS*((extractfield(dataRE(idx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL).^2))/rhoFz0;
                fun = @(p,x) p(1) * atan( p(2) * x ) + p(3) * x;
                [yl,xl]=min(sortrows([x',y']),[],1);
                [yh,xh]=max(sortrows([x',y']),[],1);
                if xl(2)<xh(2)
                    sl = sign(yl(2));
                    sh = sign(yh(2));
                else
                    sl = sign(yh(2));
                    sh = sign(yl(2));
                end
                lb = [-inf,0,-inf];
                ub = [inf,inf,inf];
                p0 = [sl*1 1 sh*1];
                opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
                p = lsqcurvefit(fun,p0,x,y,lb,ub,opts);
                tire.DREFF = p(1);
                tire.BREFF = p(2);
                tire.FREFF = p(3);
                
                RE = @(tire,data) tire.UNLOADED_RADIUS*tire.QRE0 + tire.QV1*tire.UNLOADED_RADIUS*(((extractfield(data,'N')*pi/30)*tire.UNLOADED_RADIUS)/tire.LONGVL).^2 - tire.FNOMIN/tire.VERTICAL_STIFFNESS*(tire.DREFF*atan(tire.BREFF*rho(tire,data)/( tire.FNOMIN/tire.VERTICAL_STIFFNESS))+tire.FREFF*rho(tire,data)/( tire.FNOMIN/tire.VERTICAL_STIFFNESS));
                
                for j = 1:length(dataX)
                    dataX(j).SL = RE(tire,dataX(j))'.*(dataX(j).N*pi/30)./(dataX(j).V/3.6) - 1;
                end
            end
            
            % pre-fit magic curves
            for j = 1:length(dataX)
                % Fit the B,C,D,E,Sh,Sv magic parameters to each indivual test
                [dataX(j).B,dataX(j).C,dataX(j).D,dataX(j).E,dataX(j).Sh,dataX(j).Sv] = Magic_Fit_F(dataX(j).SL,dataX(j).FX);
            end
            
            % fit Dx: PDX1 PDX2 PDX3 PPX3 PPX4
            % IA=0, P=nominal
            idx = extractfield(dataX,'P_mean')*1000 > p_bins(i_p_nom) & extractfield(dataX,'P_mean')*1000 < p_bins(i_p_nom+1) & abs(extractfield(dataX,'IA_mean')) < 0.5;
            y = -extractfield(dataX(idx),'D')./extractfield(dataX(idx),'FZ_mean');
            x = [ones(size(y)); (-extractfield(dataX(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
            [y,rem] = rmoutliers(y);
            x(:,rem) = [];
            % TODO: linear regression or deming/ortho fit??
            b = x'\y';
            tire.PDX1 = b(1);
            if pnorm_rmse(y',x'*b) < std(y)
                tire.PDX2 = b(2);
            end
            % IA~=0, P=nominal
            tire.PDX3 = 0;
            % P~=nominal
            p_points = length(unique(discretize(extractfield(dataX,'P')*1000,p_bins)));
            if p_points > 1
                idx = (extractfield(dataX,'P_mean')*1000 < p_bins(i_p_nom) | extractfield(dataX,'P_mean')*1000 > p_bins(i_p_nom+1));
                if p_points > 2
                    x = [(extractfield(dataX(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM; ((extractfield(dataX(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM).^2];
                    y = -extractfield(dataX(idx),'D')./extractfield(dataX(idx),'FZ_mean')./(tire.PDX1 + tire.PDX2*(-extractfield(dataX(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1-tire.PDX3*deg2rad(extractfield(dataX(idx),'IA_mean')).^2)-1;
                    [y,rem] = rmoutliers(y);
                    x(:,rem) = [];
                    b = x'\y';
                    if pnorm_rmse(y',x'*b) < std(y)
                        tire.PPX3 = b(1);
                        tire.PPX4 = b(2);
                    else
                        tire.PPX3 = 0;
                        tire.PPX4 = 0;
                    end
                else
                    x = (extractfield(dataX(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM;
                    y = -extractfield(dataX(idx),'D')./extractfield(dataX(idx),'FZ_mean')./(tire.PDX1 + tire.PDX2*(-extractfield(dataX(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1-tire.PDX3*deg2rad(extractfield(dataX(idx),'IA_mean')).^2)-1;
                    [y,rem] = rmoutliers(y);
                    x(:,rem) = [];
                    b = x'\y';
                    if pnorm_rmse(y',x'*b) < std(y)
                        tire.PPX3 = b(1);
                        tire.PPX4 = 0;
                    else
                        tire.PPX3 = 0;
                        tire.PPX4 = 0;
                    end
                end
            else
                tire.PPX3 = 0;
                tire.PPX4 = 0;
            end
            
            % final fit:
            y = -extractfield(dataX,'D')./extractfield(dataX,'FZ_mean');
            if p_points > 2
                fun = @(p,x) (p(1) + p(2)*x(1,:)).*(1 + p(3)*x(2,:) + p(4)*x(2,:).^2);
                x = [(-extractfield(dataX,'FZ_mean')-tire.FNOMIN)/tire.FNOMIN ; (extractfield(dataX,'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM];
                lb = [0, -inf, -inf, -inf];
                ub = [inf, 0, inf, 0];
                p0 = [max(tire.PDX1,0), min(tire.PDX2,0), tire.PPX3, min(tire.PPX4,0)];
            elseif p_points == 2
                fun = @(p,x) (p(1) + p(2)*x(1,:)).*(1 + p(3)*x(2,:));
                x = [(-extractfield(dataX,'FZ_mean')-tire.FNOMIN)/tire.FNOMIN ; (extractfield(dataX,'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM];
                lb = [0, -inf, -inf];
                ub = [inf, 0, inf];
                p0 = [max(tire.PDX1,0), min(tire.PDX2,0), tire.PPX3];
            else
                fun = @(p,x) (p(1) + p(2)*x(1,:));
                x = (-extractfield(dataX,'FZ_mean')-tire.FNOMIN)/tire.FNOMIN;
                lb = [0, -inf];
                ub = [inf, 0];
                p0 = [max(tire.PDX1,0), min(tire.PDX2,0)];
            end
            opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
            p = lsqcurvefit(fun,p0,x,y,lb,ub,opts);
            
            
            rowout{2} = pnorm_rmse(y,fun(p,x));
            if p_points > 2
                x = [(1000-tire.FNOMIN)/tire.FNOMIN ; -p(3)/p(4)/2];
                x(2) = min(max((extractfield(dataX,'P')*1000-tire.IP_NOM)/tire.IP_NOM),max(min((extractfield(dataX,'P')*1000-tire.IP_NOM)/tire.IP_NOM),x(2)));
                rowout{1} = fun(p,x);
                rowout{3} = (x(2)*tire.IP_NOM+tire.IP_NOM)/1000;
            elseif p_points == 2
                if p(3) < 0
                    x = [(1000-tire.FNOMIN)/tire.FNOMIN ; min((extractfield(dataX,'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM)];
                else
                    x = [(1000-tire.FNOMIN)/tire.FNOMIN ; max((extractfield(dataX,'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM)];
                end
                rowout{1} = fun(p,x);
                rowout{3} = (x(2)*tire.IP_NOM+tire.IP_NOM)/1000;
            else
                x = (1000-tire.FNOMIN)/tire.FNOMIN;
                rowout{1} = fun(p,x);
                rowout{3} = mean(extractfield(dataX,'P_mean'));
            end
        end
        
        % fit mu_y
        if ~isempty(dataY)
            
            % pre-fit magic curves
            for j = 1:length(dataY)
                % Fit the B,C,D,E,Sh,Sv magic parameters to each indivual test
                [dataY(j).B,dataY(j).C,dataY(j).D,dataY(j).E,dataY(j).Sh,dataY(j).Sv] = Magic_Fit_F(deg2rad(dataY(j).SA),dataY(j).FY);
            end
            
            % fit Dy: PDY1 PDY2 PDY3 PPY3 PPY4
            % IA=0, P=nominal
            idx = extractfield(dataY,'P_mean')*1000 > p_bins(i_p_nom) & extractfield(dataY,'P_mean')*1000 < p_bins(i_p_nom+1) & abs(extractfield(dataY,'IA_mean')) < 0.5;
            y = -extractfield(dataY(idx),'D')./extractfield(dataY(idx),'FZ_mean');
            x = [ones(size(y)); (-extractfield(dataY(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
            [y,rem] = rmoutliers(y);
            x(:,rem) = [];
            b = x'\y';
            tire.PDY1 = b(1);
            if pnorm_rmse(y',x'*b) < std(y)
                tire.PDY2 = b(2);
            end
            % IA~=0, P=nominal
            tire.PDY3 = 0;
            % P~=nominal
            p_points = length(unique(discretize(extractfield(dataY,'P')*1000,p_bins)));
            if p_points > 1
                idx = (extractfield(dataY,'P_mean')*1000 < p_bins(i_p_nom) | extractfield(dataY,'P_mean')*1000 > p_bins(i_p_nom+1));
                if p_points > 2
                    x = [(extractfield(dataY(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM; ((extractfield(dataY(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM).^2];
                    y = -extractfield(dataY(idx),'D')./extractfield(dataY(idx),'FZ_mean')./(tire.PDY1 + tire.PDY2*(-extractfield(dataY(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1-tire.PDY3*deg2rad(extractfield(dataY(idx),'IA_mean')).^2)-1;
                    [y,rem] = rmoutliers(y);
                    x(:,rem) = [];
                    b = x'\y';
                    if pnorm_rmse(y',x'*b) < std(y)
                        tire.PPY3 = b(1);
                        tire.PPY4 = b(2);
                    else
                        tire.PPY3 = 0;
                        tire.PPY4 = 0;
                    end
                else
                    x = (extractfield(dataY(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM;
                    y = -extractfield(dataY(idx),'D')./extractfield(dataY(idx),'FZ_mean')./(tire.PDY1 + tire.PDY2*(-extractfield(dataY(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1-tire.PDY3*deg2rad(extractfield(dataY(idx),'IA_mean')).^2)-1;
                    [y,rem] = rmoutliers(y);
                    x(:,rem) = [];
                    b = x'\y';
                    if pnorm_rmse(y',x'*b) < std(y)
                        tire.PPY3 = b(1);
                        tire.PPY4 = 0;
                    else
                        tire.PPY3 = 0;
                        tire.PPY4 = 0;
                    end
                end
            else
                tire.PPY3 = 0;
                tire.PPY4 = 0;
            end
            
            % final fit:
            y = -extractfield(dataY,'D')./extractfield(dataY,'FZ_mean');
            if p_points > 2
                fun = @(p,x) (p(1) + p(2)*x(1,:)).*(1 + p(3)*x(2,:) + p(4)*x(2,:).^2);
                x = [(-extractfield(dataY,'FZ_mean')-tire.FNOMIN)/tire.FNOMIN ; (extractfield(dataY,'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM];
                lb = [0, -inf, -inf, -inf];
                ub = [inf, 0, inf, 0];
                p0 = [max(tire.PDY1,0), min(tire.PDY2,0), tire.PPY3, min(tire.PPY4,0)];
            elseif p_points == 2
                fun = @(p,x) (p(1) + p(2)*x(1,:)).*(1 + p(3)*x(2,:));
                x = [(-extractfield(dataY,'FZ_mean')-tire.FNOMIN)/tire.FNOMIN ; (extractfield(dataY,'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM];
                lb = [0, -inf, -inf];
                ub = [inf, 0, inf];
                p0 = [max(tire.PDY1,0), min(tire.PDY2,0), tire.PPY3];
            else
                fun = @(p,x) (p(1) + p(2)*x(1,:));
                x = (-extractfield(dataY,'FZ_mean')-tire.FNOMIN)/tire.FNOMIN;
                lb = [0, -inf];
                ub = [inf, 0];
                p0 = [max(tire.PDY1,0), min(tire.PDY2,0)];
            end
            opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
            p = lsqcurvefit(fun,p0,x,y,lb,ub,opts);
            
            
            rowout{5} = pnorm_rmse(y,fun(p,x));
            if p_points > 2
                x = [(1000-tire.FNOMIN)/tire.FNOMIN ; -p(3)/p(4)/2];
                x(2) = min(max((extractfield(dataY,'P')*1000-tire.IP_NOM)/tire.IP_NOM),max(min((extractfield(dataY,'P')*1000-tire.IP_NOM)/tire.IP_NOM),x(2)));
                rowout{4} = fun(p,x);
                rowout{6} = (x(2)*tire.IP_NOM+tire.IP_NOM)/1000;
            elseif p_points == 2
                if p(3) < 0
                    x = [(1000-tire.FNOMIN)/tire.FNOMIN ; min((extractfield(dataY,'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM)];
                else
                    x = [(1000-tire.FNOMIN)/tire.FNOMIN ; max((extractfield(dataY,'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM)];
                end
                rowout{4} = fun(p,x);
                rowout{6} = (x(2)*tire.IP_NOM+tire.IP_NOM)/1000;
            else
                x = (1000-tire.FNOMIN)/tire.FNOMIN;
                rowout{4} = fun(p,x);
                rowout{6} = mean(extractfield(dataY,'P_mean'));
            end
        end
    end
    
    data_out(i,:) = rowout;
    fprintf('\b|\n');
end

header2 = {'TireID','Manufacturer','Size','Item','W_rim','OD_rim','W_tyre','OD_tyre','mass','CORNERING','DRIVE_BRAKE','COMBINED','LOADED_RADIUS','TRANSIENT','mu_x','err_x','pres_x','mu_y','err_y','pres_y'};
unit2 = {'','','','','in','in','mm','m','kg','#','#','#','#','#','-','-','kPa','-','-','kPa'};
desc2 = {'','','','','','','','','','sum','sum','sum','sum','sum','@1000N','rmse','@peak grip','@1000N','rmse','@peak grip'};
tire_table = cell2table(cell(length(tires),length(header2)));
tire_table.Properties.VariableNames = header2;
tire_table.Properties.VariableUnits = unit2;
tire_table.Properties.VariableDescriptions = desc2;

tire_table(:,15:20) = data_out;
tire_table.TireID = tires';
for i = 1:height(tire_table)
    tire_table(i,2) = out.Manufacturer(find(strcmp(tire_table.TireID(i),out.TireID),1));
    tire_table(i,3) = out.Size(find(strcmp(tire_table.TireID(i),out.TireID),1));
    tire_table(i,4) = {out.Item(find(strcmp(tire_table.TireID(i),out.TireID),1))};
    tire_table(i,5) = {out.W_rim(find(strcmp(tire_table.TireID(i),out.TireID),1))};
    tire_table(i,6) = {out.OD_rim(find(strcmp(tire_table.TireID(i),out.TireID),1))};
    tire_table(i,7) = {out.W_tyre(find(strcmp(tire_table.TireID(i),out.TireID),1))};
    tire_table(i,8) = {out.OD_tyre(find(strcmp(tire_table.TireID(i),out.TireID),1))};
    tire_table(i,9) = {{mean(cell2mat(out.mass(strcmp(tire_table.TireID(i),out.TireID))))}};
    tire_table(i,10) = {{sum(cell2mat(out.CORNERING(strcmp(tire_table.TireID(i),out.TireID))))}};
    tire_table(i,11) = {{sum(cell2mat(out.DRIVE_BRAKE(strcmp(tire_table.TireID(i),out.TireID))))}};
    tire_table(i,12) = {{sum(cell2mat(out.COMBINED(strcmp(tire_table.TireID(i),out.TireID))))}};
    tire_table(i,13) = {{sum(cell2mat(out.LOADED_RADIUS(strcmp(tire_table.TireID(i),out.TireID))))}};
    tire_table(i,14) = {{sum(cell2mat(out.TRANSIENT(strcmp(tire_table.TireID(i),out.TireID))))}};
end

writetable(tire_table,fname,'Sheet','Tyre Summary');
writetable(out,fname,'Sheet','Run Summary');

path(oldpath);

end


%% Supporting functions:

function [bins,mean_bin] = sep_bin(dat, tolin)
bw = (max(dat)-min(dat))/20;
[f,xi] = ksdensity(dat,'numpoints',max(round(length(dat)/100),100),'bandwidth',bw);%,'kernel','epanechnikov');
if nargin <2
    tol = 0.005*max(f);
else
    tol = tolin*max(f);
end
[~,bins] = findpeaks(-f,xi,'MinPeakProminence',tol);
bins = [-inf bins inf];
if nargout ~= 1
    [~,i] = max(f);
    m = xi(i);
    i_b = find(m>bins,1,'last');
    mean_bin = mean(dat(dat>bins(i_b)&dat<bins(i_b+1)));
end
end

function [m,b] = lin_orth_reg(data)
% TODO: check and update that this is proper Deming regression
[~, ~, V] = svd(data - repmat(mean(data), size(data, 1), 1), 0);
m = -V(1, end) / V(2, end);
b = mean(data * V(:, end)) / V(2, end);
end

function rmse = pnorm_rmse(x,y,n)
% p=1 results in RMSE, 2 uses a power of 4, etc
switch nargin
    case 1
        rmse = sqrt(mean(x.^2));
    case 2
        rmse = sqrt(mean((x-y).^2));
    otherwise
        rmse = (mean((x-y).^(2*n))).^(1/(2*n));
end
end

function [B,C,D,E,Sh,Sv] = Magic_Fit_F(x,F)
% fit the sine Magic Curve to a set of slip-Force data
FM = @(x,B,C,D,E,Sh,Sv) D .* sin( C .* atan( B .* (x + Sh) - E .* ( B .* (x + Sh) - atan( B .* (x + Sh) ) ) ) ) + Sv;
Sv0 = mean([max(F),min(F)]); % Sv estimate, shift vertical so max and min are equi-distance to axis
F0 = F-Sv0;
if mean(F0(x>0))>0
    [D0,i] = max(F0);
else
    [D0,i] = min(F0);
end
xm = x(i);
[K0,b] = lin_orth_reg([x(abs(F0)<0.33*max(abs(F0))),F0(abs(F0)<0.33*max(abs(F0)))]);
Sh0 = b./K0;
C0 = 1+(1-2/pi*asin(F0(end)./D0));
B0 = K0./C0./D0;
if C0>1.001
    E0 = min((B0.*xm-tan(pi/2/C0))./(B0.*xm-atan(B0.*xm)),1);
else
    E0=0;
end

fun = @(p,x) FM(x,p(1),p(2),p(3),p(4),p(5),p(6));
p0 = [B0,C0,D0,E0,Sh0,Sv0];
if sign(D0)<0
    lb = [0,0,min(F0)*1.5,-inf,min(x),min(F)];
    ub = [inf,inf,0,1,max(x),max(F)];
else
    lb = [0,0,0,-inf,min(x),min(F)];
    ub = [inf,inf,max(F0)*1.5,1,max(x),max(F)];
end
opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','MaxFunctionEvaluations',realmax,'MaxIterations',realmax); %,'PlotFcn','optimplotx','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps
p = lsqcurvefit(fun,p0,x,F,lb,ub,opts);
B=p(1);C=p(2);D=p(3);E=p(4);Sh=p(5);Sv=p(6);
end