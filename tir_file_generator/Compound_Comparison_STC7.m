function [] = Compound_Comparison_STC7
msg = "";
opts = ["Same condition" "Different condition"];
cond = menu(msg,opts);
switch cond
    case 1
        
        msg = "";
opts = ["Fy" "Mz" "Fx"];
choice = menu(msg,opts);
switch choice
    case 1
        Fy_Plot
    case 2
        Mz_Plot
    case 3
        Fx_Plot
end
    case 2
         msg = "";
opts = ["Fy" "Mz" "Fx"];
choice = menu(msg,opts);
switch choice
    case 1
        Fy_Plot2
    case 2
        Mz_Plot2
    case 3
        Fx_Plot2
end

end