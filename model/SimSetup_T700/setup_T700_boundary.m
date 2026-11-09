function MWS = setup_T700_boundary(MWS,profile,caseID)
% Select boundary data without adapting maps to experimental outputs.
C = MWS.T700.Constants;
if ismember(lower(profile),{'ballin_trim1','ballin_trim2','ballin_trim3'})
    trimID=str2double(profile(end));
    R=MWS.Reference.Ballin(MWS.Reference.Ballin.TrimID==trimID,:);
    MWS.Boundary.P2_psia = R.P2_psia;
    MWS.Boundary.T2_R = R.T2_R;
    ncPercent=100*R.Ng_rpm/sqrt(R.T2_R/C.Tstd)/C.NgDesign;
    f10=interp1(MWS.T700.Exhaust.NGcPercent,MWS.T700.Exhaust.Factor,ncPercent,'linear');
    assert(isfinite(f10) && f10>0,'A10 曲线未覆盖当前参考修正转速。');
    % Ambient static pressure equals P2 in this source inlet approximation.
    % Table B.1 does not list P49: this is a derived prescribed boundary.
    MWS.Boundary.P49_psia = R.P2_psia*f10;
    MWS.Boundary.Wf = R.Wf_lb_h/3600;
    MWS.Boundary.Qload = R.Qload_lbf_ft;
    MWS.Boundary.CaseID = 0;
    MWS.Boundary.TrimID = trimID;
    MWS.Boundary.ExhaustFactorAtReference=f10;
    MWS.Boundary.P49Source='Derived from Eq38 at reference corrected Ng; not a Table B.1 measurement';
    MWS.Boundary.Source = ['Ballin_public_reference_trim' num2str(trimID)];
elseif strcmpi(profile,'lewis')
    assert(isscalar(caseID) && ismember(caseID,1:6),'实验工况编号 CaseID 必须为 1..6。');
    R = MWS.Reference.Input(MWS.Reference.Input.CaseID==caseID,:);
    MWS.Boundary.P2_psia = R.P2_psia;
    MWS.Boundary.T2_R = R.T2_R;
    MWS.Boundary.P49_psia = R.P49_psia;
    MWS.Boundary.Wf = R.Wf_lb_s;
    MWS.Boundary.Qload = R.Qload_lbf_ft;
    MWS.Boundary.CaseID = caseID;
    MWS.Boundary.TrimID = 0;
    MWS.Boundary.Source = 'NASA_Lewis_test_article_unadapted_reference_maps';
else
    error('工况模式必须为 ballin_trim1/2/3 或 lewis。');
end
MWS.Boundary.FAR2 = 0;
MWS.Boundary.Pacc_g = 0;
MWS.Boundary.Pacc_p = 0;
MWS.Boundary.Alt = 0;
MWS.Boundary.dTamb = 0;
MWS.Boundary.Mach = 0;
MWS.Boundary.Profile = profile;
MWS.Boundary.OutletTotalPressurePrescribed = true;
MWS.Boundary.ExhaustFactorAlsoImposed = false;
end
