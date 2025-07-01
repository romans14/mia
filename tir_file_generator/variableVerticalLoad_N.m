function [] = variableVerticalLoad_N(x)
global File_tir_R20;
global File_tir_LC0;
global Norm_x;
global Norm_y_Fy;
global C;
ka = 0;
prompt = "insert the value of the pressure ";
pio = input(prompt);
prompt = "insert the value of the camber ";
g = input(prompt);
gamma = deg2rad(g);
Vx = 40/3.6;
al = deg2rad(-10:0.1:10);
Vcy = tan(al)*Vx;
Vsx = -ka*Vx;

prompt = "insert the first value of the vertical load ";
Fz = input(prompt);

msg = "Select the file you want to use";
opts = ["Hoosier_16X75x10_43075_7_in_rim_R20.tir" "Hoosier_16x75x10_LCO_8_in_rim_LC0.tir"];
file = menu(msg,opts);

switch file
    case 1
        tire = parse_tir_file(File_tir_R20);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot((C*Norm_x)/Fz,-Fy/(Norm_y_Fy*Fz))
        xlabel("[Normalized Slip Angle]")
        ylabel("[Normalized Output]")
        grid on

        hold on
        for i=1:x-1
            prompt = "insert the new value of the vertical load ";
            Fz = input(prompt);
            tire = parse_tir_file(File_tir_R20);
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot((C*Norm_x)/Fz,-Fy/(Norm_y_Fy*Fz))
            xlabel("[Normalized Slip Angle]")
            ylabel("[Normalized Output]")
        end
        hold off
    case 2
        tire = parse_tir_file(File_tir_LC0);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot((C*Norm_x)/Fz,-Fy/(Norm_y_Fy*Fz))
        xlabel("[Normalized Slip Angle]")
        ylabel("[Normalized Output]")
        grid on

        hold on
        for i=1:x-1
            prompt = "insert the new value of the vertical load ";
            Fz = input(prompt);
            tire = parse_tir_file(File_tir_LC0);
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot((C*Norm_x)/Fz,-Fy/(Norm_y_Fy*Fz))
            xlabel("[Normalized Slip Angle]")
            ylabel("[Normalized Output]")
        end
        hold off
end
end