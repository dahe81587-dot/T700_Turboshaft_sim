function MWS = setup_Shaft(MWS)
% 两轴惯量参数
% 单位：slug*ft^2，沿用 T-MATS Shaft 的原生单位

MWS.Shaft.Jg = 30;  % 燃气发生器轴惯量：案例继承值
MWS.Shaft.Jp = 30;  % 动力轴等效惯量：暂用案例值占位
end