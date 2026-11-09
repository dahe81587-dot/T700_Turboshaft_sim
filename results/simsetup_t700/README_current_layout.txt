2026-11-05 结果目录更正：当前稳态结果仅写入model/SteadyState/results/。
旧T700_SS_result_check.mat已迁入model/SteadyState/results/history/T700_SS_result_check_before_B1_rerun_20261105.mat。
本轮B.1三工况从空结果集重新运行；新文件为model/SteadyState/results/T700_SS_result_check.mat，首次检查保存后生成。
以下早期路径仅用于历史溯源，当前操作以model/SteadyState/README.txt为准。

当前生效说明（2026-11-05）：稳态脚本已移到model/SteadyState并使用T700_SS_前缀。
T700_initialize仍是唯一通用初始化入口；T700_check_parameters与PlotData保留model根目录。
以下早期实施记录用于溯源；当前命令与路线以model/SteadyState/README.txt为准。

当前入口与文件组织（2026-11-04 更新实验结果检查流程）

model根目录保留两份工程的模型、初始化、绘图及两个SimSetup目录。
SimSetup为原Turboshaft教学模型参数；SimSetup_T700为T700参数，二者不互相调用。
SimSetup_T700按实际模块名包含Compressor/GGT/FPT/Burner/Shaft/Shaft1/Inlet/Duct/Nozzle与边界设置函数。
求解器、路径、必要数据、数据来源记录等由T700_initialize直接设置。
T700初始化唯一入口是T700_initialize。旧入口与模型阶段构建脚本已退役。
历史快照和一次性维护脚本已封存到archive/history_*.zip，不应添加到MATLAB搜索路径。
早期整理曾修改两份T700模型的部件参数引用。当前T700_SS另已接入状态相关引气与有符号动力涡轮阻尼；本次仅更新检查脚本、初始化状态说明和本文档，未修改模型或特性参数。

使用：
cd('E:\postgraduate\09_Turboshaft\06_simulink\example\T700_validation\model')
MWS=T700_initialize;                 % 首次默认trim1，以后沿用已选工况
% 或 MWS=T700_initialize('lewis',4); % Lewis第4工况输入
% 表B.1三工况：T700_initialize('ballin_trim1')、('ballin_trim2')、('ballin_trim3')。
% 每次选定工况后，手动运行T700_SS，再调用T700_SS_check_result。
% 初次无参初始化默认trim1；已有本工程MWS时，无参调用沿用已选工况，避免模型InitFcn覆盖选择。
PlotData('maps');                  % 只查看当前参数特性图
% 原Turboshaft工程先运行：MWS=Turboshaft_initialize;
% SS仿真完成后： [fig,R]=PlotData('ss');
% Dyn仿真完成后：[fig,R]=PlotData('dyn',Plant_Data);
% 如使用SimulationOutput：PlotData('ss',out)或PlotData('dyn',out)。
% PlotData兼容两份工程，一次绘制站位、部件特性图与日志中存在的转速/特性图工作点。
% 调用前应确认输入结果与当前MWS来自同一目标工程和工况。

参数检查在初始化末尾自动调用。若检查失败，初始化会报错，新的MWS不会发布到工作区。
通用T700_check_parameters.m保留model根目录；稳态T700_SS_check_model.m、T700_SS_check_result.m和T700_SS_summary.m放在model/SteadyState，初始化自动加入该目录。
T700_SS_check_model检查列出的部件、边界、求解器参数绑定，并检查T700_SS引气和阻尼接口；以report.AllListedChecksPassed为总判据。
手动修改MWS后可以再次调用：report=T700_check_parameters(MWS);
手动打开并修改模型后可以调用：report=T700_SS_check_model('T700_SS',MWS);
模型检查仅审查列出的参数绑定并报告回调，不编译、不保存、不修改模型，不代表完整拓扑或收敛通过。
仿真完成后手动调用：SSreport=T700_SS_check_result;
该函数位于model，只读取现有Case02Logs、s2..s6和C_Data/GGT_Data/FPT_Data，复算六残差、图域和守恒，不修改模型或重新初始化。
检查结果保存为results/simsetup_t700/T700_SS_result_check.mat，最后显示AllChecksPassed。
同一文件中的sourceConsistency记录三工况原始f7/f8、焓温/混合关系及参考功率的对照；不改变仿真数值，也不参与AllChecksPassed判据。
adaptationAudit记录引气规律、原文动力涡轮阻尼及T45温度链的只读诊断。MATLAB调用检查函数时使用T2HM_TMATS/H2TM_TMATS原生MEX复核温度；不可用则明确跳过。已保存的Python源码复算标记NativeMEXExecuted=false，不等同于原生MEX执行。
sourceReplayAudit为2026-10-29针对当前三次用户仿真结果的离线审计，保留原文方程复算、单项敏感性、基准X与输入文件指纹。它不随后续模型修改自动更新，不表示新的Simulink运行、模型修改或实验验证；检查函数追加更新同一MAT文件并保留这份历史审计。
历史审计发现引气冻结与缺少阻尼；当前T700_SS已接入A3-A5状态相关引气和Eq41有符号阻尼，已有B.1三组结果记录DampingApplied=true。标准T-MATS焓温/守恒混合与原文线性焓温及H45=0.9623*H44仍不同，不能把KH45直接乘到T-MATS绝对焓上。
能量相对误差容差1e-3用于数值守恒筛查，不表示实验误差指标；AllChecksPassed也不表示实验验证或动态配平通过。
当前仍无自动仿真或模型构建入口。

注意：初始化会完全重建MWS，不应在需要保留仿真配平结果时重复调用。
Ballin使用profile中的trim1/2/3，第二参数应省略；Lewis必须明确提供1..6编号。
表B.1参考值直接存放在现有初始化函数中；结果检查在同一MAT文件的runs结构保留各工况最新结果，不新增结果文件。
Ballin三工况P49均由原图A10、参考修正Ng及正文Eq38估算；不是表B.1实测列，也没有接成随实际Ng变化的反馈边界。
trim1的P49现用入口环境压力14.696，而非校正流量用标准压力14.695951计算，较旧边界增加约0.00005025 psia（0.000333%），需重跑trim1。
模型原回调T700_initialize现在会进入统一的新初始化实现，加载的是T700参考参数。
模型变更仍由用户操作；当前SS引气冷却和阻尼已有连线，动态模型初值及接口另行核查。
绘图唯一入口为PlotData.m，内部使用局部函数读取两种输出格式、绘图，不增加外部入口。
T700_plot_parameters.m、PlotResults.m、PlotSSData.m已从活动目录移除，原文件封存于archive/plots_before_merge_*.zip。
四个模型绘图按钮的OpenFcn仍引用旧PlotSSData.m，需用户手动改为：
SS按钮：PlotData('ss');
Dyn按钮：PlotData('dyn');
本轮未修改任何模型回调或模型输出配置；修改按钮前请直接在命令窗口调用PlotData。
PlotData只读取已有结果，不运行模型、不修改基础工作区。
稳态图取最后一次求解样本，不代表收敛通过；动态图绘制记录时序。
PlotData统一物理站位S2/S3/S41/S45/S49。原日志s4/S4对应S41，s5/S5对应S45，s6/S6对应S49。
两模型To Workspace均为Timeseries：Dyn还同时记录Plant_Data总线和独立S1..S7；SS记录独立小写s变量。
不必为了画图重接日志总线；若后续手动统一，优先统一物理站位含义、字段、单位及时间记录。

T700_parameter_bundle.mat位于data_processed。当前只将所需常数、参考初值、
部件元数据和实验输入表写入MWS。源曲线和实验测量输出仍在数据文件中，未放入MWS。
SimSetup_T700的特性数组数值未改变，仅将HPC/HPT字段改为Compressor/GGT，双轴Jg/Jp改为Shaft.J/Shaft1.J。
数据包内部对应字段也已重命名，并通过原生MAT接口写入/回读验证。
T700_SS和T700_Dyn每份修改33处参数文本，包含Noz->Nozzle、Burner效率绑定、部件数组和惯量引用。
OPC所有XML部件解析/逐节点比较通过，连线、端口、模块开关和To Workspace记录方式未改变。
原Turboshaft两份模型未改动；GasTurbine_SS_Example_cleanup.m仅用于满足它们原有的CloseFcn引用。
该旧名称并非T700要求；清空原Turboshaft模型CloseFcn后，可删除此路径清理脚本。
Nozzle参数缺少T700几何和气体表：明确设置NaN/空数组，不可直接用于活动喷管计算。
SS喷管已关闭，采用给定P49的残差边界；SS引气冷却已接入。Dyn喷管及动态配平不在本次稳态实验验证范围。
压气机低压比支路近似、涡轮重复Nc行、涡轮参考温度/FAR适配及燃烧室压损冻结等限制继续适用；SS引气比例现随工况变化。
低压比平坦流量幅值已在原图独立复核，和原首点估计差0.05%~0.25%；转折位置未可靠独立确定，故保持特性数组不变。
A9图示Ps9/P45与正文Eq33的P49/P45不一致；A10图示Ps9/P49与Eq38的P49=Ps9*f10不一致。
继续记录现有A9图示解释、A10公式解释，未认定任何一处为已证实笔误，也未改动两曲线数值。
其他工况仍使用trim1的冻结参数适配，不能视为完整100991多工况复现。
原文印刷25页说明NASA Lewis原型机比较时替换了压气机流量和涡轮能量函数；本参数包对83579的直接比较应定位为跨发动机偏差评估。
原构建/复算报告是先前阶段的历史证据，其旧入口路径不再适用于当前目录。
data_processed中的旧stage06d构建脚本不应直接重跑，以免恢复已退役的目录与入口。
详见T700_active_file_audit.json和T700_two_project_migration.json。
MAT文件回读和静态语法检查不等同于MATLAB执行、模型运行、实验验证或动态配平；绘图入口尚待实际输出运行检查。

2026-11-05 当前验证路线：
Lewis实验验证暂缓，数据、参数和旧runs.lewis_case4等记录保留。
当前T700_SS_check_result仅接收ballin_trim1/2/3，避免混用标准配置与Lewis实验验收。
先运行T700_SS_summary只读查看已有B.1结果；不要对旧日志重新初始化后改工况标签。
Figures 6-8曲线取数和边界尚待核对。完整三项稳态任务、七步路线及命令见model/SteadyState/README.txt。
