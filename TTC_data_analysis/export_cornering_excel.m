% export_B2356runxxto_excel.m
% Questo script carica il file B2356run32.mat ed esporta le variabili in un file Excel.

% 1. Specifica il percorso del file .mat (modifica se necessario)
matFileName = 'B2356run31.mat';

% 2. Carica il file .mat
data = load(matFileName);

% 3. Estrai le variabili di interesse
FY = data.FY;   % vettore Nx1
FZ = data.FZ;
SA = data.SA;

% 4. Verifica dimensioni delle variabili
%    (opzionale, serve a controllare che abbiano la stessa lunghezza)
nFY = numel(FY);
nFZ = numel(FZ);
nSA = numel(SA);
if ~isequal(nFY, nFZ, nSA)
    error('Le variabili non hanno tutte la stessa lunghezza.');
end

% 5. Crea una tabella con le colonne desiderate
T = table( ...
    FY(:), ...    % converte in vettore colonna, se già non lo è
    FZ(:), ...
    SA(:), ...
    'VariableNames', {'FY','FZ','SA'} ...
);

% 6. Specifica il nome del file Excel di output e il nome del foglio
excelFileName = 'cornering.xlsx';
sheetName      = 'DatiTire';

% 7. Esporta la tabella in Excel
%    Se non hai MATLAB R2013b o successivo, sostituisci con xlswrite
writetable(T, excelFileName, 'Sheet', sheetName, 'Range', 'A1');

% 8. Messaggio di conferma
fprintf('Esportazione completata:\n  File Excel generato: %s\n  Foglio: %s\n', ...
    excelFileName, sheetName);
