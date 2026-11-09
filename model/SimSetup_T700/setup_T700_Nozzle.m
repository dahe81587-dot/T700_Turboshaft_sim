function MWS = setup_T700_Nozzle(MWS)
% Interface placeholders ONLY: source A10 is not nozzle geometry/gas tables.
% SS nozzle is commented. Dyn nozzle must be configured or bypassed manually.
% Empty arrays and NaN intentionally prevent treating this as usable data.
MWS.Nozzle.ATh=NaN;
MWS.Nozzle.LossPerc=NaN;
MWS.Nozzle.FARVec=[];
MWS.Nozzle.TtVec=[];
MWS.Nozzle.RArray=[];
MWS.Nozzle.TGArray=[];
MWS.Nozzle.GArray=[];
MWS.Nozzle.PeQPaVec=[];
MWS.Nozzle.CdThArray=[];
MWS.Nozzle.CvArray=[];
MWS.Nozzle.ParametersReady=false;
end
