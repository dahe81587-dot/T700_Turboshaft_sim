function MWS = T700_Dyn_initialize(varargin)
% Initialize the dynamic model from a checked, matching steady-state run.
% Loading a trim supplies initial conditions; it does not validate dynamics.
MWS=T700_initialize(varargin{:});
resultFile=fullfile(MWS.Project.SteadyResultRoot,'T700_SS_result_check.mat');
assert(isfile(resultFile),'T700:Dyn:MissingTrim', ...
    '缺少稳态结果文件，请先运行并检查对应工况的 T700_SS。');
saved=load(resultFile,'report','runs');
profile=MWS.Boundary.Profile;
if isfield(saved,'runs') && isfield(saved.runs,profile)
    trim=saved.runs.(profile);
elseif isfield(saved,'report') && strcmpi(saved.report.Profile,profile)
    trim=saved.report;
else
    error('T700:Dyn:MissingProfile','没有工况 %s 的稳态结果，请先运行并检查该工况。',profile);
end
assert(trim.AllChecksPassed && trim.SolverConverged && ~trim.JacFailed, ...
    'T700:Dyn:UncheckedTrim','所选稳态结果未通过数值与物理一致性检查。');
expected={'W_in','Rline','PR_GGT','PR_FPT','Ng','Np'};
assert(isequal(trim.UnknownOrder(:),expected(:)), ...
    'T700:Dyn:TrimOrder','稳态结果未知量顺序与动态模型不匹配。');
fields={'P2_psia','T2_R','Wf','Qload','FAR2','Pacc_g','Pacc_p'};
for k=1:numel(fields)
    name=fields{k};
    actual=MWS.Boundary.(name);
    assert(abs(trim.Boundary.(name)-actual)<=1e-9*max(1,abs(actual)), ...
        'T700:Dyn:BoundaryMismatch','稳态结果的 %s 与当前工况不匹配。',name);
end
x=trim.X(:);
validateattributes(x,{'double'},{'size',[6 1],'finite','positive'});
MWS.Input.NRICDyn=x(1:4);
MWS.Input.Ng0=x(5);
MWS.Input.Np0=x(6);
MWS.Input.LP_Shaft=x(6); % The existing Nf demand is power-turbine speed.
MWS.Input.FARin=MWS.Boundary.Wf/trim.Stations.S3.W;
validateattributes(MWS.Input.FARin,{'double'},{'scalar','finite','positive'});
MWS.Dynamic.C_Lim=MWS.Solve.C_Lim(1:4);
MWS.Dynamic.J_Calc_Per=MWS.Solve.J_Calc_Per(:,1:4);
MWS.Dynamic.Lower=MWS.Solve.Lower(1:4);
MWS.Dynamic.Upper=MWS.Solve.Upper(1:4);
assert(all(x(1:4)>=MWS.Dynamic.Lower & x(1:4)<=MWS.Dynamic.Upper), ...
    'T700:Dyn:TrimBounds','稳态初值超出当前特性图边界。');
MWS.Dynamic.UnknownOrder=expected(1:4);
MWS.Dynamic.TrimFile=resultFile;
MWS.Dynamic.TrimCheckedAt=trim.CheckedAt;
MWS.Dynamic.InitialConditionsLoaded=true;
MWS.Project.DynamicTrimReady=false; % Requires a separate no-disturbance run.
assignin('base','MWS',MWS);
fprintf('T700 动态初值已加载：Ng0=%.6f rpm，Np0=%.6f rpm；尚未完成动态验证。\n',x(5),x(6));
end
