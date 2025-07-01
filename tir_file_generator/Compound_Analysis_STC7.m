function [] = Compound_Analysis_STC7
msg = "";
opts = ["Fy" "Mz" "Fx"];
choice = menu(msg,opts);
switch choice
    case 1
      msg = "";
opts = ["Vertical Load" "Pressure" "Camber"];
choice = menu(msg,opts);
prompt = "How much values do you want to insert for the analysis? ";
x = input(prompt);
switch choice
case 1
    variableVerticalLoad(x);
case 2
    variablePressure(x);
case 3
    variableCamber(x);
end
    case 2
         msg = "";
opts = ["Vertical Load" "Pressure" "Camber"];
choice = menu(msg,opts);
prompt = "How much values do you want to insert for the analysis? ";
x = input(prompt);
switch choice
case 1
    variableVerticalLoad_Mz(x);
case 2
    variablePressure_Mz(x);
case 3
    variableCamber_Mz(x);
end
    case 3
        msg = "";
opts = ["Vertical Load" "Pressure" "Camber"];
choice = menu(msg,opts);
prompt = "How much values do you want to insert for the analysis? ";
x = input(prompt);
switch choice
case 1
    variableVerticalLoad_Fx(x);
case 2
    variablePressure_Fx(x);
case 3
    variableCamber_Fx(x);
end

end

