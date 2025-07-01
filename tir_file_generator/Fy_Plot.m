function [] = Fy_Plot
global File_tir_R20;
global File_tir_LC0;
ka = 0;
Vx = 40/3.6;
al = deg2rad(-10:0.1:10);
Vcy = tan(al)*Vx;
Vsx = -ka*Vx;


prompt = "insert the value of the vertical load ";
Fz = input(prompt);

prompt = "insert the value of the camber ";
g = input(prompt);
gamma = deg2rad(g);

prompt = "insert the value of the pressure ";
pio = input(prompt);

msg = "Choose";
 opts = ["Hoosier_16X75x10_43075_7_in_rim_R20.tir and 'Hoosier_16x75x10_LCO_8_in_rim_LC0.tir'" ""];

file = menu(msg,opts);
switch file
   
    case 1
        tire = parse_tir_file(File_tir_R20);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot(x,y)
        xlabel("[deg]")
        ylabel("[N]")
        grid on

        hold on
        for i=1:2-1
            tire = parse_tir_file(File_tir_LC0);
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot(rad2deg(al),-Fy)
            xlabel("[deg]")
            ylabel("[N]")
        end
        hold off

% The following cases need an upgrade in case of a new generation of file .tir 

   case 2
         tire = parse_tir_file('');
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot(rad2deg(al),-Fy)
        grid on

        hold on
        for i=1:2-1
            tire = parse_tir_file('');
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot(rad2deg(al),-Fy)
        end
        hold off
    case 3
        tire = parse_tir_file('');
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot(rad2deg(al),-Fy)
        grid on

        hold on
        for i=1:2-1
            tire = parse_tir_file('');
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot(rad2deg(al),-Fy)
        end
        hold off
    case 4
         tire = parse_tir_file('');
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        plot(rad2deg(al),-Fy)
        grid on

        hold on
        for i=1:2-1
            tire = parse_tir_file('');
            [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
            plot(rad2deg(al),-Fy)
        end
        hold off

end