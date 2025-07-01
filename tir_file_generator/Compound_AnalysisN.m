function [] = Compound_AnalysisN
msg = "";
opts = ["Fy" "Mz" "Fx" "Fy-Mz"];
choice = menu(msg,opts);
switch choice
    case 1
      msg = "";
opts = ["Pressure" "Camber" "Vertical Load"];
choice = menu(msg,opts);
prompt = "How much values do you want to insert for the analysis? ";
x = input(prompt);
switch choice
case 1
    variablePressureN(x);
case 2
    variableCamberN(x);
case 3
    variableVerticalLoad_N(x);

end
    case 2
         msg = "";
opts = ["Pressure" "Camber" "Vertical Load"];
choice = menu(msg,opts);
prompt = "How much values do you want to insert for the analysis? ";
x = input(prompt);
switch choice
case 1
    variablePressure_Mz_N(x);
case 2
    variableCamber_Mz_N(x);
case 3
    variableVerticalLoad_Mz_N(x);
end
    case 3
        msg = "";
opts = ["Vertical Load" "Pressure" "Camber"];
choice = menu(msg,opts);
prompt = "How much values do you want to insert for the analysis? ";
x = input(prompt);
switch choice
case 1
    variablePressure_Fx_N(x);
case 2
    variableCamber_Fx_N(x);
end
    case 4
        msg = "";
opts = ["Pressure" "Camber"];
choice = menu(msg,opts);
prompt = "How much values do you want to insert for the analysis? ";
x = input(prompt);
switch choice
case 1
    variablePressure_Fy_Mz(x);
case 2
    variableCamber_Fy_Mz(x);
end


end