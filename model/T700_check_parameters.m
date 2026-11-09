function report = T700_check_parameters(MWS)
% Data/package checks only. Does not open a model or assert convergence.
if nargin<1
    assert(evalin('base','exist(''MWS'',''var'')')==1,'请先运行 T700_initialize。');
    MWS=evalin('base','MWS');
end
groups = {'Compressor','GGT','FPT'};
for k=1:numel(groups)
    name=groups{k}; C=MWS.(name);
    if k==1, x=C.RlineVec; else, x=C.PRVec; end
    assert(isvector(x) && all(diff(x)>0));
    assert(isvector(C.NcVec) && all(diff(C.NcVec)>0));
    expected=[numel(C.NcVec),numel(x)];
    assert(isequal(size(C.WcArray),expected) && isequal(size(C.EffArray),expected));
    assert(all(isfinite(C.WcArray),'all') && all(C.WcArray>0,'all'));
    assert(all(isfinite(C.EffArray),'all') && all(C.EffArray>0 & C.EffArray<=1,'all'));
    assert(all([C.s_Nc,C.s_Wc,C.s_PR,C.s_eff]>0));
end
assert(isequal(size(MWS.Compressor.PRArray),size(MWS.Compressor.WcArray)));
assert(all(MWS.Compressor.PRArray>1,'all') && all(diff(MWS.Compressor.PRArray,1,2)<0,'all'));
assert(all(diff(MWS.Compressor.WcArray,1,2)>=-1e-12,'all'));
validateattributes(MWS.Compressor.BleedFractions,{'numeric'},{'column','numel',3,'nonnegative','finite'});
assert(sum(MWS.Compressor.BleedFractions)<1);
B=MWS.Compressor.BleedSchedule;
axes={B.B1_NGcPercent,B.B2_Wc,B.B3_Wc};
values={B.B1_Fraction,B.B2_Fraction,B.B3_Fraction};
for k=1:3
    validateattributes(axes{k},{'numeric'},{'column','finite','increasing'});
    validateattributes(values{k},{'numeric'},{'column','finite','nonnegative'});
    assert(numel(axes{k})==numel(values{k}) && numel(axes{k})>=2);
end
validateattributes(B.ReferenceCoordinates,{'numeric'},{'column','numel',3,'positive','finite'});
assert(B.Kbl>=0 && B.Kbl<=1 && B.Kb3>=0);
assert(max(B.B1_Fraction)+max(B.B2_Fraction)+max(B.B3_Fraction)+B.Kb3<1);
assert(all(MWS.Compressor.BleedEnthalpyFractions>=0 & MWS.Compressor.BleedEnthalpyFractions<=1));
assert(all(MWS.Compressor.BleedPressureFractions>=0 & MWS.Compressor.BleedPressureFractions<=1));
assert(MWS.Burner.Eff>0 && MWS.Burner.Eff<=1 && MWS.Burner.dP>=0 && MWS.Burner.dP<1);
assert(MWS.Shaft.J>0 && MWS.Shaft1.J>0);
assert(all(MWS.Solve.NR_IC>=MWS.Solve.Lower & MWS.Solve.NR_IC<=MWS.Solve.Upper));
assert(isequal(size(MWS.Solve.C_Lim),[6,1]));
for k=1:height(MWS.Project.SetupFiles)
    assert(strcmpi(which(MWS.Project.SetupFiles.Function{k}),MWS.Project.SetupFiles.File{k}));
end
report=struct('ParameterChecksPassed',true,'MATLABCheckExecuted',true, ...
    'SimulinkRun',false,'Converged',false,'DynamicTrimReady',false, ...
    'Profile',MWS.Boundary.Profile,'SetupRoot',MWS.Project.SetupRoot, ...
    'CompressorSize',size(MWS.Compressor.WcArray),'GGTSize',size(MWS.GGT.WcArray), ...
    'FPTSize',size(MWS.FPT.WcArray));
fprintf('T700 参数检查通过（ParameterChecksPassed=true）\n');
end
