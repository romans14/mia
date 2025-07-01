%Created by: Marco Loguercio Polosa
%            Michele Lauriola

%Insert the file.tir of R20
global File_tir_R20;
File_tir_R20="Hoosier_16X75x10_43075_7_in_rim_R20.tir";

%Insert the file.tir of LC0
global File_tir_LC0;
File_tir_LC0="Hoosier_16x75x10_LCO_8_in_rim_LC0.tir";

al = deg2rad(-10:0.1:10);

%Normalizing coefficient
global Norm_x;
Norm_x=(tan(al))/(1.2);
global Norm_y_Fy;
Norm_y_Fy=1.2;
global Norm_y_Mz;
Norm_y_Mz=1.2;

addpath("_lib\")
addpath("..\_lib\")

msg = "Choose the option ";
opts = ["Force analysis" "Cornering Stiffness" "Braking Stiffness"];
option = menu(msg,opts);
switch option
    case 1
        Force_Analysis;
    case 2
        Cornering_Stiffnes;
    case 3
        Braking_Stiffness;

end
