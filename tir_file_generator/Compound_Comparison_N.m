function [] = Compound_Comparison_N
msg = "";
opts = ["Same condition" "Different condition"];
cond = menu(msg,opts);
switch cond
    case 1
        
        msg = "";
opts = ["Fy" "Mz" "Fx" "Fy-Mz"];
choice = menu(msg,opts);
switch choice
    case 1
        Fy_Plot_N
    case 2
        Mz_Plot_N
    case 3
        Fx_Plot_N
    case 4
        Fy_Mz_Plot_N
end
    case 2
         
        msg = "";
opts = ["Fy" "Mz" "Fx" "Fy-Mz"];
choice = menu(msg,opts);
switch choice
    case 1
        Fy_Plot2_N
    case 2
        Mz_Plot2_N
    case 3
        Fx_Plot2_N
    case 4
        Fy_Mz_Plot2_N
end

end