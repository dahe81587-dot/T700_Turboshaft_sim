function MWS = setup_T700_Burner(MWS)
% Burner source efficiency/LHV; pressure loss frozen at Appendix-B trim 1.
% Source and approximation notes: results/simsetup_t700/README_current_layout.txt.

MWS.Burner.Eff = 0.98440787837629995;
MWS.Burner.LHV = 18300;
MWS.Burner.dP = 0.05516797096518089;
MWS.Burner.PressureLossMode = 'frozen_AppendixB_trim1';
MWS.Burner.EfficiencyMode = 'A6_constant_mean';
MWS.Burner.MetadataJSON = '{"Eff": 0.9844078783763, "LHV": 18300.0, "dP": 0.05516797096518089, "PressureLossMode": "frozen_AppendixB_trim1", "EfficiencyMode": "A6_constant_mean"}';

end
