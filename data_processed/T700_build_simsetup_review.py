"""Publish the current parameter/construction evidence as a local review."""
import csv, hashlib, html, json
from pathlib import Path
from datetime import datetime
import numpy as np
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'results'/'simsetup_t700'

def main():
    load=lambda p:json.loads(p.read_text(encoding='utf-8'))
    p=load(ROOT/'data_processed'/'T700_adapter_numeric_parameters.json')
    c=load(OUT/'T700_simsetup_construction_checks.json')
    r=load(OUT/'T700_source_replay_checks.json')
    manifest=load(ROOT/'data_processed'/'T700_remaining_functions_manifest.json')
    protected=[]
    for record in manifest['protected_file_hashes']:
        path=Path(record['path']); digest=hashlib.sha256(path.read_bytes()).hexdigest()
        protected.append(dict(Path=str(path),SHA256=digest,Unchanged=digest==record['sha256']))
    assert all(v['Unchanged'] for v in protected),'Protected source/user model changed.'
    evidence=dict(Updated='2026-10-29',ParameterFilesGenerated=True,NativeMATReadbackPassed=True,
        MATLABStaticSyntaxCheckPassed=True,MATLABParameterCheckExecuted=False,
        SimulinkCompilePerformed=False,SimulinkSimulationRun=False,DynamicTrimReady=False,
        SingleOperatingPointLinearizationPerformed=False,ExperimentalValidationPassed=False,
        ExperimentalFitPerformed=False,ProtectedFiles=protected,
        ManualMATLABExecutionSelected=True,
        RuntimeBlocker='MATLAB window detected; Computer Use was not approved. User selected manual execution of the generated entry.',
        ConstructionReport=str(OUT/'T700_simsetup_construction_checks.json'),
        SourceReplayReport=str(OUT/'T700_source_replay_checks.json'))
    # Only claim static syntax checks after a saved mlint record exists and is clean.
    syntax=(OUT/'MATLAB_static_syntax_check.txt').read_text(encoding='utf-8')
    assert 'NOFIL' not in syntax and not __import__('re').search(r'^L \d+',syntax,__import__('re').M)
    (OUT/'T700_delivery_status.json').write_text(json.dumps(evidence,indent=2),encoding='utf-8')
    rows=[]
    with (OUT/'Lewis_unadapted_source_replay_errors.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.writer(f);writer.writerow(['CaseID','Converged','Field','Prediction','Experimental','RelativeErrorPercent'])
        for key,v in r['LewisCases'].items():
            solve=v['Solve'];compare=v.get('Comparison')
            if compare:
                for name,yp,ym,err in zip(compare['Fields'],compare['Prediction'],compare['Experimental'],compare['RelativeErrorPercent']):
                    writer.writerow([key,True,name,yp,ym,err])
                errors=compare['RelativeErrorPercent']
                errorcells=''.join(f'<td>{x:+.2f}%</td>' for x in errors)
            else:
                writer.writerow([key,False,'','','',''])
                errorcells='<td colspan="7">未收敛，不生成有效预测误差</td>'
            role='低功率边界' if key=='1' else '保留验证工况' if key in ('3','5') else '计划标定工况，尚未拟合'
            rows.append(f'<tr><td>{key}</td><td>{role}</td><td>{"收敛" if solve["Converged"] else "未收敛"}</td>{errorcells}</tr>')
    maps=''.join(f'<tr><td>{g}</td><td>{np.shape(p[g]["WcArray"])}</td><td>{min(np.ravel(p[g]["EffArray"])):.5f}–{max(np.ravel(p[g]["EffArray"])):.5f}</td><td>{"11条源转速线；低压比段近似" if g=="HPC" else "重复Nc接口行；参考温度/FAR冻结"}</td></tr>' for g in ('HPC','HPT','FPT'))
    residual=r['ReferenceSolve']['Residual']
    resrows=''.join(f'<tr><td>{name}</td><td>{value:.6g}</td></tr>' for name,value in zip(r['ReferenceSolve']['Evaluation']['ResidualOrder'],residual))
    h=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>T700 SimSetup 参数包审查</title>
<style>body{{font:16px/1.75 "Microsoft YaHei",sans-serif;color:#203047;max-width:1200px;margin:38px auto;padding:0 24px;background:#f5f7fa}}h1,h2{{line-height:1.35}}section{{background:white;padding:24px;margin:22px 0;border:1px solid #dfe5ec;border-radius:12px}}table{{border-collapse:collapse;width:100%;font-size:14px}}td,th{{border:1px solid #dfe5ec;padding:8px;text-align:left}}th{{background:#edf2f7}}img{{width:100%;height:auto}}code,pre{{font-family:Consolas,monospace}}pre{{white-space:pre-wrap;background:#eef2f7;padding:16px;border-radius:8px}}.note{{background:#fff2d8;border-left:5px solid #d19122;padding:16px}}a{{color:#176b97}}small{{color:#53657a}}</style>
<h1>T700 SimSetup 参数包</h1><p>2026-10-29 · 从公开参考函数构建普通 T-MATS 参数 · 原始数据与两个原模型已核对 SHA-256，{len(protected)} 个文件均未改变。</p>
<div class="note"><b>当前结论：</b>参数包、MAT回读和静态语法检查已完成。独立方程复算取得部分收敛结果，但存在明显实验输出偏差。MATLAB参数入口、Simulink编译与仿真尚未执行，动态配平与单工作点线性化尚未完成。</div>
<section><h2>从源数据到运行模型的四层关系</h2><table><tr><th>层</th><th>位置</th><th>职责</th><th>当前证据</th></tr>
<tr><td>原始来源</td><td>sources / data_raw</td><td>保留文献、数字化点及原图</td><td>11条压气机曲线66点；A2–A11共106点</td></tr>
<tr><td>参数重建</td><td>data_processed</td><td>定义换算、热力学与参考工况适配</td><td>数组范围、回插误差、敏感性审查</td></tr>
<tr><td>参数加载</td><td>model/SimSetup_T700</td><td>setup函数与统一MWS入口</td><td>已生成；MAT回读和静态语法检查通过；MATLAB入口待执行</td></tr>
<tr><td>模型执行</td><td>model/T700_*SS_adapter.m</td><td>生成副本、接入引气冷却、求解并记录证据</td><td>脚本已生成，尚未运行</td></tr></table>
<p>原 SimSetup 与原模型回调继续保留。新入口是 <code>T700_initialize</code>；<code>T700_prepare_SS_adapter</code> 生成单独的 <code>T700_SS_T700Adapter</code>。</p></section>
<section><h2>实际参数数组</h2><table><tr><th>部件</th><th>Wc/Eff维数</th><th>效率范围</th><th>数据性质</th></tr>{maps}</table>
<p>普通格式：Wc=W√(Tt/518.67)/(Pt/14.695951)，Nc=N/√(Tt/518.67)，NcMap=Nc/s_Nc。流量lbm/s、温度degR、压力psia、转速rpm、扭矩lbf·ft。</p>
<img src="T700_simsetup_maps.png" alt="T700适配特性图"/>
<p>引气比例：{', '.join(f'{x:.7f}' for x in c['Reference']['BleedFractions'])}；燃烧效率{p['Burner']['Eff']:.7f}，热值18300 Btu/lbm，参考压损比例{p['Burner']['dP']:.7f}。</p></section>
<section><h2>参考工况独立方程复算</h2><p>这是对安装版本T-MATS部件方程的Python复算，不执行模型文件或MEX，也不等同于Simulink仿真。</p>
<p>Ballin参考边界下收敛，六未知量：<code>{', '.join(f'{x:.8g}' for x in r['ReferenceSolve']['X'])}</code>。</p>
<table><tr><th>残差</th><th>数值</th></tr>{resrows}</table>
<p>检查包括特性图范围。参考源值用于部件适配和初值，适配方程的收敛点不会与原Ballin经验模型每个站位完全一致。</p></section>
<section><h2>Lewis：未标定参考参数的误差</h2><p>没有使用实验输出调参。误差=(预测−实验)/实验。工况3/5仍作为保留验证数据；这一轮比较没有产生“验证通过”的结论。</p>
<div style="overflow:auto"><table><tr><th>工况</th><th>角色</th><th>数值状态</th><th>Ng</th><th>Np</th><th>WA2</th><th>P3</th><th>T3</th><th>T45</th><th>T49</th></tr>{''.join(rows)}</table></div>
<p>工况1/2的有界求解无进一步下降，分别靠近FPT归一化转速支撑行的下/上边界；这不证明物理上无稳态解。涡轮重复Nc行不能替代真实多转速性能资料。工况3–6虽收敛，Np和流量偏差仍明显。</p>
<a href="Lewis_unadapted_source_replay_errors.csv">查看误差CSV</a></section>
<section><h2>适用范围与待解决问题</h2><ul>
<li>HPC使用Ps3/P2源横坐标，通过Kps3=0.956转换总压比；低压比平坦段按首个已选短支路点近似，喘振边界未经验证。</li>
<li>涡轮缺少多转速线，当前为参考温度/FAR/排气系数冻结适配；A9的图示环境压力比与Ballin Eq33定义存在冲突，当前选figure_ambient解释，未把冲突认定为已证实的笔误。</li>
<li>引气、焓位置和燃烧室压损冻结在参考工况；第三路冷却在GGT出口返回。A11热惯性函数保留于数据包，尚未接入动态模型。</li>
<li>单工作点线性化为必做项，需先完成有效动态配平，再导出A/B/C/D并用小扰动比较。当前没有生成未经运行证明的矩阵。多工作点按后续控制需求决定。</li></ul></section>
<section><h2>MATLAB使用入口与完成标准</h2><pre>cd('E:\\postgraduate\\09_Turboshaft\\06_simulink\\example\\T700_validation\\model')
MWS = T700_initialize;
PlotData('maps');
% 如需Lewis第4工况：
MWS = T700_initialize('lewis',4);
% 模型修改、打开与仿真由用户手动执行。</pre>
<p>通过标准：SolverConverged=1，JacFailed=0，前四残差≤1e−6，双轴加速度≤0.05rpm/s，所有图域输入在范围内，质量误差&lt;1e−6 lbm/s。运行入口保存实际日志；达到停止时间本身不表示通过。</p>
<p>当前检测到MATLAB窗口，但computer-use返回“未获准控制MATLAB”。用户已选择手动执行生成的入口，因此上述MATLAB运行结果仍待收集。</p>
<p><a href="../../model/SimSetup_T700/README_T700.txt">完整说明、后续步骤和验收标准</a> · <a href="T700_delivery_status.json">交付状态与保护文件哈希</a> · <a href="T700_simsetup_construction_checks.json">构建审查</a> · <a href="T700_source_replay_checks.json">复算原始结果</a></p></section>
<small>来源：Ballin NASA-TM-100991 Appendix A/B；Hart &amp; Wenzel NASA-TM-83579 Tables I/II；Novikov 2012 Eq2.40。源PDF与原始提取资料在本工程sources和data_raw中。</small></html>'''
    (OUT/'T700_simsetup_review.html').write_text(h,encoding='utf-8')
    print('Protected files unchanged:',len(protected))
    print('T700_SIMSETUP_REVIEW_READY')

if __name__=='__main__':main()
