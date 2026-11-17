% Compatibility for Plot Outputs blocks already loaded with the old callback.
% The saved T700_Dyn model calls T700_PlotComponentMaps directly.
if strcmp(bdroot(gcb),'T700_Dyn')
    T700_PlotComponentMaps;
else
    PlotData('ss');
end
