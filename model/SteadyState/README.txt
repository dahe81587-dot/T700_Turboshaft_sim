T700 标准发动机稳态验证与后续路线（2026-11-05）

当前主线
采用 NASA-TM-100991 标准性能参考模型的 T-MATS 适配。Lewis 实验分支暂缓。
已有模型、部件参数、实验数据不改；历史结果按阶段归档，当前B.1三工况重新运行。
AllChecksPassed 只判断数值/物理一致性；B.1参考误差另行评价。

目录与命名
model/T700_initialize.m：唯一初始化入口，SS/Dyn/未来线性化共用；自动加入 SteadyState 路径。
model/T700_check_parameters.m：共用数据与参数检查，初始化末尾自动调用。
model/PlotData.m：通用绘图入口。
model/SteadyState/T700_SS_check_model.m：只检查已打开 T700_SS 的绑定、引气、阻尼与状态相关 A10 排气接口。
model/SteadyState/T700_SS_check_result.m：检查用户已经运行的 B.1 工况日志，并可保存报告。
model/SteadyState/T700_SS_summary.m：只读汇总已有 B.1 三工况，不运行模型、不保存文件。
未来动态和线性化脚本分别放入独立目录，待实际实现时建立。

当前三个稳态任务
1. B.1三工况：明确五项边界、六项残差、图域、引气、质量/能量守恒和八项参考误差。
2. Figures 6-8：先核对扫描时Np/负载、P49等条件，再数字化作者REAL-TIME MODEL数据。
   GE两套模型单独作为对照，不把图像取数当作原始精确数据。
   图6：Wf(lb/h)-Ng(%)；图7：Wf(lb/h)-有效轴功率(hp)；图8：Ng(%)-Ps3(psia)。
   结果报告已保存PerformancePoint坐标，但FigureBoundaryConditionsConfirmed=false。
   尚未取得曲线数据和完整边界，不能宣称Figures 6-8验证通过，也不自动生成扫描工况。
3. 动态/单点入口：选择B.1工况1附近，由当前模型完整收敛结果建立动态初值。
   不能只把论文Ng/Np填入动态模型就视作配平；DynamicTrimVerified保持false。

本轮结果保存后再查看汇总
cd('E:\postgraduate\09_Turboshaft\06_simulink\example\T700_validation\model')
addpath(fullfile(pwd,'SteadyState'))
[SSsummary,SScomparison]=T700_SS_summary;
以上命令只读本轮结果，不重新初始化MWS、不打开模型、不重新计算历史结果。第一组新结果保存前会提示暂无本轮结果。

需要重跑某个B.1工况时
MWS=T700_initialize('ballin_trim1');  % 后续按需改为trim2、trim3
手动打开本目录的T700_SS。
modelCheck=T700_SS_check_model('T700_SS',MWS);
确认modelCheck.AllListedChecksPassed=1。
清除上一轮日志：clear Case02Logs s2 s3 s4 s5 s6 C_Data GGT_Data FPT_Data P49_target P49_error P49_calc
由用户手动点击运行，成功结束后保持模型打开，不重新初始化。
SSreport=T700_SS_check_result(MWS);
只查看不落盘：SSreport=T700_SS_check_result(MWS,false);
保存位置为model/SteadyState/results/T700_SS_result_check.mat；每次保留本轮其他工况，按ballin_trim1/2/3分别记录。
保存时替换当前ballin_trim工况的最新记录；旧B.1与Lewis记录保存在results/history/T700_SS_result_check_before_B1_rerun_20261105.mat，本轮不自动读取。
日志没有独立运行编号；必须确认清除了旧日志且新仿真成功。

七步总体路线（每项时间为粗略人工操作估计）
1. 稳态基线（2-4小时）：SS、B.1。问题：各量误差及近似是什么？完成：三点数值与参考误差证据齐全。
2. 动态接口（半天-1天）：Dyn、初始化、引气/阻尼/排气。问题：与SS是否同配置？完成：初值有效、接口一致。
3. 无扰动保持（1-2小时）：SS结果启动Dyn。问题：恒输入是否漂移？完成：状态及内层残差稳定。
4. 小扰动（半天）：Wf和负载扰动。问题：方向、最终值、步长敏感性？完成：最终值与重新配平的SS一致。
5. 文献动态对比（半天-1天）：图9/10。问题：是否遵守原文固定Np等边界？完成：同条件响应对比与误差记录。
6. 单点线性化（半天-1天）：实际动态状态与附录B。问题：动态状态和代数未知量是否区分？完成：ABCD定义及步长敏感性检查。
7. 线性模型检验（半天）：同点小扰动。问题：线性与非线性增益、时间过程是否接近？完成：确定局部适用范围。
Figures 6-8范围检查属于第1步的扩展，不等于第5步动态验证。

自测
1. 为什么B.1和Figures 6-8不能互相替代？
2. 为什么SS的六个未知量不一定是六个动态状态？
3. 为什么AllChecksPassed=true仍不能说明参考误差或动态验证通过？

按阶段保存结果（2026-11-05）
稳态：model/SteadyState/results/。
动态：未来建立model/Dynamic/results/，由动态脚本读写。
线性化：未来建立model/Linearization/results/，由线性化脚本读写。
不再向工程统一results/simsetup_t700目录写入新的稳态仿真检查结果。
该旧目录的构建、数字化和文献审计资料保留作溯源，不作为本轮仿真结果。
本轮请按trim1、trim2、trim3逐个初始化、检查模型、清除旧日志、手动仿真、检查保存。
每个工况检查保存后再切换下一工况，避免日志与MWS工况错配。
历史文件迁移只改变位置，文件内容保持不变；新结果与历史记录分开。

状态相关排气检查更新（2026-11-05）
模型排气支路由用户手动修改，检查脚本不修改、不编译、不运行模型。
BleedSchedule 输出2经 Bleeds_Coordinates 标签传到 BC_NGc_Select，取实际 NGc 百分数。
BC_A10 使用 MWS.T700.Exhaust.NGcPercent / Factor，一维线性插值，越界试探采用 Clip。
BC_P1 当前取 MWS.Boundary.P2_psia，按 B.1 入口近似作为环境静压 Ps9。
BC_P49_Target 现为 Product，P49_target=Ps9*f10(NGc_actual)，接入原压力残差 Mux 输入2。
模型检查器新增 ExhaustAudit，核对块类型、参数、Goto/From来源、压力残差支路和目标日志。
结果检查器新增 report.Exhaust，用最终 Ng、入口 T2 独立复算目标，核对 P49_target / P49_error 日志及末时刻，并拒绝 A10 范围外的最终状态。
AllChecksPassed 现在同时要求上述排气检查通过；六未知量、六残差及 B.1 八项参考对比保持不变。
MWS.Boundary.P49_psia 仍是参考 Ng 对应的初始化种子，供 NR 初值和原文参考关系审计使用，不再代表活动排气目标。
活动目标看 report.Exhaust.P49Target_psia，实际压力看 report.Stations.S49.Pt，出口总温看 report.Stations.S49.Tt。
PerformancePoint.P49_psia 记录实际压力，并另存 P49Target_psia，避免将种子当作求解结果。
汇总显示各工况排气模式，旧版固定 P49 结果标为需重跑，不计入状态相关排气模式的通过进度。
A10 压力比方向仍按正文 Eq38 的既有解释处理，未声称原文图示歧义已解决；FPT 原有特性适配未改变。
本次检查脚本更新未替用户运行或保存新的仿真结果，B.1 三工况需重新运行后再评价。
