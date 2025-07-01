function [tire,flag] = TyreFit_PAC2002(fname)

% [tire,flag] = TyreFit_PAC2002(fname,M_tire)
% fname: filename for .tir file output, default tire.Tire
% M_tire: mass of tyre for mass and belt parameters, default: 4.5 kg
% tire: .tir file structure
% flag: file write flag, 0=successful
% Fit CalSpan data to a PAC2002 tir file for use in AdamsCar. There is one
% additional parameter (tire.QRC1) included in here to account for the change in tyre
% deflection as a function of camber angle, which is not included in the
% PAC2002 AdamsCar model (since it is modelled as a thin-disk single point
% of contact wheel).
% 
% TODO:
%  - create if/else warnings for all fittings checking if data is available
%    or not (at lower levels, like are camber tests available, etc)
%  - optimise time
%  - find an implementation of orthoganl/deming linear regression (might
%    just be the mean y value?) (line 272)
%  - change all linear regressions to deming regression?
%  - improve initial guess of alignment torque parameters (line 725)
%  - we may need a check on tire temperatures in more places
%  - Check if the SL calculation (line 143) is correct and comes up with
%    proper values (in early tests).
% 
% Notes:
%  - fminunc (min finding) used for final tuning due to speed over
%    lsqnonlin (regression). lsqcurvefit was unsuitable due to the complex
%    "x" input to the tire model
%  - lsqcurvefit is used where possible for its speed. uses an RMSE cost
%  - for initial guesses, linear regression was mostly used, after
%    rmoutlier() in it's default form to clip the data
% 
% Created by: Alex Schramm 06/11/2020
% v1.41 - 26/05/2021 - Alex Schramm
%         - fixed sign of slip angle in TTC data
%         - updated/added limits to magic curve coefficients
%         - added 5% damping to tire for use in VI
%         - added constraints to QFCX1 and QFCY1 (-1 to 1) for use in VI
%         - REQUIRED MODS to work in VI: 10x VERTICAL_DAMPING, QFCX1 == 0,
%           and need to add longitudinal relaxation length
%         - ADD SYMMETRIC TYRE OPTION (Pacejka p616)

addpath("_lib\")
addpath("..\_lib\")
tire = parse_tir_file();

%% Global Options
maxfuneval = 15000;
maxiter = 1000;
pnorm = 1;
for_VI = true;
sym_flag = true;

%% Load in one or more CalSpan runs
[run_files,run_path] = uigetfile('*.mat;*.dat','Choose CalSpan Data Files','MultiSelect','on');
if isequal(run_files,0)
    error('TyreFit_PAC2002: No data files selected')
end

if ischar(run_files)
    run_files = {run_files};
end

oldpath = addpath(cd); 
addpath(run_path);
addpath([run_path '\..'])

test_data = struct();
for i = 1:length(run_files)
    [~,~,ext] = fileparts( run_files{i});
    if strcmp(ext,'.mat')
        add_data = load([run_path run_files{i}]);
    else
        add_data = TTC_dat2mat(run_files{i},run_path);
    end
    fn = fieldnames(add_data);
    for j = 1:length(fn)
        test_data(i).(fn{j}) = add_data.(fn{j});
    end
end

%% Test for licenses
if license('test','distrib_computing_toolbox')
    parallel = true;
    if isempty(gcp('nocreate'))
        parpool; % start a default parallel pool if one doesn't exist
    end
else
    parallel = false;
end

if ~license('test','map_toolbox')
    error('TyreFit_PAC2002: Required toolbox license missing: map_toolbox')
end

if ~license('test','signal_toolbox')
    error('TyreFit_PAC2002: Required toolbox license missing: signal_toolbox')
end

if ~license('test','optimization_toolbox')
    error('TyreFit_PAC2002: Required toolbox license missing: optimization_toolbox')
end

if ~license('test','statistics_toolbox')
    error('TyreFit_PAC2002: Required toolbox license missing: statistics_toolbox')
end

%% Check that all runs are the same tire
% TODO: maybe add a for-loop here and loop through each unique tyre? So you
% could select all files in a directory?
tireid = unique({test_data.tireid});
if length(tireid)>1
    error('TyreFit_PAC2002: More than 1 unique tireid, please reselect data files')
end

disp('Parsing tyre data...')

% parsing tire info
[tireidstruct] = TTC_Project_Parse(run_files{1},run_path);

% take mean of largest groups
[~,P_tire] = sep_bin(extractfield(test_data,'P'));
[~,F_tire] = sep_bin(-extractfield(test_data,'FZ'));
[~,V_tire] = sep_bin(extractfield(test_data,'V'));

unloaded_radius = tireidstruct.od_tire/1000/2; % radius, m
section_width = tireidstruct.w_tire/1000; % m
rim_diameter = tireidstruct.od_rim; % in
rim_width = tireidstruct.w_rim; % in
pressure = P_tire*1000; % Pa
nom_vertical_load = F_tire; % N
velocity = V_tire/3.6; % m/s

%% Extra Inputs
aspect_ratio=(unloaded_radius-rim_diameter*0.0254/2)/section_width*100;%53; %Nom. aspect ratio in %
rim_radius=rim_diameter/2*0.0254;%0.127; %Rim Radius in m
% traj_vel=velocity;%11.17; %trajectory velocity in m/s

%% Combine data, and parse into separate tests
    
disp('Separating individual tests...')

ET_end = 0;
data = [];
for j = 1:length(test_data)
    % combine all data into arrays
    ET = extractfield(test_data(j),'ET')'+ET_end+100;
    ET_end = ET(end);
    AMBTMP = test_data(j).AMBTMP; % degC or degF  Ambient room temperature
    FX = test_data(j).FX; % N or lb         Longitudinal Force
    FY = -test_data(j).FY; % N or lb         Lateral Force
    FZ = -test_data(j).FZ; % N or lb         Normal Load
    IA = test_data(j).IA; % deg             Inclination Angle
    MX = test_data(j).MX; % N-m or lb-ft  Overturning Moment
    MZ = -test_data(j).MZ; % N-m or lb-ft  Aligning Torque
    N = test_data(j).N; % rpm             Wheel rotational speed
    NFX = -test_data(j).NFX; % unitless        Normalized longitudinal force (FX/FZ)
    NFY = test_data(j).NFY; % unitless        Normalized lateral force (FY/FZ)
    P = test_data(j).P; % kPa or psi      Tire pressure
    RE = test_data(j).RE; % cm or in        Effective Radius
    RL = test_data(j).RL; % cm or in        Loaded Radius
    RST = test_data(j).RST; % degC or degF  Road surface temperature
    % TODO: slip angle flipped from TTC data, needs confirmation
    SA = -test_data(j).SA; % deg             Slip Angle
    V = test_data(j).V; % kph or mph      Road Speed
    if isempty(test_data(j).SL) % needed since early data files don't have SL
        SL_flag = true;
        SL = test_data(j).SR; % TODO: CHECK IF THIS IS CORRECT. IS RE TRUE EVEN DURING DRIVE/BRAKE/COMBINED TESTS?
    else
        SL = test_data(j).SL;
        SL_flag = false;
    end
    SR = test_data(j).SR; % unitless        Slip Ratio based on RL (used for Calspan machine control, SR=0 does not give FX=0)
    TSTC = test_data(j).TSTC; % degC or degF  Tire Surface Temperature--Center
    TSTI = test_data(j).TSTI; % degC or degF  Tire Surface Temperature--Inboard
    TSTO = test_data(j).TSTO; % degC or degF  Tire Surface Temperature--Outboard
    T = mean([TSTC,TSTI,TSTO],2); % mean tyre temperature
    
    % figure
    % a(1) = subplot(311);
    % plot(ET,FX,'.-','DisplayName','FX')
    % hold on
    % plot(ET,FY,'.-','DisplayName','FY')
    % plot(ET,-FZ,'.-','DisplayName','FZ')
    % legend show
    % a(2) = subplot(312);
    % plot(ET,SL*100,'.-','DisplayName','SL')
    % hold on
    % plot(ET,SL,'.-','DisplayName','SA')
    % plot(ET,SL,'.-','DisplayName','IA')
    % legend show
    % a(3) = subplot(313);
    % plot(ET,P,'.-','DisplayName','P')
    % hold on
    % plot(ET,V,'.-','DisplayName','V')
    % plot(ET,T,'.-','DisplayName','T')
    % legend show
    % linkaxes(a,'x')
    
    dt = mode(diff(ET));
    idx = [0; find(diff(ET)>70*dt); length(ET)];
    L = length(data);
    for i = 1:length(idx)-1
        k = i + L;
        data(k).measurement = i; %#ok<*AGROW>
        data(k).duration = ET(idx(i+1)) - ET(idx(i)+1);
        x = idx(i)+1:idx(i+1);
        % detect test
        if strcmp(test_data(j).testid,'Cornering')
            if max(SA(x))-min(SA(x)) > 11
                data(k).test_type = 'CORNERING';
            elseif all(V(x)<10) && any(abs(SA(x))>0.5) && any(V(x)>1)
                data(k).test_type = 'TRANSIENT';
            elseif all(abs(FX(x))<250) && all(abs(SA(x))<0.5) && max(IA(x))-min(IA(x)) < 0.5 && max(V(x))-min(V(x)) < 1 && max(RL(x))-min(RL(x)) < 0.1
                data(k).test_type = 'LOADED_RADIUS';
            else
                data(k).test_type = 'WARMUP';
            end
        else
            if all(abs(SA(x))<0.5) && max(SL(x))-min(SL(x)) > 0.2
                data(k).test_type = 'DRIVE_BRAKE';
            elseif max(SL(x))-min(SL(x)) > 0.2
                data(k).test_type = 'COMBINED';
            elseif all(abs(FX(x))<250) && all(abs(SA(x))<0.5) && max(IA(x))-min(IA(x)) < 0.5 && max(V(x))-min(V(x)) < 1 && max(RL(x))-min(RL(x)) < 0.1
                data(k).test_type = 'LOADED_RADIUS';
            elseif all(V(x)<10) && any(SA(x)>0.5) && any(V(x)>1)
                data(k).test_type = 'TRANSIENT';
            else
                data(k).test_type = 'WARMUP';
            end
        end
        % test means
        data(k).V_mean = mean(V(x));
        data(k).N_mean = mean(N(x));
        data(k).P_mean = mean(P(x));
        data(k).FX_mean = mean(FX(x));
        data(k).FY_mean = mean(FY(x));
        data(k).FZ_mean = mean(FZ(x));
        data(k).IA_mean = mean(IA(x));
        data(k).SA_mean = mean(SA(x));
        data(k).RE_mean = mean(RE(x));
        data(k).T_mean = mean([TSTC(x);TSTI(x);TSTO(x)]);
        data(k).SL_flag = SL_flag;
        % test data
        data(k).ET = ET(x);
        data(k).AMBTMP = AMBTMP(x);
        data(k).FX = FX(x);
        data(k).FY = FY(x);
        data(k).FZ = FZ(x);
        data(k).IA = IA(x);
        data(k).MX = MX(x);
        data(k).MZ = MZ(x);
        data(k).N = N(x);
        data(k).NFX = NFX(x);
        data(k).NFY = NFY(x);
        data(k).P = P(x);
        data(k).RE = RE(x);
        data(k).RL = RL(x);
        data(k).RST = RST(x);
        data(k).SA = SA(x);
        data(k).SL = SL(x);
        data(k).SR = SR(x);
        data(k).TSTC = TSTC(x);
        data(k).TSTI = TSTI(x);
        data(k).TSTO = TSTO(x);
        data(k).T = T(x);
        data(k).V = V(x);
    end
end
clear AMBTMP ET FX FY FZ IA MX MZ N NFX NFY P RE RL RST SA SL SR TSTC TSTI TSTO V T

%% Tyre Nominal Data and Dimensions
tire.Tire = [tireidstruct.manuf ' ' tireidstruct.size ' ' tireidstruct.item ', ' num2str(tireidstruct.w_rim) ' inch rim'];
tire.Manufacturer = tireidstruct.manuf;
tire.Nom_section_width.value = section_width;
tire.Nom_aspect_ratio.value = aspect_ratio/100;
tire.Infl_pressure.value = pressure;
tire.Rim_diameter.value = rim_diameter;
tire.Test_speed.value = velocity;
tire.Road_surface = 'asphalt';
tire.Road_condition = 'dry';
tire.USE_MODE = 14;
tire.LONGVL = velocity;
tire.IP = pressure;
tire.IP_NOM = pressure;
tire.UNLOADED_RADIUS = unloaded_radius;
tire.WIDTH = section_width;
tire.ASPECT_RATIO = aspect_ratio/100;
tire.RIM_RADIUS = rim_radius;
tire.RIM_WIDTH = rim_width*0.0254;
tire.BOTTOMING_RADIUS = rim_radius;

%% Input ranges
tire.CAMMIN = deg2rad(min(extractfield(data,'IA')));
tire.CAMMAX = deg2rad(max(extractfield(data,'IA')));
tire.FZMIN = min(extractfield(data,'FZ'));
tire.FZMAX = max(extractfield(data,'FZ'));

%% Other:
tire.TYRE_MASS = tireidstruct.mass; % TODO: are these needed? no other belt/mass dynamics are captured...

%% Loaded radius and rolling radius fits

tire.FNOMIN = nom_vertical_load;

idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS') | strcmp(extractfield(data,'test_type'),'CORNERING') | strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') | strcmp(extractfield(data,'test_type'),'COMBINED');
p_bins = sep_bin(extractfield(data(idx),'P'));
i_p_nom = find(pressure/1000>p_bins,1,'last');
% fz_bins = sep_bin(extractfield(data(idx),'FZ'));
% i_fz_nom = find(nom_vertical_load>fz_bins,1,'last');

if any(strcmp(extractfield(data,'test_type'),'LOADED_RADIUS'))
    disp('###############################################################################')
    disp('Fitting LOADED_RADIUS tests')
    disp('###############################################################################')

    idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS');
    [T_bins,Temp] = sep_bin(extractfield(data(idx),'T'),0.8);
    i_T_nom = find(Temp>T_bins,1,'last');
    
    n_points = any(extractfield(data(idx),'N')>1); % any wheel speeds great than 1 rad/s (check if wheelspeed is available)
    
    % align 0-crossing of rho-FZ equation to find QRE0, QV1 and QRC1:
    N_bins = sep_bin(extractfield(data(idx),'N'));
    IA_bins = sep_bin(extractfield(data(idx),'IA'));
    [j,k]=meshgrid(1:length(N_bins)-1,1:length(IA_bins)-1);
    j=j(:);
    k=k(:);
    rho0 = zeros(size(j));
    ia0 = zeros(size(j));
    n0 = zeros(size(j));
    for i = 1:length(j)
        idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS') & extractfield(data,'N_mean') > N_bins(j(i)) & extractfield(data,'N_mean') < N_bins(j(i)+1) & extractfield(data,'IA_mean') > IA_bins(k(i)) & extractfield(data,'IA_mean') < IA_bins(k(i)+1);
        if any(idx)
            [~,rho0(i)] = lin_orth_reg([extractfield(data(idx),'FZ')',tire.UNLOADED_RADIUS-extractfield(data(idx),'RL')'/100]);
            ia0(i) = mean(extractfield(data(idx),'IA'));
            n0(i) = mean(extractfield(data(idx),'N'));
        else
            rho0(i) = NaN;
            ia0(i) = NaN;
            n0(i) = NaN;
        end
    end
    rho0(isnan(rho0)) = [];
    ia0(isnan(ia0)) = [];
    n0(isnan(n0)) = [];
    y = rho0;
    if n_points
        x = [-(1-cosd(ia0))./cosd(ia0), -tire.UNLOADED_RADIUS*(n0*pi/30*tire.UNLOADED_RADIUS/tire.LONGVL).^2, -tire.UNLOADED_RADIUS*ones(size(y))];
    else
        x = [-(1-cosd(ia0))./cosd(ia0), -tire.UNLOADED_RADIUS*ones(size(y))];
    end
    [~,rem] = rmoutliers(y);
    if sum(~rem)>size(x,2)
        y(rem,:) = [];
        x(rem,:) = [];
    end
    b = x\y;
    % NON ADAMS-CAR PARAMETER FIT (ADJUST RHO BASED ON CAMBER ANGLE):
    tire.QRC1 = max(0,b(1));
    if n_points
        tire.QV1 = max(0,b(2));
        tire.QRE0 = 1+b(3);
    else
        tire.QRE0 = 1+b(2);
    end
    % rho fitting eq 9
    rho = @(tire,data) max((tire.UNLOADED_RADIUS*(tire.QRE0+tire.QV1*((extractfield(data,'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL).^2)-extractfield(data,'RL')/100).*cos(deg2rad(extractfield(data,'IA'))) + tire.QRC1 * (1 - cos(deg2rad(extractfield(data,'IA')))),0);
    
    % VERTICAL_STIFFNESS fit
    idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS');
    x = rho(tire,data(idx));
    y = extractfield(data(idx),'FZ');
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    tire.VERTICAL_STIFFNESS = x'\y'; % linear regression w/ no intercept TODO: implement an orthogonal/deming regression w/ no intercept
    
    % Fz equation 8 fitting
    % fz = @(tire,data) (tire.QRE0 - tire.QV2*abs(extractfield(data,'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL - tire.QFCX1*extractfield(data,'FX')/tire.FNOMIN - tire.QFCY1*extractfield(data,'FY')/tire.FNOMIN + tire.QFCG1*deg2rad(extractfield(data,'IA')).^2 ).*(1 + tire.QPFZ1*(extractfield(data,'P')*1000 - tire.IP_NOM)/tire.IP_NOM).*(tire.QFZ1*rho(tire,data)/tire.UNLOADED_RADIUS + tire.QFZ2*(rho(tire,data)/tire.UNLOADED_RADIUS).^2 + tire.QFZ3*rho(tire,data)/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data,'IA')).^2).*tire.FNOMIN;
    % basic rho vs fz fitting: QFZ1, QFZ2 (V=0,IA=0,P=nominal) & extractfield(data,'T_mean') > T_bins(i_T_nom) & extractfield(data,'T_mean') < T_bins(i_T_nom+1)
    idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS') & extractfield(data,'V_mean') < 1 & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) < 0.5;
    x = [rho(tire,data(idx))/tire.UNLOADED_RADIUS; (rho(tire,data(idx))/tire.UNLOADED_RADIUS).^2]*tire.QRE0*tire.FNOMIN;
    y = extractfield(data(idx),'FZ');
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    % pnorm_rmse(y',x'*b)
    tire.QFZ1 = b(1);
    tire.QFZ2 = b(2);
    % gamma/Fy vs fz fitting: QFZ3 -- QFCY1, QFCG1 left at 0 (V=0,IA>0,P=nominal) & extractfield(data,'T_mean') > T_bins(i_T_nom) & extractfield(data,'T_mean') < T_bins(i_T_nom+1)
    idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS') & extractfield(data,'V_mean') < 1 & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) > 0.5;
    if any(idx)
        b = mean(rmoutliers((extractfield(data(idx),'FZ')/tire.FNOMIN./tire.QRE0 - tire.QFZ1*rho(tire,data(idx))/tire.UNLOADED_RADIUS - tire.QFZ2*(rho(tire,data(idx))/tire.UNLOADED_RADIUS).^2)./(rho(tire,data(idx))/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2)));
        tire.QFZ3 = b;
    end
    % pnorm_rmse(extractfield(data(idx),'FZ'),fz(tire,data(idx)),pnorm)
    % V/Fx vs fz fitting: QV2 -- QFCX1 left at 0 (P=nominal) & extractfield(data,'T_mean') > T_bins(i_T_nom) & extractfield(data,'T_mean') < T_bins(i_T_nom+1)
    if n_points
        idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS') & extractfield(data,'V_mean') > 1 & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1);
        b = mean(rmoutliers((extractfield(data(idx),'FZ')/tire.FNOMIN./(tire.QFZ1*rho(tire,data(idx))/tire.UNLOADED_RADIUS + tire.QFZ2*(rho(tire,data(idx))/tire.UNLOADED_RADIUS).^2 + tire.QFZ3*rho(tire,data(idx))/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2) - tire.QRE0)./(abs(extractfield(data(idx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL)));
        tire.QV2 = b;
    end
    % pnorm_rmse(extractfield(data(idx),'FZ'),fz(tire,data(idx)),pnorm)
    % dpi vs fz fitting (P~=nominal) & extractfield(data,'T_mean') > T_bins(i_T_nom) & extractfield(data,'T_mean') < T_bins(i_T_nom+1)
    idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS');
    p_points = length(unique(discretize(extractfield(data(idx),'P'),p_bins)));
    if p_points>1
        idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        x = (extractfield(data(idx),'P')*1000-tire.IP_NOM)/tire.IP_NOM;
        y = extractfield(data(idx),'FZ')./(tire.QRE0 - tire.QV2*abs(extractfield(data(idx),'N'))*tire.UNLOADED_RADIUS/tire.LONGVL - tire.QFCX1*extractfield(data(idx),'FX')/tire.FNOMIN - tire.QFCY1*extractfield(data(idx),'FY')/tire.FNOMIN + tire.QFCG1*deg2rad(extractfield(data(idx),'IA')).^2 )./(tire.QFZ1*rho(tire,data(idx))/tire.UNLOADED_RADIUS + tire.QFZ2*(rho(tire,data(idx))/tire.UNLOADED_RADIUS).^2 + tire.QFZ3*rho(tire,data(idx))/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2)/tire.FNOMIN - 1;
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        % pnorm_rmse(y',x'*b)
        tire.QPFZ1 = b;
    else
        warning('TyreFit_PAC2002: parameter QPFZ1 skipped due to lack of P data points in LOADED_RADIUS tests.')
    end
    
    % Final tuning of LOADED_RADIUS parameters & extractfield(data,'T_mean') > T_bins(i_T_nom) & extractfield(data,'T_mean') < T_bins(i_T_nom+1)
    disp('Final tuning of LOADED_RADIUS parameters. Hit "Stop" to end at current point and continue:')
    idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS');
    % 4 scenarios: wheelspeed available or not, different pressures tested or not:
    if n_points
        if p_points > 1
            p = [tire.QRE0,tire.QV1,tire.QV2,tire.QFCX1,tire.QFCY1,tire.QFCG1,tire.QPFZ1,tire.QFZ1,tire.QFZ2,tire.QFZ3,tire.QRC1];
            lb = -inf*ones(size(p));
            ub = inf*ones(size(p));
            lb(4:5) = [-1 -1];
            ub(4:5) = [1 1];
            rhop = @(tire,data,p) max((tire.UNLOADED_RADIUS*(p(1)+p(2)*((extractfield(data,'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL).^2)-extractfield(data,'RL')/100).*cos(deg2rad(extractfield(data,'IA'))) + p(11) * (1 - cos(deg2rad(extractfield(data,'IA')))),0);
            fun = @(p) pnorm_rmse(extractfield(data(idx),'FZ'), ((p(1) - p(3)*abs(extractfield(data(idx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL - p(4)*extractfield(data(idx),'FX')/tire.FNOMIN - p(5)*extractfield(data(idx),'FY')/tire.FNOMIN + p(6)*deg2rad(extractfield(data(idx),'IA')).^2 ).*(1 + p(7)*(extractfield(data(idx),'P')*1000 - tire.IP_NOM)/tire.IP_NOM).*(p(8)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS + p(9)*(rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS).^2 + p(10)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2).*tire.FNOMIN),pnorm);
        else
            p = [tire.QRE0,tire.QV1,tire.QV2,tire.QFCX1,tire.QFCY1,tire.QFCG1,tire.QFZ1,tire.QFZ2,tire.QFZ3,tire.QRC1];
            lb = -inf*ones(size(p));
            ub = inf*ones(size(p));
            lb(4:5) = [-1 -1];
            ub(4:5) = [1 1];
            rhop = @(tire,data,p) max((tire.UNLOADED_RADIUS*(p(1)+p(2)*((extractfield(data,'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL).^2)-extractfield(data,'RL')/100).*cos(deg2rad(extractfield(data,'IA'))) + p(10) * (1 - cos(deg2rad(extractfield(data,'IA')))),0);
            fun = @(p) pnorm_rmse(extractfield(data(idx),'FZ'), ((p(1) - p(3)*abs(extractfield(data(idx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL - p(4)*extractfield(data(idx),'FX')/tire.FNOMIN - p(5)*extractfield(data(idx),'FY')/tire.FNOMIN + p(6)*deg2rad(extractfield(data(idx),'IA')).^2 ).*(p(7)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS + p(8)*(rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS).^2 + p(9)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2).*tire.FNOMIN),pnorm);
        end
    else
        if p_points > 1
            p = [tire.QRE0,tire.QFCX1,tire.QFCY1,tire.QFCG1,tire.QPFZ1,tire.QFZ1,tire.QFZ2,tire.QFZ3,tire.QRC1];
            lb = -inf*ones(size(p));
            ub = inf*ones(size(p));
            lb(2:3) = [-1 -1];
            ub(2:3) = [1 1];
            rhop = @(tire,data,p) max((tire.UNLOADED_RADIUS*p(1)-extractfield(data,'RL')/100).*cos(deg2rad(extractfield(data,'IA'))) + p(9) * (1 - cos(deg2rad(extractfield(data,'IA')))),0);
            fun = @(p) pnorm_rmse(extractfield(data(idx),'FZ'), ((p(1) - p(2)*extractfield(data(idx),'FX')/tire.FNOMIN - p(3)*extractfield(data(idx),'FY')/tire.FNOMIN + p(4)*deg2rad(extractfield(data(idx),'IA')).^2 ).*(1 + p(5)*(extractfield(data(idx),'P')*1000 - tire.IP_NOM)/tire.IP_NOM).*(p(6)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS + p(7)*(rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS).^2 + p(8)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2).*tire.FNOMIN),pnorm);
        else
            p = [tire.QRE0,tire.QFCX1,tire.QFCY1,tire.QFCG1,tire.QFZ1,tire.QFZ2,tire.QFZ3,tire.QRC1];
            lb = -inf*ones(size(p));
            ub = inf*ones(size(p));
            lb(2:3) = [-1 -1];
            ub(2:3) = [1 1];
            rhop = @(tire,data,p) max((tire.UNLOADED_RADIUS*p(1)-extractfield(data,'RL')/100).*cos(deg2rad(extractfield(data,'IA'))) + p(8) * (1 - cos(deg2rad(extractfield(data,'IA')))),0);
            fun = @(p) pnorm_rmse(extractfield(data(idx),'FZ'), ((p(1) - p(2)*extractfield(data(idx),'FX')/tire.FNOMIN - p(3)*extractfield(data(idx),'FY')/tire.FNOMIN + p(4)*deg2rad(extractfield(data(idx),'IA')).^2 ).*(p(5)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS + p(6)*(rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS).^2 + p(7)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2).*tire.FNOMIN),pnorm);
        end
    end
    opts = optimoptions('fmincon','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    tic;
    p = fmincon(fun,p,[],[],[],[],lb,ub,[],opts);
    t=toc;
    delete(gcf);
    if n_points
        if p_points > 1
            tire.QRE0 = p(1);
            tire.QV1 = p(2);
            tire.QV2 = p(3);
            tire.QFCX1 = p(4);
            tire.QFCY1 = p(5);
            tire.QFCG1 = p(6);
            tire.QPFZ1 = p(7);
            tire.QFZ1 = p(8);
            tire.QFZ2 = p(9);
            tire.QFZ3 = p(10);
            tire.QRC1 = p(11);
        else
            tire.QRE0 = p(1);
            tire.QV1 = p(2);
            tire.QV2 = p(3);
            tire.QFCX1 = p(4);
            tire.QFCY1 = p(5);
            tire.QFCG1 = p(6);
            tire.QFZ1 = p(7);
            tire.QFZ2 = p(8);
            tire.QFZ3 = p(9);
            tire.QRC1 = p(10);
        end
    else
        if p_points > 1
            tire.QRE0 = p(1);
            tire.QFCX1 = p(2);
            tire.QFCY1 = p(3);
            tire.QFCG1 = p(4);
            tire.QPFZ1 = p(5);
            tire.QFZ1 = p(6);
            tire.QFZ2 = p(7);
            tire.QFZ3 = p(8);
            tire.QRC1 = p(9);
        else
            tire.QRE0 = p(1);
            tire.QFCX1 = p(2);
            tire.QFCY1 = p(3);
            tire.QFCG1 = p(4);
            tire.QFZ1 = p(5);
            tire.QFZ2 = p(6);
            tire.QFZ3 = p(7);
            tire.QRC1 = p(8);
        end
    end
    % check fit:
    disp(['Fitting complete! time: ' sprintf('%.1f',t) ' s, RMSE: ' sprintf('%.1f',fun(p)) ' N'])
    
    % figure
    % plot(extractfield(data(idx),'FZ'),'.-','DisplayName','FZ')
    % hold on
    % plot((tire.QRE0 - tire.QV2*abs(extractfield(data(idx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL - tire.QFCX1*extractfield(data(idx),'FX')/tire.FNOMIN - tire.QFCY1*extractfield(data(idx),'FY')/tire.FNOMIN + tire.QFCG1*deg2rad(extractfield(data(idx),'IA')).^2 ).*(1 + tire.QPFZ1*(extractfield(data(idx),'P')*1000 - tire.IP_NOM)/tire.IP_NOM).*(tire.QFZ1*rho(tire,data(idx))/tire.UNLOADED_RADIUS + tire.QFZ2*(rho(tire,data(idx))/tire.UNLOADED_RADIUS).^2 + tire.QFZ3*rho(tire,data(idx))/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2).*tire.FNOMIN,'.-','DisplayName','Regression')
    % plot(((p(1) - p(3)*abs(extractfield(data(idx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL - p(4)*extractfield(data(idx),'FX')/tire.FNOMIN - p(5)*extractfield(data(idx),'FY')/tire.FNOMIN + p(6)*deg2rad(extractfield(data(idx),'IA')).^2 ).*(1 + p(7)*(extractfield(data(idx),'P')*1000 - tire.IP_NOM)/tire.IP_NOM).*(p(8)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS + p(9)*(rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS).^2 + p(10)*rhop(tire,data(idx),p)/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2).*tire.FNOMIN),'.-','DisplayName','Fit')
    % plot(extractfield(data(idx),'FX'),'DisplayName','FX')
    % plot(extractfield(data(idx),'FY'),'DisplayName','FY')
    % plot(extractfield(data(idx),'V')*10,'DisplayName','V*10')
    % plot(extractfield(data(idx),'IA')*100,'DisplayName','IA*100')
    % plot(extractfield(data(idx),'N'),'DisplayName','N')
    % plot(extractfield(data(idx),'P')*10,'DisplayName','P*10')
    % plot(extractfield(data(idx),'RL')*10,'DisplayName','RL*10')
    % plot(extractfield(data(idx),'SA')*1000,'--','DisplayName','SA*1000')
    % plot(extractfield(data(idx),'SL')*1000,'--','DisplayName','SL*1000')
    % plot(extractfield(data(idx),'RST')*10,'--','DisplayName','RST*10')
    % plot(extractfield(data(idx),'TSTC')*10,'--','DisplayName','TSTC*10')
    % legend show
    % plot(extractfield(data(idx),'ET'),(tire.QRE0 - tire.QV2*abs(extractfield(data(idx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL - p(4)*extractfield(data(idx),'FX')/tire.FNOMIN - p(5)*extractfield(data(idx),'FY')/tire.FNOMIN + p(6)*deg2rad(extractfield(data(idx),'IA')).^2 ).*(1 + tire.QPFZ1*(extractfield(data(idx),'P')*1000 - tire.IP_NOM)/tire.IP_NOM).*(tire.QFZ1*rho(tire,data(idx))/tire.UNLOADED_RADIUS + tire.QFZ2*(rho(tire,data(idx))/tire.UNLOADED_RADIUS).^2 + tire.QFZ3*rho(tire,data(idx))/tire.UNLOADED_RADIUS.*deg2rad(extractfield(data(idx),'IA')).^2).*tire.FNOMIN,'.-')
    
    % Effective Rolling Radius eq 11 fitting: DREFF BREFF FREFF
    idx = strcmp(extractfield(data,'test_type'),'LOADED_RADIUS') & extractfield(data,'N_mean')>10 & extractfield(data,'V_mean')>5 &abs(extractfield(data,'FX_mean'))<200 & extractfield(data,'T_mean') > T_bins(i_T_nom) & extractfield(data,'T_mean') < T_bins(i_T_nom+1); 
    if any(idx)
        RE_data = (extractfield(data(idx),'V')/3.6)./(extractfield(data(idx),'N')*pi/30);
        rhoFz0 = tire.FNOMIN/tire.VERTICAL_STIFFNESS;
        x = rho(tire,data(idx))/rhoFz0;
        y = -(RE_data - (tire.UNLOADED_RADIUS*tire.QRE0 + tire.QV1*tire.UNLOADED_RADIUS*((extractfield(data(idx),'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL).^2))/rhoFz0;
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
        opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
        p = lsqcurvefit(fun,p0,x,y,lb,ub,opts);
        tire.DREFF = p(1);
        tire.BREFF = p(2);
        tire.FREFF = p(3);
        % Re = @(tire,data) tire.UNLOADED_RADIUS*tire.QRE0 + tire.QV1*tire.UNLOADED_RADIUS*((extractfield(data,'N')*pi/30)*tire.UNLOADED_RADIUS/tire.LONGVL).^2 - rhoFz0 * ( tire.DREFF * atan( tire.BREFF * rho(tire,data)/rhoFz0 ) + tire.FREFF * rho(tire,data)/rhoFz0 );
        
        if any([data.SL_flag]) % if SL isn't provided, need to calculate after fitting to data
            for i = find([data.SL_flag])
                RE = @(tire,data) tire.UNLOADED_RADIUS*tire.QRE0 + tire.QV1*tire.UNLOADED_RADIUS*(((extractfield(data,'N')*pi/30)*tire.UNLOADED_RADIUS)/tire.LONGVL).^2 - tire.FNOMIN/tire.VERTICAL_STIFFNESS*(tire.DREFF*atan(tire.BREFF*rho(tire,data)/( tire.FNOMIN/tire.VERTICAL_STIFFNESS))+tire.FREFF*rho(tire,data)/( tire.FNOMIN/tire.VERTICAL_STIFFNESS));
                data(i).SL = RE(tire,data(i))'.*(data(i).N*pi/30)./(data(i).V/3.6) - 1;
            end
        end
    else
        warning('TyreFit_PAC2002: No valid data for Effective Radius tests provided, fitting skipped.')
    end
else
    warning('TyreFit_PAC2002: No LOADED_RADIUS tests provided, fitting skipped.')
end

%% Pure Longitudinal Slip Fits

if any(strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE'))
    disp('###############################################################################')
    disp('Fitting DRIVE_BRAKE tests')
    disp('###############################################################################')
    
    tire.KPUMIN = min(extractfield(data,'SL'));
    tire.KPUMAX = max(extractfield(data,'SL'));

    idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE');
    list = find(idx);
    disp('Pre-Fitting Magic Curves for DRIVE_BRAKE:')
    fprintf([repmat('_',1,length(list)) '\n\n']);
    if parallel
        B = zeros(size(list));
        C = zeros(size(list));
        D = zeros(size(list));
        E = zeros(size(list));
        Sh = zeros(size(list));
        Sv = zeros(size(list));
        data_in = struct();
        for j = 1:length(list)
            i = list(j);
            data_in(j).SL = data(i).SL;
            data_in(j).FX = data(i).FX;
        end
        parfor j = 1:length(list)
            grab = data_in(j);
            % Fit the B,C,D,E,Sh,Sv magic parameters to each indivual test
            [B(j),C(j),D(j),E(j),Sh(j),Sv(j)] = Magic_Fit_F(grab.SL,grab.FX);
            fprintf('\b|\n');
        end
        for j = 1:length(list)
            i = list(j);
            data(i).B=B(j);
            data(i).C=C(j);
            data(i).D=D(j);
            data(i).E=E(j);
            data(i).Sh=Sh(j);
            data(i).Sv=Sv(j);
        end
    else
        for i = find(idx)
            [data(i).B,data(i).C,data(i).D,data(i).E,data(i).Sh,data(i).Sv] = Magic_Fit_F(data(i).SL,data(i).FX);
            fprintf('\b|\n');
        end
    end
    
    % fit Cx: PCX1
    tire.PCX1 = mean(extractfield(data(idx),'C'));
    % fit Dx: PDX1 PDX2 PDX3 PPX3 PPX4
    % IA=0, P=nominal
    idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) < 0.5;
    y = extractfield(data(idx),'D')./extractfield(data(idx),'FZ_mean');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    tire.PDX1 = b(1);
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PDX2 = b(2);
    end
    % IA~=0, P=nominal
    idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) > 0.5;
    y = -((extractfield(data(idx),'D')./extractfield(data(idx),'FZ_mean'))./(tire.PDX1 + tire.PDX2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)-1);
    x = (deg2rad(extractfield(data(idx),'IA_mean')).^2);
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PDX3 = b;
    end
    % P~=nominal
    idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE');
    p_points = length(unique(discretize(extractfield(data(idx),'P'),p_bins)));
    if p_points>2
        idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        x = [(extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM; ((extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM).^2];
        y = extractfield(data(idx),'D')./extractfield(data(idx),'FZ_mean')./(tire.PDX1 + tire.PDX2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1-tire.PDX3*deg2rad(extractfield(data(idx),'IA_mean')).^2)-1;
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.PPX3 = b(1);
            tire.PPX4 = b(2);
        end
    elseif p_points==2
        idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        x = (extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM;
        y = extractfield(data(idx),'D')./extractfield(data(idx),'FZ_mean')./(tire.PDX1 + tire.PDX2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1-tire.PDX3*deg2rad(extractfield(data(idx),'IA_mean')).^2)-1;
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.PPX3 = b(1);
            tire.PPX4 = 0;
        end
    else
        warning('TyreFit_PAC2002: parameter PPX3 and PPX4 skipped due to lack of P data points in LOADED_RADIUS tests.')
    end
    % Ex: PEX1 PEX2 PEX3 -- PEX4==0 (no asymmetry in longitudinal force curve)
    % PEX4, Fz=nominal
    idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE');
    y = extractfield(data(idx),'E');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN; ((extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN).^2];
    x(:,y<mean(y)-std(y) | y>mean(y)+std(y))=[];
    y(:,y<mean(y)-std(y) | y>mean(y)+std(y))=[];
    b=x'\y';
    tire.PEX1 = b(1);
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PEX2 = b(2);
        tire.PEX3 = b(3);
    end
    % Kx: PKX1 PKX2 PKX3 PPX1 PPX2
    % PPKX1-2-3, P=nominal
    idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1);
    y = extractfield(data(idx),'B').*extractfield(data(idx),'C').*extractfield(data(idx),'D')./(extractfield(data(idx),'FZ_mean'));
    x = (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN;
    x_bins = sep_bin(x);
    i_x_nom = find(0>x_bins,1,'last');
    fun = @(p,x) (p(1) + p(2)*x).*exp(p(3)*x);
    p = [0 0 0];
    p(1) = mean(y(abs(x)<0.1));
    if i_x_nom==1
        i = 2;
    else
        i = i_x_nom-1;
    end 
    p(2) = (p(1)-mean(y(x>x_bins(i)&x<x_bins(i+1))))/0.2 - exp(1);
    p(3) = mean(log(y./(p(1)+p(2)*x))./x);
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
    p = lsqcurvefit(fun,p,x,y,-inf*ones(size(p)),inf*ones(size(p)),opts);
    tire.PKX1 = p(1);
    tire.PKX2 = p(2);
    tire.PKX3 = p(3);
    % PPX1-2: P~=nominal;
    if p_points>2
        idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        x = [(extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM; ((extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM).^2];
        y = extractfield(data(idx),'B').*extractfield(data(idx),'C').*extractfield(data(idx),'D')./(extractfield(data(idx),'FZ_mean'))./(tire.PKX1 + tire.PKX2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./exp(tire.PKX3*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)-1;
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.PPX1 = b(1);
            tire.PPX2 = b(2);
        end
    elseif p_points==2
        idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        x = (extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM;
        y = extractfield(data(idx),'B').*extractfield(data(idx),'C').*extractfield(data(idx),'D')./(extractfield(data(idx),'FZ_mean'))./(tire.PKX1 + tire.PKX2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./exp(tire.PKX3*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)-1;
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.PPX1 = b(1);
            tire.PPX2 = 0;
        end
    else
        warning('TyreFit_PAC2002: parameter PPX1 and PPX2 skipped due to lack of P data points in LOADED_RADIUS tests.')
    end
    % Shx: PHX1 PHX2
    idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE');
    y = extractfield(data(idx),'Sh');
    x = [ones(size(y)); (extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PHX1 = b(1);
        tire.PHX2 = b(2);
    end
    % Svx: PVX1 PVX2
    y = extractfield(data(idx),'Sv')./(extractfield(data(idx),'FZ_mean'));
    x = [ones(size(y)); (extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PVX1 = b(1);
        tire.PVX2 = b(2);
    end

    % Final tuning of DRIVE_BRAKE parameters
    disp('Final tuning of DRIVE_BRAKE parameters. Hit "Stop" to end at current point and continue:')
    idx = strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE');
    if p_points>2
        p_list = 86:104;
        p = [tire.PCX1, tire.PDX1, tire.PDX2, tire.PDX3, tire.PEX1, tire.PEX2, tire.PEX3, tire.PEX4, tire.PKX1, tire.PKX2, tire.PKX3, tire.PHX1, tire.PHX2, tire.PVX1, tire.PVX2, tire.PPX1, tire.PPX2, tire.PPX3, tire.PPX4];
    elseif p_points==2
        p_list = [86:101,103];
        p = [tire.PCX1, tire.PDX1, tire.PDX2, tire.PDX3, tire.PEX1, tire.PEX2, tire.PEX3, tire.PEX4, tire.PKX1, tire.PKX2, tire.PKX3, tire.PHX1, tire.PHX2, tire.PVX1, tire.PVX2, tire.PPX1, tire.PPX3];
    else
        p_list = 86:100;
        p = [tire.PCX1, tire.PDX1, tire.PDX2, tire.PDX3, tire.PEX1, tire.PEX2, tire.PEX3, tire.PEX4, tire.PKX1, tire.PKX2, tire.PKX3, tire.PHX1, tire.PHX2, tire.PVX1, tire.PVX2];
    end
    fun = @(p) param_tuning(1,data(idx),p,p_list,tire);
    opts = optimoptions('fminunc','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    tic;
    p = fminunc(fun,p,opts);
    t=toc;
    delete(gcf);
    
    if p_points>2
        tire.PCX1 = p(1);        tire.PDX1 = p(2);        tire.PDX2 = p(3);
        tire.PDX3 = p(4);        tire.PEX1 = p(5);        tire.PEX2 = p(6);
        tire.PEX3 = p(7);        tire.PEX4 = p(8);        tire.PKX1 = p(9);
        tire.PKX2 = p(10);       tire.PKX3 = p(11);       tire.PHX1 = p(12);
        tire.PHX2 = p(13);       tire.PVX1 = p(14);       tire.PVX2 = p(15);
        tire.PPX1 = p(16);       tire.PPX2 = p(17);       tire.PPX3 = p(18);
        tire.PPX4 = p(19);
    elseif p_points==2
        tire.PCX1 = p(1);        tire.PDX1 = p(2);        tire.PDX2 = p(3);
        tire.PDX3 = p(4);        tire.PEX1 = p(5);        tire.PEX2 = p(6);
        tire.PEX3 = p(7);        tire.PEX4 = p(8);        tire.PKX1 = p(9);
        tire.PKX2 = p(10);       tire.PKX3 = p(11);       tire.PHX1 = p(12);
        tire.PHX2 = p(13);       tire.PVX1 = p(14);       tire.PVX2 = p(15);
        tire.PPX1 = p(16);       tire.PPX3 = p(17);
    else
        tire.PCX1 = p(1);        tire.PDX1 = p(2);        tire.PDX2 = p(3);
        tire.PDX3 = p(4);        tire.PEX1 = p(5);        tire.PEX2 = p(6);
        tire.PEX3 = p(7);        tire.PEX4 = p(8);        tire.PKX1 = p(9);
        tire.PKX2 = p(10);       tire.PKX3 = p(11);       tire.PHX1 = p(12);
        tire.PHX2 = p(13);       tire.PVX1 = p(14);       tire.PVX2 = p(15);
    end
    
    % check fit:
    Vcx=extractfield(data(idx),'V')/3.6;
    Vcy=tand(extractfield(data(idx),'SA')).*Vcx;
    Vsx=-extractfield(data(idx),'SL').*Vcx;
    Fz = extractfield(data(idx),'FZ');
    gamma = extractfield(data(idx),'IA')*pi/180.0;
    pio = extractfield(data(idx),'P')*1000.0;
    [Fxm,~,~,~,~] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
    disp(['Fitting complete! time: ' sprintf('%.1f',t) ' s, RMSE: ' sprintf('%.1f',pnorm_rmse(extractfield(data(idx),'FX'),Fxm)) ' N'])
else
    warning('TyreFit_PAC2002: No DRIVE_BRAKE tests provided, fitting skipped.')
end

%% Pure lateral slip fits

if any(strcmp(extractfield(data,'test_type'),'CORNERING'))

    disp('###############################################################################')
    disp('Fitting CORNERING tests')
    disp('###############################################################################')
    
    tire.ALPMIN = deg2rad(min(extractfield(data,'SA')));
    tire.ALPMAX = deg2rad(max(extractfield(data,'SA')));

    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    list = find(idx);
    disp('Pre-Fitting Magic Curves for CORNERING:')
    fprintf([repmat('_',1,length(list)) '\n\n']);
    if parallel
        B = zeros(size(list));
        C = zeros(size(list));
        D = zeros(size(list));
        E = zeros(size(list));
        Sh = zeros(size(list));
        Sv = zeros(size(list));
        data_in = struct();
        for j = 1:length(list)
            i = list(j);
            data_in(j).SA = data(i).SA;
            data_in(j).FY = data(i).FY;
        end
        parfor j = 1:length(list)
            grab = data_in(j);
            % Fit the B,C,D,E,Sh,Sv magic parameters to each indivual test
            [B(j),C(j),D(j),E(j),Sh(j),Sv(j)] = Magic_Fit_F(deg2rad(grab.SA),grab.FY);
            fprintf('\b|\n');
        end
        for j = 1:length(list)
            i = list(j);
            data(i).B=B(j);
            data(i).C=C(j);
            data(i).D=D(j);
            data(i).E=E(j);
            data(i).Sh=Sh(j);
            data(i).Sv=Sv(j);
        end
    else
        for i = find(idx)
            [data(i).B,data(i).C,data(i).D,data(i).E,data(i).Sh,data(i).Sv] = Magic_Fit_F(deg2rad(data(i).SA),data(i).FY);
            fprintf('\b|\n');
        end
    end

    % fit Cy: PCY1
    tire.PCY1 = mean(extractfield(data(idx),'C'));
    % fit Dy: PDY1 PDY2 PDY3 PPY3 PPY4
    % IA=0, P=nominal
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) < 0.5;
    y = extractfield(data(idx),'D')./extractfield(data(idx),'FZ_mean');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    tire.PDY1 = b(1);
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PDY2 = b(2);
    end
    % IA~=0, P=nominal
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) > 0.5;
    y = -((extractfield(data(idx),'D')./extractfield(data(idx),'FZ_mean'))./(tire.PDY1 + tire.PDY2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)-1);
    x = (deg2rad(extractfield(data(idx),'IA_mean')).^2);
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PDY3 = b;
    end
    % P~=nominal
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    p_points = length(unique(discretize(extractfield(data(idx),'P'),p_bins)));
    if p_points>2
        idx = strcmp(extractfield(data,'test_type'),'CORNERING') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        x = [(extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM; ((extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM).^2];
        y = extractfield(data(idx),'D')./extractfield(data(idx),'FZ_mean')./(tire.PDY1 + tire.PDY2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1-tire.PDY3*deg2rad(extractfield(data(idx),'IA_mean')).^2)-1;
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.PPY3 = b(1);
            tire.PPY4 = b(2);
        end
    elseif p_points==2
        idx = strcmp(extractfield(data,'test_type'),'CORNERING') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        x = (extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM;
        y = extractfield(data(idx),'D')./extractfield(data(idx),'FZ_mean')./(tire.PDY1 + tire.PDY2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1-tire.PDY3*deg2rad(extractfield(data(idx),'IA_mean')).^2)-1;
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.PPY3 = b(1);
            tire.PPY4 = 0;
        end
    else
        warning('TyreFit_PAC2002: parameter PPX3 and PPX4 skipped due to lack of P data points in LOADED_RADIUS tests.')
    end
    % Ey: PEY1 PEY2 -- PEY3 PEY4==0 (no asymmetry in longitudinal force curve)
    % PEX4, Fz=nominal
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    y = extractfield(data(idx),'E');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    x(:,y<mean(y)-std(y) | y>mean(y)+std(y))=[];
    y(:,y<mean(y)-std(y) | y>mean(y)+std(y))=[];
    b=x'\y';
    tire.PEY1 = b(1);
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PEY2 = b(2);
    end
    % By: PKY1 PKY2 PKY3 PPY1 PPY2
    % PKY1 PKY2: P=nominal, IA=0
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) < 0.5;
    y = extractfield(data(idx),'B').*extractfield(data(idx),'C').*extractfield(data(idx),'D')/tire.FNOMIN;
    x = (extractfield(data(idx),'FZ_mean'))./tire.FNOMIN;
    fun = @(p,x) p(1)*sin(2*atan(x./p(2)));
    p = [0 0];
    [p(1),i] = max(abs(y));
    p(1) = p(1)*sign(y(i));
    p(2) = x(i);
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
    p = lsqcurvefit(fun,p,x,y,-inf*ones(size(p)),inf*ones(size(p)),opts);
    tire.PKY1 = p(1);
    tire.PKY2 = p(2);
    % PKY3: P=nominal, IA~=0
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) > 0.5;
    tire.PKY3 = mean((1-extractfield(data(idx),'B').*extractfield(data(idx),'C').*extractfield(data(idx),'D')/tire.FNOMIN/tire.PKY1./(sin(2*atan(extractfield(data(idx),'FZ_mean')/tire.PKY2/tire.FNOMIN))))./abs(deg2rad(extractfield(data(idx),'IA_mean'))));
    % PPY1 PPY2: P~=nominal
    if p_points>1
        idx = strcmp(extractfield(data,'test_type'),'CORNERING') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        x = [(extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM; extractfield(data(idx),'FZ_mean')/tire.FNOMIN/tire.PKY2];
        y = extractfield(data(idx),'B').*extractfield(data(idx),'C').*extractfield(data(idx),'D')/tire.FNOMIN/tire.PKY1./(1-abs(deg2rad(extractfield(data(idx),'IA_mean'))));
        fun = @(p,x) (1 + p(1)*x(1,:)).*sin(2*atan(x(2,:)./(1+p(2)*x(1,:))));
        p = [0 0];
        opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
        p = lsqcurvefit(fun,p,x,y,-inf*ones(size(p)),inf*ones(size(p)),opts);
        tire.PPY1 = p(1);
        tire.PPY2 = p(2);
    else
        warning('TyreFit_PAC2002: parameter PPX3 and PPX4 skipped due to lack of P data points in LOADED_RADIUS tests.')
    end
    % Shy: PHY1 PHY2 PHY3
    % PHY1 PHY2: IA=0
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & abs(extractfield(data,'IA_mean')) < 0.5;
    y = extractfield(data(idx),'Sh');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    b=x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PHY1 = b(1);
        tire.PHY2 = b(2);
    end
    % PHY3: IA~=0
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & abs(extractfield(data,'IA_mean')) > 0.5;
    tire.PHY3 = mean((extractfield(data(idx),'Sh') - (tire.PHY1+tire.PHY2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN))./deg2rad(extractfield(data(idx),'IA_mean')));
    % Svy: PVY1 PVY2 PVY3 PVY4
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    y = extractfield(data(idx),'Sv')./(extractfield(data(idx),'FZ_mean'));
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN; deg2rad(extractfield(data(idx),'IA_mean')); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN.*deg2rad(extractfield(data(idx),'IA_mean'))];
    b=x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.PVY1 = b(1);
        tire.PVY2 = b(2);
        tire.PVY3 = b(3);
        tire.PVY4 = b(4);
    end

    % Final tuning of CORNERING parameters
    disp('Final tuning of CORNERING parameters. Hit "Stop" to end at current point and continue:')
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    if p_points>2
        p_list = 127:148;
        p = [tire.PCY1, tire.PDY1, tire.PDY2, tire.PDY3, tire.PEY1, tire.PEY2, tire.PEY3, tire.PEY4, tire.PKY1, tire.PKY2, tire.PKY3, tire.PHY1, tire.PHY2, tire.PHY3, tire.PVY1, tire.PVY2, tire.PVY3, tire.PVY4, tire.PPY1, tire.PPY2, tire.PPY3, tire.PPY4];
    elseif p_points == 2
        p_list = 127:147;
        p = [tire.PCY1, tire.PDY1, tire.PDY2, tire.PDY3, tire.PEY1, tire.PEY2, tire.PEY3, tire.PEY4, tire.PKY1, tire.PKY2, tire.PKY3, tire.PHY1, tire.PHY2, tire.PHY3, tire.PVY1, tire.PVY2, tire.PVY3, tire.PVY4, tire.PPY1, tire.PPY2, tire.PPY3];
    else
        p_list = 127:144;
        p = [tire.PCY1, tire.PDY1, tire.PDY2, tire.PDY3, tire.PEY1, tire.PEY2, tire.PEY3, tire.PEY4, tire.PKY1, tire.PKY2, tire.PKY3, tire.PHY1, tire.PHY2, tire.PHY3, tire.PVY1, tire.PVY2, tire.PVY3, tire.PVY4];
    end
    fun = @(p) param_tuning(2,data(idx),p,p_list,tire);
    opts = optimoptions('fminunc','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    tic;
    p = fminunc(fun,p,opts);
    t=toc;
    delete(gcf);
    if p_points > 2
        tire.PCY1 = p(1);        tire.PDY1 = p(2);        tire.PDY2 = p(3);
        tire.PDY3 = p(4);        tire.PEY1 = p(5);        tire.PEY2 = p(6);
        tire.PEY3 = p(7);        tire.PEY4 = p(8);        tire.PKY1 = p(9);
        tire.PKY2 = p(10);       tire.PKY3 = p(11);       tire.PHY1 = p(12);
        tire.PHY2 = p(13);       tire.PHY3 = p(14);       tire.PVY1 = p(15);
        tire.PVY2 = p(16);       tire.PVY3 = p(17);       tire.PVY4 = p(18);
        tire.PPY1 = p(19);       tire.PPY2 = p(20);       tire.PPY3 = p(21);
        tire.PPY4 = p(22);
    elseif p_points == 2
        tire.PCY1 = p(1);        tire.PDY1 = p(2);        tire.PDY2 = p(3);
        tire.PDY3 = p(4);        tire.PEY1 = p(5);        tire.PEY2 = p(6);
        tire.PEY3 = p(7);        tire.PEY4 = p(8);        tire.PKY1 = p(9);
        tire.PKY2 = p(10);       tire.PKY3 = p(11);       tire.PHY1 = p(12);
        tire.PHY2 = p(13);       tire.PHY3 = p(14);       tire.PVY1 = p(15);
        tire.PVY2 = p(16);       tire.PVY3 = p(17);       tire.PVY4 = p(18);
        tire.PPY1 = p(19);       tire.PPY2 = p(20);       tire.PPY3 = p(21);
    else
        tire.PCY1 = p(1);        tire.PDY1 = p(2);        tire.PDY2 = p(3);
        tire.PDY3 = p(4);        tire.PEY1 = p(5);        tire.PEY2 = p(6);
        tire.PEY3 = p(7);        tire.PEY4 = p(8);        tire.PKY1 = p(9);
        tire.PKY2 = p(10);       tire.PKY3 = p(11);       tire.PHY1 = p(12);
        tire.PHY2 = p(13);       tire.PHY3 = p(14);       tire.PVY1 = p(15);
        tire.PVY2 = p(16);       tire.PVY3 = p(17);       tire.PVY4 = p(18);
    end
    
    % check fit:
    Vcx=extractfield(data(idx),'V')/3.6;
    Vcy=tand(extractfield(data(idx),'SA')).*Vcx;
    Vsx=-extractfield(data(idx),'SL').*Vcx;
    Fz = extractfield(data(idx),'FZ');
    gamma = extractfield(data(idx),'IA')*pi/180.0;
    pio = extractfield(data(idx),'P')*1000.0;
    [~,Fym,~,~,~] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
    disp(['Fitting complete! time: ' sprintf('%.1f',t) ' s, RMSE: ' sprintf('%.1f',pnorm_rmse(extractfield(data(idx),'FY'),Fym)) ' N'])

    %% Aligning Torque, Pure Slip

    % TODO: need to improve the initial guess fitting!
    disp('###############################################################################')
    disp('Fitting Aligning Torque')
    disp('###############################################################################')

    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    list = find(idx);
    disp('Pre-Fitting Magic Curves for Aligning Torque:')
    fprintf([repmat('_',1,length(list)) '\n\n']);
    if parallel
        Bt = zeros(size(list));
        Ct = zeros(size(list));
        Dt = zeros(size(list));
        Et = zeros(size(list));
        Sht = zeros(size(list));
        Br = zeros(size(list));
        Dr = zeros(size(list));
        data_in = struct();
        for j = 1:length(list)
            i = list(j);
            data_in(j).V = data(i).V;
            data_in(j).SA = data(i).SA;
            data_in(j).SL = data(i).SL;
            data_in(j).FZ = data(i).FZ;
            data_in(j).IA = data(i).IA;
            data_in(j).P = data(i).P;
            data_in(j).FY = data(i).FY;
            data_in(j).MZ = data(i).MZ;
        end
        parfor j = 1:length(list)
            grab = data_in(j);
            % Fit the B,C,D,E,Sh,Sv magic parameters to each indivual test
            Vcx=grab.V/3.6;
            Vcy=tand(grab.SA).*Vcx;
            Vsx=-grab.SL.*Vcx;
            Fz = grab.FZ;
            gamma = deg2rad(grab.IA);
            pio = grab.P*1000.0;
            [~,~,~,~,coMF] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
            B = mean(coMF.By);
            C = mean(coMF.Cy);
            D = mean(coMF.Dy);
            E = mean(coMF.Ey);
            Sh = mean(coMF.Shy);
            Sv = mean(coMF.Svy);
            [Bt(j),Ct(j),Dt(j),Et(j),Sht(j),Br(j),Dr(j)] = Magic_Fit_M(deg2rad(grab.SA),grab.FY,grab.MZ,B,C,D,E,Sh,Sv);
            fprintf('\b|\n');
        end
        for j = 1:length(list)
            i = list(j);
            data(i).Bt = Bt(j);
            data(i).Ct = Ct(j);
            data(i).Dt = Dt(j);
            data(i).Et = Et(j);
            data(i).Sht = Sht(j);
            data(i).Br = Br(j);
            data(i).Dr = Dr(j);
        end
    else
        for i = find(idx)
            Vcx=data(i).V/3.6;
            Vcy=tand(data(i).SA).*Vcx;
            Vsx=-data(i).SL.*Vcx;
            Fz = data(i).FZ;
            gamma = deg2rad(data(i).IA);
            pio = data(i).P*1000.0;
            [~,~,~,~,coMF] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
            B = mean(coMF.By);
            C = mean(coMF.Cy);
            D = mean(coMF.Dy);
            E = mean(coMF.Ey);
            Sh = mean(coMF.Shy);
            Sv = mean(coMF.Svy);
            [data(i).Bt,data(i).Ct,data(i).Dt,data(i).Et,data(i).Sht,data(i).Br,data(i).Dr] = Magic_Fit_M(deg2rad(data(i).SA),data(i).FY,data(i).MZ,B,C,D,E,Sh,Sv);
            fprintf('\b|\n');
        end
    end

    % QBZ1, QBZ2, QBZ3 (IA=0)
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & abs(extractfield(data,'IA_mean')) < 0.5;
    y = extractfield(data(idx),'Bt');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN; ((extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN).^2];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QBZ1 = b(1);
        tire.QBZ2 = b(2);
        tire.QBZ3 = b(3);
    end
    % QBZ4, QBZ5=0 (IA>0)
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & abs(extractfield(data,'IA_mean')) > 0.5;
    y = (extractfield(data(idx),'Bt')./(tire.QBZ1 + tire.QBZ2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN + tire.QBZ3*((extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN).^2)-1);
    x = deg2rad(extractfield(data(idx),'IA_mean'));
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QBZ4 = b;
    end
    % QBZ9, QBZ10
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    y = extractfield(data(idx),'Br');
    By = zeros(size(y));
    Cy = zeros(size(y));
    list = find(idx);
    for j = 1:sum(idx)
        i = list(j);
        Vcx=data(i).V/3.6;
        Vcy=tand(data(i).SA).*Vcx;
        Vsx=-data(i).SL.*Vcx;
        Fz = data(i).FZ;
        gamma = deg2rad(data(i).IA);
        pio = data(i).P*1000.0;
        [~,~,~,~,coMF] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
        By(j) = mean(coMF.By);
        Cy(j) = mean(coMF.Cy);
    end
    x = [ones(size(y)); By.*Cy];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QBZ9 = b(1);
        tire.QBZ10 = b(2);
    end
    % QCZ1
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    y = extractfield(data(idx),'Ct');
    x = ones(size(y));
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QCZ1 = b;
    end
    % QDZ1, QDZ2 (P=nominal, IA=0)
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) < 0.5;
    y = extractfield(data(idx),'Dt')./(extractfield(data(idx),'FZ_mean'))/tire.UNLOADED_RADIUS*tire.FNOMIN;
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QDZ1 = b(1);
        tire.QDZ2 = b(2);
    end
    % QDZ3, QDZ4 (P=nominal, IA>0)
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) > 0.5;
    y = extractfield(data(idx),'Dt')./(extractfield(data(idx),'FZ_mean'))/tire.UNLOADED_RADIUS*tire.FNOMIN./(tire.QDZ1 + tire.QDZ2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)-1;
    x = [deg2rad(extractfield(data(idx),'IA_mean')); deg2rad(extractfield(data(idx),'IA_mean')).^2];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QDZ3 = b(1);
        tire.QDZ4 = b(2);
    end
    % QDZ6, QDZ7, QDZ8, QDZ9
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    y = extractfield(data(idx),'Dr')./(extractfield(data(idx),'FZ_mean'))/tire.UNLOADED_RADIUS;
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN; deg2rad(extractfield(data(idx),'IA_mean')); deg2rad(extractfield(data(idx),'IA_mean')).*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QDZ6 = b(1);
        tire.QDZ7 = b(2);
        tire.QDZ8 = b(3);
        tire.QDZ9 = b(4);
    end
    % QEZ1, QEZ2, QEZ3, QEZ4=0, QEZ5=0
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    y = extractfield(data(idx),'Et');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN; ((extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN).^2];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QEZ1 = b(1);
        tire.QEZ2 = b(2);
        tire.QEZ3 = b(3);
    end
    % QHZ1, QHZ2, QHZ3, QHZ4
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    y = extractfield(data(idx),'Sht');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN; deg2rad(extractfield(data(idx),'IA_mean')); deg2rad(extractfield(data(idx),'IA_mean')).*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    if pnorm_rmse(y',x'*b) < std(y)
        tire.QHZ1 = b(1);
        tire.QHZ2 = b(2);
        tire.QHZ3 = b(3);
        tire.QHZ4 = b(4);
    end
    % QPZ1 QPZ2
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    p_points = length(unique(discretize(extractfield(data(idx),'P'),p_bins)));
    if p_points>1
        idx = strcmp(extractfield(data,'test_type'),'CORNERING') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        % QPZ1
        y = (1-extractfield(data(idx),'Dt')./(extractfield(data(idx),'FZ_mean'))/tire.UNLOADED_RADIUS*tire.FNOMIN./(tire.QDZ1 + tire.QDZ2*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)./(1 + tire.QDZ3*deg2rad(extractfield(data(idx),'IA_mean')) + tire.QDZ4*deg2rad(extractfield(data(idx),'IA_mean')).^2));
        x = ((extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM);
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.QPZ1 = b;
        end
        % QPZ2
        y = ((extractfield(data(idx),'Dr')./(extractfield(data(idx),'FZ_mean'))/tire.UNLOADED_RADIUS-(tire.QDZ6 + tire.QDZ7*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN))./(tire.QDZ8*deg2rad(extractfield(data(idx),'IA_mean')) + tire.QDZ9*deg2rad(extractfield(data(idx),'IA_mean')).*(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN)-1);
        x = ((extractfield(data(idx),'P_mean')*1000-tire.IP_NOM)/tire.IP_NOM);
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.QPZ2 = b;
        end
    else
        warning('TyreFit_PAC2002: parameter PPX3 and PPX4 skipped due to lack of P data points in LOADED_RADIUS tests.')
    end

    % Final tuning of Aligning Torque parameters
    disp('Final tuning of Aligning Torque parameters. Hit "Stop" to end at current point and continue:')
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    if p_points > 1
        p_list = 174:200;
        p = [tire.QBZ1, tire.QBZ2, tire.QBZ3, tire.QBZ4, tire.QBZ5, tire.QBZ9, tire.QBZ10, tire.QCZ1, tire.QDZ1, tire.QDZ2, tire.QDZ3, tire.QDZ4, tire.QDZ6, tire.QDZ7, tire.QDZ8, tire.QDZ9, tire.QEZ1, tire.QEZ2, tire.QEZ3, tire.QEZ4, tire.QEZ5, tire.QHZ1, tire.QHZ2, tire.QHZ3, tire.QHZ4, tire.QPZ1, tire.QPZ2];
    else
        p_list = 174:198;
        p = [tire.QBZ1, tire.QBZ2, tire.QBZ3, tire.QBZ4, tire.QBZ5, tire.QBZ9, tire.QBZ10, tire.QCZ1, tire.QDZ1, tire.QDZ2, tire.QDZ3, tire.QDZ4, tire.QDZ6, tire.QDZ7, tire.QDZ8, tire.QDZ9, tire.QEZ1, tire.QEZ2, tire.QEZ3, tire.QEZ4, tire.QEZ5, tire.QHZ1, tire.QHZ2, tire.QHZ3, tire.QHZ4];
    end
    % p = zeros(size(p_list));
    fun = @(p) param_tuning(4,data(idx),p,p_list,tire);
    opts = optimoptions('fminunc','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    tic;
    p = fminunc(fun,p,opts);
    t=toc;
    delete(gcf);
    if p_points > 1
        tire.QBZ1 = p(1);        tire.QBZ2 = p(2);        tire.QBZ3 = p(3);
        tire.QBZ4 = p(4);        tire.QBZ5 = p(5);        tire.QBZ9 = p(6);
        tire.QBZ10 = p(7);       tire.QCZ1 = p(8);        tire.QDZ1 = p(9);
        tire.QDZ2 = p(10);       tire.QDZ3 = p(11);       tire.QDZ4 = p(12);
        tire.QDZ6 = p(13);       tire.QDZ7 = p(14);       tire.QDZ8 = p(15);
        tire.QDZ9 = p(16);       tire.QEZ1 = p(17);       tire.QEZ2 = p(18);
        tire.QEZ3 = p(19);       tire.QEZ4 = p(20);       tire.QEZ5 = p(21);
        tire.QHZ1 = p(22);       tire.QHZ2 = p(23);       tire.QHZ3 = p(24);
        tire.QHZ4 = p(25);       tire.QPZ1 = p(26);       tire.QPZ2 = p(27);
    else
        tire.QBZ1 = p(1);        tire.QBZ2 = p(2);        tire.QBZ3 = p(3);
        tire.QBZ4 = p(4);        tire.QBZ5 = p(5);        tire.QBZ9 = p(6);
        tire.QBZ10 = p(7);       tire.QCZ1 = p(8);        tire.QDZ1 = p(9);
        tire.QDZ2 = p(10);       tire.QDZ3 = p(11);       tire.QDZ4 = p(12);
        tire.QDZ6 = p(13);       tire.QDZ7 = p(14);       tire.QDZ8 = p(15);
        tire.QDZ9 = p(16);       tire.QEZ1 = p(17);       tire.QEZ2 = p(18);
        tire.QEZ3 = p(19);       tire.QEZ4 = p(20);       tire.QEZ5 = p(21);
        tire.QHZ1 = p(22);       tire.QHZ2 = p(23);       tire.QHZ3 = p(24);
        tire.QHZ4 = p(25);
    end
    
    % check fit:
    Vcx=extractfield(data(idx),'V')/3.6;
    Vcy=tand(extractfield(data(idx),'SA')).*Vcx;
    Vsx=-extractfield(data(idx),'SL').*Vcx;
    Fz = extractfield(data(idx),'FZ');
    gamma = extractfield(data(idx),'IA')*pi/180.0;
    pio = extractfield(data(idx),'P')*1000.0;
    [~,~,~,Mzm,~] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
    disp(['Fitting complete! time: ' sprintf('%.1f',t) ' s, RMSE: ' sprintf('%.1f',pnorm_rmse(extractfield(data(idx),'MZ'),Mzm)) ' Nm'])

else
    warning('TyreFit_PAC2002: No CORNERING tests provided, fitting skipped.')
end



%%  Combined Slip

if any(strcmp(extractfield(data,'test_type'),'COMBINED'))

    disp('###############################################################################')
    disp('Fitting COMBINED tests')
    disp('###############################################################################')
    
    idx = strcmp(extractfield(data,'test_type'),'COMBINED');
    % filter data inputs in individual tests
    xydata = [];
    for i = find(idx)
        % 2-way butterworth filter, no phase lag
        dt = mode(diff(data(i).ET));
        [b,a] = butter(4,5*dt*2);
        fx_f = filtfilt(b,a,data(i).FX);
        % inputs to fitting equations
        sa = deg2rad(data(i).SA);
        sl = data(i).SL;
        dfz = (-data(i).FZ-tire.FNOMIN)/tire.FNOMIN;
        % modelled force
        Vcx0=data(i).V/3.6;
        Vcy0=tand(data(i).SA).*Vcx0;
        Vsx0=-data(i).SL.*Vcx0;
        Fz0 = data(i).FZ;
        gamma0 = deg2rad(data(i).IA);
        pio0 = data(i).P*1000.0;
        [Fx0,~,~,~,~] = MF4_nopsi_adams(tire,Vcx0,Vcy0,Vsx0,Fz0,gamma0,pio0);
        fx0_f = filtfilt(b,a,Fx0);
        % keep only points where denominator is large
        id = abs(fx0_f)>0.1*max(abs(fx0_f));
        xydata = [xydata; sa(id) sl(id) dfz(id) fx_f(id)./fx0_f(id)];
    end
    
    % FX combined tests, find Gxa (RBX1, RBX2, RCX1, REX1, REX2, RHX1)
    p = [1 0 1 1 0 0]; % leave RBX2, REX2, RHX1 at 0. Start RBX1, RCX1, REX1 at 1;
    sa = xydata(:,1)';
    sl = xydata(:,2)';
    dfz = xydata(:,3)';
    y = xydata(:,4)';
    clear xydata
    
    sa_bins = sep_bin(sa);
    sa_means = zeros(1,length(sa_bins)-1);
    y_means = zeros(1,length(sa_bins)-1);
    for i = 1:length(sa_bins)-1
        sa_means(i) = mean(sa(sa>sa_bins(i) & sa<sa_bins(i+1)));
        y_means(i) = mean(y(sa>sa_bins(i) & sa<sa_bins(i+1)));
    end
    % add point (0,1), and mirror for fitting
    sa_tab = sortrows([sa_means,0,-sa_means;y_means,1,y_means]')';
    sa_means = sa_tab(1,:);
    y_means = sa_tab(2,:);
    % a rough fit for RBX1 (B) and REX1 (E), RCX1 (C) left at 1 -> assumes an asymptote of 0
    fun = @(p,x) cos(atan(p(1)*x - p(2)*(p(1)*x - atan(p(1)*x))));
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
    p0 = lsqcurvefit(fun,[1 1],sa_means,y_means,-inf*[1 1],inf*[1 1],opts);
    p(1) = p0(1);
    p(4) = p0(2);
    
    % try fitting to kappa-dependence (RBX2, need to adjust RBX1 and REX1 as well)
    dfz_bins = sep_bin(dfz);
    i_dfz_nom = find(0>dfz_bins,1,'last');
    id2 = dfz>dfz_bins(i_dfz_nom)&dfz<dfz_bins(i_dfz_nom+1);
    y2 = tan(acos(min(1,max(-1,y(id2)))));
    x2 = [sl(id2); abs(sa(id2))];
    fun = @(p2,x) p2(1)*cos(atan(p2(2)*x(1,:))).*x(2,:)-(p2(3)).*(p2(1)*cos(atan(p2(2)*x(1,:))).*x(2,:) + atan(p2(1)*cos(atan(p2(2)*x(1,:))).*x(2,:)));
    p2 = [p0(1) 1 p0(2)];
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
    p2 = lsqcurvefit(fun,p2,x2,y2,-inf*[1 1 1],inf*[1 1 1],opts);
    p(1) = p2(1);
    p(2) = p2(2);
    p(4) = p2(3);
    
    % find a function of E and dfz
    Edfz = zeros(1,length(dfz_bins)-1);
    dfz_mean = Edfz;
    dfz_mean(i_dfz_nom) = mean(dfz(id2));
    for i = 1:length(dfz_bins)-1
        if i == i_dfz_nom
            Edfz(i) = p2(3);
        else
            id3 = dfz>dfz_bins(i)&dfz<dfz_bins(i+1);
            y3 = tan(acos(min(1,max(-1,y(id3)))));
            x3 = [sl(id3); abs(sa(id3))];
            fun = @(p3,x) p2(1)*cos(atan(p2(2)*x(1,:))).*x(2,:)-(p3).*(p2(1)*cos(atan(p2(2)*x(1,:))).*x(2,:) + atan(p2(1)*cos(atan(p2(2)*x(1,:))).*x(2,:)));
            p3 = p2(3);
            opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
            p3 = lsqcurvefit(fun,p3,x3,y3,-inf,inf,opts);
            Edfz(i) = p3;
            dfz_mean(i) = mean(dfz(id3));
        end
    end
    b = [ones(size(Edfz)); dfz_mean]'\Edfz';
    p(4) = b(1);
    p(5) = b(2);
    
    % final fit:
    disp('Final tuning of Combined Longitudinal parameters. Hit "Stop" to end at current point and continue:')
    x = [sl; sa; dfz];
    fun = @(p,x) (cos(p(3)*atan((p(1)*cos(atan(p(2)*x(1,:)))).*(x(2,:)+p(6))-(p(4)+p(5)*x(3,:)).*((p(1)*cos(atan(p(2)*x(1,:)))).*(x(2,:)+p(6))-atan((p(1)*cos(atan(p(2)*x(1,:)))).*(x(2,:)+p(6)))))))./(cos(p(3)*atan((p(1)*cos(atan(p(2)*x(1,:)))).*p(6)-(p(4)+p(5)*x(3,:)).*((p(1)*cos(atan(p(2)*x(1,:)))).*p(6)-atan((p(1)*cos(atan(p(2)*x(1,:)))).*p(6))))));
    opts=optimoptions('lsqcurvefit','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    tic
    p = lsqcurvefit(fun,p,x,y,-inf*ones(size(p)),inf*ones(size(p)),opts);
    t=toc;
    delete(gcf);
    tire.RBX1 = p(1);
    tire.RBX2 = p(2);
    tire.RCX1 = p(3);
    tire.REX1 = p(4);
    tire.REX2 = p(5);
    tire.RHX1 = p(6);
    
    % check fit:
    Vcx=extractfield(data(idx),'V')/3.6;
    Vcy=tand(extractfield(data(idx),'SA')).*Vcx;
    Vsx=-extractfield(data(idx),'SL').*Vcx;
    Fz = extractfield(data(idx),'FZ');
    gamma = extractfield(data(idx),'IA')*pi/180.0;
    pio = extractfield(data(idx),'P')*1000.0;
    [Fxm,~,~,~,~] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
    disp(['Fitting complete! time: ' sprintf('%.1f',t) ' s, RMSE: ' sprintf('%.1f',pnorm_rmse(extractfield(data(idx),'FX'),Fxm)) ' N'])
    
    % FY combined tests, find Gyk (RBY1, RBY2, RBY3, RCY1, REY1, REY2, RHY1, RHY2, RVY1, RVY2, RVY3, RVY4, RVY5, RVY6)
    list = find(idx);
    disp('Pre-Fitting Magic Curves for FY Combined:')
    fprintf([repmat('_',1,length(list)) '\n\n']);
    if parallel
        Byk = zeros(size(list));
        Cyk = zeros(size(list));
        Eyk = zeros(size(list));
        Shyk = zeros(size(list));
        Dvyk = zeros(size(list));
        rvy5 = zeros(size(list));
        rvy6 = zeros(size(list));
        data_in = struct();
        for j = 1:length(list)
            i = list(j);
            %data_in(j).V = data(i).V;
            %data_in(j).SA = data(i).SA;
            data_in(j).SL = data(i).SL;
            %data_in(j).FZ = data(i).FZ;
            %data_in(j).IA = data(i).IA;
            %data_in(j).P = data(i).P;
            data_in(j).FY = data(i).FY;
        end
        parfor j = 1:length(list)
            grab = data_in(j);
            % Fit the B,C,D,E,Sh,Sv magic parameters to each indivual test
            %Vcx=grab.V/3.6;
            %Vcy=tand(grab.SA).*Vcx;
            %Vsx=-grab.SL.*Vcx;
            %Fz = grab.FZ;
            %gamma = grab.IA*pi/180.0;
            %pio = grab.P*1000.0;
            %[~,Fym,~,~,~] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
            [Byk(j),Cyk(j),Eyk(j),Shyk(j),Dvyk(j),rvy5(j),rvy6(j)] = Magic_Fit_CombFy(grab.SL,grab.FY);
            fprintf('\b|\n');
        end
        for j = 1:length(list)
            i = list(j);
            data(i).Byk = Byk(j);
            data(i).Cyk = Cyk(j);
            data(i).Eyk = Eyk(j);
            data(i).Shyk = Shyk(j);
            data(i).Dvyk = Dvyk(j);
            data(i).rvy5 = rvy5(j);
            data(i).rvy6 = rvy6(j);
        end
    else
        for i = find(idx)
            %Vcx=data(i).V/3.6;
            %Vcy=tand(data(i).SA).*Vcx;
            %Vsx=-data(i).SL.*Vcx;
            %Fz = data(i).FZ;
            %gamma = data(i).IA*pi/180.0;
            %pio = data(i).P*1000.0;
            %[~,Fym,~,~,~] = MF4_nopsi_adams(tire,Vcx,Vcy,0,Fz,gamma,pio);
            [data(i).Byk,data(i).Cyk,data(i).Eyk,data(i).Shyk,data(i).Dvyk,data(i).rvy5,data(i).rvy6] = Magic_Fit_CombFy(data(i).SL,data(i).FY);
            fprintf('\b|\n');
        end
    end
    
    sa_bins = sep_bin(extractfield(data(idx),'SA'));
    sa_points = length(unique(discretize(extractfield(data(idx),'SA_mean'),sa_bins)));
    % RBY1-2-3
    if sa_points > 2
        x = deg2rad(extractfield(data(idx),'SA_mean'));
        y = extractfield(data(idx),'Byk');
        fun = @(p,x) p(1)*cos(atan(p(2)*(x-p(3))));
        opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
        p = lsqcurvefit(fun,[1 1 1],x,y,-inf*[1 1 1],inf*[1 1 1],opts);
        tire.RBY1 = p(1);
        tire.RBY2 = p(2);
        tire.RBY3 = p(3);
    else
        x = deg2rad(extractfield(data(idx),'SA_mean'));
        y = extractfield(data(idx),'Byk');
        fun = @(p,x) p(1)*cos(atan(p(2)*(x)));
        opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
        p = lsqcurvefit(fun,[1 1],x,y,-inf*[1 1],inf*[1 1],opts);
        tire.RBY1 = p(1);
        tire.RBY2 = p(2);
    end
    
    % RCY1
    tire.RCY1 = mean(rmoutliers(extractfield(data(idx),'Cyk')));
    
    % REY1-2
    y = extractfield(data(idx),'Eyk');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    tire.REY1 = b(1);
    if pnorm_rmse(y',x'*b) < std(y)
        tire.REY2 = b(2);
    end
    
    % RHY1-2
    y = extractfield(data(idx),'Shyk');
    x = [ones(size(y)); (extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    tire.RHY1 = b(1);
    if pnorm_rmse(y',x'*b) < std(y)
        tire.RHY2 = b(2);
    end
    
    % RVY1-3
    Dy = zeros(1,sum(idx));
    for j = 1:sum(idx)
        i = list(j);
        Vcx=data(i).V/3.6;
        Vcy=tand(data(i).SA).*Vcx;
        Vsx=-data(i).SL.*Vcx;
        Fz = data(i).FZ;
        gamma = deg2rad(data(i).IA);
        pio = data(i).P*1000.0;
        [~,~,~,~,coMF] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
        Dy(j) = mean(coMF.Dy);
    end
    y = extractfield(data(idx),'Dvyk')./Dy;
    x = [(extractfield(data(idx),'FZ_mean')-tire.FNOMIN)/tire.FNOMIN; deg2rad(extractfield(data(idx),'IA_mean')); deg2rad(extractfield(data(idx),'SA_mean'))];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    fun = @(p,x) (p(1) + p(2)*x(1,:) + p(3)*x(2,:)).*cos(atan(p(4)*x(3,:)));
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax);
    p = lsqcurvefit(fun,[1 1 1 1],x,y,-inf*[1 1 1 1],inf*[1 1 1 1],opts);
    tire.RVY1 = p(1);
    tire.RVY2 = p(2);
    tire.RVY3 = p(3);
    tire.RVY4 = p(4);
    
    % RVY5-6
    tire.RVY5 = mean(rmoutliers(extractfield(data(idx),'rvy5')));
    tire.RVY6 = mean(rmoutliers(extractfield(data(idx),'rvy6')));
    
    % final fit:
    disp('Final tuning of Combined Lateral parameters. Hit "Stop" to end at current point and continue:')    
    
    if sa_points > 2
        p_list = 149:162;
        p = [tire.RBY1,tire.RBY2,tire.RBY3,tire.RCY1,tire.RHY1,tire.RVY1,tire.RVY2,tire.RVY3,tire.RVY4,tire.RVY5,tire.RVY6,tire.REY1,tire.REY2,tire.RHY2];
    else
        p_list = [149:150,152:162];
        p = [tire.RBY1,tire.RBY2,tire.RCY1,tire.RHY1,tire.RVY1,tire.RVY2,tire.RVY3,tire.RVY4,tire.RVY5,tire.RVY6,tire.REY1,tire.REY2,tire.RHY2];
    end
    
    fun = @(p) param_tuning(2,data(idx),p,p_list,tire);
    opts = optimoptions('fminunc','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    tic;
    p = fminunc(fun,p,opts);
    t=toc;
    delete(gcf);
    
    if sa_points > 2
        tire.RBY1 = p(1);        tire.RBY2 = p(2);
        tire.RBY3 = p(3);        tire.RCY1 = p(4);
        tire.RHY1 = p(5);        tire.RVY1 = p(6);
        tire.RVY2 = p(7);        tire.RVY3 = p(8);
        tire.RVY4 = p(9);        tire.RVY5 = p(10);
        tire.RVY6 = p(11);        tire.REY1 = p(12);
        tire.REY2 = p(13);        tire.RHY2 = p(14);
    else
        tire.RBY1 = p(1);        tire.RBY2 = p(2);
        tire.RCY1 = p(3);        tire.RHY1 = p(4);
        tire.RVY1 = p(5);        tire.RVY2 = p(6);
        tire.RVY3 = p(7);        tire.RVY4 = p(8);
        tire.RVY5 = p(9);        tire.RVY6 = p(10);
        tire.REY1 = p(11);        tire.REY2 = p(12);
        tire.RHY2 = p(13);
    end
    
    % check fit:
    disp(['Fitting complete! time: ' sprintf('%.1f',t) ' s, RMSE: ' sprintf('%.1f',fun(p)) ' N'])
    
    % Aligning torque combined fit SSZ1-4:
    Vcx=extractfield(data(idx),'V')/3.6;
    Vcy=tand(extractfield(data(idx),'SA')).*Vcx;
    Vsx=-extractfield(data(idx),'SL').*Vcx;
    Fz = extractfield(data(idx),'FZ');
    gamma = extractfield(data(idx),'IA')*pi/180.0;
    pio = extractfield(data(idx),'P')*1000.0;
    y = (extractfield(data(idx),'MZ') - Out4(@MF4_nopsi_adams,tire,Vcx,Vcy,Vsx,Fz,gamma,pio))./extractfield(data(idx),'FX')./tire.UNLOADED_RADIUS; % with SSZ1-4==0, Mz == -t*Fy' + Mzr (+0*Fx)
    x = [ones(size(y)); extractfield(data(idx),'FY')/tire.FNOMIN; deg2rad(extractfield(data(idx),'IA')); deg2rad(extractfield(data(idx),'IA')).*(extractfield(data(idx),'FZ')-tire.FNOMIN)/tire.FNOMIN];
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    b = x'\y';
    tire.SSZ1 = b(1);
    if pnorm_rmse(y',x'*b) < std(y)
        tire.SSZ2 = b(2);
        tire.SSZ3 = b(3);
        tire.SSZ4 = b(4);
    end
    
    % final fit:
    disp('Final tuning of Combined Aligning Torque parameters. Hit "Stop" to end at current point and continue:')
    p_list = 201:204;
    p = [tire.SSZ1,tire.SSZ2,tire.SSZ3,tire.SSZ4];
    fun = @(p) param_tuning(4,data(idx),p,p_list,tire);
    opts = optimoptions('fminunc','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    tic;
    p = fminunc(fun,p,opts);
    t=toc;
    delete(gcf);
    tire.SSZ1 = p(1);
    tire.SSZ2 = p(2);
    tire.SSZ3 = p(3);
    tire.SSZ4 = p(4);
    
    % check fit:
    disp(['Fitting complete! time: ' sprintf('%.1f',t) ' s, RMSE: ' sprintf('%.1f',fun(p)) ' Nm'])
    
else
    warning('TyreFit_PAC2002: No COMBINED tests provided, fitting skipped.')
end

%% Overturning Torque

if any(strcmp(extractfield(data,'test_type'),'CORNERING'))

    disp('###############################################################################')
    disp('Fitting Overturning Torque')
    disp('###############################################################################')

    % IA=0, P=nominal
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) < 0.5;
    y = extractfield(data(idx),'MX')./(extractfield(data(idx),'FZ'))/tire.UNLOADED_RADIUS;
    x = [extractfield(data(idx),'FY')/tire.FNOMIN; extractfield(data(idx),'FZ')/tire.FNOMIN];
    fun = @(p,x) p(2)*x(1,:) + p(3)*cos(p(4)*atan((p(5)*x(2,:)).^2)).*sin(p(6)*atan(p(7)*x(1,:))) + p(1);
    p = ones(1,7);
    b = [ones(size(y)); x(1,:)]'\y';
    p(1) = b(1);
    p(2) = b(2);
    y3 = y-p(2)*x(1,:)-p(1);
    p(3) = max(abs(y3));
    y4 = acos(y3/p(3));
    x4 = x(2,:).^2;
    p(4) = mean(y4(x4>0.75*max(x4)))*2/pi;
    p(5) = mean(rmoutliers(sqrt(abs(tan(y4/p(4))./x4))));
    y6 = asin(y4./cos(p(4)*atan((p(5)*x(2,:)).^2))/max(y4./cos(p(4)*atan((p(5)*x(2,:)).^2))));
    x6 = x(1,:);
    p(6) = mean(y6(x6>0.75*max(x6)))*2/pi;
    p(7) = mean(rmoutliers(abs(tan(y6/p(4))./x6)));
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    p = lsqcurvefit(fun,p,x,y,-inf*ones(size(p)),inf*ones(size(p)),opts);
    tire.QSX1 = p(1);
    tire.QSX3 = p(2);
    tire.QSX4 = p(3);
    tire.QSX5 = p(4);
    tire.QSX6 = p(5);
    tire.QSX8 = p(6);
    tire.QSX9 = p(7);
    
    % IA~=0, P=nominal
    idx = strcmp(extractfield(data,'test_type'),'CORNERING') & extractfield(data,'P_mean') > p_bins(i_p_nom) & extractfield(data,'P_mean') < p_bins(i_p_nom+1) & abs(extractfield(data,'IA_mean')) > 0.5;
    y = extractfield(data(idx),'MX')./(extractfield(data(idx),'FZ'))/tire.UNLOADED_RADIUS - tire.QSX1 - tire.QSX3*extractfield(data(idx),'FY')/tire.FNOMIN;
    x = [extractfield(data(idx),'FY')/tire.FNOMIN; extractfield(data(idx),'FZ')/tire.FNOMIN; deg2rad(extractfield(data(idx),'IA'))];
    fun = @(p,x) tire.QSX4*cos(tire.QSX5*atan((tire.QSX6*x(2,:)).^2)).*sin(p(2)*x(3,:)+tire.QSX8*atan(tire.QSX9*x(1,:))) + (p(3)*atan(p(4)*x(2,:)) - p(1)).*x(3,:);
    p = ones(1,4);
    y2 = (y - tire.QSX4*cos(tire.QSX5*atan((tire.QSX6*x(2,:)).^2)).*sin(tire.QSX8*atan(tire.QSX9*x(1,:))))./x(3,:);
    b = [ones(size(y)); x(2,:)]'\y2';
    p(1) = b(1);
    y5 = y2-p(1);
    p(3) = mean(y5(x(2,:)>0.75*max(x(2,:))))*2/pi;
    p(4) = mean(rmoutliers(abs(tan(y5/p(3))./x(2,:))));
    p(2) = mean((asin(max(-1,min(1,(y - (p(3)*atan(p(4)*x(2,:)) - p(1)).*x(3,:))./(tire.QSX4*cos(tire.QSX5*atan((tire.QSX6*x(2,:)).^2)))/max((y - (p(3)*atan(p(4)*x(2,:)) - p(1)).*x(3,:))./(tire.QSX4*cos(tire.QSX5*atan((tire.QSX6*x(2,:)).^2)))))))-tire.QSX8*atan(tire.QSX9*x(1,:)))./x(3,:));
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax,'UseParallel',parallel);
    p = lsqcurvefit(fun,p,x,y,-inf*ones(size(p)),inf*ones(size(p)),opts);
    tire.QSX2 = p(1);
    tire.QSX7 = p(2);
    tire.QSX10 = p(3);
    tire.QSX11 = p(4);
    
    % P~=nominal
    idx = strcmp(extractfield(data,'test_type'),'CORNERING');
    p_points = length(unique(discretize(extractfield(data(idx),'P'),p_bins)));
    if p_points>1
        idx = strcmp(extractfield(data,'test_type'),'CORNERING') & (extractfield(data,'P_mean') < p_bins(i_p_nom) | extractfield(data,'P_mean') > p_bins(i_p_nom+1));
        % QPX1
        y = ((tire.QSX10*atan(tire.QSX11*(extractfield(data(idx),'FZ')/tire.FNOMIN))-(extractfield(data(idx),'MX')./(extractfield(data(idx),'FZ'))/tire.UNLOADED_RADIUS - tire.QSX1 - tire.QSX3*extractfield(data(idx),'FY')/tire.FNOMIN - tire.QSX4*cos(tire.QSX5*atan((tire.QSX6*(extractfield(data(idx),'FZ')/tire.FNOMIN)).^2)).*sin(tire.QSX7*deg2rad(extractfield(data(idx),'IA'))+tire.QSX8*atan(tire.QSX9*extractfield(data(idx),'FY')/tire.FNOMIN)))./deg2rad(extractfield(data(idx),'IA')))/tire.QSX2-1);
        x = ((extractfield(data(idx),'P')*1000-tire.IP_NOM)/tire.IP_NOM);
        [y,rem] = rmoutliers(y);
        x(:,rem) = [];
        b = x'\y';
        if pnorm_rmse(y',x'*b) < std(y)
            tire.QPX1 = b;
        end
    else
        warning('TyreFit_PAC2002: parameter PPX3 and PPX4 skipped due to lack of P data points in LOADED_RADIUS tests.')
    end
    
    % final fit: TODO: this one takes a while, maybe a bad initial guess?
    disp('Final tuning of Overturning Torque parameters. Hit "Stop" to end at current point and continue:')
    if p_points>1
        p_list = 115:126;
        p = [tire.QSX1,tire.QSX2,tire.QSX3,tire.QSX4,tire.QSX5,tire.QSX6,tire.QSX7,tire.QSX8,tire.QSX9,tire.QSX10,tire.QSX11,tire.QPX1];
    else
        p_list = 115:125;
        p = [tire.QSX1,tire.QSX2,tire.QSX3,tire.QSX4,tire.QSX5,tire.QSX6,tire.QSX7,tire.QSX8,tire.QSX9,tire.QSX10,tire.QSX11];
    end
    fun = @(p) param_tuning(3,data(idx),p,p_list,tire);
    opts = optimoptions('fminunc','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    tic;
    p = fminunc(fun,p,opts);
    t=toc;
    delete(gcf);
    if p_points>1
        tire.QSX1 = p(1);        tire.QSX2 = p(2);        tire.QSX3 = p(3);
        tire.QSX4 = p(4);        tire.QSX5 = p(5);        tire.QSX6 = p(6);
        tire.QSX7 = p(7);        tire.QSX8 = p(8);        tire.QSX9 = p(9);
        tire.QSX10 = p(10);      tire.QSX11 = p(11);      tire.QPX1 = p(12);
    else
        tire.QSX1 = p(1);        tire.QSX2 = p(2);        tire.QSX3 = p(3);
        tire.QSX4 = p(4);        tire.QSX5 = p(5);        tire.QSX6 = p(6);
        tire.QSX7 = p(7);        tire.QSX8 = p(8);        tire.QSX9 = p(9);
        tire.QSX10 = p(10);      tire.QSX11 = p(11);
    end
    
    % check fit:
    disp(['Fitting complete! time: ' sprintf('%.1f',t) ' s, RMSE: ' sprintf('%.1f',fun(p)) ' Nm'])
    
else
    warning('TyreFit_PAC2002: No CORNERING tests provided, Overturning Torque fitting skipped.')
end


%% Transient, Relaxation Lengths

if any(strcmp(extractfield(data,'test_type'),'TRANSIENT'))

    disp('###############################################################################')
    disp('Fitting TRANSIENT tests')
    disp('###############################################################################')
    
    % Transient solution for variable Vcx and Vsy:
    % set: x == transient alpha
    %  Vx[t] == Vcx
    %  Vy[t] == Vsy
    %      s == sigma
    % x'[t] + Vx[t]*x[t]/s == -Vy[t]/s
    % dx[t] == int( Vx[T], T, [0 t] )
    % dy[t] == int( exp( dx[T]/s ) * Vy[T], T, [0 t] )
    %  x[t] == exp( - dx[t]/s ) * ( x[0] - dy[t]/s )
    dx = @(x) cumtrapz(x(:,1),x(:,2));
    dy = @(s,x) cumtrapz(x(:,1),exp(dx(x)/s).*x(:,3));
    xofun = @(s,x,x0) exp( -dx(x)/s ) .* ( x0 - dy(s,x)/s );
    
    idx = strcmp(extractfield(data,'test_type'),'TRANSIENT');
    list = find(idx);
    disp('Pre-Fitting Relaxation Lengths for FY:')
    fprintf([repmat('_',1,length(list)) '\n\n']);
    if parallel
        s_up = zeros(1,length(list));
        % s_down = zeros(1,length(list));
        data_in = struct();
        for j = 1:length(list)
            i = list(j);
            data_in(j).V = data(i).V;
            data_in(j).SA = data(i).SA;
            data_in(j).SL = data(i).SL;
            data_in(j).FZ = data(i).FZ;
            data_in(j).IA = data(i).IA;
            data_in(j).P = data(i).P;
            data_in(j).FY = data(i).FY;
            data_in(j).ET = data(i).ET;
        end
        parfor j = 1:length(list)
            grab = data_in(j);
            % modelled steady state force
            Vcx=grab.V/3.6;
            Vcy=tand(grab.SA).*Vcx;
            Vsx=-grab.SL.*Vcx;
            Fz = grab.FZ;
            gamma = deg2rad(grab.IA);
            pio = grab.P*1000.0;
            [~,Fy0,~,~,co] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
            
            % find the useful transients
            b_v = abs(grab.V)>2;
            b_sa = abs(grab.SA)>0.5;
            sgn_sa = sign(mean(grab.SA(b_sa)));
            i1 = find(diff(b_v&b_sa)>0);
            i1 = find(diff(grab.V(1:i1))<=0,1,'last')+1;
            i2 = (find((sgn_sa*(grab.FY-Fy0))<0&b_v&b_sa,1,'first')-1);
            if isempty(i2)
                i2 = find(diff(b_v&b_sa)<0)-2;
                i2 = find(abs(grab.V(i1:i2))>3.2,1,'last')+i1-2;
            end
            i_up = i1:i2; % 0 to SA
            % i1 = find(diff(b_v)>0&~b_sa(1:end-1));
            % i1 = find(diff(grab.V(1:i1))<=0,1,'last')+1;
            % i2 = (find((sgn_sa*(grab.FY(i1:end)-Fy0(i1:end)))>0,1,'first')+i1-2);
            % if isempty(i2)
            %     i2 = length(grab.ET);
            % end
            % i_down = i1:i2; % SA to 0
            
            % up test
            % data:
            t = grab.ET(i_up);
            vx = Vcx(i_up);
            vy = Vcy(i_up);
            xi = deg2rad(grab.SA(i_up));
            Fo = grab.FY(i_up);
            % Fm = Fy0(i_up);
            xo = zeros(size(xi));
            for k = 1:length(t)
                xm = min(tire.ALPMAX,abs(fzero(@(x) co.By(k)*x - co.Ey(k)*(co.By(k)*x-atan(co.By(k)*x)) - tan(pi/2/co.Cy),0)));
                xfun = @(x) Out2(@MF4_nopsi_adams,tire,vx(k),-tan(x).*vx(k),Vsx(i_up(k)),Fz(i_up(k)),gamma(i_up(k)),pio(i_up(k))) - Fo(k);
                if isfinite(xm) && (xfun(xm)>0)~=(xfun(-xm)>0)
                    xo(k) = fzero(xfun,[-xm,xm]);
                else
                    xo(k) = fzero(xfun,0);
                end
            end
            % transient solution equation:
            x0 = xo(1);
            fun = @(p,x) xofun(p,x,x0);
            x = [t, vx, vy];
            y = xo;
            opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax,'UseParallel',false);
            s_up(j) = lsqcurvefit(fun,0.2,x,y,0,inf,opts);
            
            % TODO: This fit might need better entry criteria. Check if the
            % transient 'xo' is actually rising/decaying towards xi, etc.
            % Check if which of up or down is better, does one produce
            % noisier results (noisy in the relaxation length fit output)?
            
            % % down test
            % % data:
            % t = grab.ET(i_down);
            % vx = Vcx(i_down);
            % vy = Vcy(i_down);
            % xi = deg2rad(grab.SA(i_down));
            % Fo = grab.FY(i_down);
            % % Fm = Fy0(i_down);
            % xo = zeros(size(xi));
            % for k = 1:length(t)
            %     xm = min(tire.ALPMAX,abs(fzero(@(x) co.By(k)*x - co.Ey(k)*(co.By(k)*x-atan(co.By(k)*x)) - tan(pi/2/co.Cy),0)));
            %     xfun = @(x) Out2(@MF4_nopsi_adams,tire,vx(k),-tan(x).*vx(k),Vsx(i_down(k)),Fz(i_down(k)),gamma(i_down(k)),pio(i_down(k))) - Fo(k);
            %     if isfinite(xm) && (xfun(xm)>0)~=(xfun(-xm)>0)
            %         xo(k) = fzero(xfun,[-xm,xm]);
            %     else
            %         xo(k) = fzero(xfun,0);
            %     end
            % end
            % % transient solution equation:
            % x0 = xo(1);
            % fun = @(p,x) xofun(p,x,x0);
            % x = [t, vx, vy];
            % y = xo;
            % opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax,'UseParallel',false);
            % s_down(j) = lsqcurvefit(fun,s_up(j),x,y,0,inf,opts);
            fprintf('\b|\n');
        end
        for j = 1:length(list)
            i = list(j);
            data(i).sigma_y_up = s_up(j);
            % data(i).sigma_y_down = s_down(j);
        end
    else
        for j = 1:length(list)
            i = list(j);

            % modelled steady state forceVcx=data(i).V/3.6;
            Vcx=data(i).V/3.6;
            Vcy=tand(data(i).SA).*Vcx;
            Vsx=-data(i).SL.*Vcx;
            Fz = data(i).FZ;
            gamma = deg2rad(data(i).IA);
            pio = data(i).P*1000.0;
            [~,Fy0,~,~,co] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);

            % find the useful transients
            b_v = abs(data(i).V)>2;
            b_sa = abs(data(i).SA)>0.5;
            sgn_sa = sign(mean(data(i).SA(b_sa)));
            i1 = find(diff(b_v&b_sa)>0);
            i1 = find(diff(data(i).V(1:i1))<=0,1,'last')+1;
            i2 = (find((sgn_sa*(data(i).FY-Fy0))<0&b_v&b_sa,1,'first')-1);
            if isempty(i2)
                i2 = find(diff(b_v&b_sa)<0)-2;
                i2 = find(abs(data(i).V(i1:i2))>3.2,1,'last')+i1-2;
            end
            i_up = i1:i2; % 0 to SA
            % i1 = find(diff(b_v)>0&~b_sa(1:end-1));
            % i1 = find(diff(data(i).V(1:i1))<=0,1,'last')+1;
            % i2 = (find((sgn_sa*(data(i).FY(i1:end)-Fy0(i1:end)))>0,1,'first')+i1-2);
            % if isempty(i2)
            %     i2 = length(data(i).ET);
            % end
            % i_down = i1:i2; % SA to 0

            % up test
            % data:
            t = data(i).ET(i_up);
            vx = Vcx(i_up);
            vy = Vcy(i_up);
            xi = deg2rad(data(i).SA(i_up));
            Fo = data(i).FY(i_up);
            xo = zeros(size(xi));
            for k = 1:length(t)
                xm = min(tire.ALPMAX,abs(fzero(@(x) co.By(k)*x - co.Ey(k)*(co.By(k)*x-atan(co.By(k)*x)) - tan(pi/2/co.Cy),0)));
                xfun = @(x) Out2(@MF4_nopsi_adams,tire,vx(k),-tan(x).*vx(k),Vsx(i_up(k)),Fz(i_up(k)),gamma(i_up(k)),pio(i_up(k))) - Fo(k);
                if isfinite(xm) && (xfun(xm)>0)~=(xfun(-xm)>0)
                    xo(k) = fzero(xfun,[-xm,xm]);
                else
                    xo(k) = fzero(xfun,0);
                end
            end
            % transient solution equation:
            x0 = xo(1);
            fun = @(p,x) xofun(p,x,x0);
            x = [t, vx, vy];
            y = xo;
            opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax,'UseParallel',false);
            s_up = lsqcurvefit(fun,0.2,x,y,0,inf,opts);

            % % down test
            % % data:
            % t = data(i).ET(i_down);
            % vx = Vcx(i_down);
            % vy = Vcy(i_down);
            % xi = deg2rad(data(i).SA(i_down));
            % Fo = data(i).FY(i_down);
            % xo = zeros(size(xi));
            % for k = 1:length(t)
            %     xm = min(tire.ALPMAX,abs(fzero(@(x) co.By(k)*x - co.Ey(k)*(co.By(k)*x-atan(co.By(k)*x)) - tan(pi/2/co.Cy),0)));
            %     xfun = @(x) Out2(@MF4_nopsi_adams,tire,vx(k),-tan(x).*vx(k),Vsx(i_down(k)),Fz(i_down(k)),gamma(i_down(k)),pio(i_down(k))) - Fo(k);
            %     if isfinite(xm) && (xfun(xm)>0)~=(xfun(-xm)>0)
            %         xo(k) = fzero(xfun,[-xm,xm]);
            %     else
            %         xo(k) = fzero(xfun,0);
            %     end
            % end
            % % transient solution equation:
            % x0 = xo(1);
            % fun = @(p,x) xofun(p,x,x0);
            % x = [t, vx, vy];
            % y = xo;
            % opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps,'MaxFunctionEvaluations',realmax,'MaxIterations',realmax,'UseParallel',false);
            % s_down = lsqcurvefit(fun,s_up,x,y,0,inf,opts);

            data(i).sigma_y_up = s_up;
            % data(i).sigma_y_down = s_down;
            
            fprintf('\b|\n');
        end
    end
    
    % PTY1 PTY2
    % PTY3=0 (no camber data included in TTC, need to update if that changes)
    % (I think there's a typo in the Adams doc, it shows PKY3)
    idx = strcmp(extractfield(data,'test_type'),'TRANSIENT');
    x = extractfield(data(idx),'FZ_mean')/tire.FNOMIN;
    y = extractfield(data(idx),'sigma_y_up')/tire.UNLOADED_RADIUS;
    [y,rem] = rmoutliers(y);
    x(:,rem) = [];
    p = ones(1,2);
    p(1) = mean(y(x>0.75*max(x)));
    fun = @(p) pnorm_rmse(y,p(1)*sin(2*atan(x/p(2))));
    opts = optimoptions('fminunc','Display','final-detailed','PlotFcn',{@optimplotx,@optimplotfunccount,@optimplotfval,@optimplotstepsize,@optimplotfirstorderopt},'MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter,'UseParallel',parallel);
    p = fminunc(fun,p,opts);
    delete(gcf);
    tire.PTY1 = p(1);
    tire.PTY2 = p(2);
    % TODO: not a very good fit, needs works. Maybe another fit function
    % that time-marches the transient tests and checks the RMSE based on
    % changes in PTY1/2?
    % figure
    % plot(x,y,'.')
    % hold on
    % plot(x,p(1)*sin(2*atan(x/p(2)))),'.')
    
else
    warning('TyreFit_PAC2002: No TRANSIENT tests provided, fitting skipped.')
end

%% Other additions for VI

if for_VI
    tire.VERTICAL_DAMPING = 500;
    tire.QFCX1 = 0;
    tire.PTX1 = 0.01;
end

if sym_flag
    tire.RHX1 = 0;
    tire.QSX1 = 0;
    tire.PEY3 = 0;
    tire.PHY1 = 0;
    tire.PHY2 = 0;
    tire.PVY1 = 0;
    tire.PVY2 = 0;
    tire.RBY3 = 0;
    tire.RVY1 = 0;
    tire.RVY2 = 0;
    tire.QBZ4 = 0;
    tire.QDZ6 = 0;
    tire.QDZ7 = 0;
    tire.QEZ4 = 0;
    tire.QHZ1 = 0;
    tire.QHZ2 = 0;
    tire.SSZ1 = 0;
    tire.QDZ3 = 0;
end

%% write tire structure to a tir file
if nargin<1
    fname = [tireidstruct.manuf '_' replace(tireidstruct.size,{'/','-','.0','.'},{'_','x','',''}) '_' strrep(tireidstruct.item,' ','') '_' sprintf('%.0f_in_rim',tireidstruct.w_rim) '.tir'];
end
flag = write2tir_PAC2002(tire,fname);
if flag==0
    disp('###############################################################################')
    disp(['Fitting complete, tir file saved as: ' fname])
    disp('###############################################################################')
end
path(oldpath);

end


%% Useful Plots:
% str = 'COMBINED'; % LOADED_RADIUS DRIVE_BRAKE CORNERING COMBINED TRANSIENT WARMUP
% idx = strcmp(extractfield(data,'test_type'),str);
% % idx=strcmp(extractfield(data,'test_type'),'LOADED_RADIUS') | strcmp(extractfield(data,'test_type'),'DRIVE_BRAKE') | strcmp(extractfield(data,'test_type'),'CORNERING') | strcmp(extractfield(data,'test_type'),'COMBINED');
% Vcx=extractfield(data(idx),'V')/3.6;
% Vcy=tand(extractfield(data(idx),'SA')).*Vcx;
% Vsx=-extractfield(data(idx),'SL').*Vcx;
% Fz = extractfield(data(idx),'FZ');
% gamma = extractfield(data(idx),'IA')*pi/180.0;
% pio = extractfield(data(idx),'P')*1000.0;
% [Fxm,Fym,Mxm,Mzm,~] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
% fy_o = extractfield(data(idx),'FY');
% fx_o = extractfield(data(idx),'FX');
% mz_o = extractfield(data(idx),'MZ');
% mx_o = extractfield(data(idx),'MX');
% et_i = extractfield(data(idx),'ET');
% sa_i = extractfield(data(idx),'SA');
% sl_i = extractfield(data(idx),'SL');
% fz_i = extractfield(data(idx),'FZ');
% ia_i = extractfield(data(idx),'IA');
% p_i = extractfield(data(idx),'P');
% v_i = extractfield(data(idx),'V');
% t_i = extractfield(data(idx),'T');
% sse = (extractfield(data(idx),'FY')-Fym).^2;
% 
% figure;
% a1=subplot(211);
% plot(et_i,fy_o,'.-','DisplayName','data')
% hold on
% plot(et_i,Fym,'.-','DisplayName','model')
% % yyaxis('right')
% % plot(et_i,fy_o,'.-','DisplayName','fy')
% % title(str)
% legend show
% a2=subplot(212);
% plot(et_i,sa_i,'.-','DisplayName','SA')
% hold on
% plot(et_i,sl_i*100,'.-','DisplayName','SL')
% plot(et_i,fz_i/10,'.-','DisplayName','FZ')
% plot(et_i,ia_i*10,'.-','DisplayName','IA')
% plot(et_i,p_i,'.-','DisplayName','P')
% plot(et_i,sse/max(sse)*100,'.-','DisplayName','Fx error')
% plot(et_i,v_i,'.-','DisplayName','V')
% plot(et_i,t_i,'.-','DisplayName','T')
% legend show
% linkaxes(get(gcf,'children'),'x')
% plot(et_i,(extractfield(data(idx),'FX')-Fxm).^4/max((extractfield(data(idx),'FX')-Fxm).^4)*100,'.-','DisplayName','SSE4')

% i=439;
% MF4_nopsi_adams(tire,Vcx(i),Vcy(i),Vsx(i),Fz(i),gamma(i),pio(i));

% figure;
% plot(sl_i,fx_o,'.')
% hold on
% plot(sl_i,Fxm,'.')

% figure;
% a1=subplot(211);
% plot(et_i,fy_o,'.-','DisplayName','test')
% hold on
% plot(et_i,Fym,'.-','DisplayName','model')
% legend show
% a2=subplot(212);
% plot(et_i,sa_i,'.-','DisplayName','SA')
% hold on
% plot(et_i,fz_i/10,'.-','DisplayName','FZ')
% plot(et_i,ia_i*10,'.-','DisplayName','IA')
% plot(et_i,p_i,'.-','DisplayName','P')
% plot(et_i,sse/3000,'.-','DisplayName','Fy error')
% plot(et_i,v_i,'.-','DisplayName','V')
% legend show
% linkaxes(get(gcf,'children'),'x')


%% Supporting functions:

function [cost,Model_out] = param_tuning(F_i,data,p,p_list,tire)
    % F_i - output index: 1=Fx, 2=Fy, 3=Mx, 4=Mz
    % data - test data structure
    % p - parameter values
    % p - parameter indices (in tire structure)
    % tire - tire structure
    pnorm = 1;
    if length(p)~=length(p_list)
        error('TyreFit_PAC2002: incorrect input to param_tuning')
    end
    switch F_i
        case 1
            out = extractfield(data,'FX');
        case 2
            out = extractfield(data,'FY');
        case 3
            out = extractfield(data,'MX');
        case 4
            out = extractfield(data,'MZ');
        otherwise
            error('TyreFit_PAC2002: incorrect input to param_tuning')
    end
    fields = fieldnames(tire);
    for i = 1:length(p_list)
        j = p_list(i);
        tire.(fields{j}) = p(i);
    end
    
    Vcx=extractfield(data,'V')/3.6;
    Vcy=tand(extractfield(data,'SA')).*Vcx;
    Vsx=-extractfield(data,'SL').*Vcx;
    Fz = extractfield(data,'FZ');
    gamma = extractfield(data,'IA')*pi/180.0;
    pio = extractfield(data,'P')*1000.0;
    F_out = zeros(4,length(Vcx));
    [F_out(1,:),F_out(2,:),F_out(3,:),F_out(4,:),~] = MF4_nopsi_adams(tire,Vcx,Vcy,Vsx,Fz,gamma,pio);
    
    % rmse cost
    cost = pnorm_rmse(out,F_out(F_i,:),pnorm);
    
    % if modelled output is requested:
    if nargout>1
        Model_out = F_out(F_i,:);
    end
end

function [m,b] = lin_orth_reg(data)
% TODO: check and update that this is proper Deming regression
    [~, ~, V] = svd(data - repmat(mean(data), size(data, 1), 1), 0);
    m = -V(1, end) / V(2, end);
    b = mean(data * V(:, end)) / V(2, end);
end

function [bins,mean_bin] = sep_bin(dat, tol)
    bw = (max(dat)-min(dat))/20;
    [f,xi] = ksdensity(dat,'numpoints',max(round(length(dat)/100),100),'bandwidth',bw);%,'kernel','epanechnikov');
    if nargin <2
        tol = 0.005*max(f);
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

function [B,C,D,E,Sh,Sv] = Magic_Fit_F(x,F)
    % fit the sine Magic Curve to a set of slip-Force data
    FM = @(x,B,C,D,E,Sh,Sv) D .* sin( C .* atan( B .* (x + Sh) - E .* ( B .* (x + Sh) - atan( B .* (x + Sh) ) ) ) ) + Sv;
    Sv0 = mean([max(F),min(F)]); % Sv estimate, shift vertical so max and min are equi-distance to axis
    F0 = F-Sv0;
    if mean(F0(x>0))>0
        xn = x;
    else
        xn = -x;
        %[~,i] = min(F0);
        %D0 = -min(F0); %pos
    end
    [~,i] = max(F0);
    D0 = max(F0); %pos
    xm = xn(i);
    [K0,b] = lin_orth_reg([xn(abs(F0)<0.33*max(abs(F0))),F0(abs(F0)<0.33*max(abs(F0)))]);
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
        lb = [0,1,min(F0)*1.5,-inf,min(xn),min(F)];
        ub = [inf,2,0,1,max(xn),max(F)];
    else
        lb = [0,1,0,0,min(xn),min(F)];
        ub = [inf,2,max(F0)*1.5,1,max(xn),max(F)];
    end
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','MaxFunctionEvaluations',realmax,'MaxIterations',realmax); %,'PlotFcn','optimplotx','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps
    p = lsqcurvefit(fun,p0,xn,F,lb,ub,opts);
    C=p(2);D=p(3);E=p(4);Sv=p(6);
    if mean(F0(x>0))>0
        B=p(1);
        Sh=p(5);
    else
        B=-p(1);
        Sh=-p(5);
    end
    
    % figure
    % xp = min(x):0.001:max(x);
    % plot(x,F,'.')
    % hold on
    % plot(xp,FM(xp,p(1),p(2),p(3),p(4),p(5),p(6)))
    
    % Having trouble with the orthogonal fit. fminsearch is slow, cannot
    % implment bounds on the parameters, and ends up pushing D higher than
    % max(F0)
    % cost = @(p) MF_ortho_cost(x,F,p(1),p(2),p(3),p(4),p(5),p(6),x_lim);
    % p0 = [B0,C0,D0,E0,Sh0,Sv0];
    % opts = optimset('Display','iter','PlotFcn',@optimplotx);
    % p = fminsearch(cost,p0,opts)
end

function [Bt,Ct,Dt,Et,Sht,Br,Dr] = Magic_Fit_M(x,F,M,B,C,D,E,Sh,Sv)
    % fit the combined cose and sine Magic Curves to a set of slip-Moment
    % data
    
    % TODO: Magic_Fit_F was refined, refine this similarily (set parameter limits, better initial guesses etc.):
    Mzr = @(x,Dr,Br) Dr.*cos(atan(Br.*(x+Sh+Sv/B/C/D))).*cos(x);
    t = @(x,Bt,Ct,Dt,Et,Sht) (Dt .* cos(Ct .* atan(Bt.*(x+Sht)-Et.*(Bt.*(x+Sht)-atan(Bt.*(x+Sht)))))).*cos(x);
    FM = @(x) D .* sin( C .* atan( B .* (x + Sh) - E .* ( B .* (x + Sh) - atan( B .* (x + Sh) ) ) ) ) + Sv;
    MM = @(x,Bt,Ct,Dt,Et,Sht,Dr,Br) -t(x,Bt,Ct,Dt,Et,Sht).*FM(x) + Mzr(x,Dr,Br);
    Dr0 = max(mean(M(abs(F)<100)),0);
    Br0 = abs(B);
    t_est = -(M-Mzr(x,Dr0,Br0))./F;
    Bt0 = abs(B);
    Dt0 = mean(t_est(abs(M)>5&abs(F)>200));
    Ct0 = 2/pi*acos(min(1,max(-1,mean(t_est(x>0.9*max(x)))/Dt0)));
    Et0 = E;
    Sht0 = 0;
    
    fun = @(p,x) MM(x,p(1),p(2),p(3),p(4),p(5),p(6),p(7));
    p0 = [Bt0,Ct0,Dt0,Et0,Sht0,Dr0,Br0];
    lb = [0,1,0,-inf,min(x),0,0];
    ub = [inf,2,inf,1,max(x),inf,inf];
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','MaxFunctionEvaluations',realmax,'MaxIterations',realmax); %,'PlotFcn','optimplotx','OptimalityTolerance',0,'FunctionTolerance',eps,'StepTolerance',eps
    p = lsqcurvefit(fun,p0,x,M,lb,ub,opts);
    Bt=p(1);Ct=p(2);Dt=p(3);Et=p(4);Sht=p(5);Dr=p(6);Br=p(7);
end

function [Byk,Cyk,Eyk,Shyk,Dvyk,rvy5,rvy6] = Magic_Fit_CombFy(x,F)
    % fit the combined cose and sine Magic Curves to a set of slip-Combined
    % Force data
    
    % TODO: Magic_Fit_F was refined, refine this similarily (set parameter limits, better initial guesses etc.):
    maxfuneval = 15000;
    maxiter = 1000;
    
    %condition vectors
    x = x(:);
    F = F(:);
    %Fm = Fm(:);

    F0 = mean(F(abs(x)<0.02));
    
    p0 = [1,1,1,0.001,0.001,0.001,0.001];
    fun = @(p,x) F0*cos(p(2)*atan(p(1)*(x+p(4))-p(3)*(p(1)*(x+p(4))-atan(p(1)*(x+p(4))))))/cos(p(2)*atan(p(1)*p(4)-p(3)*(p(1)*p(4)-atan(p(1)*p(4))))) + p(5)*sin(p(6)*atan(p(7)*x));
    
    if mean(F)>0
        p0(4) = -mean(x(F>0.9*max(F)));
    else
        p0(4) = -mean(x(F<0.9*min(F)));
    end

    y = F./F0;
    fun0 = @(p,x) cos(p(2)*atan(p(1)*x-p(3)*(p(1)*x-atan(p(1)*x))));
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','MaxFunctionEvaluations',maxfuneval/10,'MaxIterations',maxiter/10);
    %pin=[1;1;1;zeros(length(x)-3,1)];
    p = lsqcurvefit(fun0,[1 1 1],x,y,-inf*[1 1 1],inf*[1 1 1],opts);
    p0(1:3) = p;
    
%     y = F-fun(p0,x);
%     fun0 = @(p,x) p(1)*sin(p(2)*atan(p(3)*x));
%     opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','MaxFunctionEvaluations',maxfuneval/10,'MaxIterations',maxiter/10);
%     p = [1 1 1];
%     p(1)=max(abs(y))*sign(mean(y(x>0))-mean(y(x<0)));
%     [v1,i1]=max(y);
%     [v2,i2]=min(y);
%     p(3) = abs((v1-v2)./(x(i1)-x(i2))/p(1)/p(2));
%     p = lsqcurvefit(fun0,p,x,y,-inf*[1 1 1],inf*[1 1 1],opts);
%     p0(5:7) = p;
    
    lb = [0,1,-inf,min(x),-inf,-inf,-inf];
    ub = [inf,2,1,max(x),inf,inf,inf];
%     if sign(p0(5))<0
%         ub(5) = 0;
%     else
%         lb(5) = 0;
%     end
    opts=optimoptions('lsqcurvefit','Display','off','FiniteDifferenceType','central','MaxFunctionEvaluations',maxfuneval,'MaxIterations',maxiter);
    p = lsqcurvefit(fun,p0,x,F,lb,ub,opts);
    Byk=p(1);Cyk=p(2);Eyk=p(3);Shyk=p(4);Dvyk=p(5);rvy5=p(6);rvy6=p(7);
end

% function cost = MF_ortho_cost(x_test,F_test,B,C,D,E,Sh,Sv,x_lim)
%     % returns a scalar cost based on orthogonal distances from
%     % (x_test,F_test) to the magic formula equation based on
%     % (B,C,D,E,Sh,Sv). Normalized via x_lim and D. Can accept vectors in
%     % all inputs
%     if nargin < 9
%         x_lim = max(abs(x_test));
%     end
%     F0 = @(x) D .* sin( C .* atan( B .* (x + Sh) - E .* ( B .* (x + Sh) - atan( B .* (x + Sh) ) ) ) ) + Sv;
%     F0p = @(x) (C .* D .* (B - E .* (B - B./(1 + B.^2 .* (x + Sh).^2))) .* cos(C .* atan(B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh))))))./(1 + (B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh)))).^2);
%     % F0pp = @(x) -((2 .* B.^3 .* C .* D .* E .* (x + Sh) .* cos( C .* atan( B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh))))))./((1 + B.^2 .* (x + Sh).^2).^2 .* (1 + (B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh)))).^2))) - (2 .* C .* D .* (B - E .* (B - B./( 1 + B.^2 .* (x + Sh).^2))).^2 .* (B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh)))) .* cos( C .* atan( B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh))))))./(1 + (B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh)))).^2).^2 - (C.^2 .* D .* (B - E .* (B - B./(1 + B.^2 .* (x + Sh).^2))).^2 .* sin( C .* atan( B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh))))))./(1 + (B .* (x + Sh) - E .* (B .* (x + Sh) - atan(B .* (x + Sh)))).^2).^2;
%     L = @(x) sqrt(((x_test - x)/x_lim).^2+((F_test - F0(x))./D).^2);
%     % Lp = @(x,i) ((x - x_test) .* D.^2 + x_lim.^2 .* (-F_test + F0(x)) .* F0p( x))./(D.^2 .* x_lim.^2 .* sqrt((x - x_test).^2./ x_lim.^2 + (F_test - F0(x)).^2./D.^2));
%     % Lpp = @(x) -((((x - x_test) .* D.^2 + x_lim.^2 .* (-F_test + F0(x)) .* F0p( x)).^2 - ((x - x_test).^2 .* D.^2 + x_lim.^2 .* (F_test - F0(x)).^2) .* (D.^2 + x_lim.^2 .* (F0p( x).^2 + (-F_test + F0(x)) .* F0pp( x))))./(D.^4 .* x_lim.^4 .* ((x - x_test).^2./x_lim.^2 + (F_test - F0(x)).^2./ D.^2).^(3./2)));
%     
%     x_new = zeros(size(x_test));
%     for i = 1:length(x_test)
%         Lpi = @(x) ((x - x_test(i)) .* D.^2 + x_lim.^2 .* (-F_test(i) + F0(x)) .* F0p( x))./(D.^2 .* x_lim.^2 .* sqrt((x - x_test(i)).^2./ x_lim.^2 + (F_test(i) - F0(x)).^2./D.^2));
%         opts = optimset('TolX',eps);
%         if Lpi(x_test(i))>0
%             x0 = [min(x_test),x_test(i)];
%         else
%             x0 = [x_test(i),max(x_test)];
%         end
%         if x0(1)*x0(2)>0
%             x_new(i)=x_test(i);
%         else
%             x_new(i)=fzero(Lpi,x0,opts);
%         end
%     end
%     cost = sum(L(x_new)); % orthogonal residuals! use sum or rmse or something to combine into scalar
%     
%     % figure
%     % plot(x_test,F_test,'.')
%     % hold on
%     % plot(sort(x_new),F0(sort(x_new)))
%     % plot([x_new,x_test]'=p();[F0(x_new),F_test]')
% end

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

function Z = Out2(FUN,varargin)
% Z = Out2(FUN,VARARGIN);
%	Provides the second output from the function
[~,Z] = FUN(varargin{:});
end
function Z = Out4(FUN,varargin)
[~,~,~,Z] = FUN(varargin{:});
end