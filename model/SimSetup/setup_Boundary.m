function MWS = setup_Boundary(MWS)
% 教学模型的环境、供油和负载边界
% 环境、供油和附件功率暂时保持案例原值

MWS.Boundary.Alt   = 0;    % 高度，ft
MWS.Boundary.dTamb = 0;    % 相对标准大气的温差，degF
MWS.Boundary.Mach  = 0;    % 马赫数
MWS.Boundary.Wf    = 3;    % 燃油质量流量，lbm/s

MWS.Boundary.Pacc_g = 0;   % Ng轴附件提取功率，hp
MWS.Boundary.Pacc_p = 0;   % 动力轴附件提取功率，hp

% 动力轴负载扭矩的正幅值，单位 lbf*ft
% 尚未选定教学负载，NaN明确表示待定
MWS.Boundary.Qload = NaN;
end