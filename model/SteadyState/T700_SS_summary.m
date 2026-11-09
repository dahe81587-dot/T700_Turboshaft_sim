function [summary,comparisonTable] = T700_SS_summary(source)
% Read-only B.1 summary. No initialization, model loading, simulation or saving.
% T700_SS_summary reads the existing project result MAT-file.
% T700_SS_summary(runs) summarizes an explicitly supplied run structure.
if nargin<1
    source=fullfile(fileparts(mfilename('fullpath')),'results','T700_SS_result_check.mat');
end
if isstruct(source)
    runs=source;
else
    source=char(string(source));
    assert(isfile(source),'暂无本轮稳态结果，请先手动运行 B.1 工况并执行 T700_SS_check_result。目标文件：%s',source);
    saved=load(source,'runs','report');
    if isfield(saved,'runs')
        runs=saved.runs;
    else
        assert(isfield(saved,'report') && isfield(saved.report,'Profile'), ...
            '结果文件缺少 runs 或有效 report。');
        runs=struct;
        runs.(matlab.lang.makeValidName(saved.report.Profile))=saved.report;
    end
end
assert(isstruct(runs) && isscalar(runs),'runs 应为标量结构体。');
TrimID=(1:3)'; HasResult=false(3,1); NumericalChecksPassed=false(3,1);
HasReferenceComparison=false(3,1); MaxAbsoluteErrorPercent=nan(3,1);
Status=repmat({'尚无保存结果'},3,1);
ExhaustMode=repmat({'未记录'},3,1); StateDependentExhaustPassed=false(3,1);
rows=cell(0,7);
for id=1:3
    key=sprintf('ballin_trim%d',id);
    if ~isfield(runs,key), continue; end
    r=runs.(key); HasResult(id)=true;
    ExhaustMode{id}='旧版固定 P49 或未记录';
    if isfield(r,'Exhaust') && isfield(r.Exhaust,'Mode') && ...
            strcmp(r.Exhaust.Mode,'state_dependent_A10_Eq38')
        ExhaustMode{id}='实际 NGc 驱动 A10';
        StateDependentExhaustPassed(id)=isfield(r.Exhaust,'AllChecksPassed') && ...
            isequal(r.Exhaust.AllChecksPassed,true) && ...
            isfield(r,'AllChecksPassed') && isequal(r.AllChecksPassed,true);
    end
    if isfield(r,'AllChecksPassed')
        NumericalChecksPassed(id)=isequal(r.AllChecksPassed,true);
    end
    Status{id}='缺少 B.1 参考对比';
    if ~isfield(r,'ReferenceComparison'), continue; end
    c=r.ReferenceComparison;
    assert(c.TrimID==id,'保存结果 %s 的参考工况编号不符。',key);
    values=c.Simulation(:); refs=c.Reference(:);
    assert(numel(values)==8 && numel(refs)==8 && ...
        all(isfinite(values)) && all(isfinite(refs)) && all(refs>0), ...
        '工况 %d 的 B.1 对比数组不完整或无效。',id);
    assert(numel(c.Quantities)==8 && numel(c.Units)==8);
    errors=100*(values-refs)./refs;
    HasReferenceComparison(id)=true;
    MaxAbsoluteErrorPercent(id)=max(abs(errors));
    if NumericalChecksPassed(id)
        Status{id}='数值通过；参考误差待评价';
    else
        Status{id}='数值检查未通过';
    end
    if strcmp(ExhaustMode{id},'旧版固定 P49 或未记录')
        Status{id}='旧排气边界结果，需重跑';
    elseif ~StateDependentExhaustPassed(id)
        Status{id}='状态相关排气或其他数值检查未通过';
    end
    for j=1:8
        rows(end+1,:)={id,c.Quantities{j},c.Units{j},refs(j),values(j),errors(j),abs(errors(j))}; %#ok<AGROW>
    end
end
summary=table(TrimID,HasResult,NumericalChecksPassed,HasReferenceComparison, ...
    MaxAbsoluteErrorPercent,ExhaustMode,StateDependentExhaustPassed,Status);
comparisonTable=cell2table(rows,'VariableNames', ...
    {'TrimID','Quantity','Unit','Reference','Simulation','ErrorPercent','AbsoluteErrorPercent'});
fprintf('B.1 三工况汇总：已有 %d/3 组结果，数值检查通过 %d/3 组。\n', ...
    sum(HasResult),sum(NumericalChecksPassed));
fprintf('状态相关排气模式下，总数值检查通过 %d/3 组；旧版结果不计入此进度。\n', ...
    sum(StateDependentExhaustPassed));
showTable(summary,{'B1工况','是否有结果','原记录数值检查是否通过','是否有参考对比', ...
    '最大绝对相对误差_pct','排气模式','新模式总数值检查是否通过','状态'});
if ~isempty(rows)
    fprintf('B.1 逐项参考误差（同源模型对比）：\n');
    showTable(comparisonTable,{'B1工况','物理量','单位','参考值','仿真值','相对误差_pct','绝对相对误差_pct'});
end
fprintf('本汇总只读取已保存记录，不证明这些记录对应当前尚未保存的模型。\n');
fprintf('尚未设定 B.1 参考误差限；Figures 6-8 与动态配平未由此汇总验收。\n');
end

function showTable(value,labels)
for k=1:width(value)
    if islogical(value{:,k})
        flags=value{:,k}; words=repmat({'否'},height(value),1);
        words(flags)={'是'}; value.(value.Properties.VariableNames{k})=words;
    end
end
value.Properties.VariableNames=labels;
disp(value);
end
