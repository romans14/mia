clear
clc

t = importdata('C:\Users\Matteo\OneDrive\UNI\UNIFI\tesi\continental\materiale continental\Continental\DataSet\DriveBrake_Combined\B1965run48.dat');

%% Estrazione Dati
names   = t.textdata{2};
nchans  = size (t.data,2);

%Assigning data arry to each name
for n=1:nchans % demultiplex
[name,names]=strtok(names);
eval([upper(name) '= t.data(:,' num2str(n) ');']);
end

clear names
clear name

%% Grafici per verificare cosa succede nella prova
figure

subplot (4,1,1)
plot (ET,V,'.')
ylabel('Speed [km/hr]')

subplot(4,1,2)
plot (ET, P,'.')
ylabel('Pressure [kPa]')

subplot(4,1,3)
plot(ET,FZ,'.')
ylabel('FZ [N]')

subplot(4,1,4)
plot(ET,FZ,'.')
ylabel('Load [N]')
xlabel('Tempo [s]')

figure
plot (ET,-FZ,'.')
grid on
xlabel('Time [s]')
ylabel('FZ [N]')

%% Estrazione Dati a Pressioni Costanti
for i=1:length(ET)-1
    p = 0;
    count = 0;
    for j=1:length(ET)-1
        if (abs(P(i)-P(j))<5)
            count = count+1;
            p = p+P(j);
        end
    end
    P(i) = p/count;
end
P = round (P,-1);
p = unique(P);

t.data(:,8) = P;

figure
subplot(4,1,1)
plot(ET,SA,'.')
ylabel('SlipAngle')

subplot(4,1,2)
plot(ET,SL,'.')
ylabel('SlipRatio')

IA = round (IA);
ia = unique (IA);
subplot(4,1,3)
plot(ET,IA,'.')
ylabel('Camber')

V = round(V,-1);
v = unique(V);


% Media delle FZ
FZ = abs(FZ);
FZ = round(FZ,-1);
for i=1:length(FZ)

    if(FZ(i)<=500)
        FZ(i)=400;
    end

    if(FZ(i)>500 && FZ(i)<=850)
        FZ(i)=700;
    end

    if(FZ(i)>850 && FZ(i)<=1300)
        FZ(i)=1100;
    end

    if(FZ(i)>1300)
        FZ(i)=1500;
    end
end
fz = unique(FZ);

subplot(4,1,4)
plot(ET,TSTC,'.')
ylabel('Tire Temperature [°C]')
xlabel('Tempo [s]')

% FX0 = FX./FZ;
% FY0 = FY./FZ;
% MZ0 = MZ./FZ;

SA = round(SA);
sa = unique(SA);
nincls = length(ia);
nslips = length(sa);

q = 0;
fmdata = zeros(q);
% Subset the data:
for n=1:length (ET)
    
    q=q+1;
    fmdata(q,1)=IA(n);
    fmdata(q,2)=SL(n);
    fmdata(q,3)=SA(n);
    fmdata(q,4)=FX(n);
    fmdata(q,5)=FY(n);
    fmdata(q,6)=MZ(n);
    fmdata(q,10)=P(n);
    fmdata(q,11)=FZ(n);
    fmdata(q,12)=TSTI(n);
    fmdata(q,13)=TSTC(n);
    fmdata(q,14)=TSTO(n);
    
end



for n=1:length(p)
    Pn = find(fmdata(:,10) == p(n));
       fmdatan = fmdata(Pn,:);
       
    for k=1:nslips
        SAk = find(fmdatan(:,3) == sa(k));
        fmdatank = fmdatan(SAk,:);
        figure
        title(sprintf('Longitudinal Force vs. Slip Ratio (P = %gkPa, SA= %g°)',p(n),sa(k)))
        hold all
        for h=1:length(fz)
            FZh = find(fmdatank(:,11) == fz(h));
            fmdatankh = fmdatank(FZh,:);
            for z=1:nincls
                IAz = find(fmdatankh(:,1) == ia(z));
                fmdatankhz = fmdatankh(IAz,:);
            
                grid on
                ylabel('FX [N]')
                xlabel('Slip [-]')
                plot (fmdatankhz(:,2),fmdatankhz(:,4),'LineWidth',2,'DisplayName',sprintf('FZ=%dN, IA=%i°',fz(h),ia(z)))
            end
            %Sollecitazioni
%             f = csaps(fmdatankz(:,2),fmdatankz(:,4),.999);
%             fnplt(f)

%             lgd{z} = strcat(sprintf('IA=%g°, SA=%g°, P=%gkPa',ia(z),sa(k),p(n)));
        end
%         legend (lgd,'location','best')
        legend ('location','best')
    end
end


for n=1:length(p)
    Pn = find(fmdata(:,10) == p(n));
    fmdatan = fmdata(Pn,:);
    figure
    title(sprintf('Ellisse di aderenza (P = %gkPa)',p(n)))
    hold on
    for h=2:length(fz)
        FZh = find(fmdatan(:,11) == fz(h));
        fmdatanh = fmdatan(FZh,:);

        for k=1:nincls
            IAk = find(fmdatanh(:,1) == ia(k));
            fmdatanhk = fmdatanh(IAk,:);

            %Sollecitazioni
            plot (fmdatanhk(:,5),fmdatanhk(:,4),'LineWidth',2,'DisplayName',sprintf('IA=%i°, FZ=%dN',ia(k),fz(h)))
            ylabel('FX [N]')
            xlabel('FY [N]')
            grid on
            legend('-DynamicLegend','Location','best')
        end
            
    end
end

%% Temperature
for n=1:length(p)
    Pn = find(fmdata(:,10) == p(n));
       fmdatan = fmdata(Pn,:);
       FZh = find(fmdatan(:,11)>1000 & fmdatan(:,11)<1200);
       fmdatanh = fmdatan(FZh,:);


    for k=1:nslips
        SAk = find(fmdatanh(:,3) == sa(k));
        fmdatanhk = fmdatanh(SAk,:);      
        figure
            for z=1:nincls
                subplot(nincls,1,z)
                IAz = find(fmdatanhk(:,1) == ia(z));
                fmdatanhkz = fmdatanhk(IAz,:);
                plot (fmdatanhkz(:,2),fmdatanhkz(:,12),'LineWidth',2,'DisplayName',sprintf('TSTI'))
                hold on
                plot (fmdatanhkz(:,2),fmdatanhkz(:,13),'LineWidth',2,'DisplayName',sprintf('TSTC'))
                hold on
                plot (fmdatanhkz(:,2),fmdatanhkz(:,14),'LineWidth',2,'DisplayName',sprintf('TSTO'))
                grid on
                title(sprintf('Tire Temperatrure vs. Slip Ratio (P = %gkPa, IA= %g°, SA= %g°)',p(n),ia(z),sa(k)))
                ylabel('Temperature °C')
                xlabel('Slip [-]')
                legend ('location','best')

            end 
    end

    IA0 = find(fmdatanh(:,1) == 0);
    fmdatanh0 = fmdatanh(IA0,:);
    figure
    for k=1:nslips
        SAk = find(fmdatanh0(:,3) == 0);
        fmdatanh0k = fmdatanh0(SAk,:);
        subplot(nslips,1,k)
        plot (fmdatanh0k(:,2),fmdatanh0k(:,12),'LineWidth',2,'DisplayName',sprintf('TSTI'))
        hold on
        plot (fmdatanh0k(:,2),fmdatanh0k(:,13),'LineWidth',2,'DisplayName',sprintf('TSTC'))
        hold on
        plot (fmdatanh0k(:,2),fmdatanh0k(:,14),'LineWidth',2,'DisplayName',sprintf('TSTO'))
        grid on
        title(sprintf('Tire Temperatrure vs. Slip Ratio (P = %gkPa, IA= %g°, SA= %g°, FZ= %gN)',p(n),0,sa(k),1100))
        ylabel('Temperature °C')
        xlabel('Slip [-]')
        legend ('location','best')
    end
end