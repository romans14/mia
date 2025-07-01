function [] = Cornering_Stiffnes
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
 opts = ["Hoosier_16X75x10_43075_7_in_rim_R20.tir" "'Hoosier_16x75x10_LCO_8_in_rim_LC0.tir'"];

file = menu(msg,opts);
switch file
   
    case 1
        tire = parse_tir_file(File_tir_R20);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        x=(al);
        y=-Fy;
        plot(x,y)
        xlabel("[rad]")
        ylabel("[N]")
        grid on
        [x0, y0] = ginput(1); % acquisizione delle coordinate del punto iniziale
        [~, idx] = min(abs(x - x0)); % ricerca dell'indice del punto iniziale
        m = (y(idx+1) - y(idx)) / (x(idx+1) - x(idx)); % calcolo della pendenza iniziale
        disp(['Cornering Stiffnes is ', num2str(m)]);

    case 2
        tire = parse_tir_file(File_tir_LC0);
        [Fx,Fy,Mx,Mz] = MF4_nopsi_adams(tire,Vx,Vcy,Vsx,Fz,gamma,pio);
        figure
        x=(al);
        y=-Fy;
        plot(x,y)
        xlabel("[rad]")
        ylabel("[N]")
        grid on
        [x0, y0] = ginput(1); % acquisizione delle coordinate del punto iniziale
        [~, idx] = min(abs(x - x0)); % ricerca dell'indice del punto iniziale
        m = (y(idx+1) - y(idx)) / (x(idx+1) - x(idx)); % calcolo della pendenza iniziale
        disp(['Cornering Stiffnes is ', num2str(m)]);

end
