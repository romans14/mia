function [] = Fy_Plot_N
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

prompt = "insert the value of the vertical load ";
Fz = input(prompt);

prompt = "insert the value of the camber ";
g = input(prompt);
gamma = deg2rad(g);

prompt = "insert the value of the pressure ";
pio = input(prompt);

msg = "Choose";
 opts = ["Not mecanical trail" "mecanical trail"];

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
            tire = parse_tir_file(File_tir_LC0);
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
             plot((C*Norm_x)/Fz,-(Fy*m)/(Fz*Norm_y_Fy))
           
        end
        hold off



end