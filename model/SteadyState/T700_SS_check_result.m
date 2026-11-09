function report = T700_SS_check_result(MWS,saveResults)
% Check an already completed T700 SS run. No initialization/model changes.
% Uses existing Case02Logs, station and component diagnostic workspace logs.
% Assumes ordinary off-design turbine format, zero inlet FAR and rear GGT cooling.
% Residuals are reconstructed from logged diagnostics, not a direct Mux log.
% Optional saveResults=false displays checks without writing result files.
if nargin<1, MWS=workspaceValue('MWS'); end
if nargin<2, saveResults=true; end
assert(ismember(lower(MWS.Boundary.Profile),{'ballin_trim1','ballin_trim2','ballin_trim3'}), ...
    '当前稳态主线只检查 B.1 三工况，请先选择 ballin_trim1/2/3；Lewis 验证已暂缓。');
validateattributes(saveResults,{'logical'},{'scalar'});
logs=workspaceValue('Case02Logs');
solver=logs.getElement('Case02_S').Values;
xSignal=logs.getElement('Case02_X').Values;
x=lastValue(xSignal); x=x(:);
assert(numel(x)==6,'稳态未知量 X 应包含 6 个元素。');
stationNames={'s2','s3','s4','s5','s6'};
canonical={'S2','S3','S41','S45','S49'};
stationFields={'W','ht','Tt','Pt','FAR'};
S=struct;
for k=1:5
    raw=workspaceValue(stationNames{k});
    S.(canonical{k})=readScalars(raw,stationFields);
end
assert(abs(S.S2.FAR)<1e-12,'此守恒检查要求入口 FAR=0。');
D.Compressor=readScalars(workspaceValue('C_Data'), ...
    {'Wcin','WcMap','s_C_Wc','NcMap','PRMap','Nmech','Wbleeds','Pwrout'});
fields={'Wcs1in','WcMap','s_T_Wc','NcMap','PRMap','Nmech','Pwrout'};
D.GGT=readScalars(workspaceValue('GGT_Data'),fields);
D.FPT=readScalars(workspaceValue('FPT_Data'),fields);
assert(all([D.Compressor.Wcin,D.GGT.Wcs1in,D.FPT.Wcs1in]>0));

report=struct;
report.CheckerVersion=4;
report.ValidationScope='NASA_TM_100991_standard_reference_reproduction';
report.CheckedAt=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
report.Profile=MWS.Boundary.Profile;
report.Boundary=MWS.Boundary;
% Retain the reference-Ng value for initial-seed/reference audits only.
report.Boundary.P49Role='initial_seed_and_reference_audit_only';
report.Boundary.P49Source='A10 at reference Ng; active target is report.Exhaust.P49Target_psia';
report.X=x;
report.UnknownOrder=MWS.Solve.UnknownOrder;
report.Stations=S;
report.Diagnostics=D;
report.SolverConverged=logical(lastValue(getValue(solver,'Converged')));
report.JacFailed=logical(lastValue(getValue(solver,'JacFailed')));
report.ResidualOrder=MWS.Solve.ResidualOrder;
report.ResidualSource='Reconstructed from logged ordinary T-MATS component diagnostics';
report.InputContextMatches=abs(S.S2.Pt-MWS.Boundary.P2_psia)<1e-7 && ...
    abs(S.S2.Tt-MWS.Boundary.T2_R)<1e-6 && ...
    abs((S.S41.W-S.S3.W)-MWS.Boundary.Wf)<1e-7;

% Constants are from installed constants_TMATS.h / Shaft library.
hpToTorque=5252.113;
accessoryHpToTorque=5252.11;
btuPerSecondToHp=1.414853;
torqueC=hpToTorque*D.Compressor.Pwrout/D.Compressor.Nmech;
torqueG=hpToTorque*D.GGT.Pwrout/D.GGT.Nmech;
torqueF=hpToTorque*D.FPT.Pwrout/D.FPT.Nmech;
netNg=torqueC+torqueG-accessoryHpToTorque*MWS.Boundary.Pacc_g/x(5);
% Current model contains the signed Ballin speed-deviation correction.
% Validate its fixed settings before reconstructing the logged shaft balance.
damping=readPowerTurbineDamping('T700_SS');
damping.Torque_lbf_ft=damping.Gain_lbf_ft_per_rpm*(x(6)-damping.NpDesign_rpm);
damping.Power_hp=damping.Torque_lbf_ft*x(6)/hpToTorque;
accessoryTorque=accessoryHpToTorque*MWS.Boundary.Pacc_p/x(6);
netNp=torqueF-damping.Torque_lbf_ft-MWS.Boundary.Qload-accessoryTorque;
report.DampingApplied=true;
report.Damping=damping;
report.PowerBreakdown.GasPower_hp=D.FPT.Pwrout;
report.PowerBreakdown.DampingPower_hp=damping.Power_hp;
report.PowerBreakdown.AccessoryPower_hp=accessoryTorque*x(6)/hpToTorque;
report.PowerBreakdown.ShaftOutputPower_hp= ...
    (torqueF-damping.Torque_lbf_ft-accessoryTorque)*x(6)/hpToTorque;
report.PowerBreakdown.LoadPower_hp=MWS.Boundary.Qload*x(6)/hpToTorque;
report.Exhaust=checkExhaustState(MWS,x,S,xSignal);
r=[report.Exhaust.PressureResidual; ...
    (D.Compressor.Wcin-D.Compressor.WcMap*D.Compressor.s_C_Wc)/D.Compressor.Wcin; ...
    (D.GGT.Wcs1in-D.GGT.WcMap*D.GGT.s_T_Wc)/D.GGT.Wcs1in; ...
    (D.FPT.Wcs1in-D.FPT.WcMap*D.FPT.s_T_Wc)/D.FPT.Wcs1in; ...
    60*netNg/(2*pi*MWS.Shaft.J);60*netNp/(2*pi*MWS.Shaft1.J)];
report.Residual=r;
report.ResidualTolerances=MWS.Solve.C_Lim(:);
report.ResidualsPassed=all(abs(r)<=report.ResidualTolerances);
report.ShaftNetTorque_lbf_ft=[netNg;netNp];

% Check the actual requested map coordinates, not a clamped interpolated value.
coords=[x(2),D.Compressor.NcMap;D.GGT.PRMap,D.GGT.NcMap;D.FPT.PRMap,D.FPT.NcMap];
names={'Compressor','GGT','FPT'};
inRange=false(3,1);
for k=1:3
    C=MWS.(names{k});
    if k==1, axis=C.RlineVec; else, axis=C.PRVec; end
    inRange(k)=coords(k,1)>=min(axis) && coords(k,1)<=max(axis) && ...
        coords(k,2)>=min(C.NcVec) && coords(k,2)<=max(C.NcVec);
    report.MapCoordinates.(names{k})=coords(k,:);
    report.MapLimits.(names{k})=[min(axis),max(axis);min(C.NcVec),max(C.NcVec)];
end
report.MapInputsInRange=inRange;
report.MapRangesPassed=all(inRange);

% Reconstruct the current BleedSchedule from the final logged state.
% Match the model's endpoint clipping for diagnostics, but reject an
% out-of-domain final solution through AllChecksPassed below.
B=MWS.Compressor.BleedSchedule;
ref=B.ReferenceCoordinates;
ngc=100*x(5)/(ref(3)*sqrt(S.S2.Tt/ref(1)));
wc=D.Compressor.Wcin;
report.BleedScheduleCoordinates=[ngc;wc];
report.BleedScheduleInRange= ...
    ngc>=B.B1_NGcPercent(1) && ngc<=B.B1_NGcPercent(end) && ...
    wc>=B.B2_Wc(1) && wc<=B.B2_Wc(end) && ...
    wc>=B.B3_Wc(1) && wc<=B.B3_Wc(end);
q1=min(max(ngc,B.B1_NGcPercent(1)),B.B1_NGcPercent(end));
q2=min(max(wc,B.B2_Wc(1)),B.B2_Wc(end));
q3=min(max(wc,B.B3_Wc(1)),B.B3_Wc(end));
b1=interp1(B.B1_NGcPercent,B.B1_Fraction,q1,'linear');
b2=interp1(B.B2_Wc,B.B2_Fraction,q2,'linear');
b3=interp1(B.B3_Wc,B.B3_Fraction,q3,'linear');
% Two discarded streams; the third returns at the GGT outlet.
fractions=[b1+b2;b3*(1-B.Kbl)+B.Kb3;b3*B.Kbl];
report.BleedScheduleMode='state_dependent_A3_A5';
report.BleedFractionsAtSolution=fractions;
hfractions=MWS.Compressor.BleedEnthalpyFractions(:);
assert(numel(fractions)==3 && numel(hfractions)==3);
bleedW=S.S2.W*fractions;
bleedH=S.S2.ht+hfractions*(S.S3.ht-S.S2.ht);
returnedCooling=S.S45.W-S.S41.W;
report.BleedFlowExpected_lbm_s=bleedW;
report.TotalBleedLogged_lbm_s=D.Compressor.Wbleeds;
report.CoolingReturnLogged_lbm_s=returnedCooling;
report.BleedConfigurationPassed=abs(D.Compressor.Wbleeds-sum(bleedW))<1e-6 && ...
    abs(returnedCooling-bleedW(3))<1e-6;
report.MassError_lbm_s=S.S49.W-(S.S2.W+MWS.Boundary.Wf-sum(bleedW(1:2)));
report.MassTolerance_lbm_s=1e-6;
report.MassBalancePassed=abs(report.MassError_lbm_s)<=report.MassTolerance_lbm_s;

% Steady enthalpy balances [Btu/s]; using logged ht preserves gas-table datum.
heatIn=MWS.Boundary.Wf*MWS.Burner.LHV*MWS.Burner.Eff;
power=[D.Compressor.Pwrout;D.GGT.Pwrout;D.FPT.Pwrout]/btuPerSecondToHp;
energy=[S.S2.W*S.S2.ht-S.S3.W*S.S3.ht-sum(bleedW.*bleedH)-power(1); ...
    S.S3.W*S.S3.ht+heatIn-S.S41.W*S.S41.ht; ...
    S.S41.W*S.S41.ht+bleedW(3)*bleedH(3)-S.S45.W*S.S45.ht-power(2); ...
    S.S45.W*S.S45.ht-S.S49.W*S.S49.ht-power(3)];
scale=[max([abs(S.S2.W*S.S2.ht),abs(S.S3.W*S.S3.ht),abs(power(1)),1]); ...
    max([abs(heatIn),abs(S.S41.W*S.S41.ht),1]); ...
    max([abs(S.S41.W*S.S41.ht),abs(power(2)),1]); ...
    max([abs(S.S45.W*S.S45.ht),abs(power(3)),1])];
report.EnergyComponentOrder={'Compressor','Burner','GGT','FPT'};
report.EnergyError_Btu_s=energy;
report.EnergyRelativeError=energy./scale;
report.EnergyRelativeTolerance=1e-3; % Numerical screening, not experimental accuracy.
report.EnergyBalancePassed=all(abs(report.EnergyRelativeError)<=report.EnergyRelativeTolerance);
report.AllChecksPassed=report.SolverConverged && ~report.JacFailed && ...
    report.InputContextMatches && report.Exhaust.AllChecksPassed && ...
    report.ResidualsPassed && report.MapRangesPassed && ...
    report.BleedScheduleInRange && ...
    report.BleedConfigurationPassed && report.MassBalancePassed && report.EnergyBalancePassed;
report.ExperimentalValidationPassed=false;
report.ExperimentalValidationStatus='not_applicable_Ballin_model_reference';
report.DynamicTrimVerified=false;
report.LowPRCompressorRegionUsed=x(2)>2;
report.FixedParameterReferenceTrim=1;
report.SourcePressureRatioAmbiguityResolved=false;
% Table B.1 comparison is source-model consistency, not experimental validation.
if startsWith(lower(report.Profile),'ballin_trim') && isfield(MWS.Reference,'Ballin')
    ref=MWS.Reference.Ballin(MWS.Reference.Ballin.TrimID==MWS.Boundary.TrimID,:);
    comparison.Quantities={'Ng','Np','Ps3','P41','P45','T41','T45','Power'};
    comparison.Units={'rpm','rpm','psia','psia','psia','degR','degR','hp'};
    comparison.Reference=[ref.Ng_rpm;ref.Np_rpm;ref.Ps3_psia;ref.P41_psia; ...
        ref.P45_psia;ref.T41_R;ref.T45_R;ref.Power_hp];
    comparison.Simulation=[x(5);x(6);S.S3.Pt*MWS.T700.Constants.Kps3; ...
        S.S41.Pt;S.S45.Pt;S.S41.Tt;S.S45.Tt;report.PowerBreakdown.ShaftOutputPower_hp];
    comparison.ErrorPercent=100*(comparison.Simulation-comparison.Reference)./comparison.Reference;
    comparison.Source='NASA-TM-100991 Appendix B Table B.1; PDF67 printed53';
    comparison.TrimID=MWS.Boundary.TrimID;
    comparison.Ps3Convention='Ps3=Kps3*logged total pressure Pt3';
    comparison.PowerConvention='Effective shaft output after signed damping and accessory torque; gas power reported separately';
    comparison.IndependentExperimentalValidation=false;
    report.ReferenceComparison=comparison;
    fprintf('B.1 同源参考对比（误差单位：%%）：\n');
    showChineseTable(table(comparison.Quantities(:),comparison.Units(:),comparison.Reference, ...
        comparison.Simulation,comparison.ErrorPercent), ...
        {'物理量','单位','参考值','仿真值','相对误差_pct'});
end
% Keep the source functions for existing Ballin relationship audits only.
sourceData=load(MWS.Project.ParameterBundle,'T700Parameters');
report.ReferenceAccuracyStatus='pending_review_no_agreed_error_limits';
report.FigureComparisonStatus='pending_reference_digitization_and_boundary_alignment';
% These coordinates support later Figures 6-8 comparison; they are not GE data.
report.PerformancePoint=struct('Wf_lb_h',MWS.Boundary.Wf*3600, ...
    'NgPercent',100*x(5)/MWS.T700.Constants.NgDesign, ...
    'Power_hp',report.PowerBreakdown.ShaftOutputPower_hp, ...
    'Ps3_psia',S.S3.Pt*MWS.T700.Constants.Kps3, ...
    'Np_rpm',x(6),'Qload_lbf_ft',MWS.Boundary.Qload, ...
    'P2_psia',MWS.Boundary.P2_psia,'T2_R',MWS.Boundary.T2_R, ...
    'P49_psia',S.S49.Pt,'P49Target_psia',report.Exhaust.P49Target_psia, ...
    'FigureBoundaryConditionsConfirmed',false);

residualLabels={'P49 状态相关排气残差';'Compressor 流量残差';'GGT 流量残差'; ...
    'FPT 流量残差';'Ng 转速变化率 (rpm/s)';'Np 转速变化率 (rpm/s)'};
showChineseTable(table(residualLabels,r,report.ResidualTolerances,abs(r)<=report.ResidualTolerances), ...
    {'残差项','残差值','容差','是否通过'});
checks={'InputContextMatches','ExhaustChecksPassed','ResidualsPassed','MapRangesPassed','BleedScheduleInRange', ...
    'BleedConfigurationPassed','MassBalancePassed','EnergyBalancePassed'};
report.ExhaustChecksPassed=report.Exhaust.AllChecksPassed;
checkLabels={'日志与当前输入一致','状态相关排气检查通过','六项残差检查通过','特性图坐标在范围内','引气查表坐标在范围内', ...
    '引气及冷却配置检查通过','质量守恒检查通过','能量守恒检查通过'};
for k=1:numel(checks), fprintf('%s：%s\n',checkLabels{k},passText(report.(checks{k}))); end
fprintf('排气查表 NGc=%.8g%%，A10 系数=%.8g，范围检查：%s。\n', ...
    report.Exhaust.NGcPercent,report.Exhaust.Factor,passText(report.Exhaust.InRange));
fprintf('P49 (psia)：计算值 %.8g，目标日志 %.8g，独立复算目标 %.8g；T49=%.8g R。\n', ...
    S.S49.Pt,report.Exhaust.LoggedTarget_psia,report.Exhaust.P49Target_psia,S.S49.Tt);
fprintf('P49 目标日志匹配：%s；残差日志匹配：%s；日志末时刻匹配：%s。\n', ...
    passText(report.Exhaust.TargetLogMatches),passText(report.Exhaust.ResidualLogMatches), ...
    passText(report.Exhaust.LogTimeMatches));
fprintf('初始化 P49=%.8g psia 仅作初值及参考关系审计，不再作为活动压力目标。\n', ...
    report.Exhaust.InitialSeedP49_psia);
fprintf('引气查表坐标：[NGc (%%), Wc (lbm/s)] = %.8g, %.8g\n',ngc,wc);
fprintf('最终引气比例 [第4级排出、出口排出、冷却回流]：%.8g, %.8g, %.8g\n',fractions);
fprintf('质量守恒误差 (lbm/s)：%.6g\n',report.MassError_lbm_s);
fprintf('有符号阻尼转矩 (lbf*ft)：%.8g；阻尼功率 (hp)：%.8g\n', ...
    damping.Torque_lbf_ft,damping.Power_hp);
fprintf('功率 (hp)：FPT 燃气功率 %.8g，有效轴输出 %.8g，负载功率 %.8g\n', ...
    report.PowerBreakdown.GasPower_hp,report.PowerBreakdown.ShaftOutputPower_hp, ...
    report.PowerBreakdown.LoadPower_hp);
outDir=fullfile(fileparts(mfilename('fullpath')),'results');
resultFile=fullfile(outDir,'T700_SS_result_check.mat');
report.ResultFile=resultFile;
runs=struct;
if isfile(resultFile)
    previousResults=load(resultFile);
    if isfield(previousResults,'runs')
        runs=previousResults.runs;
    elseif isfield(previousResults,'report') && isfield(previousResults.report,'Profile')
        old=previousResults.report;
        if strcmpi(old.Profile,'lewis')
            oldKey=sprintf('lewis_case%d',old.Boundary.CaseID);
        else
            oldKey=old.Profile;
        end
        runs.(matlab.lang.makeValidName(oldKey))=old;
    end
end
key=report.Profile;
runs.(matlab.lang.makeValidName(key))=report;
[steadySummary,~]=T700_SS_summary(runs);
report.SteadySummary=steadySummary;
report.ResultsSaved=saveResults;
runs.(matlab.lang.makeValidName(key))=report;
sourceConsistency=checkSourceRelations(runs,sourceData.T700Parameters.SourceFunctions);
adaptationAudit=checkAdaptation(runs,sourceData.T700Parameters);
% Keep dated offline source-replay evidence, with its own baseline fingerprints.
if saveResults
    if ~isfolder(outDir), mkdir(outDir); end
    if isfile(resultFile)
        save(resultFile,'report','runs','sourceConsistency','adaptationAudit','steadySummary','-append');
    else
        save(resultFile,'report','runs','sourceConsistency','adaptationAudit','steadySummary');
    end
    fprintf('检查结果已保存：%s\n',resultFile);
else
    fprintf('本次仅显示检查结果，未写入结果文件。\n');
end
fprintf('数值与物理一致性总检查：%s（AllChecksPassed=%d）。\n', ...
    passText(report.AllChecksPassed),report.AllChecksPassed);
fprintf('B.1 参考误差需单独评价；数值检查通过不等于参考误差全部合格。\n');
fprintf('Figures 6-8 性能范围对比与动态配平尚待后续完成。\n');
end

function exhaust=checkExhaustState(MWS,x,S,xSignal)
% Replay the model's linear A10 lookup with clipped numerical trials.
% The FINAL state must lie inside A10; clipped out-of-domain states fail.
C=MWS.T700.Constants; A=MWS.T700.Exhaust;
axis=A.NGcPercent(:); values=A.Factor(:);
validateattributes(axis,{'numeric'},{'column','finite','increasing','nonempty'});
assert(numel(axis)>=2 && numel(values)==numel(axis) && ...
    all(isfinite(values)) && all(values>0),'A10 断点和系数必须有效且长度一致。');
exhaust.Mode='state_dependent_A10_Eq38';
exhaust.Interpretation=A.Interpretation;
exhaust.SourcePressureRatioAmbiguityResolved=false;
exhaust.NGcPercent=100*x(5)/(C.NgDesign*sqrt(S.S2.Tt/C.Tstd));
exhaust.InRange=exhaust.NGcPercent>=axis(1) && exhaust.NGcPercent<=axis(end);
query=min(max(exhaust.NGcPercent,axis(1)),axis(end));
exhaust.Factor=interp1(axis,values,query,'linear');
% B.1 inlet approximation: BC_P1 uses the same ambient pressure as P2.
exhaust.Ps9_psia=MWS.Boundary.P2_psia;
exhaust.P49Target_psia=exhaust.Ps9_psia*exhaust.Factor;
exhaust.InitialSeedP49_psia=MWS.Boundary.P49_psia;
exhaust.P49Calculated_psia=S.S49.Pt;
exhaust.T49_R=S.S49.Tt;
targetSignal=workspaceValue('P49_target');
residualSignal=workspaceValue('P49_error');
exhaust.LoggedTarget_psia=lastValue(targetSignal);
exhaust.LoggedResidual=lastValue(residualSignal);
assert(isscalar(exhaust.LoggedTarget_psia) && isscalar(exhaust.LoggedResidual), ...
    'P49_target 和 P49_error 的最终日志必须为标量。');
exhaust.PressureResidual=(S.S49.Pt-exhaust.P49Target_psia)/exhaust.P49Target_psia;
exhaust.TargetLogTolerance_psia=1e-7;
exhaust.ResidualLogTolerance=1e-9;
exhaust.TargetLogMatches=abs(exhaust.LoggedTarget_psia-exhaust.P49Target_psia)<=exhaust.TargetLogTolerance_psia;
exhaust.ResidualLogMatches=abs(exhaust.LoggedResidual-exhaust.PressureResidual)<=exhaust.ResidualLogTolerance;
exhaust.LogTimeMatches=matchingEndTime(xSignal,targetSignal) && ...
    matchingEndTime(xSignal,residualSignal);
exhaust.AllChecksPassed=exhaust.InRange && exhaust.TargetLogMatches && ...
    exhaust.ResidualLogMatches && exhaust.LogTimeMatches;
end

function ok=matchingEndTime(a,b)
ok=isa(a,'timeseries') && isa(b,'timeseries') && ...
    ~isempty(a.Time) && ~isempty(b.Time);
if ok
    ok=abs(a.Time(end)-b.Time(end))<=1e-9*max(1,abs(a.Time(end)));
end
end

function damping=readPowerTurbineDamping(mdl)
% Read the open model only; no loading, updating, saving or simulation.
assert(bdIsLoaded(mdl),'检查仿真结果时，请保持 T700_SS 模型打开。');
settings={
    'PT_NpDesign','Value','20900'
    'PT_SpeedError','Inputs','+-'
    'PT_DampingGain','Gain','0.06854*2*pi/60'
    'PT_DampingSign','Gain','-1'
    'Mux3','Inputs','3'};
for k=1:size(settings,1)
    actual=get_param([mdl '/' settings{k,1}],settings{k,2});
    assert(strcmp(regexprep(actual,'\s+',''),settings{k,3}), ...
        '模块 %s 的阻尼设置不符，请先运行 T700_SS_check_model。',settings{k,1});
end
damping.Mode='Ballin_Eq41_signed_speed_deviation';
damping.NpDesign_rpm=20900;
damping.Kdamp_lbf_ft_s_rad=0.06854;
damping.Gain_lbf_ft_per_rpm=0.06854*2*pi/60;
damping.ModelFile=get_param(mdl,'FileName');
damping.ModelDirty=get_param(mdl,'Dirty');
end

function audit=checkAdaptation(runs,P)
% Read-only diagnosis. This audit does not change model settings.
% The saved-run flag distinguishes older undamped and newer damped runs.
% Ballin Eq12-16,29-30,41 / Table A.1. Current topology has rear cooling.
F=P.SourceFunctions; C=P.Constants;
audit.Source='NASA-TM-100991 Eq12-16,24-30,41 and Table A.1';
audit.ModelOrParameterChangesApplied=false;
audit.IndependentExperimentalValidation=false;
audit.NativeMEXExecuted=exist('T2HM_TMATS','file')==3 && exist('H2TM_TMATS','file')==3;
audit.Bleeds.Columns={'TrimID','NGc_percent','B1_FrozenTrim1','B1_SourceAtActualNg', ...
    'B1_SourceAtReferenceNg','Stage4FractionConfigured','Stage4FractionSource', ...
    'AdditionalStage4BleedAtFixedInlet_lbm_s','CoolingConfigured_lbm_s','CoolingSource_lbm_s'};
audit.Bleeds.Values=zeros(0,numel(audit.Bleeds.Columns));
audit.Damping.Kdamp_lbf_ft_s_rad=.06854;
audit.Damping.NpDesign_rpm=20900;
audit.Damping.Columns={'TrimID','Np_Current_rpm','SourceDampingTorque_lbf_ft', ...
    'SourceDampingPowerAtCurrent_hp','FrozenGasPathPredictedNp_rpm', ...
    'PredictedNpErrorPercent','PredictedLoadPower_hp','DampingAppliedInSavedRun'};
audit.Damping.Values=zeros(0,numel(audit.Damping.Columns));
audit.Damping.Interpretation=['Frozen logged gas path and FPT gas power; ' ...
    'algebraic calculation only, not a Simulink run. For undamped historical runs it is a sensitivity; ' ...
    'for damped runs it checks the already-applied balance. Source damping is signed about NpDesign.'];
audit.Thermal.Columns={'TrimID','T45_Replay_R','T45_Logged_R','ReplayMinusLogged_R', ...
    'T45_NativeWithSourceDh_R','T45_Ballin_R', ...
    'NativeThermoMixContribution_R','MapDhContribution_R'};
audit.Thermal.Values=zeros(0,numel(audit.Thermal.Columns));
audit.Thermal.EvaluationMethod='Unavailable: native thermodynamic MEX functions are not on the path';
if audit.NativeMEXExecuted
    audit.Thermal.EvaluationMethod='Native T2HM_TMATS / H2TM_TMATS MEX calls';
end
audit.Thermal.Interpretation=['NativeWithSourceDh retains recorded mass flows, FAR and ' ...
    'compressor-outlet cooling enthalpy. Contributions are fixed-state diagnostics.'];
keys=fieldnames(runs);
for k=1:numel(keys)
    r=runs.(keys{k});
    if ~startsWith(lower(r.Profile),'ballin_trim') || ~isfield(r,'ReferenceComparison'), continue; end
    S=r.Stations; ref=r.ReferenceComparison.Reference(:); trim=r.Boundary.TrimID;
    ngc=100*r.X(5)/sqrt(S.S2.Tt/C.Tstd)/C.NgDesign;
    ngcRef=100*ref(1)/sqrt(S.S2.Tt/C.Tstd)/C.NgDesign;
    b1=lookup(F.A03,ngc); b2=lookup(F.A04,r.Diagnostics.Compressor.Wcin);
    b3=lookup(F.A05,r.Diagnostics.Compressor.Wcin);
    configured=r.BleedFlowExpected_lbm_s(1)/S.S2.W;
    wcool=S.S45.W-S.S41.W;
    audit.Bleeds.Values(end+1,:)=[trim,ngc,P.Reference.B1,b1,lookup(F.A03,ngcRef), ...
        configured,b1+b2,S.S2.W*(b1+b2-configured),wcool,S.S2.W*b3*C.Kbl];
    kd=audit.Damping.Kdamp_lbf_ft_s_rad*2*pi/60;
    n=r.X(6); power=r.Diagnostics.FPT.Pwrout; q=r.Boundary.Qload;
    qd=kd*(n-audit.Damping.NpDesign_rpm);
    a=q-kd*audit.Damping.NpDesign_rpm;
    predicted=2*power*5252.113/(a+sqrt(a^2+4*kd*power*5252.113));
    audit.Damping.Values(end+1,:)=[trim,n,qd,qd*n/5252.113,predicted, ...
        100*(predicted/ref(2)-1),q*predicted/5252.113, ...
        isfield(r,'DampingApplied') && r.DampingApplied];
    if audit.NativeMEXExecuted
        % Compare temperatures; never multiply Ballin KH45 into native absolute h.
        hin=T2HM_TMATS(S.S41.Tt,S.S41.FAR);
        hc=T2HM_TMATS(S.S3.Tt,0);
        dhModel=r.Diagnostics.GGT.Pwrout/1.414853/S.S41.W;
        dhSource=(.0018326*S.S41.Tt+.0856)*lookup(F.A07,S.S45.Pt/S.S41.Pt);
        hReplay=(S.S41.W*(hin-dhModel)+wcool*hc)/S.S45.W;
        hSource=(S.S41.W*(hin-dhSource)+wcool*hc)/S.S45.W;
        tReplay=H2TM_TMATS(hReplay,S.S45.FAR);
        tNative=H2TM_TMATS(hSource,S.S45.FAR);
        tBallin=3.519*.9623*(.301*S.S41.Tt-86.905-dhSource)+179.1;
        audit.Thermal.Values(end+1,:)=[trim,tReplay,S.S45.Tt,tReplay-S.S45.Tt, ...
            tNative,tBallin,tNative-tBallin,S.S45.Tt-tNative];
    end
end
fprintf('原文引气规律、阻尼及热力学关系复核（仅用于诊断）：\n');
showChineseTable(array2table(audit.Bleeds.Values),{'B1工况','NGc_pct','B1历史冻结值','B1实际Ng查表值','B1参考Ng查表值','第4级引气配置比例','第4级引气原文比例','第4级引气差值_lbm_s','冷却配置流量_lbm_s','冷却原文流量_lbm_s'});
showChineseTable(array2table(audit.Damping.Values),{'B1工况','当前Np_rpm','原文阻尼转矩_lbf_ft','当前阻尼功率_hp','固定气路估算Np_rpm','估算Np误差_pct','估算负载功率_hp','保存结果是否含阻尼'});
if audit.NativeMEXExecuted
    showChineseTable(array2table(audit.Thermal.Values),{'B1工况','T45复算_R','T45日志_R','复算减日志_R','原文焓降配原生热力T45_R','原文关系T45_R','热力混合影响_R','特性焓降影响_R'});
else
    fprintf('已跳过热力学复算：MATLAB 路径中未找到 T2HM_TMATS / H2TM_TMATS MEX。\n');
end
end

function result=checkSourceRelations(runs,functions)
% Reference-relationship audit only; does not alter any simulated result.
% Table A.1: H41=.301*T41-86.905; H45=.9623*H44; T45=3.519*H45+179.1.
result.Columns={'TrimID','GGT_dH_ErrorPercent','FPT_dH_ErrorPercent', ...
    'T45_SourceAtActualUpstream_R','T45_Model_R','ModelMinusSourceT45_R', ...
    'T45_SourceAtReference_R','T45_Table_R','SourceMinusTableT45_R', ...
    'Power_SourceAtReference_hp','Power_Table_hp','SourcePowerErrorPercent'};
result.Values=zeros(0,numel(result.Columns));
result.Interpretation='A9 figure ambient ratio; A10 Eq38; definition conflict remains unresolved';
result.IndependentExperimentalValidation=false;
keys=fieldnames(runs);
for k=1:numel(keys)
    r=runs.(keys{k});
    if ~startsWith(lower(r.Profile),'ballin_trim') || ~isfield(r,'ReferenceComparison'), continue; end
    S=r.Stations; D=r.Diagnostics; ref=r.ReferenceComparison.Reference(:);
    a7=S.S45.Pt/S.S41.Pt;
    a8=S.S49.Pt/S.S45.Pt;
    sourceGT=(.0018326*S.S41.Tt+.0856)*lookup(functions.A07,a7);
    sourcePT=(.0018326*S.S45.Tt+.0856)*lookup(functions.A08,a8);
    modelGT=D.GGT.Pwrout/1.414853/S.S41.W;
    modelPT=D.FPT.Pwrout/1.414853/S.S45.W;
    actualSourceT45=3.519*.9623*(.301*S.S41.Tt-86.905-sourceGT)+179.1;
    refGT=(.0018326*ref(6)+.0856)*lookup(functions.A07,ref(5)/ref(4));
    refSourceT45=3.519*.9623*(.301*ref(6)-86.905-refGT)+179.1;
    refTheta45=.0018326*ref(7)+.0856;
    refDh=refTheta45*lookup(functions.A08,r.Boundary.P49_psia/ref(5));
    refW=lookup(functions.A09,r.Boundary.P2_psia/ref(5))*ref(5)/sqrt(refTheta45);
    refPower=refW*refDh*1.414853;
    row=[r.ReferenceComparison.TrimID,100*(modelGT/sourceGT-1), ...
        100*(modelPT/sourcePT-1),actualSourceT45,S.S45.Tt,S.S45.Tt-actualSourceT45, ...
        refSourceT45,ref(7),refSourceT45-ref(7),refPower,ref(8),100*(refPower/ref(8)-1)];
    result.Values(end+1,:)=row;
end
end

function y=lookup(curve,x)
y=interp1(curve.X(:),curve.Y(:),x,'linear',NaN);
assert(isfinite(y),'参考关系对比超出原文曲线的数字化范围。');
end

function value=workspaceValue(name)
assert(evalin('base',sprintf('exist(''%s'',''var'')',name))==1, ...
    '缺少日志 %s，请先运行目标工况的 T700_SS 仿真。',name);
value=evalin('base',name);
end

function result=readScalars(raw,fields)
result=struct;
for k=1:numel(fields)
    value=lastValue(getValue(raw,fields{k}));
    assert(isscalar(value),'诊断量 %s 应为标量。',fields{k});
    result.(fields{k})=value;
end
end

function value=getValue(raw,name)
assert(isstruct(raw) && isfield(raw,name),'日志中缺少字段 %s。',name);
value=raw.(name);
end

function value=lastValue(raw)
if isa(raw,'timeseries')
    assert(~isempty(raw.Time),'日志时间序列为空。');
    value=getdatasamples(raw,numel(raw.Time));
elseif isnumeric(raw) || islogical(raw)
    if isvector(raw), value=raw; else, value=raw(end,:); end
else
    error('暂不支持此日志数据类型：%s。',class(raw));
end
value=double(value(:));
assert(~isempty(value) && all(isfinite(value)),'日志结果为空，或含 NaN/Inf。');
end

function text=passText(value)
if value, text='通过'; else, text='未通过'; end
end

function showChineseTable(value,labels)
% Translate a display copy; saved field names and status codes stay stable.
for k=1:width(value)
    if islogical(value{:,k})
        flags=value{:,k}; words=repmat({'否'},height(value),1);
        words(flags)={'是'}; value.(value.Properties.VariableNames{k})=words;
    end
end
value.Properties.VariableNames=labels;
disp(value);
end
