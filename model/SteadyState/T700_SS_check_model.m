function report = T700_SS_check_model(mdl,MWS)
% Read-only binding and selected bleed-topology audit of an open model.
% Does not load/update/save/simulate a model or initialize workspace parameters.
if nargin<1, mdl='T700_SS'; end
if nargin<2
    assert(evalin('base','exist(''MWS'',''var'')')==1,'请先运行 T700_initialize。');
    MWS=evalin('base','MWS');
end
mdl=char(string(mdl));
assert(strcmp(mdl,'T700_SS'),'此脚本仅检查 T700_SS；动态及线性化检查将单独建立。');
assert(bdIsLoaded(mdl),'检查前，请手动打开目标模型。');
assert(isfield(MWS,'Compressor') && isfield(MWS,'GGT'),'检查 T700 模型前，请先运行 T700_initialize。');
B={
    'Compressor','Y_C_Map_NcVec_M','MWS.Compressor.NcVec'
    'Compressor','X_C_RlineVec_M','MWS.Compressor.RlineVec'
    'Compressor','T_C_Map_WcArray_M','MWS.Compressor.WcArray'
    'Compressor','T_C_Map_PRArray_M','MWS.Compressor.PRArray'
    'Compressor','T_C_Map_EffArray_M','MWS.Compressor.EffArray'
    'Compressor','s_C_Nc_M','MWS.Compressor.s_Nc'
    'Compressor','s_C_Wc_M','MWS.Compressor.s_Wc'
    'Compressor','s_C_PR_M','MWS.Compressor.s_PR'
    'Compressor','s_C_Eff_M','MWS.Compressor.s_eff'
    'Compressor','X_C_Map_WcSurgeVec_M','MWS.Compressor.WcMapSurge'
    'Compressor','T_C_Map_PRSurgeVec_M','MWS.Compressor.PRMapSurge'
    'Compressor','FBLDEN_M','on'
    'Compressor','C_FBD_M','MWS.Compressor.BleedFractions'
    'Compressor','C_BFht_M','MWS.Compressor.BleedEnthalpyFractions'
    'Compressor','C_BFPt_M','MWS.Compressor.BleedPressureFractions'
    'GGT','Y_T_Map_NcVec_M','MWS.GGT.NcVec'
    'GGT','X_T_Map_PRVec_M','MWS.GGT.PRVec'
    'GGT','T_T_Map_WcArray_M','MWS.GGT.WcArray'
    'GGT','T_T_Map_EffArray_M','MWS.GGT.EffArray'
    'GGT','s_T_Nc_M','MWS.GGT.s_Nc'
    'GGT','s_T_Wc_M','MWS.GGT.s_Wc'
    'GGT','s_T_PR_M','MWS.GGT.s_PR'
    'GGT','s_T_Eff_M','MWS.GGT.s_eff'
    'GGT','CFlwEn_M','on'
    'GGT','T_CoolFlwPos_M','1'
    'FPT','Y_T_Map_NcVec_M','MWS.FPT.NcVec'
    'FPT','X_T_Map_PRVec_M','MWS.FPT.PRVec'
    'FPT','T_T_Map_WcArray_M','MWS.FPT.WcArray'
    'FPT','T_T_Map_EffArray_M','MWS.FPT.EffArray'
    'FPT','s_T_Nc_M','MWS.FPT.s_Nc'
    'FPT','s_T_Wc_M','MWS.FPT.s_Wc'
    'FPT','s_T_PR_M','MWS.FPT.s_PR'
    'FPT','s_T_Eff_M','MWS.FPT.s_eff'
    'Burner','Eff_M','MWS.Burner.Eff'
    'Burner','LHV_M','MWS.Burner.LHV'
    'Burner','dPnormBurner_M','MWS.Burner.dP'
    'Shaft','Shaft_Inertia_M','MWS.Shaft.J'
    'Shaft1','Shaft_Inertia_M','MWS.Shaft1.J'
    'BC_T2','Value','MWS.Boundary.T2_R'
    'BC_P2','Value','MWS.Boundary.P2_psia'
    'BC_Wf','Value','MWS.Boundary.Wf'
    'BC_Qload','Value','MWS.Boundary.Qload'
    'BC_P1','Value','MWS.Boundary.P2_psia'
    'BC_NGc_Select','InputPortWidth','2'
    'BC_NGc_Select','Indices','1'
    'BC_A10','NumberOfTableDimensions','1'
    'BC_A10','BreakpointsForDimension1','MWS.T700.Exhaust.NGcPercent'
    'BC_A10','Table','MWS.T700.Exhaust.Factor'
    'BC_A10','InterpMethod','Linear point-slope'
    'BC_A10','ExtrapMethod','Clip'
    'BC_P49_Target','Inputs','**'
    'BC_P49_Select','OutputSignals','Pt'
    'BC_P49_Error','Expr','(u(1)-u(2))/u(2)'
    'Log_P49_Target','VariableName','P49_target'
    'Log_P49_Target','SaveFormat','Timeseries'
    'SS NR Solver w JacobianCalc','SJac_Per_M','MWS.Solve.J_Calc_Per'
    'SS NR Solver w JacobianCalc','SNR_IC_M','MWS.Solve.NR_IC'
    'SS NR Solver w JacobianCalc','SNR_DX_M','MWS.Solve.NR_dx'
    'SS NR Solver w JacobianCalc','SNR_Mx_M','MWS.Solve.Upper'
    'SS NR Solver w JacobianCalc','SNR_Mn_M','MWS.Solve.Lower'
    'SS NR Solver w JacobianCalc','SJacobianAttempts_M','MWS.Solve.NR_Jac_Re'
    'SS NR Solver w JacobianCalc','Cond_Limits_M','MWS.Solve.C_Lim'};
actual=cell(size(B,1),1); matches=false(size(B,1),1);
paths=cell(size(B,1),1);
for k=1:size(B,1)
    try
        component=B{k,1}; paths{k}=[mdl '/' component];
        if ismember(component,{'Compressor','GGT','FPT','Burner','Shaft','Shaft1'})
            % An edited Compressor is a local masked subsystem, not necessarily
            % an active library reference. Only select the top-level component.
            candidates=find_system(mdl,'SearchDepth',1,'FollowLinks','off', ...
                'LookUnderMasks','none','Name',component);
            assert(isscalar(candidates),'顶层应只有一个对应的气路部件。');
            paths{k}=candidates{1};
        end
        actual{k}=get_param(paths{k},B{k,2});
        matches(k)=strcmp(strtrim(actual{k}),B{k,3});
    catch err
        actual{k}=['无法读取：' err.message];
    end
end
report.Model=mdl;
report.File=get_param(mdl,'FileName');
report.Profile=MWS.Boundary.Profile;
report.Bindings=cell2table([B,paths,actual,num2cell(matches)], ...
    'VariableNames',{'Block','Parameter','Expected','Path','Actual','Matches'});
report.ListedBindingsMatch=all(matches);
report.BleedAuditRequired=strcmp(mdl,'T700_SS');
report.BleedAudit=struct('Checked',false,'Passed',false);
if report.BleedAuditRequired
    report.BleedAudit=checkBleedTopology(mdl);
end
report.DampingAuditRequired=strcmp(mdl,'T700_SS');
report.DampingAudit=struct('Checked',false,'Passed',false);
if report.DampingAuditRequired
    report.DampingAudit=checkDampingTopology(mdl);
end
report.ExhaustAudit=checkExhaustTopology(mdl);
report.AllListedChecksPassed=report.ListedBindingsMatch && report.ExhaustAudit.Passed && ...
    (~report.BleedAuditRequired || report.BleedAudit.Passed) && ...
    (~report.DampingAuditRequired || report.DampingAudit.Passed);
report.PreLoadFcn=get_param(mdl,'PreLoadFcn');
report.InitFcn=get_param(mdl,'InitFcn');
report.ReadOnly=true;
report.CompilationChecked=false;
report.FullTopologyChecked=false;
report.ConvergenceChecked=false;
showChineseTable(report.Bindings,{'模块','参数','预期值','模块路径','实际值','是否匹配'});
fprintf('参数绑定检查结果：%d（1=通过，0=未通过）。本次未修改、编译或仿真模型。\n',all(matches));
if report.BleedAuditRequired, showChineseTable(report.BleedAudit.Checks,{'引气检查项','是否通过','详情'}); end
if report.DampingAuditRequired, showChineseTable(report.DampingAudit.Checks,{'阻尼检查项','是否通过','详情'}); end
showChineseTable(report.ExhaustAudit.Checks,{'排气检查项','是否通过','详情'});
fprintf('模型参数与接口总检查：%d（AllListedChecksPassed，1=通过，0=未通过）。\n',report.AllListedChecksPassed);
end

function audit=checkBleedTopology(mdl)
% Check named interfaces and the current schedule implementation only.
% This is deliberately not a complete topology or runtime validation.
root=[mdl '/BleedSchedule'];
comp=[mdl '/Compressor'];
fun=[root '/MATLAB Function'];
names={}; passed=false(0,1); details={};
check('Compressor 具有 4 个输入端口',@() portCount(comp,'Inport',4));
check('引气规律模块具有 4 个输入、3 个输出', ...
    @() portCount(root,'Inport',4) && portCount(root,'Outport',3));
for k=1:4
    label={'W2','T2','P2','Ng'};
    check(['引气规律输入 ' label{k}], ...
        @() strcmp(get_param([root '/' label{k}],'Port'),num2str(k)) && ...
        connected([root '/' label{k}],1,fun,k));
end
fields={'B1_NGcPercent','B1_Fraction','B2_Wc','B2_Fraction', ...
    'B3_Wc','B3_Fraction','ReferenceCoordinates','Kbl','Kb3'};
for k=1:numel(fields)
    check(['引气规律参数 ' fields{k}], ...
        @() parameterSource(fun,k+4,['MWS.Compressor.BleedSchedule.' fields{k}]));
end
signals={'W','Tt','Pt'};
for k=1:3
    check(['入口信号 ' signals{k}],@() inletSource(mdl,root,k,signals{k}));
end
check('Ng 与 Compressor 使用同一机械转速信号', ...
    @() inputSource(root,4)==inputSource(comp,3));
check('引气比例输出接入 Compressor 输入 4',@() connected(root,1,comp,4));
check('外部引气比例接入 S-Function 输入 3', ...
    @() strcmp(get_param([comp '/BleedFractionsIn'],'Port'),'4') && ...
    strcmp(get_param([comp '/BleedFractionsIn'],'PortDimensions'),'3') && ...
    strcmp(get_param([comp '/Compressor'],'FunctionName'),'Compressor_TMATS') && ...
    connected([comp '/BleedFractionsIn'],1,[comp '/Compressor'],3));
check('引气比例 beta 经 Reshape 接入输出 1', ...
    @() connected(fun,1,[root '/Reshape'],1) && ...
    connected([root '/Reshape'],1,[root '/BleedFractions'],1) && ...
    strcmp(get_param([root '/BleedFractions'],'Port'),'1') && ...
    strcmp(get_param([root '/Reshape'],'OutputDimensionality'),'1-D array'));
check('查表坐标与范围标志接入输出 2、3', ...
    @() connected(fun,2,[root '/Coordinates'],1) && ...
    connected(fun,3,[root '/InRange'],1) && ...
    strcmp(get_param([root '/Coordinates'],'Port'),'2') && ...
    strcmp(get_param([root '/InRange'],'Port'),'3'));
check('第 3 股引气接入 GGT 冷却入口', ...
    @() connected(comp,2,[mdl '/Selector'],1) && ...
    strcmp(get_param([mdl '/Selector'],'Indices'),'11:15') && ...
    connected([mdl '/Selector'],1,[mdl '/GGT'],1));
check('引气规律方程与已核对实现一致',@() scheduleCode(fun));
audit.Checked=true;
audit.Passed=all(passed);
audit.Checks=table(names(:),passed,details(:), ...
    'VariableNames',{'Check','Passed','Detail'});

    function check(name,test)
        names{end+1,1}=name;
        try
            ok=logical(test());
            assert(isscalar(ok),'检查函数必须返回一个逻辑标量。');
            passed(end+1,1)=ok;
            if ok, details{end+1,1}='符合';
            else, details{end+1,1}='参数绑定、连线或方程与预期不符'; end
        catch err
            passed(end+1,1)=false;
            details{end+1,1}=err.message;
        end
    end
end

function audit=checkDampingTopology(mdl)
% Ballin Eq41: add -Kd*(2*pi/60)*(Np-20900) to the shaft torque vector.
design=[mdl '/PT_NpDesign']; err=[mdl '/PT_SpeedError'];
gain=[mdl '/PT_DampingGain']; signBlock=[mdl '/PT_DampingSign'];
mux=[mdl '/Mux3']; shaft=[mdl '/Shaft1'];
checks={
    '设计转速 Np_design=20900 rpm',@() strcmp(get_param(design,'BlockType'),'Constant') && parameterMatches(design,'Value','20900')
    '转速偏差为 Np-Np_design',@() strcmp(get_param(err,'BlockType'),'Sum') && parameterMatches(err,'Inputs','+-')
    '阻尼增益包含 rpm 到 rad/s 的换算',@() strcmp(get_param(gain,'BlockType'),'Gain') && parameterMatches(gain,'Gain','0.06854*2*pi/60')
    '轴转矩中减去阻尼转矩 Qd',@() strcmp(get_param(signBlock,'BlockType'),'Gain') && parameterMatches(signBlock,'Gain','-1')
    '阻尼计算采用动力轴机械转速',@() sameSignalSource(err,1,shaft,3)
    '设计转速接入减法端口',@() connected(design,1,err,2)
    '转速偏差接入阻尼增益',@() connected(err,1,gain,1)
    'Qd 接入负号模块',@() connected(gain,1,signBlock,1)
    '轴转矩向量具有 3 个输入',@() portCount(mux,'Inport',3)
    '负载负转矩保持接入输入 1',@() parameterMatches([mdl '/BC_LoadSign'],'Gain','-1') && connected([mdl '/BC_LoadSign'],1,mux,1)
    'FPT 燃气转矩保持接入输入 2',@() connected([mdl '/From13'],1,mux,2) && parameterMatches([mdl '/From13'],'GotoTag','FPT_Torque')
    '负阻尼转矩接入输入 3',@() connected(signBlock,1,mux,3)
    '转矩向量接入轴转矩输入',@() connected(mux,1,shaft,1)};
passed=false(size(checks,1),1); details=cell(size(passed));
for k=1:size(checks,1)
    try
        passed(k)=logical(checks{k,2}());
        if passed(k), details{k}='符合';
        else, details{k}='参数或连线与预期不符'; end
    catch problem
        details{k}=problem.message;
    end
end
audit.Checked=true; audit.Passed=all(passed);
audit.Checks=table(checks(:,1),passed,details, ...
    'VariableNames',{'Check','Passed','Detail'});
end

function audit=checkExhaustTopology(mdl)
% State-dependent Eq38 closure; Goto/From is accepted within this top level.
select=[mdl '/BC_NGc_Select']; lookup=[mdl '/BC_A10'];
product=[mdl '/BC_P49_Target']; mux=[mdl '/BC_P49_Mux'];
checks={
    'NGc 使用 Selector，索引从 1 开始',@() strcmp(get_param(select,'BlockType'),'Selector') && parameterMatches(select,'IndexMode','One-based') && parameterMatches(select,'NumberOfDimensions','1')
    'Selector 采用对话框索引向量',@() isequal(get_param(select,'IndexOptionArray'),{'Index vector (dialog)'})
    'A10 使用一维 Lookup Table',@() strcmp(get_param(lookup,'BlockType'),'Lookup_n-D') && parameterMatches(lookup,'BreakpointsSpecification','Explicit values')
    'P49 目标使用 Product',@() strcmp(get_param(product,'BlockType'),'Product')
    '环境压力 BC_P1 为 Constant',@() strcmp(get_param([mdl '/BC_P1'],'BlockType'),'Constant')
    '坐标取自 BleedSchedule 输出 2',@() connectedViaTag([mdl '/BleedSchedule'],2,select,1)
    'NGc 接入 A10 输入',@() connected(select,1,lookup,1)
    'A10 系数接入压力乘积输入 1',@() connected(lookup,1,product,1)
    '环境静压接入压力乘积输入 2',@() connected([mdl '/BC_P1'],1,product,2)
    'FPT 出口接入总压选择器',@() connected([mdl '/FPT'],1,[mdl '/BC_P49_Select'],1)
    '计算 P49 接入残差 Mux 输入 1',@() connected([mdl '/BC_P49_Select'],1,mux,1)
    '状态相关目标接入残差 Mux 输入 2',@() connected(product,1,mux,2)
    '压力 Mux 保留两个输入',@() portCount(mux,'Inport',2)
    '压力向量接入归一化残差',@() connected(mux,1,[mdl '/BC_P49_Error'],1)
    'P49_target 日志为 To Workspace',@() strcmp(get_param([mdl '/Log_P49_Target'],'BlockType'),'ToWorkspace')
    '状态相关目标接入 P49_target 日志',@() connected(product,1,[mdl '/Log_P49_Target'],1)
    '通用 Nozzle 保持关闭',@() parameterMatches([mdl '/Nozzle'],'Commented','on')};
passed=false(size(checks,1),1); details=cell(size(passed));
for k=1:size(checks,1)
    try
        passed(k)=logical(checks{k,2}());
        if passed(k), details{k}='符合';
        else, details{k}='参数、信号来源或连线与状态相关排气方案不符'; end
    catch problem
        details{k}=problem.message;
    end
end
audit.Checked=true; audit.Passed=all(passed);
audit.Mode='state_dependent_A10_Eq38';
audit.Checks=table(checks(:,1),passed,details,'VariableNames',{'Check','Passed','Detail'});
end

function ok=connectedViaTag(source,outIndex,destination,inIndex)
ports=get_param(source,'PortHandles'); actual=inputSource(destination,inIndex);
ok=actual==ports.Outport(outIndex);
if ok, return; end
from=get_param(actual,'Parent');
if ~strcmp(get_param(from,'BlockType'),'From'), return; end
parent=get_param(from,'Parent'); tag=get_param(from,'GotoTag');
goto=find_system(parent,'SearchDepth',1,'FollowLinks','off','LookUnderMasks','none', ...
    'BlockType','Goto','GotoTag',tag);
assert(isscalar(goto),'当前顶层的 Goto 标签 %s 必须唯一。',tag);
ok=inputSource(goto{1},1)==ports.Outport(outIndex);
end

function ok=parameterMatches(block,parameter,expected)
ok=strcmp(regexprep(get_param(block,parameter),'\s+',''), ...
    regexprep(expected,'\s+',''));
end

function ok=sameSignalSource(a,ai,b,bi)
pa=inputSource(a,ai); pb=inputSource(b,bi);
ok=pa==pb;
if ok, return; end
% Separate From blocks with the same tag in the same parent carry one signal.
sa=get_param(pa,'Parent'); sb=get_param(pb,'Parent');
ok=strcmp(get_param(sa,'BlockType'),'From') && ...
    strcmp(get_param(sb,'BlockType'),'From') && ...
    strcmp(get_param(sa,'Parent'),get_param(sb,'Parent')) && ...
    strcmp(get_param(sa,'GotoTag'),get_param(sb,'GotoTag'));
end

function ok=portCount(block,kind,count)
p=get_param(block,'PortHandles');
ok=numel(p.(kind))==count;
end

function source=inputSource(block,index)
p=get_param(block,'PortHandles');
line=get_param(p.Inport(index),'Line');
assert(line~=-1,'输入端口 %d 未连接，模块：%s。',index,block);
source=get_param(line,'SrcPortHandle');
assert(isscalar(source) && source~=-1,'无法确定输入信号来源。');
end

function ok=connected(source,outIndex,destination,inIndex)
p=get_param(source,'PortHandles');
ok=inputSource(destination,inIndex)==p.Outport(outIndex);
end

function ok=parameterSource(fun,index,expected)
p=inputSource(fun,index);
block=get_param(p,'Parent');
ok=strcmp(get_param(block,'BlockType'),'Constant') && ...
    strcmp(strtrim(get_param(block,'Value')),expected);
end

function ok=inletSource(mdl,root,index,signal)
p=inputSource(root,index);
selector=get_param(p,'Parent');
assert(strcmp(get_param(selector,'BlockType'),'BusSelector'),'此处应为 Bus Selector 模块。');
signals=strtrim(strsplit(get_param(selector,'OutputSignals'),','));
ports=get_param(selector,'PortHandles');
selected=find(ports.Outport==p);
ok=isscalar(selected) && strcmp(signals{selected},signal) && ...
    connected([mdl '/BC_Inlet'],1,selector,1);
end

function ok=scheduleCode(fun)
r=sfroot;
chart=r.find('-isa','Stateflow.EMChart','Path',fun);
assert(isscalar(chart),'此处应只有一个 MATLAB Function 图表。');
actual=normalizeCode(chart.Script);
expected=normalizeCode(sprintf([ ...
    'function [beta,coord,inRange] = bleed_schedule( ...\n' ...
    'W2,T2,P2,Ng,x1,y1,x2,y2,x3,y3,ref,Kbl,Kb3)\n' ...
    'theta=T2/ref(1); delta=P2/ref(2);\n' ...
    'Wc=W2*sqrt(theta)/delta;\n' ...
    'NGcPercent=100*Ng/(ref(3)*sqrt(theta));\n' ...
    'coord=[NGcPercent;Wc];\n' ...
    'inRange=NGcPercent>=x1(1)&&NGcPercent<=x1(end)&& ...\n' ...
    'Wc>=x2(1)&&Wc<=x2(end)&&Wc>=x3(1)&&Wc<=x3(end);\n' ...
    'q1=min(max(NGcPercent,x1(1)),x1(end));\n' ...
    'q2=min(max(Wc,x2(1)),x2(end));\n' ...
    'q3=min(max(Wc,x3(1)),x3(end));\n' ...
    'B1=interp1(x1,y1,q1,''linear'');\n' ...
    'B2=interp1(x2,y2,q2,''linear'');\n' ...
    'B3=interp1(x3,y3,q3,''linear'');\n' ...
    'beta=[B1+B2;B3*(1-Kbl)+Kb3;B3*Kbl]; end\n']));
ok=strcmp(actual,expected);
end

function code=normalizeCode(code)
% Strip comments/continuations/whitespace; a different implementation is
% reported for review even if it might be mathematically equivalent.
code=regexprep(code,'%[^\r\n]*','');
code=strrep(code,'...','');
code=regexprep(code,'\s+','');
end

function showChineseTable(value,labels)
% Localize console headings without changing returned report field names.
for k=1:width(value)
    if islogical(value{:,k})
        flags=value{:,k}; words=repmat({'否'},height(value),1);
        words(flags)={'是'}; value.(value.Properties.VariableNames{k})=words;
    end
end
value.Properties.VariableNames=labels;
disp(value);
end
