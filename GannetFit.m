function MRS_struct = GannetFit(MRS_struct, varargin)
%Gannet 3.0 GannetFit
%Started by RAEE Nov 5, 2012
%Updates by MGS, MM 2016-2017

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Gannet 3.0 version of Gannet Fit - analysis tool for GABA-edited MRS
% Need some new sections like
%   1. GABA, Glx and GSH Fit
%   2. Water Fit
%   3. Cr Fit
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Changes made to the code for Gannet3.0:
% GABA and Glx outputs are saved in seperate structure fields -- MGSaleh 29 June 2016
% Concentration estimates from GABAGlx fitting -- MGSaleh 13 July 2016
% GSH output is saved in seperate structure fields -- MGSaleh January 2017

% Input parameters and some definitions:
% Determine whether multiple regions and fitting targets or not and then use it to
% create a loop -- MGSaleh 2016

if MRS_struct.p.PRIAM % deciding how many regions are there -- MGSaleh 2016
    vox = {MRS_struct.p.Vox};
else
    vox = {MRS_struct.p.Vox{1}};
end

if MRS_struct.p.HERMES && nargin < 2
    target = {MRS_struct.p.target, MRS_struct.p.target2};
else
    % varargin = Optional arguments if user wants to overwrite fitting
    %            parameters set in GannetPreInitialise; can include several
    %            options, which are:
    %            'GABA' or 'Glx': target metabolite
    if nargin > 1
        switch varargin{1}
            case 'GABA'
                MRS_struct.p.target = 'GABA';
            case 'Glx'
                MRS_struct.p.target = 'Glx';
            case 'GABAGlx'
                MRS_struct.p.target = 'GABAGlx';
            case 'GSH'
                MRS_struct.p.target = 'GSH';
        end
    end
    target = {MRS_struct.p.target};
end

freq = MRS_struct.spec.freq;
MRS_struct.versionfit = '170705';
pdfdirname = './GannetFit_output'; % MM (170121)

lsqopts = optimset('lsqcurvefit');
lsqopts = optimset(lsqopts,'Display','off','TolFun',1e-10,'Tolx',1e-10,'MaxIter',1e5);
nlinopts = statset('nlinfit');
nlinopts = statset(nlinopts,'MaxIter',1e4);

% Loop over voxels if PRIAM
for kk = 1:length(vox)
    
    if strcmp(MRS_struct.p.Reference_compound,'H2O')
        WaterData = MRS_struct.spec.(vox{kk}).water;
    end
    
    % Loop over edited spectra if HERMES
    for trg = 1:length(target)
        
        fprintf('\nFitting %s...',target{trg});
        
        % Defining variables -- MGSaleh 2016
        DIFF = MRS_struct.spec.(vox{kk}).(target{trg}).diff;
        OFF  = MRS_struct.spec.(vox{kk}).(target{trg}).off;
        numscans = size(DIFF,1);
        
        for ii = 1:numscans
            
            if strcmp(target{trg},'GABA')
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %   1.  GABA Fit
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                % Hard code it to fit from 2.79 ppm to 3.55 ppm
                freqbounds = find(freq <= 3.55 & freq >= 2.79); % MM (170705)
                plotbounds = find(freq <= 3.6 & freq >= 2.7);
                
                maxinGABA = abs(max(real(DIFF(ii,freqbounds))) - min(real(DIFF(ii,freqbounds))));                
                grad_points = (real(DIFF(ii,freqbounds(end))) - real(DIFF(ii,freqbounds(1)))) ./ abs(freqbounds(end) - freqbounds(1));
                LinearInit = grad_points ./ abs(freq(1) - freq(2));
                constInit = (real(DIFF(ii,freqbounds(end))) + real(DIFF(ii,freqbounds(1))))./2;
                
                GaussModelInit1 = [maxinGABA -90 3.026 -LinearInit constInit];
                lb = [0 -200 2.87 -40*maxinGABA -2000*maxinGABA];
                ub = [4000*maxinGABA -40 3.12 40*maxinGABA 1000*maxinGABA];
                
                % Least-squares model fitting
                GaussModelInit = lsqcurvefit(@GaussModel, GaussModelInit1, freq(freqbounds), real(DIFF(ii,freqbounds)), lb, ub, lsqopts);
                [GaussModelParam, resid] = nlinfit(freq(freqbounds), real(DIFF(ii,freqbounds)), @GaussModel, GaussModelInit, nlinopts);
                % 1111013 restart the optimisation, to ensure convergence
                %for fit_iter = 1:100
                %    [GaussModelParam, residg] = nlinfit(freq(freqbounds), real(DIFF(ii,freqbounds)), @GaussModel, GaussModelInit, nlinopts);
                %    GaussModelInit = GaussModelParam;
                %end
                
                GABAheight = GaussModelParam(1);
                MRS_struct.out.(vox{kk}).(target{trg}).FitError(ii) = 100*std(resid)/GABAheight;
                MRS_struct.out.(vox{kk}).(target{trg}).Area(ii) = GaussModelParam(1)./sqrt(-GaussModelParam(2))*sqrt(pi);
                sigma = sqrt(1/(2*(abs(GaussModelParam(2)))));
                MRS_struct.out.(vox{kk}).(target{trg}).FWHM(ii) = abs((2* MRS_struct.p.LarmorFreq) * sigma);
                MRS_struct.out.(vox{kk}).(target{trg}).ModelParam(ii,:) = GaussModelParam;
                MRS_struct.out.(vox{kk}).(target{trg}).Resid(ii,:) = resid;
                
                % Calculate SNR of GABA signal (MM: 170502)
                noiseSigma_DIFF = CalcNoise(freq, DIFF(ii,:));
                MRS_struct.out.(vox{kk}).(target{trg}).SNR(ii) = abs(GABAheight)/noiseSigma_DIFF;
                
            elseif strcmp(target{trg},'GSH')
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %   1.  GSH Fit
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                % Hard code it to fit from 2.35 ppm to 3.3 ppm
                freqbounds = find(freq <= 3.3 & freq >= 2.35); % MM (170705)
                plotbounds = find(freq <= 4.2 & freq >= 1.75);
                
                %offset = real(mean(DIFF(ii, freqbounds(1:10)),2) + mean(DIFF(ii, freqbounds((end-9):end)),2))/2;
                %slope = real(mean(DIFF(ii, freqbounds(1:10)),2) - mean(DIFF(ii, freqbounds((end-9):end)),2))/real(MRS_struct.spec.freq(freqbounds(1)) - MRS_struct.spec.freq(freqbounds(end)));
                peak_amp = 0.03; %Presumably this won't work for some data... for now it seems to work.
                
                FiveGaussModelInit = [peak_amp*0.7 -300 2.95 peak_amp*0.8 -500 2.73 -peak_amp*2.5 -1000 2.61 -peak_amp*2.5 -1000 2.55 peak_amp*0.5 -600 2.42  0 0 0.02];
                lb = [0 -5000   2.9 0 -5000  2.68 -0.3 -5000    2.57 -0.3 -5000   2.48 0 -5000    2.3 -0.1 -0.01 -0.01];
                ub = [0.1 -50   3.0 0.1 -50   2.8   0 -50    2.68      0 -50   2.57 0.1 0     2.43 0.1 0.01 0.03];
                
                % Least-squares model fitting
                FiveGaussModelInit = lsqcurvefit(@FiveGaussModel, FiveGaussModelInit, freq(freqbounds), real(DIFF(ii,freqbounds)), lb, ub, lsqopts);
                [FiveGaussModelParam, resid] = nlinfit(freq(freqbounds), real(DIFF(ii,freqbounds)), @FiveGaussModel, FiveGaussModelInit, nlinopts);
                
                MRS_struct.out.(vox{kk}).GSH.FiveGaussModel(ii,:)=FiveGaussModelParam;
                GSHGaussModelParam=FiveGaussModelParam;
                GSHGaussModelParam(4:3:13)=0;
                %NAAGaussModelParam=FiveGaussModelParam;
                %NAAGaussModelParam(1)=0;
                
                BaselineModelParam=GSHGaussModelParam;
                BaselineModelParam(1)=0;                
                
                % GSH fitting output -- MGSaleh
                MRS_struct.out.(vox{kk}).(target{trg}).Area(ii) = real(sum(FiveGaussModel(GSHGaussModelParam, freq(freqbounds)) - FiveGaussModel(BaselineModelParam, freq(freqbounds)))) ...
                    * abs(freq(1)-freq(2));
                GSHheight = GSHGaussModelParam(1);
                
                % Range to determine residuals for GSH (MM: 170705)
                residfreq = freq(freqbounds);
                residGSH = resid(residfreq <= 3.3 & residfreq >= 2.77);
                
                % GSH fitting output -- MGSaleh
                MRS_struct.out.(vox{kk}).(target{trg}).FitError(ii) = 100*std(residGSH)/GSHheight;
                sigma = sqrt(1/(2*(abs(GSHGaussModelParam(2)))));
                MRS_struct.out.(vox{kk}).(target{trg}).FWHM(ii) =  abs((2*MRS_struct.p.LarmorFreq)*sigma);
                MRS_struct.out.(vox{kk}).(target{trg}).ModelParam(ii,:) = GSHGaussModelParam;
                MRS_struct.out.(vox{kk}).(target{trg}).Resid(ii,:) = residGSH;
                
                % Calculate SNR of GSH signal (MM: 170502)
                noiseSigma_DIFF = CalcNoise(freq, DIFF(ii,:));
                MRS_struct.out.(vox{kk}).(target{trg}).SNR(ii) = abs(GSHheight)/noiseSigma_DIFF;
                
            elseif strcmp(target{trg},'Lac')
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %   1.  Lac Fit
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                % This is a work in progress - currenly mainly code copied form GSH
                % Hard code it to fit from 0.5 ppm to 1.8 ppm              
                freqbounds = find(freq <= 1.8 & freq >= 0.5); % MM (170705)
                plotbounds = find(freq <= 2 & freq >= 0);
                
                offset = (mean(DIFF(ii,freqbounds(1:10)),2) + mean(DIFF(ii,freqbounds((end-9):end)),2))/2;
                slope = (mean(DIFF(ii,freqbounds(1:10)),2) - mean(DIFF(ii,freqbounds((end-9):end)),2))/abs(freq(freqbounds(1)) - freq(freqbounds(end)));
                peak_amp = 0.03; %Presumably this won't work for some data... for now it seems to work.
                
                FourGaussModelInit = [peak_amp*0.16 -100 1.18 peak_amp*0.3 -1000 1.325   offset slope 0];
                lb = [0 -300 0.9 0 -5000 1.0  -1 -1 -1];
                ub = [1 0 1.4 1 0 1.6  1 1 1];
                
                %Plot the starting fit model
                %figure(99)
                %subplot(1,2,1)
                %plot(MRS_struct.spec.freq(freqbounds),real(MRS_struct.spec.diff(ii,freqbounds)),MRS_struct.spec.freq(freqbounds),FourGaussModel(initx,MRS_struct.spec.freq(freqbounds)));
                
                FourGaussModelInit = lsqcurvefit(@FourGaussModel, FourGaussModelInit, freq(freqbounds), real(DIFF(ii,freqbounds)), lb, ub,lsqopts);
                [FourGaussModelParam, resid] = nlinfit(freq(freqbounds), real(DIFF(ii,freqbounds)), @FourGaussModel, FourGaussModelInit, nlinopts);

                %subplot(1,2,2)
                %plot(MRS_struct.spec.freq(freqbounds),real(MRS_struct.spec.diff(ii,freqbounds)),MRS_struct.spec.freq(freqbounds),FourGaussModel(FourGaussModelParam,MRS_struct.spec.freq(freqbounds)),MRS_struct.spec.freq(freqbounds),FourGaussModel([FourGaussModelParam(1:3) 0 FourGaussModelParam(5:end)],MRS_struct.spec.freq(freqbounds)));
                %error('Fitting Init model plot')                
                
                LacGaussModelParam=FourGaussModelParam;
                LacGaussModelParam(1)=0;
                MMGaussModelParam=FourGaussModelParam;
                MMGaussModelParam(4)=0;
                
                BaselineModelParam=MMGaussModelParam;
                BaselineModelParam(1)=0;
                
                MRS_struct.out.GABAArea(ii)=real(sum(FourGaussModel(LacGaussModelParam, freq(freqbounds))-FourGaussModel(BaselineModelParam, freq(freqbounds))))*(freq(1)-freq(2));
                %Not sure how to handle fit error. For now, do whole range
                GABAheight = LacGaussModelParam(ii,4);
                MRS_struct.out.GABAFitError(ii)=  100*std(resid)/GABAheight;
                
            elseif strcmp(MRS_struct.p.target,'Glx')
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %   1.  Glx Fit
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                % Hard code it to fit from 3.45 ppm to 4.1 ppm
                freqbounds = find(freq <= 4.1 & freq >= 3.45); % MM (170705)
                plotbounds = find(freq <= 4.5 & freq >= 3);
                
                maxinGABA = max(real(DIFF(ii,freqbounds)));
                grad_points = (real(DIFF(ii,freqbounds(end))) - real(DIFF(ii,freqbounds(1)))) ./ abs(freqbounds(end) - freqbounds(1));
                LinearInit = grad_points ./ abs(freq(1) - freq(2));
                constInit = (real(DIFF(ii,freqbounds(end))) + real(DIFF(ii,freqbounds(1))))./2;
                
                GaussModelInit = [maxinGABA -90 3.72 maxinGABA -90 3.77 -LinearInit constInit];
                lb = [0 -200 3.72-0.01 0 -200 3.77-0.01 -40*maxinGABA -2000*maxinGABA];
                ub = [4000*maxinGABA -40 3.72+0.01 4000*maxinGABA -40 3.77+0.01 40*maxinGABA 1000*maxinGABA];
                
                GaussModelInit = lsqcurvefit(@DoubleGaussModel, GaussModelInit, freq(freqbounds), real(DIFF(ii,freqbounds)), lb, ub, lsqopts);
                [GaussModelParam, resid] = nlinfit(freq(freqbounds), real(DIFF(ii,freqbounds)), @DoubleGaussModel, GaussModelInit, nlinopts);
                
                Glxheight = max(GaussModelParam([1,4]));
                MRS_struct.out.(vox{kk}).(target{trg}).FitError(ii) = 100*std(resid)/Glxheight;
                MRS_struct.out.(vox{kk}).(target{trg}).Area(ii) = (GaussModelParam(1)./sqrt(-GaussModelParam(2))*sqrt(pi)) + ...
                    (GaussModelParam(4)./sqrt(-GaussModelParam(5))*sqrt(pi));
                sigma = ((1/(2*(abs(GaussModelParam(2))))).^(1/2)) + ((1/(2*(abs(GaussModelParam(5))))).^(1/2));
                MRS_struct.out.(vox{kk}).(target{trg}).FWHM(ii) = abs((2*MRS_struct.p.LarmorFreq)*sigma);
                MRS_struct.out.(vox{kk}).(target{trg}).ModelParam(ii,:) = GaussModelParam;
                MRS_struct.out.(vox{kk}).(target{trg}).Resid(ii,:) = resid;
                
                % Calculate SNR of Glx signal (MM: 170502)
                noiseSigma_DIFF = CalcNoise(freq, DIFF(ii,:));
                MRS_struct.out.(vox{kk}).Glx.SNR(ii) = abs(Glxheight)/noiseSigma_DIFF;
                
            elseif strcmp(target{trg},'GABAGlx')
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %   1.  GABA+Glx Fit
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                % Hard code it to fit from 2.79 ppm to 4.1 ppm
                freqbounds = find(freq <= 4.1 & freq >= 2.79); % MM (170705)
                plotbounds = find(freq <= 4.2 & freq >= 2.7);

                maxinGABA = max(real(DIFF(ii,freqbounds)));
                grad_points = (real(DIFF(ii,freqbounds(end))) - real(DIFF(ii,freqbounds(1)))) ./ abs(freqbounds(end) - freqbounds(1));
                LinearInit = grad_points ./ abs(freq(1) - freq(2));
                
                GaussModelInit = [maxinGABA -400 3.725 maxinGABA -400 3.775 maxinGABA -90 3.02 -LinearInit 0 0];
                lb = [-4000*maxinGABA -800 3.725-0.02 -4000*maxinGABA -800 3.775-0.02 -4000*maxinGABA -200 3.02-0.05 -40*maxinGABA -2000*maxinGABA -2000*maxinGABA];
                ub = [4000*maxinGABA -40 3.725+0.02 4000*maxinGABA -40 3.775+0.02 4000*maxinGABA -40 3.02+0.05 40*maxinGABA 1000*maxinGABA 1000*maxinGABA];
                
                % Down-weight Cho subtraction artifact and signals
                % downfield of Glx (for HERMES) by including observation
                % weights in nonlinear regression; improves accuracy of
                % peak fittings (MM: 170701)
                w = ones(size(DIFF(ii,freqbounds)));
                residfreq = freq(freqbounds);
                ChoRange = residfreq >= 3.16 & residfreq <= 3.285;
                GlxDownFieldRange = residfreq >= 3.9 & residfreq <= 4.2;
                if MRS_struct.p.HERMES
                    w(ChoRange | GlxDownFieldRange) = 0.001;
                else
                    w(ChoRange) = 0.001;
                end
                
                % Least-squares model fitting
                GaussModelInit = lsqcurvefit(@GABAGlxModel, GaussModelInit, freq(freqbounds), real(DIFF(ii,freqbounds)), lb, ub, lsqopts);
                [GaussModelParam, resid] = nlinfit(freq(freqbounds), real(DIFF(ii,freqbounds)), @GABAGlxModel, GaussModelInit, nlinopts, 'Weights', w);
                
                % Range to determine residuals for GABA and Glx (MM: 170705)
                residGABA = resid(residfreq <= 3.55 & residfreq >= 2.79);
                residGlx = resid(residfreq <= 4.10 & residfreq >= 3.45);
                
                % GABA fitting output -- MGSaleh
                MRS_struct.out.(vox{kk}).GABA.Area(ii) = (GaussModelParam(7)./sqrt(-GaussModelParam(8))*sqrt(pi));
                GABAheight = GaussModelParam(7);
                MRS_struct.out.(vox{kk}).GABA.FitError(ii) = 100*std(residGABA)/GABAheight;
                sigma = sqrt(1/(2*(abs(GaussModelParam(8)))));
                MRS_struct.out.(vox{kk}).GABA.FWHM(ii) = abs((2*MRS_struct.p.LarmorFreq)*sigma);
                MRS_struct.out.(vox{kk}).GABA.ModelParam(ii,:) = GaussModelParam;
                MRS_struct.out.(vox{kk}).GABA.Resid(ii,:) = residGABA;
                
                % Calculate SNR of GABA signal (MM: 170502)
                noiseSigma_DIFF = CalcNoise(freq, DIFF(ii,:));
                MRS_struct.out.(vox{kk}).GABA.SNR(ii) = abs(GABAheight)/noiseSigma_DIFF;
                
                % Glx fitting output -- MGSaleh
                MRS_struct.out.(vox{kk}).Glx.Area(ii) = (GaussModelParam(1)./sqrt(-GaussModelParam(2))*sqrt(pi)) + ...
                    (GaussModelParam(4)./sqrt(-GaussModelParam(5))*sqrt(pi));
                Glxheight = max(GaussModelParam([1,4]));
                MRS_struct.out.(vox{kk}).Glx.FitError(ii) = 100*std(residGABA)/Glxheight;
                sigma = sqrt(1/(2*(abs(GaussModelParam(2))))) + sqrt(1/(2*(abs(GaussModelParam(5)))));
                MRS_struct.out.(vox{kk}).Glx.FWHM(ii) = abs((2*MRS_struct.p.LarmorFreq)*sigma);
                MRS_struct.out.(vox{kk}).Glx.ModelParam(ii,:) = GaussModelParam;
                MRS_struct.out.(vox{kk}).Glx.Resid(ii,:) = residGlx;
                
                % Calculate SNR of Glx signal (MM: 170502)
                MRS_struct.out.(vox{kk}).Glx.SNR(ii) = abs(Glxheight)/noiseSigma_DIFF;
                                
            else
                
                error('Fitting MRS_struct.p.target not recognised');
                
            end
            
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %   1a. Start up the output figure
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
            if ishandle(102)
                clf(102) % MM (170629)
            end
            h = figure(102);
            % MM (170629): Open figure in center of screen
            scr_sz = get(0, 'ScreenSize');
            fig_w = 1000;
            fig_h = 707;
            set(h, 'Position', [(scr_sz(3)-fig_w)/2, (scr_sz(4)-fig_h)/2, fig_w, fig_h]);
            set(h,'Color',[1 1 1]);
            figTitle = 'GannetFit Output';
            set(gcf,'Name',figTitle,'Tag',figTitle, 'NumberTitle','off');
            
            % GABA plot
            ha = subplot(2,2,1);
            metabmin = min(real(DIFF(ii,plotbounds)));
            metabmax = max(real(DIFF(ii,plotbounds)));
            resmax = max(resid);
            resid = resid + metabmin - resmax;
            if strcmp(target{trg},'GABA')
                plot(freq(plotbounds), real(DIFF(ii,plotbounds)), 'b', ...
                    freq(freqbounds), GaussModel(GaussModelParam,freq(freqbounds)), 'r', ...
                    freq(freqbounds), resid, 'k');
                set(gca,'XLim',[2.6 3.6]);
            elseif strcmp(target{trg},'GSH')
                plot(freq(plotbounds), real(DIFF(ii,plotbounds)), 'b' ,...
                    freq(freqbounds), FiveGaussModel(FiveGaussModelParam,freq(freqbounds)), 'r', ...
                    freq(freqbounds), FiveGaussModel(GSHGaussModelParam,freq(freqbounds)), 'g', ...
                    freq(freqbounds),resid, 'k');
                set(gca,'XLim',[1.8 4.2]);
            elseif strcmp(target{trg},'Lac')
                plot(freq(plotbounds), real(DIFF(ii,plotbounds)), 'b', ...
                    freq(freqbounds), FourGaussModel(FourGaussModelParam,freq(freqbounds)), 'r', ...
                    freq(freqbounds), FourGaussModel(MMGaussModelParam, freq(freqbounds)), 'r' , ...
                    freq(freqbounds), resid, 'k');
                set(gca,'XLim',[0 2.1]);
            elseif strcmp(target{trg},'Glx')
                plot(freq(plotbounds), real(DIFF(ii,plotbounds)), 'b', ...
                    freq(freqbounds), DoubleGaussModel(GaussModelParam,freq(freqbounds)), 'r', ...
                    freq(freqbounds), resid, 'k');
                set(gca,'XLim',[3.4 4.2])
            elseif strcmp (target{trg},'GABAGlx')
                plot(freq(plotbounds), real(DIFF(ii,plotbounds)), 'b', ...
                    freq(freqbounds), GABAGlxModel(GaussModelParam,freq(freqbounds)), 'r', ...
                    freq(freqbounds), resid, 'k');
                set(gca,'XLim',[2.7 4.2])
            end
            if strcmpi(MRS_struct.p.vendor,'Siemens')
                legendtxt = regexprep(MRS_struct.gabafile{ii*2-1}, '_','-');
            else
                legendtxt = regexprep(MRS_struct.gabafile{ii}, '_','-');
            end
            title(legendtxt);
            set(gca,'XDir','reverse');
            
            % From here on is cosmetic - adding labels etc.
            switch target{trg}
                case 'GABA'
                    h = text(3,metabmax/4,MRS_struct.p.target);
                    set(h, 'horizontalAlignment', 'center');
                    labelbounds = freq <= 2.4 & freq >= 2; % MM (170705)
                    tailtop = max(real(DIFF(ii,labelbounds)));
                    tailbottom = min(real(DIFF(ii,labelbounds)));
                    h = text(2.8, min(resid), 'residual');
                    set(h, 'horizontalAlignment', 'left');
                    text(2.8, tailtop+metabmax/20, 'data', 'Color', [0 0 1]);
                    text(2.8, tailbottom-metabmax/20, 'model', 'Color', [1 0 0]);
                    
                case 'GSH'
                    h = text(2.95,metabmax,target{trg});
                    set(h, 'horizontalAlignment', 'center');
                    labelbounds = freq <= 2.4 & freq >= 1.75; % MM (170705)
                    tailtop = max(real(DIFF(ii,labelbounds)));
                    tailbottom = min(real(DIFF(ii,labelbounds)));
                    h = text(2.25, min(resid),'residual');
                    set(h, 'horizontalAlignment', 'left');
                    text(2.25, tailtop+metabmax/20, 'data', 'Color', [0 0 1]);
                    text(2.45, tailbottom-20*metabmax/20, 'model', 'Color', [1 0 0]);
                    
                case 'Glx'
                    h = text(3.8,metabmax/4,MRS_struct.p.target);
                    set(h, 'horizontalAlignment', 'center');
                    labelbounds = freq <= 3.6 & freq >= 3.4; % MM (170705)
                    tailtop = max(real(DIFF(ii,labelbounds)));
                    tailbottom = min(real(DIFF(ii,labelbounds)));
                    h = text(3.5, min(resid),'residual');
                    set(h, 'horizontalAlignment', 'left');
                    text(3.5, tailtop+metabmax/20, 'data', 'Color', [0 0 1]);
                    text(3.5, tailbottom-metabmax/20, 'model', 'Color', [1 0 0]);
                    
                case 'GABAGlx'
                    h = text(3, metabmax/4, 'GABA');
                    h2 = text(3.755, metabmax/4, 'Glx');
                    set(h, 'horizontalAlignment', 'center');
                    set(h2, 'horizontalAlignment', 'center');
                    h = text(2.8, min(resid), 'residual');
                    set(h, 'horizontalAlignment', 'left');
                    labelbounds = freq <= 2.8 & freq >= 2.7; % MM (170705)
                    tailtop = max(real(DIFF(ii,labelbounds)));
                    tailbottom = min(real(DIFF(ii,labelbounds)));
                    text(2.8, tailtop+metabmax/20, 'data', 'Color', [0 0 1]);
                    text(2.8, tailbottom-metabmax/20, 'model', 'Color', [1 0 0]);
            end
            set(gca,'YTick',[]);
            set(gca,'Box','off');
            set(gca,'YColor','white');
            
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %   2.  Water Fit
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
            if strcmp(MRS_struct.p.Reference_compound,'H2O')
                
                % Estimate height and baseline from data
                [maxinWater, watermaxindex] = max(real(WaterData(ii,:)),[],2);
                waterbase = mean(real(WaterData(ii,1:500)));
                
                % Philips data do not phase well based on first point, so do a preliminary
                % fit, then adjust phase of WaterData accordingly
                % Do this only if the eddy current correction is not performed on water -- MGSaleh 2016
                if strcmpi(MRS_struct.p.vendor,'Philips') && ~MRS_struct.p.water_phase_correction
                    %Run preliminary fit of data
                    LGModelInit = [maxinWater 20 freq(watermaxindex) 0 waterbase -50];
                    %Fit from 5.6 ppm to 3.8 ppm RE 110826
                    freqbounds = freq <= 5.6 & freq >= 3.8; % MM (170705)
                    
                    % Do the water fit (Lorentz-Gauss)
                    LGModelParam = nlinfit(freq(freqbounds), real(WaterData(ii,freqbounds)), @LorentzGaussModel, LGModelInit, nlinopts);
                    
                    Eerror=zeros([120 1]);
                    for jj=1:120
                        Data=WaterData(ii,freqbounds)*exp(1i*pi/180*jj*3);
                        Model=LorentzGaussModel(LGModelParam,freq(freqbounds));
                        Eerror(jj)=sum((real(Data)-Model).^2);
                    end
                    [~,index]=min(Eerror);
                    WaterData(ii,:) = WaterData(ii,:)*exp(1i*pi/180*index*3);
                end
                
                LGPModelInit = [maxinWater 20 freq(watermaxindex) 0 waterbase -50 0];
                lb = [0.01*maxinWater 1 4.6 0 0 -50 -pi];
                ub = [40*maxinWater 100 4.8 0.000001 1 0 pi];
                
                %Fit from 5.6 ppm to 3.8 ppm RE 110826
                freqbounds = freq <= 5.6 & freq >= 3.8; % MM (170705)
                
                % Least-squares model fitting
                LGPModelInit = lsqcurvefit(@LorentzGaussModelP, LGPModelInit, freq(freqbounds), real(WaterData(ii,freqbounds)), lb, ub, lsqopts);
                [LGPModelParam, residw] = nlinfit(freq(freqbounds), real(WaterData(ii,freqbounds)), @LorentzGaussModelP, LGPModelInit, nlinopts);
                % MM (170705)
                %if ~any(strcmpi(MRS_struct.p.vendor,{'GE','Siemens'}))
                %   % Remove phase and run again
                %   WaterData(ii,:) = WaterData(ii,:)*exp(1i*LGPModelParam(7));
                %   LGPModelParam(7) = 0;
                %   [LGPModelParam, residw] = nlinfit(freq(freqbounds), real(WaterData(ii,freqbounds)), @LorentzGaussModelP, LGPModelParam, nlinopts);
                %end
                
                WaterArea = sum(real(LorentzGaussModel(LGPModelParam(1:end-1),freq(freqbounds))) - BaselineModel(LGPModelParam(3:5),freq(freqbounds)),2);
                MRS_struct.out.(vox{kk}).Water.Area(ii) = WaterArea * abs(freq(1)-freq(2));
                waterheight = LGPModelParam(1);
                MRS_struct.out.(vox{kk}).Water.FitError(ii) = 100*std(residw)/waterheight;
                % MM (170202)
                LG = real(LorentzGaussModel(LGPModelParam(1:end-1),freq(freqbounds))) - BaselineModel(LGPModelParam(3:5),freq(freqbounds));
                LG = LG./max(LG);
                ind = find(LG >= 0.5);
                f = freq(freqbounds);
                w = abs(f(ind(1)) - f(ind(end)));
                MRS_struct.out.(vox{kk}).Water.FWHM(ii) = w * MRS_struct.p.LarmorFreq;
                MRS_struct.out.(vox{kk}).Water.ModelParam(ii,:) = LGPModelParam;
                MRS_struct.out.(vox{kk}).Water.Resid(ii,:) = residw; % MM (160913)
                
                % Calculate SNR of GABA signal (MM: 170502)
                noiseSigma_Water = CalcNoise(freq, WaterData(ii,:));
                MRS_struct.out.(vox{kk}).Water.SNR(ii) = abs(waterheight)/noiseSigma_Water;
                
                % Root sum square fit error and concentration in institutional units -- MGSaleh & MM
                switch target{trg}
                    case 'GABA'
                        MRS_struct.out.(vox{kk}).GABA.FitError_W = sqrt(MRS_struct.out.(vox{kk}).GABA.FitError(ii).^2 + MRS_struct.out.(vox{kk}).Water.FitError.^2);
                        MRS_struct = CalcInstUnits(MRS_struct, vox{kk}, 'GABA', ii);
                        
                    case 'Glx'
                        MRS_struct.out.(vox{kk}).Glx.FitError_W = sqrt(MRS_struct.out.(vox{kk}).Glx.FitError(ii).^2 + MRS_struct.out.(vox{kk}).Water.FitError.^2);
                        MRS_struct = CalcInstUnits(MRS_struct, vox{kk}, 'Glx', ii);
                        
                    case 'GABAGlx'
                        MRS_struct.out.(vox{kk}).GABA.FitError_W = sqrt(MRS_struct.out.(vox{kk}).GABA.FitError(ii).^2 + MRS_struct.out.(vox{kk}).Water.FitError.^2);
                        MRS_struct.out.(vox{kk}).Glx.FitError_W = sqrt(MRS_struct.out.(vox{kk}).Glx.FitError(ii).^2 + MRS_struct.out.(vox{kk}).Water.FitError.^2);
                        MRS_struct = CalcInstUnits(MRS_struct, vox{kk}, 'GABA', ii);
                        MRS_struct = CalcInstUnits(MRS_struct, vox{kk}, 'Glx', ii);
                        
                    case 'GSH'
                        MRS_struct.out.(vox{kk}).GSH.FitError_W = sqrt(MRS_struct.out.(vox{kk}).GSH.FitError(ii).^2 + MRS_struct.out.(vox{kk}).Water.FitError.^2);
                        MRS_struct = CalcInstUnits(MRS_struct, vox{kk}, (target{trg}), ii);
                end
                
                % Generate scaled spectra (for plotting) CJE Jan2011, MM (170705)
                MRS_struct.spec.(vox{kk}).(target{trg}).off_scaled(ii,:) = ...
                    MRS_struct.spec.(vox{kk}).(target{trg}).off(ii,:) .* (1/MRS_struct.out.(vox{kk}).Water.ModelParam(ii,1));
                MRS_struct.spec.(vox{kk}).(target{trg}).on_scaled(ii,:) = ...
                    MRS_struct.spec.(vox{kk}).(target{trg}).on(ii,:) .* (1/MRS_struct.out.(vox{kk}).Water.ModelParam(ii,1));
                MRS_struct.spec.(vox{kk}).(target{trg}).diff_scaled(ii,:) = ...
                    MRS_struct.spec.(vox{kk}).(target{trg}).diff(ii,:) .* (1/MRS_struct.out.(vox{kk}).Water.ModelParam(ii,1));
                
                % MM (170703): Reorder structure fields 
                MRS_struct.out.(vox{kk}).Water = orderfields(MRS_struct.out.(vox{kk}).Water, {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError'});
                
                hb = subplot(2,2,3);
                watmin = min(real(WaterData(ii,:)));
                watmax = max(real(WaterData(ii,:)));
                resmax = max(residw);
                residw = residw + watmin - resmax;
                plot(freq(freqbounds), real(WaterData(ii,freqbounds)), 'b', ...
                    freq(freqbounds), real(LorentzGaussModelP(LGPModelParam,freq(freqbounds))), 'r', ...
                    freq(freqbounds), residw, 'k');
                set(gca,'XDir','reverse');
                set(gca,'YTick',[]);
                set(gca,'Box','off');
                set(gca,'YColor','white');
                xlim([4.2 5.2]);
                % Add on some labels
                hwat = text(4.8,watmax/2,'Water');
                set(hwat,'HorizontalAlignment','right');
                % Get the right vertical offset for the residual label
                labelfreq = freq(freqbounds); % MM (170705)
                rlabelbounds = labelfreq <= 4.4 & labelfreq >= 4.25;
                axis_bottom = axis;
                hwatres = text(4.4, max(min(residw(rlabelbounds))-0.05*watmax, axis_bottom(3)), 'residual');
                set(hwatres, 'horizontalAlignment', 'left');
                
                
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %   2a.  Residual Water Fit (MM: 170209)
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                if ~MRS_struct.p.HERMES
                    
                    water_OFF = OFF(ii,:);
                    freqWaterOFF = freq <= 4.68+0.4 & freq >= 4.68-0.4;
                    water_OFF = water_OFF(freqWaterOFF);
                    
                    [maxResidWater, maxInd] = max(abs(real(water_OFF)));
                    s = sign(real(water_OFF(maxInd)));
                    maxResidWater = s * maxResidWater;
                    waterbase = mean(real(OFF(ii,1:500)));
                    LGPModelInit = [maxResidWater 20 4.68 0 waterbase -50 0];
                    lb = [maxResidWater-abs(2*maxResidWater) 1 4.6 0 0 -200 -pi];
                    ub = [maxResidWater+abs(2*maxResidWater) 100 4.8 0.000001 1 0 pi];
                    
                    LGPModelInit = lsqcurvefit(@LorentzGaussModelP, LGPModelInit, freq(freqWaterOFF), real(water_OFF), lb, ub, lsqopts);
                    [MRS_struct.out.(vox{kk}).ResidWater.ModelParam(ii,:), residRW] = nlinfit(freq(freqWaterOFF), real(water_OFF), @LorentzGaussModelP, LGPModelInit, nlinopts);
                    MRS_struct.out.(vox{kk}).ResidWater.FitError(ii) = 100*std(residRW)/MRS_struct.out.(vox{kk}).ResidWater.ModelParam(ii,1);
                    
                    MRS_struct.out.(vox{kk}).ResidWater.SuppressionFactor(ii) = ...
                        (MRS_struct.out.(vox{kk}).Water.ModelParam(ii,1) - abs(MRS_struct.out.(vox{kk}).ResidWater.ModelParam(ii,1))) ...
                        / MRS_struct.out.(vox{kk}).Water.ModelParam(ii,1);
                    
                    %figure(22);
                    %plot(freq(freqWaterOFF), real(water_OFF), 'b', ...
                    %    freq(freqWaterOFF), LorentzGaussModelP(MRS_struct.out.(vox{kk}).ResidWater.ModelParam(ii,:),freq(freqWaterOFF)), 'r');
                    
                end
                
            end
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %   3.  Cr Fit
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
            Cr_OFF = OFF(ii,:);
            freqboundsChoCr = freq <= 3.6 & freq >= 2.6; % MM (170705)
            
            % Do some detective work to figure out the initial parameters
            ChoCrMeanSpec = Cr_OFF(freqboundsChoCr).';
            Baseline_offset = real(ChoCrMeanSpec(1)+ChoCrMeanSpec(end))/2;
            Width_estimate = 0.05;
            Area_estimate = (max(real(ChoCrMeanSpec))-min(real(ChoCrMeanSpec)))*Width_estimate*4;
            ChoCr_initx = [Area_estimate Width_estimate 3.02 0 Baseline_offset 0 1] ...
                .* [1 2*MRS_struct.p.LarmorFreq MRS_struct.p.LarmorFreq 180/pi 1 1 1];
            ChoCrModelParam = FitChoCr(freq(freqboundsChoCr), ChoCrMeanSpec, ChoCr_initx, MRS_struct.p.LarmorFreq);
            MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,:) = ChoCrModelParam ./ [1 2*MRS_struct.p.LarmorFreq MRS_struct.p.LarmorFreq 180/pi 1 1 1];
            
            % Initialise fitting pars     
            freqboundsCr = freq <= 3.12 & freq >= 2.72; % MM (170705)
            LorentzModelInit = [max(real(Cr_OFF(freqboundsCr))) 0.05 3.0 0 0 0];

            % Least-squares model fitting
            LorentzModelInit = lsqcurvefit(@LorentzModel, LorentzModelInit, freq(freqboundsCr), real(Cr_OFF(freqboundsCr)), [], [], lsqopts);
            [LorentzModelParam, residCr] = nlinfit(freq(freqboundsCr), real(Cr_OFF(freqboundsCr)), @LorentzModel, LorentzModelInit, nlinopts);
            
            MRS_struct.out.(vox{kk}).Cr.ModelParam(ii,:) = LorentzModelParam; % MM (160913)
            Crheight = LorentzModelParam(1)/(2*pi*LorentzModelParam(2)); % MM (170202)
            MRS_struct.out.(vox{kk}).Cr.FitError(ii) = 100*std(residCr)/Crheight;
            MRS_struct.out.(vox{kk}).Cr.Resid(ii,:) = residCr;
            
            MRS_struct.out.(vox{kk}).Cr.Area(ii) = sum(real(TwoLorentzModel([MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,1:(end-1)) 0],freq(freqboundsChoCr)) - ...
                TwoLorentzModel([0 MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,2:(end-1)) 0],freq(freqboundsChoCr)))) * abs(freq(1)-freq(2));
            MRS_struct.out.(vox{kk}).Cho.Area(ii) = sum(real(TwoLorentzModel(MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,1:(end)),freq(freqboundsChoCr)) - ...
                TwoLorentzModel([MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,1:(end-1)) 0],freq(freqboundsChoCr)))) * abs(freq(1)-freq(2));
            MRS_struct.out.(vox{kk}).Cr.FWHM(ii) = ChoCrModelParam(2);
            
            % Calculate SNR of Cr signal (MM: 170502)
            noiseSigma_OFF = CalcNoise(freq, OFF(ii,:));
            MRS_struct.out.(vox{kk}).Cr.SNR(ii) = abs(Crheight)/noiseSigma_OFF;            
            
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %   4.  NAA Fit
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
            NAA_OFF = OFF(ii,:);
            freqbounds = find(freq <= 2.25 & freq >= 1.75); % MM (170705)
            
            maxinNAA = max(real(NAA_OFF(freqbounds)));
            grad_points = (real(NAA_OFF(freqbounds(end))) - real(NAA_OFF(freqbounds(1)))) ./ abs(freqbounds(end) - freqbounds(1)); %in points
            LinearInit = grad_points ./ abs(freq(1) - freq(2));
            constInit = (real(NAA_OFF(freqbounds(end))) + real(NAA_OFF(freqbounds(1)))) ./ 2;
            
            LorentzModelInit = [maxinNAA 0.05 2.01 0 -LinearInit constInit];
            lb = [0 0.01 1.97 0 -40*maxinNAA -2000*maxinNAA];
            ub = [4000*maxinNAA 0.1 2.05 0.5 40*maxinNAA 1000*maxinNAA];
            
            % Least-squares model fitting
            LorentzModelInit = lsqcurvefit(@LorentzModel, LorentzModelInit, freq(freqbounds), real(NAA_OFF(freqbounds)), lb, ub, lsqopts);
            [LorentzModelParam, resid] = nlinfit(freq(freqbounds), real(NAA_OFF(freqbounds)), @LorentzModel, LorentzModelInit, nlinopts);            
            
            NAAheight = LorentzModelParam(1)/(2*pi*LorentzModelParam(2));
            MRS_struct.out.(vox{kk}).NAA.FitError(ii) = 100*std(resid)/NAAheight;
            NAAModelParam = LorentzModelParam;
            NAAModelParam(4) = 0;
            MRS_struct.out.(vox{kk}).NAA.Area(ii) = sum(LorentzModel(NAAModelParam,freq(freqbounds)) - BaselineModel(NAAModelParam([3 6 5]),freq(freqbounds)), 2) * abs(freq(1)-freq(2));
            MRS_struct.out.(vox{kk}).NAA.FWHM(ii) = abs((2*MRS_struct.p.LarmorFreq) * NAAModelParam(2));
            MRS_struct.out.(vox{kk}).NAA.ModelParam(ii,:) = LorentzModelParam;
            MRS_struct.out.(vox{kk}).NAA.Resid(ii,:) = resid;
            
            % Calculate SNR of NAA signal (MM: 170502)
            MRS_struct.out.(vox{kk}).NAA.SNR(ii) = abs(NAAheight) / noiseSigma_OFF;
                        
            % Root sum square fit errors and concentrations as metabolite ratios -- MGSaleh & MM
            if strcmpi(target{trg},'GABAGlx')
                MRS_struct.out.(vox{kk}).GABA.FitError_Cr(ii) = sqrt(MRS_struct.out.(vox{kk}).GABA.FitError(ii).^2 + MRS_struct.out.(vox{kk}).Cr.FitError(ii).^2);
                MRS_struct.out.(vox{kk}).Glx.FitError_Cr(ii) = sqrt(MRS_struct.out.(vox{kk}).Glx.FitError(ii).^2 + MRS_struct.out.(vox{kk}).Cr.FitError(ii).^2);
                MRS_struct.out.(vox{kk}).GABA.FitError_NAA(ii) = sqrt(MRS_struct.out.(vox{kk}).GABA.FitError(ii).^2 + MRS_struct.out.(vox{kk}).NAA.FitError(ii).^2);
                MRS_struct.out.(vox{kk}).Glx.FitError_NAA(ii) = sqrt(MRS_struct.out.(vox{kk}).Glx.FitError(ii).^2 + MRS_struct.out.(vox{kk}).NAA.FitError(ii).^2);
                MRS_struct.out.(vox{kk}).GABA.ConcCr(ii) = MRS_struct.out.(vox{kk}).GABA.Area(ii) / MRS_struct.out.(vox{kk}).Cr.Area(ii);
                MRS_struct.out.(vox{kk}).GABA.ConcCho(ii) = MRS_struct.out.(vox{kk}).GABA.Area(ii) / MRS_struct.out.(vox{kk}).Cho.Area(ii);
                MRS_struct.out.(vox{kk}).GABA.ConcNAA(ii) = MRS_struct.out.(vox{kk}).GABA.Area(ii) / MRS_struct.out.(vox{kk}).NAA.Area(ii);
                MRS_struct.out.(vox{kk}).Glx.ConcCr(ii) = MRS_struct.out.(vox{kk}).Glx.Area(ii) / MRS_struct.out.(vox{kk}).Cr.Area(ii);
                MRS_struct.out.(vox{kk}).Glx.ConcCho(ii) = MRS_struct.out.(vox{kk}).Glx.Area(ii) / MRS_struct.out.(vox{kk}).Cho.Area(ii);
                MRS_struct.out.(vox{kk}).Glx.ConcNAA(ii) = MRS_struct.out.(vox{kk}).Glx.Area(ii) / MRS_struct.out.(vox{kk}).NAA.Area(ii);                
            else
                MRS_struct.out.(vox{kk}).(target{trg}).FitError_Cr(ii) = sqrt(MRS_struct.out.(vox{kk}).(target{trg}).FitError(ii).^2 + MRS_struct.out.(vox{kk}).Cr.FitError(ii).^2);
                MRS_struct.out.(vox{kk}).(target{trg}).FitError_NAA(ii) = sqrt(MRS_struct.out.(vox{kk}).(target{trg}).FitError(ii).^2 + MRS_struct.out.(vox{kk}).NAA.FitError(ii).^2);
                MRS_struct.out.(vox{kk}).(target{trg}).ConcCr(ii) = MRS_struct.out.(vox{kk}).(target{trg}).Area(ii) / MRS_struct.out.(vox{kk}).Cr.Area(ii);
                MRS_struct.out.(vox{kk}).(target{trg}).ConcCho(ii) = MRS_struct.out.(vox{kk}).(target{trg}).Area(ii) / MRS_struct.out.(vox{kk}).Cho.Area(ii);
                MRS_struct.out.(vox{kk}).(target{trg}).ConcNAA(ii) = MRS_struct.out.(vox{kk}).(target{trg}).Area(ii) / MRS_struct.out.(vox{kk}).NAA.Area(ii);
            end
            
            % MM (170703): Reorder structure fields
            if ~MRS_struct.p.HERMES % MM (170703): work on this for GSH data
                if strcmp(MRS_struct.p.Reference_compound,'H2O')
                    if strcmpi(target{trg},'GABAGlx')
                        MRS_struct.out.(vox{kk}).GABA = orderfields(MRS_struct.out.(vox{kk}).GABA, ...
                            {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError', 'FitError_W', 'FitError_Cr', 'FitError_NAA', 'ConcIU', 'ConcCr', 'ConcCho', 'ConcNAA'});
                        MRS_struct.out.(vox{kk}).Glx = orderfields(MRS_struct.out.(vox{kk}).Glx, ...
                            {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError', 'FitError_W', 'FitError_Cr', 'FitError_NAA', 'ConcIU', 'ConcCr', 'ConcCho', 'ConcNAA'});
                    else
                        MRS_struct.out.(vox{kk}).(target{trg}) = orderfields(MRS_struct.out.(vox{kk}).(target{trg}), ...
                            {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError', 'FitError_W', 'FitError_Cr', 'FitError_NAA', 'ConcIU', 'ConcCr', 'ConcCho', 'ConcNAA'});
                    end
                else
                    if strcmpi(target{trg},'GABAGlx')
                        MRS_struct.out.(vox{kk}).GABA = orderfields(MRS_struct.out.(vox{kk}).GABA, ...
                            {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError', 'FitError_Cr', 'FitError_NAA', 'ConcCr', 'ConcCho', 'ConcNAA'});
                        MRS_struct.out.(vox{kk}).Glx = orderfields(MRS_struct.out.(vox{kk}).Glx, ...
                            {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError', 'FitError_Cr', 'FitError_NAA', 'ConcCr', 'ConcCho', 'ConcNAA'});
                    else
                        MRS_struct.out.(vox{kk}).(target{trg}) = orderfields(MRS_struct.out.(vox{kk}).(target{trg}), ...
                            {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError', 'FitError_Cr', 'FitError_NAA', 'ConcCr', 'ConcCho', 'ConcNAA'});
                    end
                end
            end
            MRS_struct.out.(vox{kk}).Cr = orderfields(MRS_struct.out.(vox{kk}).Cr, {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError'});
            MRS_struct.out.(vox{kk}).NAA = orderfields(MRS_struct.out.(vox{kk}).NAA, {'Area', 'FWHM', 'SNR', 'ModelParam', 'Resid', 'FitError'});
                        
            
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %   5. Build GannetFit Output
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            
            Crmin = min(real(Cr_OFF(freqboundsCr)));
            Crmax = max(real(Cr_OFF(freqboundsCr)));
            resmaxCr = max(residCr);
            residCr = residCr + Crmin - resmaxCr;
            if strcmp(MRS_struct.p.Reference_compound,'H2O')
                h = subplot(2,2,4);
                plot(freq, real(Cr_OFF), 'b', ...
                    freq(freqboundsChoCr), real(TwoLorentzModel(MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,:),freq(freqboundsChoCr))), 'r', ...
                    freq(freqboundsChoCr), real(TwoLorentzModel([MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,1:(end-1)) 0],freq(freqboundsChoCr))), 'r', ...                    
                    freq(freqboundsCr), residCr, 'k');
                set(gca,'XDir','reverse');
                set(gca,'YTick',[],'Box','off');
                xlim([2.6 3.6]);
                set(gca,'YColor','white');
                hcr=text(2.94,Crmax*0.75,'Creatine');
                set(hcr,'horizontalAlignment', 'left')
                %Transfer Cr plot into insert
                subplot(2,2,3)
                [h_m, h_i]=inset(hb,h);
                set(h_i,'fontsize',6);
                insert=get(h_i,'pos');
                axi=get(hb,'pos');
                set(h_i,'pos',[axi(1)+axi(3)-insert(3) insert(2:4)]);
                %Add labels
                hwat=text(4.8,watmax/2,'Water');
                set(hwat,'horizontalAlignment', 'right')
                set(h_m,'YTickLabel',[]);
                set(h_m,'XTickLabel',[]);
                set(gca,'Box','off')
                set(gca,'YColor','white');
            else
                hb=subplot(2,2,3);
                plot(freq, real(Cr_OFF), 'b', ...
                    freq(freqboundsChoCr), real(TwoLorentzModel(MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,:),freq(freqboundsChoCr))), 'r', ...
                    freq(freqboundsChoCr), real(TwoLorentzModel([MRS_struct.out.(vox{kk}).ChoCr.ModelParam(ii,1:(end-1)) 0],freq(freqboundsChoCr))), 'r', ...
                    freq(freqboundsCr), residCr, 'k');
                set(gca,'XDir','reverse');
                set(gca,'YTick',[]);
                xlim([2.6 3.6]);
                crlabelbounds = freq <= 3.12 & freq >= 2.9; % MM (170705)
                hcres=text(3.12, max(residCr(crlabelbounds))+0.05*Crmax, 'residual');
                set(hcres,'horizontalAlignment', 'left');
                text(2.8,0.3*Crmax,'data','Color',[0 0 1]);
                text(2.8,0.2*Crmax,'model','Color',[1 0 0]);
                text(2.94,Crmax*0.75,'Creatine');
            end
            
            % And running the plot
            if any(strcmp('mask',fieldnames(MRS_struct))) == 1
                h=subplot(2,2,2);
                get(h,'pos'); % get position of axes
                set(h,'pos',[0.52 0.52 0.42 0.42]) % move the axes slightly
                imagesc(squeeze(MRS_struct.mask.img(ii,:,1:round(size(MRS_struct.mask.img,3)/3))));
                colormap('gray');
                caxis([0 1])
                axis equal;
                axis tight;
                axis off;
                subplot(2,2,4,'replace');
            else
                subplot(2,2,2);
                axis off;
            end
            
            % MM (170703): Cleaner text alignment
            text_pos = 0.9; % A variable to determine y-position of text on printout on figure -- Added by MGSaleh
            
            if strcmp(MRS_struct.p.vendor,'Siemens')
                tmp = [': ' MRS_struct.gabafile{ii*2-1}];
            else
                tmp = [': ' MRS_struct.gabafile{ii}];
            end
            tmp = regexprep(tmp, '_','-');
            text(0, text_pos, 'Filename', 'FontName', 'Helvetica', 'FontSize', 10);
            text(0.375, text_pos, tmp, 'FontName', 'Helvetica', 'FontSize', 10);
            
            %if isfield(MRS_struct.p,'voxdim')
            %    tmp = [num2str(MRS_struct.p.Navg(ii)) ' averages of a ' num2str(MRS_struct.p.voxdim(ii,1)*MRS_struct.p.voxdim(ii,2)*MRS_struct.p.voxdim(ii,3)*.001) '-mL voxel'];
            %else
            %    tmp = [num2str(MRS_struct.p.Navg(ii)) ' averages'];
            %end
            %text(0, text_pos-0.1, tmp, 'FontName', 'Helvetica', 'FontSize', 10);
            
            %if isfield(MRS_struct.p,'voxdim')
            %    SNRfactor = round(sqrt(MRS_struct.p.Navg(ii))*MRS_struct.p.voxdim(ii,1)*MRS_struct.p.voxdim(ii,2)*MRS_struct.p.voxdim(ii,3)/1e3);
            %    tmp = [': ' num2str(SNRfactor)];
            %    text(0, text_pos-0.2, 'SNR factor', 'FontName', 'Helvetica', 'FontSize', 10);
            %    text(0.375, text_pos-0.2, tmp, 'FontName', 'Helvetica', 'FontSize', 10);
            %end
            
            % Some changes to accomodate multiplexed fitting output
            switch target{trg}
                case 'GABA'
                    tmp1 = 'GABA+ Area';
                    tmp2 = sprintf(': %.3g', MRS_struct.out.(vox{kk}).GABA.Area(ii));
                    
                case 'Glx'
                    tmp1 = 'Glx Area';
                    tmp2 = sprintf(' : %.3g', MRS_struct.out.(vox{kk}).Glx.Area(ii));
                    
                case 'GABAGlx'
                    tmp1 = 'GABA+/Glx Area';
                    tmp2 = sprintf(': %.3g/%.3g', MRS_struct.out.(vox{kk}).GABA.Area(ii), MRS_struct.out.(vox{kk}).Glx.Area(ii));
                    
                case 'GSH'
                    tmp1 = 'GSH Area';
                    tmp2 = sprintf(': %.3g', MRS_struct.out.(vox{kk}).(target{trg}).Area(ii));
            end
            text(0, text_pos-0.3, tmp1, 'FontName', 'Helvetica', 'FontSize', 10);
            text(0.375, text_pos-0.3, tmp2, 'FontName', 'Helvetica', 'FontSize', 10);
            
            % MGSaleh 2016, MM (170703): Some changes to accomodate multiplexed fitting output
            if strcmp(MRS_struct.p.Reference_compound,'H2O')
                
                tmp = sprintf(': %.3g/%.3g', MRS_struct.out.(vox{kk}).Water.Area(ii), MRS_struct.out.(vox{kk}).Cr.Area(ii));
                text(0, text_pos-0.4, 'Water/Cr Area', 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.4, tmp, 'FontName', 'Helvetica', 'FontSize', 10);
                
                tmp = sprintf(': %.1f/%.1f Hz', MRS_struct.out.(vox{kk}).Water.FWHM(ii), MRS_struct.out.(vox{kk}).Cr.FWHM(ii));
                text(0, text_pos-0.5, 'FWHM (Water/Cr)', 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.5, tmp, 'FontName', 'Helvetica', 'FontSize', 10);                
                
                switch target{trg}
                    case {'GABA','Glx','GSH'}
                        tmp1 = sprintf(': %.1f/%.1f%%', MRS_struct.out.(vox{kk}).(target{trg}).FitError_W(ii), MRS_struct.out.(vox{kk}).(target{trg}).FitError_Cr(ii));
                        tmp2 = [target{trg} ' (Water)'];
                        tmp4 = [target{trg} ' (Cr)'];
                        if strcmpi(target{trg},'GABA')
                            tmp2 = 'GABA+ (Water)';
                            tmp3 = sprintf(': %.3f i.u.', MRS_struct.out.(vox{kk}).(target{trg}).ConcIU(ii));
                            tmp4 = 'GABA+ (Cr)';
                            tmp5 = sprintf(': %.3f', MRS_struct.out.(vox{kk}).(target{trg}).ConcCr(ii));
                        else
                            tmp3 = sprintf(': %.3f i.u.', MRS_struct.out.(vox{kk}).(target{trg}).ConcIU(ii));
                            tmp5 = sprintf(': %.3f', MRS_struct.out.(vox{kk}).(target{trg}).ConcCr(ii));
                        end
                        
                    case 'GABAGlx'
                        tmp1 = sprintf(': GABA: %.1f/%.1f%% / Glx: %.1f/%.1f%%', MRS_struct.out.(vox{kk}).GABA.FitError_W(ii), MRS_struct.out.(vox{kk}).GABA.FitError_Cr(ii), ...
                            MRS_struct.out.(vox{kk}).Glx.FitError_W(ii), MRS_struct.out.(vox{kk}).Glx.FitError_Cr(ii));
                        tmp2 = 'GABA+/Glx (Water)';
                        tmp3 = sprintf(': %.3f/%.3f i.u.', MRS_struct.out.(vox{kk}).GABA.ConcIU(ii), MRS_struct.out.(vox{kk}).Glx.ConcIU(ii));
                        tmp4 = 'GABA+/Glx (Cr)';
                        tmp5 = sprintf(': %.3f/%.3f', MRS_struct.out.(vox{kk}).GABA.ConcCr(ii), MRS_struct.out.(vox{kk}).Glx.ConcCr(ii));
                end
                text(0, text_pos-0.6, 'FitErr (Water/Cr)', 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.6, tmp1, 'FontName', 'Helvetica', 'FontSize', 10);
                text(0, text_pos-0.7, tmp2, 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.7, tmp3, 'FontName', 'Helvetica', 'FontSize', 10);
                text(0, text_pos-0.8, tmp4, 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.8, tmp5, 'FontName', 'Helvetica', 'FontSize', 10);
                
            else
                
                tmp = sprintf(' : %.3g ', MRS_struct.out.(vox{kk}).Cr.Area(ii));
                text(0, text_pos-0.4, 'Cr Area', 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.4, tmp, 'FontName', 'Helvetica', 'FontSize', 10);
                
                tmp = sprintf(': %.1f Hz', MRS_struct.out.(vox{kk}).Cr.FWHM(ii));
                text(0, text_pos-0.5, 'FWHM (Cr)', 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.5, tmp, 'FontName', 'Helvetica', 'FontSize', 10);                
                
                switch target{trg}
                    case {'GABA','Glx','GSH'}
                        tmp1 = sprintf(': %.1f%%', MRS_struct.out.(vox{kk}).(target{trg}).FitError_Cr(ii));
                        tmp2 = [target{trg} ' (Cr)'];
                        if strcmpi(target{trg},'GABA')
                            tmp2 = 'GABA+ (Cr)';
                            tmp3 = sprintf('+/Cr: %.3f', MRS_struct.out.(vox{kk}).(target{trg}).ConcCr(ii));
                        else
                            tmp3 = sprintf('+/Cr: %.3f', MRS_struct.out.(vox{kk}).(target{trg}).ConcCr(ii));
                        end
                        
                    case 'GABAGlx'
                        tmp1 = sprintf(': GABA: %.1f%% / Glx: %.1f%%', MRS_struct.out.(vox{kk}).GABA.FitError_Cr(ii), MRS_struct.out.(vox{kk}).Glx.FitError_Cr(ii));
                        tmp2 = 'GABA+/Glx (Cr)';
                        tmp3 = sprintf(': %.3f/%.3f', MRS_struct.out.(vox{kk}).GABA.ConcCr(ii), MRS_struct.out.(vox{kk}).Glx.ConcCr(ii));
                end
                text(0, text_pos-0.6, 'FitErr (Cr)', 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.6, tmp1, 'FontName', 'Helvetica', 'FontSize', 10);
                text(0, text_pos-0.8, tmp2, 'FontName', 'Helvetica', 'FontSize', 10);
                text(0.375, text_pos-0.8, tmp3, 'FontName', 'Helvetica', 'FontSize', 10);
                
            end
            
            tmp = [': ' MRS_struct.versionfit];
            text(0, text_pos-0.9, 'FitVer', 'FontName', 'Helvetica', 'FontSize', 10);
            text(0.375, text_pos-0.9, tmp, 'FontName', 'Helvetica', 'FontSize', 10);
            
            % Add Gannet logo
            if any(strcmp('mask',fieldnames(MRS_struct))) == 1
                subplot(2,2,4)
            else
                subplot(2,2,4,'replace')
            end
            axis off;
            script_path=which('GannetFit');
            Gannet_logo=[script_path(1:(end-12)) '/Gannet3_logo.png'];
            A2=imread(Gannet_logo,'png','BackgroundColor',[1 1 1]);
            axes('Position',[0.80, 0.05, 0.15, 0.15]);
            image(A2); axis off; axis square;
            
            % Save PDF
            if strcmp(MRS_struct.p.vendor,'Siemens')
                pfil_nopath = MRS_struct.gabafile{ii*2-1};
            else
                pfil_nopath = MRS_struct.gabafile{ii};
            end
            % For Philips .data
            if strcmpi(MRS_struct.p.vendor,'Philips_data')
                fullpath = MRS_struct.gabafile{ii};
                fullpath = regexprep(fullpath, '.data', '_data');
                fullpath = regexprep(fullpath, '\', '_');
                fullpath = regexprep(fullpath, '/', '_');
            end
            tmp = strfind(pfil_nopath,'/');
            tmp2 = strfind(pfil_nopath,'\');
            if tmp
                lastslash=tmp(end);
            elseif tmp2
                % maybe it's Windows...
                lastslash=tmp2(end);
            else
                % it's in the current dir...
                lastslash=0;
            end
            if strcmpi(MRS_struct.p.vendor,'Philips')
                tmp = strfind(pfil_nopath,'.sdat');
                tmp1 = strfind(pfil_nopath,'.SDAT');
                if size(tmp,1) > size(tmp1,1)
                    dot7 = tmp(end); % just in case there's another .sdat somewhere else...
                else
                    dot7 = tmp1(end); % just in case there's another .sdat somewhere else...
                end
            elseif strcmpi(MRS_struct.p.vendor,'GE')
                tmp = strfind(pfil_nopath, '.7');
                dot7 = tmp(end); % just in case there's another .7 somewhere else...
            elseif strcmpi(MRS_struct.p.vendor,'Philips_data')
                tmp = strfind(pfil_nopath, '.data');
                dot7 = tmp(end); % just in case there's another .data somewhere else...
            elseif strcmpi(MRS_struct.p.vendor,'Siemens')
                tmp = strfind(pfil_nopath, '.rda');
                dot7 = tmp(end); % just in case there's another .rda somewhere else...
            elseif strcmpi(MRS_struct.p.vendor,'Siemens_twix')
                tmp = strfind(pfil_nopath, '.dat');
                dot7 = tmp(end); % just in case there's another .dat somewhere else...
            end
            pfil_nopath = pfil_nopath(lastslash+1:dot7-1);
            if sum(strcmp(listfonts,'Helvetica')) > 0
                set(findall(h,'type','text'),'FontName','Helvetica');
                set(ha,'FontName','Helvetica');
                set(hb,'FontName','Helvetica');
            end
            
            % Save PDF output
            set(gcf,'PaperUnits','inches');
            set(gcf,'PaperSize',[11 8.5]);
            set(gcf,'PaperPosition',[0 0 11 8.5]);
            if strcmpi(MRS_struct.p.vendor,'Philips_data')
                pdfname = [pdfdirname '/' fullpath '_' target{trg} '_fit.pdf']; % MGSaleh 2016, MM (170703)
            else
                pdfname = [pdfdirname '/' pfil_nopath  '_' target{trg} '_fit.pdf']; % MGSaleh 2016, MM (170703)
            end
            if ~exist(pdfdirname,'dir')
                mkdir(pdfdirname);
            end
            saveas(gcf, pdfname);
            if ii == numscans && MRS_struct.p.mat == 1
                if strcmpi(MRS_struct.p.vendor,'Philips_data')
                    matname = [pdfdirname '/' 'MRS_struct' '.mat'];
                else
                    matname = [pdfdirname '/' 'MRS_struct' '.mat'];
                end
                save(matname,'MRS_struct');
            end
            
            % 140116: ADH reorder structure
            if isfield(MRS_struct, 'mask') == 1
                if isfield(MRS_struct, 'waterfile') == 1
                    structorder = {'versionload', 'versionfit', 'ii', ...
                        'gabafile', 'waterfile', 'p', 'fids', 'spec', 'out', 'mask'};
                else
                    structorder = {'versionload', 'versionfit','ii', ...
                        'gabafile', 'p', 'fids', 'spec', 'out', 'mask'};
                end
            else
                if isfield(MRS_struct, 'waterfile') == 1
                    structorder = {'versionload', 'versionfit', 'ii', ...
                        'gabafile', 'waterfile', 'p', 'fids', 'spec', 'out'};
                else
                    structorder = {'versionload', 'versionfit','ii', ...
                        'gabafile', 'p', 'fids', 'spec', 'out'};
                end
            end
            
            MRS_struct = orderfields(MRS_struct, structorder);
            
            % Dec 09: based on FitSeries.m:  Richard's GABA Fitting routine
            %     Fits using GaussModel
            % Feb 10: Change the quantification method for water.  Regions of poor homogeneity (e.g. limbic)
            %     can produce highly asymetric lineshapes, which are fitted poorly.  Don't fit - integrate
            %     the water peak.
            % March 10: 100301
            %           use MRS_struct to pass loaded data data, call MRSGABAinstunits from here.
            %           scaling of fitting to sort out differences between original (RE) and my analysis of FEF data
            %           change tolerance on gaba fit
            % 110308:   Keep definitions of fit functions in MRSGABAfit, rather
            %               than in separate .m files
            %           Ditto institutional units calc
            %           Include FIXED version of Lorentzian fitting
            %           Get Navg from struct (need version 110303, or later of
            %               MRSLoadPfiles
            %           rejig the output plots - one fig per scan.
            % 110624:   set parmeter to choose fitting routine... for awkward spectra
            %           report fit error (100*stdev(resid)/gabaheight), rather than "SNR"
            %           can estimate this from confidence interval for nlinfit - need
            %               GABA and water estimates
            
            % 111111:   RAEE To integrate in Philips data, which doesn't always have
            % water spectr, we need to add in referenceing to Cr... through
            % MRS_struct.p.Reference_compound
            % 140115: MRS_struct.p.Reference_compound is now
            %   MRS_struct.p.Reference compound
            %
            %111214 integrating CJE's changes on water fitting (pre-init and revert to
            %linear bseline). Also investigating Navg(ii)
            
        end
    end
    
    fprintf('\n\n');
    
end


%%%%%%%%%%%%%%%%%%%%%%%% GAUSS MODEL %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function F = GaussModel(x,freq)
% Function for Gauss Model

% x(1) = gaussian amplitude
% x(2) = 1/(2*sigma^2)
% x(3) = centre freq of peak
% x(4) = amplitude of linear baseline
% x(5) = constant amplitude offset

F = x(1)*exp(x(2)*(freq-x(3)).*(freq-x(3)))+x(4)*(freq-x(3))+x(5);


%%%%%%%%%%%%%%%%  LORENTZGAUSSMODEL %%%%%%%%%%%%%%%%%%%%
function F = LorentzGaussModel(x,freq)
% Function for LorentzGaussModel Model

% CJE 24Nov10 - removed phase term from fit - this is now dealt with
% by the phasing of the water ref scans in MRSLoadPfiles
%Lorentzian Model multiplied by a Gaussian.
% x(1) = Amplitude of (scaled) Lorentzian
% x(2) = 1 / hwhm of Lorentzian (hwhm = half width at half max)
% x(3) = centre freq of Lorentzian
% x(4) = linear baseline slope
% x(5) = constant baseline amplitude
% x(6) =  -1 / 2 * sigma^2  of gaussian

% Lorentzian  = (1/pi) * (hwhm) / (deltaf^2 + hwhm^2)
% Peak height of Lorentzian = 4 / (pi*hwhm)
% F is a normalised Lorentzian - height independent of hwhm
%   = Lorentzian / Peak

F = (x(1)*ones(size(freq))./(x(2)^2*(freq-x(3)).*(freq-x(3))+1)) ... % Lorentzian
    .* (exp(x(6)*(freq-x(3)).*(freq-x(3)))) ... % Gaussian
    + x(4)*(freq-x(3)) ... % linear baseline
    + x(5); % constant baseline


%%%%%%%%%%%%%%%% LORENTZGAUSSMODEL WITH PHASE %%%%%%%%%%%%%%%%%%%%
function F = LorentzGaussModelP(x,freq)
% Function for LorentzGaussModel Model with Phase

% Lorentzian Model multiplied by a Gaussian
% x(1) = Amplitude of (scaled) Lorentzian
% x(2) = 1 / hwhm of Lorentzian (hwhm = half width at half max)
% x(3) = centre freq of Lorentzian
% x(4) = linear baseline slope
% x(5) = constant baseline amplitude
% x(6) =  -1 / 2 * sigma^2  of gaussian
% x(7) = phase (in rad)

% Lorentzian  = (1/pi) * (hwhm) / (deltaf^2 + hwhm^2)
% Peak height of Lorentzian = 4 / (pi*hwhm)
% F is a normalised Lorentzian - height independent of hwhm
%   = Lorentzian / Peak

F = ((cos(x(7))*x(1)*ones(size(freq)) + sin(x(7))*x(1)*x(2)*(freq-x(3)))./(x(2)^2*(freq-x(3)).*(freq-x(3))+1)) ... % Lorentzian
    .* (exp(x(6)*(freq-x(3)).*(freq-x(3)))) ... % Gaussian
    + x(4)*(freq-x(3)) ... % linear baseline
    + x(5); % constant baseline


%%%%%%%%%%%%%%%%%%%%%%%% DOUBLE GAUSS MODEL (MM: 150211) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function F = DoubleGaussModel(x,freq)
% Function for DoubleGaussModel Model

% Two Gaussians
%  x(1) = gaussian amplitude 1
%  x(2) = width 1 ( 1/(2*sigma^2) )
%  x(3) = centre freq of peak 1
%  x(4) = gaussian amplitude 2
%  x(5) = width 2 ( 1/(2*sigma^2) )
%  x(6) = centre freq of peak 2
%  x(7) = amplitude of linear baseline
%  x(8) = constant amplitude offset

% MM: Allowing peaks to vary individually seems to work better than keeping
% the distance fixed (i.e., including J in the function)

F = x(1)*exp(x(2)*(freq-x(3)).*(freq-x(3))) + ...
    x(4)*exp(x(5)*(freq-x(6)).*(freq-x(6))) + ...
    x(7)*(freq-x(3))+x(8);


%%%%%%%%%%%%%%%%%%%%%%%% TRIPLE GAUSS MODEL (MM: 150211) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function F = GABAGlxModel(x,freq)
% Function for GABA+Glx model

% Three Gaussians
%  x(1) = gaussian amplitude 1
%  x(2) = width 1 ( 1/(2*sigma^2) )
%  x(3) = centre freq of peak 1
%  x(4) = gaussian amplitude 2
%  x(5) = width 2 ( 1/(2*sigma^2) )
%  x(6) = centre freq of peak 2
%  x(7) = gaussian amplitude 3
%  x(8) = width 3 ( 1/(2*sigma^2) )
%  x(9) = centre freq of peak 3
%  x(10) = linear baseline slope
%  x(11) = sine baseline term
%  x(12) = cosine baseline term

% MM: Allowing peaks to vary individually seems to work better than keeping
% the distance fixed (i.e., including J in the function)

F = x(1)*exp(x(2)*(freq-x(3)).*(freq-x(3))) + ...
    x(4)*exp(x(5)*(freq-x(6)).*(freq-x(6))) + ...
    x(7)*exp(x(8)*(freq-x(9)).*(freq-x(9))) + ...
    x(10)*(freq-x(3)) + ...
    x(11)*sin(pi*freq/1.31/4)+x(12)*cos(pi*freq/1.31/4);


%%%%%%%%%%%%%%% BASELINE %%%%%%%%%%%%%%%%%%%%%%%
function F = BaselineModel(x,freq)
% Function for Baseline Model

F = x(2)*(freq-x(1))+x(3);


%%%%%%%%%%%%%%%%%%% CALC INST UNITS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function MRS_struct = CalcInstUnits(MRS_struct, vox, metab, ii)
% Function for quantifying concentration in institutional units
% Convert metabolits and water areas to institutional units
% (pseudo-concentration in mmol/L)

TR = MRS_struct.p.TR(ii)/1000;
TE = MRS_struct.p.TE(ii)/1000;
PureWaterConc = 55000; % mmol/L
WaterVisibility = 0.65; % this is approx the value from Ernst, Kreis, Ross (1993, JMR)
T1_Water = 1.100; % average of WM and GM, estimated from Wansapura et al. (1999, JMRI)
T2_Water = 0.095; % average of WM and GM, estimated from Wansapura et al. (1999, JMRI)
N_H_Water = 2;

% MGSaleh 2016
switch metab
    case 'GABA'
        EditingEfficiency = 0.5;
        T1_Metab = 1.31;  % from Puts et al. (2013, JMRI)
        T2_Metab = 0.088; % from Edden et al. (2012, JMRI)
        N_H_Metab = 2;
        MM = 0.45; % MM correction: fraction of GABA in GABA+ peak. (In TrypDep, 30 subjects: 55% of GABA+ was MM)
        % This fraction is platform and implementation dependent, base on length and
        % shape of editing pulses and ifis Henry method
        T1_Factor = (1-exp(-TR./T1_Water)) ./ (1-exp(-TR./T1_Metab));
        T2_Factor = exp(-TE./T2_Water) ./ exp(-TE./T2_Metab);
        
    case 'Glx'
        EditingEfficiency = 0.4; % determined by FID-A simulations using 83-Hz (FWHM) editing pulses
        T1_Metab = 1.23; % Posse et al. 2007 (MRM)
        T2_Metab = 0.18; % Ganji et al. 2012 (NMR Biomed)
        N_H_Metab = 1;
        MM = 1; % MM not co-edited -- MGSaleh
        T1_Factor = (1-exp(-TR./T1_Water)) ./ (1-exp(-TR./T1_Metab));
        T2_Factor = exp(-TE./T2_Water) ./ exp(-TE./T2_Metab);
        
    case 'GSH'
        EditingEfficiency = 0.74;  % At 3T based on Quantification of Glutathione in the Human Brain by MR Spectroscopy at 3 Tesla:
        % Comparison of PRESS and MEGA-PRESS
        % Faezeh Sanaei Nezhad etal. DOI 10.1002/mrm.26532, 2016 -- MGSaleh
        T1_Metab = 0.40 ; % At 3T based on Doubly selective multiple quantum chemical shift imaging and
        % T1 relaxation time measurement of glutathione (GSH) in the human brain in vivo
        % In-Young Choi et al. NMR Biomed. 2013; 26: 28?34 -- MGSaleh
        T2_Metab = 0.12; % At 3T based on the ISMRM abstract
        % T2 relaxation times of 18 brain metabolites determined in 83 healthy volunteers in vivo
        % Milan Scheidegger et al. Proc. Intl. Soc. Mag. Reson. Med. 22 (2014)-- MGSaleh
        N_H_Metab = 2;
        MM = 1;
        T1_Factor = (1-exp(-TR./T1_Water)) ./ (1-exp(-TR./T1_Metab));
        T2_Factor = exp(-TE./T2_Water) ./ exp(-TE./T2_Metab);
        
    case 'Lac'
        EditingEfficiency = 1.0;
        T1_Metab = 1 ; % Need to check in the literature -- MGSaleh
        T2_Metab = 1; % Need to check in the literature -- MGSaleh
        N_H_Metab = 2; % Need to check in the literature -- MGSaleh
        MM = 1; % Not affected by MM -- MGSaleh
        T1_Factor = (1-exp(-TR./T1_Water)) ./ (1-exp(-TR./T1_Metab));
        T2_Factor = exp(-TE./T2_Water) ./ exp(-TE./T2_Metab);
end

if strcmpi(MRS_struct.p.vendor,'Siemens')
    % Factor of 2 is appropriate for averaged Siemens data (read in separately as ON and OFF)
    MRS_struct.out.(vox).(metab).ConcIU(ii) = (MRS_struct.out.(vox).(metab).Area(ii) ./ MRS_struct.out.(vox).Water.Area(ii))  ...
        * PureWaterConc * WaterVisibility * T1_Factor * T2_Factor * (N_H_Water./N_H_Metab) ...
        * MM ./ 2 ./ EditingEfficiency;
else
    MRS_struct.out.(vox).(metab).ConcIU(ii) = (MRS_struct.out.(vox).(metab).Area(ii) ./ MRS_struct.out.(vox).Water.Area(ii))  ...
        * PureWaterConc * WaterVisibility * T1_Factor * T2_Factor * (N_H_Water./N_H_Metab) ...
        * MM ./ EditingEfficiency;
end


%%%%%%%%%%%%%%% INSET FIGURE %%%%%%%%%%%%%%%%%%%%%%%
function [h_main, h_inset]=inset(main_handle, inset_handle,inset_size)
% Function for figure settings

% The function plotting figure inside figure (main and inset) from 2 existing figures.
% inset_size is the fraction of inset-figure size, default value is 0.35
% The outputs are the axes-handles of both.
%
% An examle can found in the file: inset_example.m
%
% Moshe Lindner, August 2010 (C).

if nargin==2
    inset_size=0.35;
end

inset_size=inset_size*.5;
new_fig=gcf;
main_fig = findobj(main_handle,'Type','axes');
h_main = copyobj(main_fig,new_fig);
set(h_main,'Position',get(main_fig,'Position'))
inset_fig = findobj(inset_handle,'Type','axes');
h_inset = copyobj(inset_fig,new_fig);
ax=get(main_fig,'Position');
set(h_inset,'Position', [1.3*ax(1)+ax(3)-inset_size 1.001*ax(2)+ax(4)-inset_size inset_size*0.7 inset_size*0.9])







