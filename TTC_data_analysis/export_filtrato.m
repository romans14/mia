% export_B2356runxxto_excel.m
% Questo script carica il file B2356run72.mat, applica un filtro su IA e P,
% e esporta le variabili FX, FZ e SR filtrate in un file Excel.

% 1. Specifica il percorso del file .mat (modifica se necessario)
matFileName = 'B2356run72.mat';

% 2. Carica il file .mat
data = load(matFileName);

% 3. Estrai le variabili di interesse e convertile in vettori colonna
FX = data.FX(:);   % forza orizzontale
FZ = data.FZ(:);   % forza verticale
SR = data.SR(:);   % slip ratio
IA = data.IA(:);   % camber angle (°)
P  = data.P(:);    % pressione (psi o bar, in base ai dati)

% 4. Verifica che tutte le variabili abbiano la stessa lunghezza
n = numel(FX);
if ~isequal(n, numel(FZ), numel(SR), numel(IA), numel(P))
    error('Le variabili non hanno tutte la stessa lunghezza.');
end

% 5. Applica il filtro: IA tra -0.05 e +0.05, P tra 75 e 83
idx = (IA >= 0.2) & (IA <= 0.7) & (P >= 65) & (P <= 75);

% 6. Isola i dati filtrati
FX_f = FX(idx);
FZ_f = FZ(idx);
SR_f = SR(idx);
IA_f = IA(idx);
P_f = P(idx);

% 7. Crea una tabella con le colonne filtrate
T = table(FX_f, FZ_f, SR_f, IA_f, P_f, 'VariableNames', {'FX','FZ','SR','IA','P'});

% 8. Specifica il nome del file Excel di output e il nome del foglio
excelFileName = 'drive_brake_filtered.xlsx';
sheetName      = 'IA_m005_0p05_P75_83';

% 9. Esporta la tabella filtrata in Excel
writetable(T, excelFileName, 'Sheet', sheetName, 'Range', 'A1')

% 10. Messaggio di conferma
fprintf('Esportati %d campioni filtrati (IA ∈ [-0.05,0.05], P ∈ [75,83]) nel file "%s", foglio "%s".\n', ...
    height(T), excelFileName, sheetName);
