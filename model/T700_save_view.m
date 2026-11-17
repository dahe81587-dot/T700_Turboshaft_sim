function T700_save_view(fileName)
% Save an SDI view while preserving newlines in composite signal names.
% R2024a round-trip workaround; does not modify the model or signal data.
if nargin<1 || isempty(fileName)
    [f,p]=uiputfile('*.mldatx','Save Simulation Data Inspector view');
    if isequal(f,0),return;end
    fileName=fullfile(p,f);
end
[folder,stem,ext]=fileparts(fileName);
if isempty(ext),fileName=fullfile(folder,[stem '.mldatx']);end
Simulink.sdi.saveView(fileName);
T700_escape_view_newlines(fileName);
fprintf('Saved view with preserved signal-name newlines: %s\n',fileName);
end
