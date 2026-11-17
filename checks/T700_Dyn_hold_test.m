function report=T700_Dyn_hold_test(profile,duration,stepSizes,resultDir,reuseRaw,maxIterations)
% Open-loop constant-Wf/constant-load trim-hold screening in a private copy.
% Criteria are engineering numerical checks, not experimental acceptance limits.
if nargin<1, profile='ballin_trim1'; end
if nargin<2, duration=60; end
if nargin<3, stepSizes=[0.015 0.0075]; end
if nargin<5, reuseRaw=false; end
if nargin<6, maxIterations=[]; end
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<4
    resultDir=fullfile(root,'results',['dyn_hold_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
end
validateattributes(duration,{'numeric'},{'scalar','positive','finite'});
validateattributes(stepSizes,{'numeric'},{'vector','positive','finite'});
if ~isfolder(resultDir), mkdir(resultDir); end
addpath(fullfile(root,'model'));
diary(fullfile(resultDir,'test_log.txt'));
cleanupDiary=onCleanup(@()diary('off'));
source=fullfile(root,'model','T700_Dyn.mdl');
if bdIsLoaded('T700_Dyn')
    assert(strcmp(get_param('T700_Dyn','Dirty'),'off'), ...
        'T700:Hold:UnsavedSource','请先处理 T700_Dyn 的未保存修改。');
end
load_system(source);
MWS=T700_Dyn_initialize(profile);
saved=load(MWS.Dynamic.TrimFile,'report','runs');
if isfield(saved.runs,profile), trim=saved.runs.(profile); else, trim=saved.report; end
model='T700_Dyn_Hold';
assert(~bdIsLoaded(model),'T700:Hold:AlreadyLoaded','测试副本已加载。');
save_system('T700_Dyn',fullfile(resultDir,[model '.mdl']));
cleanupModel=onCleanup(@()close_system(model,0));
inner=[model '/While Iterator' newline 'Subsystem'];
plant=[inner '/Plantmodel'];

% Remove PI actuation and the 15 s demand step from the test input path.
disconnectOutput([model '/Simple PI controller'],1);
set_param([model '/Simple PI controller'],'Commented','on');
set_param([model '/Step1'],'After','MWS.Input.LP_Shaft');
add_block('simulink/Sources/Constant',[model '/Hold_Wf'], ...
    'Value','MWS.Boundary.Wf','Position',[450 1640 570 1670]);
add_line(model,'Hold_Wf/1',['While Iterator' newline 'Subsystem/1'],'autorouting','on');
add_line(model,'Hold_Wf/1','Fuel to Air Ratio/1','autorouting','on');
set_param([model '/Fuel to Air Ratio'],'VariableName','Wf_cmd');
set_param([inner '/FAR'],'Name','Wf');
set_param([inner '/Goto24'],'GotoTag','Wf_cmd');
set_param([inner '/From18'],'GotoTag','Wf_cmd');
set_param([plant '/FAR'],'Name','Wf');
set_param([plant '/Goto4'],'GotoTag','Wf_cmd');
set_param([plant '/From32'],'GotoTag','Wf_cmd');

% Feed Wf directly to the burner. Calculate FAR=Wf/W3 for diagnostics only.
disconnectOutput([plant '/Product'],1);
set_param([plant '/Product'],'Inputs','/*');
add_block('simulink/Signal Routing/Goto',[plant '/Hold_FAR'], ...
    'GotoTag','FAR','Position',[460 -480 540 -450]);
add_line(plant,'Product/1','Hold_FAR/1','autorouting','on');
add_line(plant,'From32/1','Burner/1','autorouting','on');
add_line(plant,'From32/1','Goto25/1','autorouting','on');
addLog(inner,'Iterative NR Solver w JacobianCalc/3','Hold_NR',[2460 730 2570 760]);
addLog(inner,'Mux1/1','Hold_residual',[2460 780 2570 810]);
addLog(inner,'Iterative NR Solver w JacobianCalc/2','Hold_z',[2460 830 2570 860]);
addLog(inner,'While Iterator/1','Hold_iterations',[2460 880 2570 910]);
addLog(inner,'Iterative NR Solver w JacobianCalc/1','Hold_continue',[2460 930 2570 960]);
addLog(model,['While Iterator' newline 'Subsystem/1'],'Hold_Ngdot',[1740 1460 1850 1490]);
addLog(model,['While Iterator' newline 'Subsystem/2'],'Hold_Npdot',[1740 1810 1850 1840]);
addLog(plant,'BC_Qload/1','Hold_Qload',[850 -280 960 -250]);
set_param(model,'StopTime',num2str(duration),'SignalLogging','off');
originalMaxIterations=get_param([inner '/While Iterator'],'MaxIters');
if ~isempty(maxIterations)
    validateattributes(maxIterations,{'numeric'},{'scalar','integer','positive'});
    set_param([inner '/While Iterator'],'MaxIters',num2str(maxIterations));
end
actualMaxIterations=get_param([inner '/While Iterator'],'MaxIters');
fprintf('WHILE_LIMIT source=%s test=%s\n',originalMaxIterations,actualMaxIterations);
save_system(model);

criteria=struct('SpeedRelative',1e-4,'GasPathRelative',5e-4, ...
    'ShaftRate_rpm_s',0.05,'Residual',MWS.Dynamic.C_Lim(:)', ...
    'MassBalance_lbm_s',1e-6,'StepComparisonRelative',1e-5);
report=struct('Profile',profile,'Duration_s',duration,'SourceModel',source, ...
    'HarnessModel',get_param(model,'FileName'),'TrimCheckedAt',trim.CheckedAt, ...
    'SourceMaxIterations',originalMaxIterations,'TestMaxIterations',actualMaxIterations, ...
    'TestMode','open_loop_constant_Wf_and_Qload','Criteria',criteria, ...
    'CriteriaOrigin','proposed_numerical_screening_not_experimental_tolerances', ...
    'ExperimentalValidationPerformed',false,'TransientValidationPerformed',false);
histories=cell(numel(stepSizes),1);
for k=1:numel(stepSizes)
    fprintf('HOLD_RUN_START profile=%s duration=%g step=%g\n',profile,duration,stepSizes(k));
    set_param(model,'FixedStep',num2str(stepSizes(k),17));
    if reuseRaw
        raw=load(fullfile(resultDir,sprintf('run_%02d_raw.mat',k)),'out');
        out=raw.out;
    else
        out=sim(model,'ReturnWorkspaceOutputs','on');
        save(fullfile(resultDir,sprintf('run_%02d_raw.mat',k)),'out','-v7.3');
    end
    [run,history]=analyse(out,trim,MWS,criteria,stepSizes(k),duration);
    report.Runs(k)=run;
    histories{k}=history;
    disp(struct2table(run.Metrics));
    writetable(struct2table(run.Metrics),fullfile(resultDir,sprintf('metrics_%02d.csv',k)),'Encoding','UTF-8');
    fprintf('HOLD_RUN_END passed=%d maxIterations=%g\n',run.Passed,run.MaxIterations);
    save(fullfile(resultDir,sprintf('run_%02d.mat',k)),'out','run','history','-v7.3');
    makePlot(history,run,fullfile(resultDir,sprintf('hold_step_%g.png',stepSizes(k))));
end
report.StepComparisonPassed=true;
report.StepComparison=struct([]);
for k=2:numel(histories)
    a=histories{1}; b=histories{k};
    error=abs(interp1(b.Time,b.Values,a.Time,'linear')-a.Values)./max(abs(a.Reference),eps);
    report.StepComparison(k-1).Steps=[stepSizes(1) stepSizes(k)];
    report.StepComparison(k-1).Names=a.Names;
    report.StepComparison(k-1).MaxRelative=max(error,[],1);
    report.StepComparisonPassed=report.StepComparisonPassed && all(max(error,[],1)<=criteria.StepComparisonRelative);
end
report.Passed=all([report.Runs.Passed]) && report.StepComparisonPassed;
report.CheckedAt=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
save(fullfile(resultDir,'hold_report.mat'),'report');
writeJson(fullfile(resultDir,'hold_report.json'),report);
fprintf('HOLD_TEST_COMPLETE passed=%d\nRESULT_DIR=%s\n',report.Passed,resultDir);
end

function disconnectOutput(block,port)
ph=get_param(block,'PortHandles'); line=get_param(ph.Outport(port),'Line');
if line~=-1, delete_line(line); end
end

function addLog(system,source,name,position)
add_block('simulink/Sinks/To Workspace',[system '/' name], ...
    'VariableName',name,'SaveFormat','Timeseries','MaxDataPoints','inf', ...
    'SampleTime','-1','Position',position);
add_line(system,source,[name '/1'],'autorouting','on');
end

function [run,h]=analyse(out,trim,MWS,c,step,duration)
[t,ng]=series(out.CompData.Nmech);
get=@(ts)sample(ts,t);
z=get(out.Hold_z);
values=[ng,get(out.FPTData.Nmech),z, ...
    get(out.S3.Pt),get(out.S3.Tt),get(out.S41.Pt),get(out.S41.Tt), ...
    get(out.S45.Pt),get(out.S45.Tt),get(out.S49.Pt),get(out.S49.Tt)];
names={'Ng','Np','W_in','Rline','PR_GGT','PR_FPT','P3','T3','P41','T41','P45','T45','P49','T49'};
units={'rpm','rpm','lbm/s','-','-','-','psia','R','psia','R','psia','R','psia','R'};
reference=[trim.X(5:6)',trim.X(1:4)',trim.Stations.S3.Pt,trim.Stations.S3.Tt, ...
    trim.Stations.S41.Pt,trim.Stations.S41.Tt,trim.Stations.S45.Pt,trim.Stations.S45.Tt, ...
    trim.Stations.S49.Pt,trim.Stations.S49.Tt];
tolerances=[c.SpeedRelative*ones(1,2),c.GasPathRelative*ones(1,numel(names)-2)];
residual=get(out.Hold_residual);
rate=[get(out.Hold_Ngdot),get(out.Hold_Npdot)];
wf=get(out.Plant_Data.Wf); q=get(out.Hold_Qload);
mass=get(out.S49.W)-(get(out.S2.W)+wf-(get(out.S2.W)-get(out.S3.W)-(get(out.S45.W)-get(out.S41.W))));
metricCells=cell(1,numel(names));
for j=1:numel(names)
    dev=values(:,j)-reference(j);
    tail=t>=0.8*duration;
    fit=polyfit(t(tail)-t(find(tail,1)),values(tail,j),1);
    metricCells{j}=struct('Name',names{j},'Unit',units{j},'Reference',reference(j), ...
        'Initial',values(1,j),'Final',values(end,j),'MaxAbsError',max(abs(dev)), ...
        'MaxRelativeError',max(abs(dev))/abs(reference(j)), ...
        'TailPeakToPeak',max(values(tail,j))-min(values(tail,j)), ...
        'TailSlope_per_s',fit(1),'RelativeTolerance',tolerances(j), ...
        'Passed',max(abs(dev))/abs(reference(j))<=tolerances(j));
end
metrics=[metricCells{:}];
finiteCount=checkFinite(out.Plant_Data)+checkFinite(out.Hold_NR)+checkFinite(out.Hold_residual)+ ...
    checkFinite(out.Hold_Ngdot)+checkFinite(out.Hold_Npdot);
nr=out.Hold_NR;
assert(isfield(nr,'JacFalied'),'T700:Hold:NRLog','无法找到求解器 JacFalied 状态。');
noJacFailure=~any(get(nr.JacFalied),'all');
if ismember('Hold_continue',out.who)
    noUnconvergedOutputs=~any(get(out.Hold_continue),'all');
else
    noUnconvergedOutputs=all(max(abs(residual),[],1)<=c.Residual);
end
maxResidual=max(abs(residual),[],1);
maxRates=max(abs(rate),[],1);
constantInputs=all(abs(wf-MWS.Boundary.Wf)<1e-12) && ...
    all(abs(q-MWS.Boundary.Qload)<1e-12) && ...
    all(abs(get(out.S2.Pt)-MWS.Boundary.P2_psia)<1e-12) && ...
    all(abs(get(out.S2.Tt)-MWS.Boundary.T2_R)<1e-12);
mapOK=true;
components={out.CompData,out.GGTData,out.FPTData}; configs={MWS.Compressor,MWS.GGT,MWS.FPT};
for j=1:3
    nc=get(components{j}.NcMap);
    if j==1, coord=z(:,2); axis=configs{j}.RlineVec; else, coord=z(:,j+1); axis=configs{j}.PRVec; end
    mapOK=mapOK && all(nc>=min(configs{j}.NcVec) & nc<=max(configs{j}.NcVec)) && ...
        all(coord>=min(axis) & coord<=max(axis));
end
run=struct('Step_s',step,'EndTime_s',t(end),'SampleCount',numel(t), ...
    'FiniteTimeseriesChecked',finiteCount,'ConstantInputsPassed',constantInputs, ...
    'MaxWfDeviation_lbm_s',max(abs(wf-MWS.Boundary.Wf)), ...
    'MaxQloadDeviation_lbf_ft',max(abs(q-MWS.Boundary.Qload)), ...
    'NoJacobianFailure',noJacFailure,'MaxIterations',max(get(out.Hold_iterations)), ...
    'NoUnconvergedOutputs',noUnconvergedOutputs, ...
    'ResidualOrder',{MWS.Solve.ResidualOrder(1:4)},'MaxAbsResidual',maxResidual, ...
    'ResidualsPassed',all(maxResidual<=c.Residual), ...
    'MaxAbsShaftRates_rpm_s',maxRates,'ShaftRatesPassed',all(maxRates<=c.ShaftRate_rpm_s), ...
    'MaxMassBalanceError_lbm_s',max(abs(mass)),'MassBalancePassed',max(abs(mass))<=c.MassBalance_lbm_s, ...
    'MapRangesPassed',mapOK,'Metrics',metrics);
run.Passed=constantInputs && noJacFailure && noUnconvergedOutputs && run.ResidualsPassed && run.ShaftRatesPassed && ...
    run.MassBalancePassed && mapOK && all([metrics.Passed]) && abs(t(end)-duration)<1e-8;
h=struct('Time',t,'Values',values,'Names',{names},'Reference',reference, ...
    'Rates',rate,'Residuals',residual,'Wf',wf,'Qload',q);
end

function [t,y]=series(ts)
t=double(ts.Time(:));
data=double(ts.Data);
if ts.IsTimeFirst
    y=reshape(data,numel(t),[]);
else
    n=ndims(data); y=reshape(permute(data,[n 1:n-1]),numel(t),[]);
end
[t,index]=unique(t,'last'); y=y(index,:);
end

function y=sample(ts,t)
[sourceTime,data]=series(ts);
if isscalar(sourceTime)
    % Simulink logs a constant-rate signal only once (normally at t=0).
    y=repmat(data,numel(t),1);
elseif isequal(sourceTime,t)
    y=data;
else
    y=interp1(sourceTime,data,t,'linear');
end
assert(all(isfinite(y),'all'),'T700:Hold:Sample','日志采样出现非有限值。');
end

function count=checkFinite(value)
count=0;
if isa(value,'timeseries')
    assert(~isempty(value.Data) && all(isfinite(value.Data(:))),'T700:Hold:Nonfinite','日志包含 NaN/Inf。');
    count=1;
elseif isstruct(value)
    for field=fieldnames(value)', count=count+checkFinite(value.(field{1})); end
else
    error('T700:Hold:LogType','不支持的日志类型：%s。',class(value));
end
end

function makePlot(h,run,file)
fig=figure('Visible','off','Position',[100 100 1450 1050],'Color','white');
cleanup=onCleanup(@()close(fig));
tiledlayout(4,2,'TileSpacing','compact','Padding','compact');
nexttile; plot(h.Time,h.Values(:,1:2)-h.Reference(1:2),'LineWidth',1.3); grid on;
ylabel('Speed error [rpm]'); legend('Ng','Np','Location','best'); title('Shaft speeds relative to saved trim');
nexttile; plot(h.Time,h.Rates,'LineWidth',1.2); grid on; ylabel('rpm/s'); legend('Ng dot','Np dot'); title('Shaft derivatives');
nexttile; plot(h.Time,100*(h.Values(:,[7 9 11 13])./h.Reference([7 9 11 13])-1),'LineWidth',1.2); grid on;
ylabel('Pressure error [%]'); legend('P3','P41','P45','P49'); title('Gas path pressures');
nexttile; plot(h.Time,100*(h.Values(:,[8 10 12 14])./h.Reference([8 10 12 14])-1),'LineWidth',1.2); grid on;
ylabel('Temperature error [%]'); legend('T3','T41','T45','T49'); title('Gas path temperatures');
nexttile; plot(h.Time,100*(h.Values(:,3:6)./h.Reference(3:6)-1),'LineWidth',1.2); grid on;
ylabel('Algebraic error [%]'); legend('W in','Rline','PR GGT','PR FPT'); title('Four algebraic variables');
nexttile; semilogy(h.Time,max(abs(h.Residuals),realmin),'LineWidth',1.1); hold on; yline(1e-6,'k--'); grid on;
ylabel('Absolute residual'); legend('P49','Comp','GGT','FPT','Limit'); title('Accepted gas path residuals');
nexttile; plot(h.Time,h.Wf,'LineWidth',1.2); grid on; ylabel('Wf [lbm/s]'); xlabel('Time [s]'); title('Constant fuel input');
nexttile; plot(h.Time,h.Qload,'LineWidth',1.2); grid on; ylabel('Qload [lbf ft]'); xlabel('Time [s]'); title('Constant shaft load');
sgtitle(sprintf('T700 open-loop trim hold | dt = %g s | numerical screen pass = %d',run.Step_s,run.Passed));
exportgraphics(fig,file,'Resolution',150);
end

function writeJson(file,value)
fid=fopen(file,'w','n','UTF-8'); assert(fid~=-1,'结果文件无法写入。');
cleanup=onCleanup(@()fclose(fid)); fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));
end
