% MATLAB script: ellissi di aderenza PAC2002 da file .tir con parsing avanzato
% ====================================================================
clear; clc;

%% 1) Selezione file .tir
[filename, pathname] = uigetfile('*.tir', 'Seleziona il file .tir PAC2002');
if isequal(filename,0)
    error('Nessun file selezionato.');
end
tirFile = fullfile(pathname, filename);

%% 2) Lettura parametri .tir
p = readTirParameters(tirFile);

%% 3) Input condizioni operative
% Carico verticale
if isfield(p, 'FNOMIN')
    Fz0 = p.FNOMIN;
else
    Fz0 = input('Inserisci il carico nominale FNOMIN [N]: ');
end
Fz = input('Inserisci il carico operativo Fz [N]: ');
if isempty(Fz) || Fz<=0
    error('Carico non valido.');
end
% Pressione pneumatico
pi0 = getParam(p,'IP_NOM',2e5);
P = input(sprintf('Inserisci la pressione pneumatico P [Pa] (default=%.0f): ', pi0));
if isempty(P) || P<=0
    P = pi0;
end
% Angolo di camber
camDeg = input('Inserisci l''angolo di camber [deg]: ');
gamma = deg2rad(camDeg);

%% 4) Definizione dei range di slip massimi
amin = input('Valore minimo di α_{max} [deg]: ');
amax = input('Valore massimo di α_{max} [deg]: ');
numA = input('Numero di valori di α_{max} da generare: ');
if isempty(amin) || isempty(amax) || isempty(numA) || numA < 1
    error('Intervallo di α_{max} non valido.');
end
alphaMaxVec = unique([linspace(amin, amax, numA), 0]);
alphaMaxVec = sort(alphaMaxVec);

kmin = input('Valore minimo di κ_{max}: ');
kmax = input('Valore massimo di κ_{max}: ');
numK = input('Numero di valori di κ_{max} da generare: ');
if isempty(kmin) || isempty(kmax) || isempty(numK) || numK < 1
    error('Intervallo di κ_{max} non valido.');
end
kappaMaxVec = unique([linspace(kmin, kmax, numK), 0]);
kappaMaxVec = sort(kappaMaxVec);

%% 5) Calcolo e plot delle ellissi per tutte le combinazioni alpha-kappa
numA = numel(alphaMaxVec);
numK = numel(kappaMaxVec);
orange = [1 0.5 0];
blue    = [0 0.4470 0.7410];
figure('Name', sprintf('Ellissi di aderenza a Fz=%.0f N, P=%.0f Pa, cam=%.1f°', Fz, P, camDeg), 'NumberTitle', 'off');
hold on; grid on;
count = 0;
for iA = 1:numA
    aMax = alphaMaxVec(iA);
    aRad = deg2rad(aMax);
    alpha_vec = deg2rad(linspace(-aMax, aMax, 200));
    for jK = 1:numK
        kMax = kappaMaxVec(jK);
        kappa_vec = linspace(-kMax, kMax, 200);

        % bordo con kappa = -kMax
        Kfix = -kMax * ones(size(alpha_vec));
        Fx1 = MF_PAC2002_Fx_pure(Kfix, 0, Fz, gamma, P, p) .* MF_PAC2002_Gx(Kfix, alpha_vec, Fz, gamma, P, p);
        Fy1 = MF_PAC2002_Fy_pure(0, alpha_vec, Fz, gamma, P, p) .* MF_PAC2002_Gy(Kfix, alpha_vec, Fz, gamma, P, p);

        % bordo con alpha = aMax
        Afix = aRad * ones(size(kappa_vec));
        Fx2 = MF_PAC2002_Fx_pure(kappa_vec, 0, Fz, gamma, P, p) .* MF_PAC2002_Gx(kappa_vec, Afix, Fz, gamma, P, p);
        Fy2 = MF_PAC2002_Fy_pure(0, Afix, Fz, gamma, P, p) .* MF_PAC2002_Gy(kappa_vec, Afix, Fz, gamma, P, p);

        % bordo con kappa = kMax
        Kfix = kMax * ones(size(alpha_vec));
        Fx3 = MF_PAC2002_Fx_pure(Kfix, 0, Fz, gamma, P, p) .* MF_PAC2002_Gx(Kfix, fliplr(alpha_vec), Fz, gamma, P, p);
        Fy3 = MF_PAC2002_Fy_pure(0, fliplr(alpha_vec), Fz, gamma, P, p) .* MF_PAC2002_Gy(Kfix, fliplr(alpha_vec), Fz, gamma, P, p);

        % bordo con alpha = -aMax
        Afix = -aRad * ones(size(kappa_vec));
        Fx4 = MF_PAC2002_Fx_pure(fliplr(kappa_vec), 0, Fz, gamma, P, p) .* MF_PAC2002_Gx(fliplr(kappa_vec), Afix, Fz, gamma, P, p);
        Fy4 = MF_PAC2002_Fy_pure(0, Afix, Fz, gamma, P, p) .* MF_PAC2002_Gy(fliplr(kappa_vec), Afix, Fz, gamma, P, p);

        count = count + 1;
        label = sprintf('α_{max}=%.1f°, κ_{max}=%.2f', aMax, kMax);
        h(1) = plot(Fy1, Fx1, '-', 'Color', orange, 'LineWidth', 2, 'DisplayName', label);
        set(h(1),'UserData',struct('alpha',alpha_vec,'kappa',Kfix));
        h(2) = plot(Fy2, Fx2, '-', 'Color', blue,    'LineWidth', 2, 'HandleVisibility','off');
        set(h(2),'UserData',struct('alpha',Afix,'kappa',kappa_vec));
        h(3) = plot(Fy3, Fx3, '-', 'Color', orange, 'LineWidth', 2, 'HandleVisibility','off');
        set(h(3),'UserData',struct('alpha',fliplr(alpha_vec),'kappa',Kfix));
        h(4) = plot(Fy4, Fx4, '-', 'Color', blue,    'LineWidth', 2, 'HandleVisibility','off');
        set(h(4),'UserData',struct('alpha',Afix,'kappa',fliplr(kappa_vec)));
    end
end
xlabel('F_y [N]'); ylabel('F_x [N]');
title(sprintf('Ellissi di aderenza PAC2002 a Fz=%.0fN, P=%.0fPa, cam=%.1f°', Fz, P, camDeg));
legend('Location','Best');
dcm = datacursormode(gcf);
set(dcm,'UpdateFcn',@showSlip);
datacursormode on;
hold off;

%% --- Local functions ----------------------------------------------
function params = readTirParameters(tirFilename)
    fid = fopen(tirFilename,'r'); if fid<0, error('Impossibile aprire il file: %s',tirFilename); end
    params = struct();
    while ~feof(fid)
        line = fgetl(fid); if ~ischar(line), break; end
        tkn = regexp(line, '^\s*(\S+)\s*=\s*([-+]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)', 'tokens');
        if ~isempty(tkn)
            name = tkn{1}{1}; val = str2double(tkn{1}{2}); if ~isnan(val), params.(name) = val; end
        end
        if contains(line, '% : COMMENT : Tire')
            tt = regexp(line, '% : COMMENT : Tire\s+(.*)','tokens'); params.tireName = strtrim(tt{1}{1});
        end
    end
    fclose(fid);
end

function Fx = MF_PAC2002_Fx_pure(kappa,~,Fz,gamma,P,p)
    Fz0 = p.FNOMIN; dfz=(Fz-Fz0)/Fz0;
    pi0=getParam(p,'IP_NOM',2e5); dpi=(P-pi0)/pi0;
    Cx1=getParam(p,'PCX1',1);
    Dx1=getParam(p,'PDX1',1); Dx2=getParam(p,'PDX2',0); Dx3=getParam(p,'PDX3',0);
    Ex1=getParam(p,'PEX1',0); Ex2=getParam(p,'PEX2',0); Ex3=getParam(p,'PEX3',0); Ex4=getParam(p,'PEX4',0);
    Kx1=getParam(p,'PKX1',10); Kx2=getParam(p,'PKX2',0); Kx3=getParam(p,'PKX3',0);
    Hx1=getParam(p,'PHX1',0); Hx2=getParam(p,'PHX2',0);
    Vx1=getParam(p,'PVX1',0); Vx2=getParam(p,'PVX2',0);
    px1=getParam(p,'PPX1',0); px2=getParam(p,'PPX2',0); px3=getParam(p,'PPX3',0); px4=getParam(p,'PPX4',0);
  
    %formule per il calcolo
    mu = (Dx1 + Dx2*dfz)*(1 - Dx3*(gamma^2))*(1 + px3*dpi + px4*dpi^2);
    D = mu * Fz; 
    C = Cx1; 
    K = Fz * (Kx1 + Kx2*dfz) * exp(Kx3*dfz) * (1 + px1*dpi + px2*dpi^2);
    B = K/(C*D + eps); 
    SH = Hx1 + Hx2*dfz;
    k = kappa + SH;
    E = (Ex1 + Ex2*dfz + Ex3*dfz^2) * (1 - Ex4*sign(k)); 
    SV = Fz * (Vx1 + Vx2*dfz);  
    Fx0 = D .* sin(C .* atan(B .* k - E .* (B .* k - atan(B .* k))));
    Fx = Fx0 + SV;
end

function Fy = MF_PAC2002_Fy_pure(~,alpha,Fz,gamma,P,p)
    Fz0=p.FNOMIN; dfz=(Fz-Fz0)/Fz0;
    pi0=getParam(p,'IP_NOM',2e5); dpi=(P-pi0)/pi0;
    Cy1=getParam(p,'PCY1',1.1);
    Dy1=getParam(p,'PDY1',1); Dy2=getParam(p,'PDY2',0); Dy3=getParam(p,'PDY3',0);
    Ey1=getParam(p,'PEY1',0); Ey2=getParam(p,'PEY2',0); Ey3=getParam(p,'PEY3',0); Ey4=getParam(p,'PEY4',0);
    Ky1=getParam(p,'PKY1',20); Ky2=getParam(p,'PKY2',0); Ky3=getParam(p,'PKY3',0);
    Hy1=getParam(p,'PHY1',0); Hy2=getParam(p,'PHY2',0); Hy3=getParam(p,'PHY3',0);
    Vy1=getParam(p,'PVY1',0); Vy2=getParam(p,'PVY2',0); Vy3=getParam(p,'PVY3',0); Vy4=getParam(p,'PVY4',0);
    py1=getParam(p,'PPY1',0); py2=getParam(p,'PPY2',0); py3=getParam(p,'PPY3',0); py4=getParam(p,'PPY4',0);
   
    %formule per il calcolo
    mu = (Dy1 + Dy2*dfz) * (1 + py3*dpi + py4*dpi^2)*(1 - Dy3*gamma^2);
    D = mu * Fz;
    C = Cy1; 
    Ky0 = Ky1 * Fz0*(1 + py1*dpi)*sin(2*atan(Fz/(Ky2*Fz0*(1 + py2*dpi))));
    K = Ky0 * (1 - Ky3 * abs(gamma));
    B = K/(C*D + eps);
    SH = (Hy1 + Hy2*dfz) + Hy3 * gamma;
    a = alpha + SH;
    E = (Ey1 + Ey2*dfz) * (1 - (Ey3 + Ey4*gamma)*sign(a));
    SV = Fz * (Vy1 + Vy2*dfz + (Vy3 + Vy4*dfz)*gamma);
    Fy0 = D .* sin(C .* atan(B .* a - E .* (B .* a - atan(B .* a))));
    Fy = Fy0 + SV;
end

function Gx = MF_PAC2002_Gx(kappa,alpha,Fz,gamma,P,p)
    Fz0=p.FNOMIN; dfz=(Fz-Fz0)/Fz0;
    pi0=getParam(p,'IP_NOM',2e5); dpi=(P-pi0)/pi0;
    rBx1=getParam(p,'RBX1',0); rBx2=getParam(p,'RBX2',0); rCx1=getParam(p,'RCX1',1);
    rEx1=getParam(p,'REX1',0); rEx2=getParam(p,'REX2',0); rHx1=getParam(p,'RHX1',0);

    %formule per il calcolo
    alpha_s=alpha+rHx1; 
    B_alpha = rBx1 .* cos(atan(rBx2 .* kappa));
    C_alpha=rCx1; 
    E_alpha=rEx1+rEx2*dfz;
   
    Gx = cos(C_alpha .* atan(B_alpha .* alpha_s - E_alpha .* (B_alpha .* alpha_s - atan(B_alpha .* alpha_s)))) ./ ...
         cos(C_alpha .* atan(B_alpha .* rHx1 - E_alpha .* (B_alpha .* rHx1 - atan(B_alpha .* rHx1))));
end

function Gy = MF_PAC2002_Gy(kappa,alpha,Fz,gamma,P,p)
    Fz0=p.FNOMIN; dfz=(Fz-Fz0)/Fz0;
    pi0=getParam(p,'IP_NOM',2e5); dpi=(P-pi0)/pi0;
    rBy1=getParam(p,'RBY1',0); rBy2=getParam(p,'RBY2',0); rBy3=getParam(p,'RBY3',0);
    rCy1=getParam(p,'RCY1',1); rEy1=getParam(p,'REY1',0); rEy2=getParam(p,'REY2',0);
    rHy1=getParam(p,'RHY1',0); rHy2=getParam(p,'RHY2',0);

    %formule per il calcolo
    kappa_s=kappa+(rHy1+rHy2*dfz); 
    B_k = rBy1 .* cos(atan(rBy2 .* (alpha - rBy3)));
    C_k=rCy1; 
    E_k=rEy1+rEy2*dfz;

    Gy = cos(C_k .* atan(B_k .* kappa_s - E_k .* (B_k .* kappa_s - atan(B_k .* kappa_s))));
end

function val = getParam(s,field,def)
    if isfield(s,field), val = s.(field); else val = def; end
end

function txt = showSlip(~,event_obj)
    idx = event_obj.DataIndex;
    ud = get(event_obj.Target,'UserData');
    alpha = ud.alpha(idx);
    kappa = ud.kappa(idx);
    txt = {sprintf('alpha = %.2f deg', rad2deg(alpha)), ...
           sprintf('kappa = %.4f', kappa)};
end
