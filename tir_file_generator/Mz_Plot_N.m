function [] = Mz_Plot_N
global File_tir_R20;
global File_tir_LC0;
global Norm_x;
global Norm_y_Mz;
global C;
ka = 0;
Vx = 40/3.6;
al = deg2rad(-10:0.1:10);
Vcy = tan(al)*Vx;
Vsx = -ka*Vx;

m=0.004; % mecanical trail
prompt = "insert the value of the vertical load ";
Fz = input(prompt);

prompt = "insert the value of the camber ";
g = input(prompt);
gamma = deg2rad(g);

prompt = "insert the value of the pressure ";
pio = input(prompt);

        msg = "Choose";
 opts = ["Mz" "Total moment"];
file = menu(msg,opts);
switch file
   
    case 1
        tire = parse_tir_file(File_tir_R20);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot((C*Norm_x)/Fz,-Mz/(Fz*Norm_y_Mz))
        xlabel("[Normalized slip angle]")
        ylabel("[Normalized output]")
        grid on

        hold on
        for i=1:2-1
            tire = parse_tir_file(File_tir_LC0);
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot((C*Norm_x)/Fz,-Mz/(Fz*Norm_y_Mz))
            xlabel("[Normalized slip angle]")
            ylabel("[Normalized output]")
        end
        hold off
    case 2 %total moment
         tire = parse_tir_file(File_tir_R20);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        TM=(Mz+(Fy*m));
        plot((C*Norm_x)/Fz,-TM/(Fz*Norm_y_Mz))
        xlabel("[Normalized slip angle]")
        ylabel("[Normalized output]")
        grid on

        hold on
        for i=1:2-1
            tire = parse_tir_file(File_tir_LC0);
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            TM=(Mz+(Fy*m));
            plot((C*Norm_x)/Fz,-TM/(Fz*Norm_y_Mz))
            xlabel("[Normalized slip angle]")
            ylabel("[Normalized output]")
        end
        hold off

end
