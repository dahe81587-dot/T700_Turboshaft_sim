function bundle = T700_MapHistory(action,source,label)
% Compact component-map trajectories. Reading logs never runs a simulation.
% refresh: merge available T700_Dyn logs into a persistent compact MAT archive.
% read: read only the archive. add: archive an explicit SimulationOutput/struct.
if nargin<1, action='refresh'; end
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'results','component_maps');
file=fullfile(folder,'T700_map_history.mat');
bundle=struct('Version',1,'Maps',struct,'MapSignature','', ...
    'Runs',struct('Name',{},'Source',{},'Signature',{},'Components',{}));
if isfile(file)
    saved=load(file,'bundle'); bundle=saved.bundle;
end
if strcmpi(action,'read'), return; end
assert(ismember(lower(action),{'refresh','add'}),'T700:Maps:Action','Unknown history action.');
maps=currentMaps(root,bundle.Maps);
mapSignature=mapDigest(maps);
assert(isempty(bundle.MapSignature) || strcmp(mapSignature,bundle.MapSignature), ...
    'T700:Maps:ChangedMaps', ...
    'Component maps changed since these runs were archived. Use matching map parameters before overlaying runs.');
bundle.Maps=maps; bundle.MapSignature=mapSignature;
before=numel(bundle.Runs);
if strcmpi(action,'add')
    if nargin<3, label='Workspace result'; end
    components=fromOutput(source);
    bundle=mergeRun(bundle,char(label),'SimulationOutput',components);
else
    % The public run API reads existing logs without opening the Inspector UI.
    try
        ids=Simulink.sdi.getAllRunIDs;
    catch
        ids=[]; % Workspace logs and the compact archive do not require SDI.
    end
    for k=1:numel(ids)
        r=Simulink.sdi.getRun(ids(k));
        try
            components=fromRun(r);
            if ~isempty(fieldnames(components))
                bundle=mergeRun(bundle,r.Name,'Logged T700_Dyn run',components);
            end
        catch problem
            warning('T700:Maps:SkippedRun','Skipped run "%s": %s',r.Name,problem.message);
        end
    end
    % Also support normal workspace outputs when no matching run is retained.
    if evalin('base','exist(''out'',''var'')')==1
        try
            candidate=fromOutput(evalin('base','out'));
            signature=componentDigest(candidate);
            if ~any(strcmp({bundle.Runs.Signature},signature))
                label=sprintf('Workspace output %d',numel(bundle.Runs)+1);
                bundle=mergeRun(bundle,label,'Workspace out',candidate);
            end
        catch
            % An unrelated workspace variable named out is not a T700 result.
        end
    end
    % Standard To Workspace logging is sufficient; SDI is not required.
    keys={'CompData','GGTData','FPTData'};
    workspaceSource=struct;
    for k=1:numel(keys)
        if evalin('base',sprintf('exist(''%s'',''var'')',keys{k}))==1
            workspaceSource.(keys{k})=evalin('base',keys{k});
        end
    end
    if all(isfield(workspaceSource,keys))
        try
            candidate=fromOutput(workspaceSource);
            signature=componentDigest(candidate);
            if ~any(strcmp({bundle.Runs.Signature},signature))
                label=sprintf('Workspace component run %d',numel(bundle.Runs)+1);
                bundle=mergeRun(bundle,label,'To Workspace logs',candidate);
            end
        catch problem
            warning('T700:Maps:WorkspaceLogs','Workspace map logs were not archived: %s',problem.message);
        end
    end
end
if numel(bundle.Runs)~=before || ~isfile(file)
    if ~isfolder(folder), mkdir(folder); end
    temporary=[tempname(folder) '.mat'];
    save(temporary,'bundle','-v7');
    movefile(temporary,file,'f');
end
fprintf('T700 component maps: %d archived runs, %d newly added.\n',numel(bundle.Runs),numel(bundle.Runs)-before);
end

function maps=currentMaps(root,fallback)
maps=fallback;
if evalin('base','exist(''MWS'',''var'')')==1
    candidate=evalin('base','MWS');
    if isstruct(candidate) && isfield(candidate,'Project') && ...
            isfield(candidate.Project,'Root') && strcmpi(candidate.Project.Root,root) && ...
            all(isfield(candidate,{'Compressor','GGT','FPT'}))
        for name={'Compressor','GGT','FPT'}, maps.(name{1})=candidate.(name{1}); end
    end
end
assert(all(isfield(maps,{'Compressor','GGT','FPT'})), ...
    'T700:Maps:MissingParameters','Initialize T700_Dyn once before plotting component maps.');
end

function components=fromRun(r)
components=struct;
keys={'CompData','GGTData','FPTData'};
names={'Compressor','GGT','FPT'};
fields={'WcMap','PRMap','EffMap','NcMap'};
signals=cell(3,4); scores=zeros(3,4);
for j=1:r.SignalCount
    signal=r.getSignalByIndex(j);
    % Ignore other models, even when their component log names are identical.
    if ~strcmp(signal.Model,'T700_Dyn'), continue; end
    signalName=strrep(strrep(signal.Name,'<',''),'>','');
    for c=1:3
        for f=1:4
            suffix=[keys{c} '.' fields{f}];
            if strcmp(signalName,suffix) || endsWith(signalName,['.' suffix])
                score=1+startsWith(signalName,'PlantData.Data.');
                if score>scores(c,f), signals{c,f}=signal; scores(c,f)=score; end
            end
        end
    end
end
if ~any(scores,'all'), return; end
assert(all(scores>0,'all'),'T700:Maps:MissingSignal', ...
    'Need WcMap, PRMap, EffMap and NcMap for all three components.');
for c=1:3
    data=struct;
    for f=1:4, data.(fields{f})=signals{c,f}.Values; end
    components.(names{c})=normalizeComponent(data);
end
end

function components=fromOutput(source)
keys={'CompData','GGTData','FPTData'};
names={'Compressor','GGT','FPT'};
plant=value(source,'Plant_Data');
if isempty(plant), plant=value(source,'PlantData'); end
if isempty(plant) && isstruct(source) && isfield(source,'Data'), plant=source; end
data=value(plant,'Data');
components=struct;
for c=1:3
    component=value(data,keys{c});
    if isempty(component), component=value(source,keys{c}); end
    assert(~isempty(component),'T700:Maps:MissingLog','No %s component log.',keys{c});
    components.(names{c})=normalizeComponent(component);
end
end

function result=normalizeComponent(data)
fields={'WcMap','PRMap','EffMap','NcMap'};
[t,w]=series(value(data,'WcMap'));
result=struct('Time',t,'WcMap',w);
for k=2:4
    [tx,y]=series(value(data,fields{k}));
    if isscalar(tx)
        y=repmat(y,numel(t),1);
    elseif ~isequal(tx,t)
        assert(t(1)>=tx(1) && t(end)<=tx(end),'T700:Maps:TimeRange','Component signal time ranges differ.');
        y=interp1(tx,y,t,'linear');
    end
    assert(all(isfinite(y)),'T700:Maps:Nonfinite','Nonfinite map trajectory.');
    result.(fields{k})=y;
end
end

function v=value(source,name)
v=[];
if isa(source,'Simulink.SimulationData.Signal'), source=source.Values; end
if isa(source,'Simulink.SimulationOutput')
    if ismember(name,source.who), v=source.get(name); end
elseif isstruct(source) && isscalar(source) && isfield(source,name)
    v=source.(name);
end
end

function [t,y]=series(ts)
if isa(ts,'Simulink.SimulationData.Signal'), ts=ts.Values; end
assert(isa(ts,'timeseries'),'T700:Maps:LogType','Map diagnostics must be scalar timeseries.');
t=double(ts.Time(:));
if ts.IsTimeFirst
    y=reshape(double(ts.Data),numel(t),[]);
else
    n=ndims(ts.Data); y=reshape(permute(double(ts.Data),[n 1:n-1]),numel(t),[]);
end
assert(size(y,2)==1 && ~isempty(t) && all(isfinite(t)) && all(isfinite(y)), ...
    'T700:Maps:InvalidLog','Empty, nonfinite or nonscalar component log.');
assert(all(diff(t)>=0),'T700:Maps:TimeOrder','Log time must be nondecreasing.');
[t,index]=unique(t,'last'); y=y(index);
end

function bundle=mergeRun(bundle,name,origin,components)
signature=componentDigest(components);
for k=1:numel(bundle.Runs)
    if strcmp(bundle.Runs(k).Signature,signature) && strcmp(bundle.Runs(k).Name,name), return; end
end
run=struct('Name',char(name),'Source',origin,'Signature',signature,'Components',components);
bundle.Runs(end+1)=run;
end

function signature=componentDigest(components)
md=java.security.MessageDigest.getInstance('SHA-256');
for name={'Compressor','GGT','FPT'}
    component=components.(name{1});
    for field={'Time','WcMap','PRMap','EffMap','NcMap'}
        updateDigest(md,component.(field{1}));
    end
end
signature=finishDigest(md);
end

function signature=mapDigest(maps)
md=java.security.MessageDigest.getInstance('SHA-256');
for name={'Compressor','GGT','FPT'}
    c=maps.(name{1});
    if strcmp(name{1},'Compressor')
        fields={'NcVec','WcArray','EffArray','s_Nc','s_Wc','s_PR','s_eff', ...
            'PRArray','RlineVec','WcMapSurge','PRMapSurge'};
    else
        fields={'NcVec','WcArray','EffArray','s_Nc','s_Wc','s_PR','s_eff','PRVec'};
    end
    for f=fields, if isfield(c,f{1}), updateDigest(md,c.(f{1})); end, end
end
signature=finishDigest(md);
end

function updateDigest(md,numbers)
shape=double(size(numbers)); md.update(typecast(shape(:),'uint8'));
md.update(typecast(double(numbers(:)),'uint8'));
end

function signature=finishDigest(md)
signature=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
