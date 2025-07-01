clear
clc

[filename, pathname]= uigetfile('*.dat','Enter TIRF Test File');
t=importdata([pathname filename]);

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
plot(ET,AMBTMP,'.')
ylabel('T_AMB[°C]')

subplot(4,1,4)
plot(ET,SR,'.')
ylabel('SlipRatio')

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
plot(ET,TSTC,'.')
ylabel('TSTC [°C]')
xlabel('Tempo [s]')

IA = round (IA);
ia = unique (IA);
subplot(4,1,3)
plot(ET,IA,'.')
ylabel('Camber')

SA = round(SA,1);
V = round(V,-1);
v = unique(V);


% Media delle FZ
FZ = abs(FZ);
FY0 = FY./FZ;
MZ0 = MZ./FZ;

for i=1:length(FZ)

    if(FZ(i)<=300)
        FZ(i)=220;
    end

    if(FZ(i)>300 && FZ(i)<=550)
        FZ(i)=440;
    end

    if(FZ(i)>550 && FZ(i)<=900)
        FZ(i)=770;
    end

    if(FZ(i)>900 && FZ(i)<=1300)
        FZ(i)=1110;
    end

    if(FZ(i)>1300)
        FZ(i)=1550;
    end
end

fz = unique (FZ);

subplot(4,1,4)
plot(ET,FZ,'.')
ylabel('VerticalLoad')
xlabel('Tempo [s]')

q = 0;
fmdata = zeros(q);
% Subset the data:
for n=1:length (ET)
    
    q=q+1;
    fmdata(q,1)=IA(n);
    fmdata(q,2)=FZ(n);
    fmdata(q,3)=SA(n);
    fmdata(q,4)=FY0(n);
    fmdata(q,5)=MZ0(n);
    fmdata(q,6)=FX(n);
    fmdata(q,7)=TSTI(n);
    fmdata(q,8)=TSTC(n);
    fmdata(q,9)=TSTO(n);
    fmdata(q,10)=P(n);
    fmdata(q,11)=FY(n);
    fmdata(q,12)=MZ(n);
    fmdata(q,13)=ET(n);
    
end


% Cornering Stiffnes
figure
hold on
for n=1:length(p)
    Pn = find(fmdata(:,10) == p(n));
    fmdatan = fmdata(Pn,:);
    
    IA0 = find(fmdatan(:,1) == 0);
    fmdatan0 = fmdatan(IA0,:);
    SA0 = find (fmdatan0(:,3)>-0.3 & fmdatan0(:,3)<0);
    fmdatan00 = fmdatan0(SA0,:);

    for z = 1:length(fz)
        FZz0 = find(fmdatan00(:,2) == fz(z));
        fmdatan00z = fmdatan00(FZz0,:);

        C_sa(z) = mean (-fmdatan00z(:,11)./fmdatan00z(:,3));
    end

    plot (fz,C_sa,'o')
%     C_SA = csaps(fz,C_sa,.9);
%     fnplt(C_SA)
    grid on
    title(sprintf('Cornering Stiffnes'));
    xlabel('FZ [N]')
    ylabel('Cornering Stiffnes [N/°]')
    lgd{n} = strcat(sprintf('P=%gkPa',p(n)));
end
legend (lgd,'location','best')

% Temperature
for n=1:length(p)
    Pn = find(fmdata(:,10) == p(n));
    fmdatan = fmdata(Pn,:);

    for k=3:length(fz)
    FZk = find(fmdatan(:,2) == fz(k));
    fmdatank = fmdatan(FZk,:);
%     FY
    figure
    count = 0;
        for z = 1:length(ia)
            IAz = find(fmdatank(:,1) == ia(z));
            fmdatankz = fmdatank(IAz,:);
%             TSTI vs. Slip
            
%             count = count+1;
%             subplot(length(ia)-2,1,count)
            subplot(length(ia),1,z)
            plot (fmdatankz(:,3),fmdatankz(:,7),'LineWidth',2,'DisplayName',sprintf('TSTI'))
            ylabel('T [°C]')
            legend ('-DynamicLegend','Location','best')
            grid on
            hold on
%             TSTC vs. Slip
            plot (fmdatankz(:,3),fmdatankz(:,8),'LineWidth',2,'DisplayName',sprintf('TSTC'))
            ylabel('T [°C]')
            grid on
            hold on
%             TSTO vs. Slip
            plot (fmdatankz(:,3),fmdatankz(:,9),'LineWidth',2,'DisplayName',sprintf('TSTO'))
            title(sprintf('Tire Temperatrure vs. Slip Ratio (P = %gkPa, IA= %g°, FZ= %gN)',p(n),ia(z),fz(k)))
            xlabel('Slip Angle [deg]')
            ylabel('T [°C]')
            grid on

        end
        
    end
end

% Sollecitazioni
for n=1:length(p)
    Pn = find(fmdata(:,10) == p(n));
    fmdatan = fmdata(Pn,:);

    for k=3:length(fz)
    FZk = find(fmdatan(:,2) == fz(k));
    fmdatank = fmdatan(FZk,:);
%     FY
    figure
        for z = 1:length(ia)
            IAz = find(fmdatank(:,1) == ia(z));
            fmdatankz = fmdatank(IAz,:);
%             FY vs. Slip
            plot (fmdatankz(:,3),fmdatankz(:,11),'LineWidth',2,'DisplayName',sprintf('IA=%i°',ia(z)))
            ylabel('FY')
            title(sprintf('FY vs. SA (P = %g kPa, FZ = %g N)',p(n),fz(k)))
            xlim([-8,8]);
            xlabel('SA')
            legend ('-DynamicLegend','Location','best')
            grid on
            hold on
        end

%         MZ
        figure
        for z = 1:length(ia)
            IAz = find(fmdatank(:,1) == ia(z));
            fmdatankz = fmdatank(IAz,:);
%             FY vs. Slip
            plot (fmdatankz(:,3),fmdatankz(:,12),'LineWidth',2,'DisplayName',sprintf('IA=%i°',ia(z)))
            ylabel('MZ')
            xlabel('SA')
            xlim([-8,8]);
            title(sprintf('MZ vs. SA (P = %g kPa, FZ = %g N)',p(n),fz(k)))
            legend ('-DynamicLegend','Location','best')
            grid on
            hold on
        end
    end
end

% %% WarmUp
% for n=1:length(p)
%     Pn = find(fmdata(:,10) == p(n));
%     fmdatan = fmdata(Pn,:);
% 
%     IA0 = find(fmdatan(:,1) == 0);
%     fmdatan0 = fmdatan(IA0,:);
%     FZ0 = find (fmdatan0(:,2)>1000 & fmdatan0(:,2)<1200);
%     fmdatan00 = fmdatan0(FZ0,:);
% 
%     figure
%     plot3 (fmdatan00(:,8),fmdatan00(:,13),fmdatan00(:,11),'LineWidth',2)
%     ylim([150,250])
%     xlabel('Tire Surface Temperature Center [°C]')
%     ylabel('Time [sec]')
%     zlabel('Lateral Force')
%     grid on
%     title(sprintf('Lateral Force vs. Temperature (P = %g kPa, FZ = %g N, IA = %g°)',p(n),1100,0))
%     view(0,0)
% end