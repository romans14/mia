% plot_drive_brake_from_excel.m
% 1) Legge i dati Excel, 2) estrae FX,FZ,SR, 3) plotta scatter3.

% 1. Leggi il foglio Excel
excelFile = 'drive_brake_filtered.xlsx';
sheetName = 'IA_m005_0p05_P75_83';

% Se hai MATLAB R2019a o successivo, readtable gestisce anche celle vuote / intestazioni
T = readtable(excelFile, 'Sheet', sheetName);

% 2. Estrai le variabili
FX = T.FX;
FZ = T.FZ;
SR = T.SR;

% 3. Crea scatter3
figure;
scatter3(FZ, SR, FX, 36, SR, 'filled');
xlabel('FZ (N)');
ylabel('SR');
zlabel('FX (N)');
title('Scatter 3D: FX vs FZ vs SR');
grid on;
view(45,30);  % imposta angolo di visuale (azimut, elevazione)

% 4. (Opzionale) Colormap per evidenziare SR
colorbar;
colormap parula;

% 5. Salva figura se ti serve
% saveas(gcf, 'scatter3_drive_brake.png');
