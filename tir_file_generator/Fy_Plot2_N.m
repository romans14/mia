function [] = Fy_Plot2_N
global File_tir_R20;
global File_tir_LC0;
global Norm_x;
global Norm_y_Fy;
global C;
ka = 0;
Vx = 40/3.6;
al = deg2rad(-10:0.1:10);
Vcy = tan(al)*Vx;
Vsx = -ka*Vx;
m=0.004; %mecanical trail

prompt = "insert the value of the vertical load for R20 ";
Fz = input(prompt);

prompt = "insert the value of the camber for R20 ";
g = input(prompt);
gamma = deg2rad(g);

prompt = "insert the value of the pressure for R20 ";
pio = input(prompt);

msg = "Choose";
opts = ["Not mecanical trail" "Mecanical trail"];

file = menu(msg,opts);
switch file
   
    case 1
        tire = parse_tir_file(File_tir_R20);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot((C*Norm_x)/Fz,-Fy/(Fz*Norm_y_Fy))
        grid on

        hold on
        for i=1:2-1
            promt = "insert the same value of vertical load as before"
            prompt = "insert the value of the vertical load for LC0 ";
            Fz = input(prompt);
            prompt = "insert the value of the camber for LC0 ";
            g = input(prompt);
            gamma = deg2rad(g);
            prompt = "insert the value of the pressure for LC0 ";
            pio = input(prompt);

            tire = parse_tir_file(File_tir_LC0);
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot((C*Norm_x)/Fz,-Fy/(Fz*Norm_y_Fy))
        end
        hold off
    case 2 %mecanical trail
        tire = parse_tir_file(File_tir_R20);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot((C*Norm_x)/Fz,-(Fy*m)/(Fz*Norm_y_Fy))
        grid on

        hold on
        for i=1:2-1
            promt = "insert the same value of vertical load as before"
            prompt = "insert the value of the vertical load for LC0 ";
            Fz = input(prompt);
            prompt = "insert the value of the camber for LC0 ";
            g = input(prompt);
            gamma = deg2rad(g);
            prompt = "insert the value of the pressure for LC0 ";
            pio = input(prompt);

            tire = parse_tir_file(File_tir_LC0);
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot((C*Norm_x)/Fz,-(Fy*m)/(Fz*Norm_y_Fy))
        end
        hold off



end