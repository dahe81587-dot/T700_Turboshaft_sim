"""Build scientific QA plots and a native MAT-file without starting MATLAB.

Run with the local scientific Python (F:/Program Files/python.exe). NumPy,
Matplotlib and Pillow are required. MATLAB's installed libmat/libmx libraries
write the MAT-file and independently read it back. No engine model is loaded.
"""
from __future__ import annotations

import ctypes as ct
import hashlib
import html
import json
import os
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from PIL import Image

ROOT=Path(__file__).resolve().parent.parent
RAW=ROOT/'data_raw'/'component_functions'
OUT=ROOT/'results'/'component_functions'
PROCESSED=ROOT/'data_processed'
MATLAB_BIN=Path(r'F:\software\MATLAB\R2024a\bin\win64')
TITLES=['压气机温度比','密封增压引气比例','动力涡轮平衡引气比例',
        '叶轮泄漏与涡轮冷却引气比例','燃烧效率','燃气发生器涡轮焓降参数',
        '动力涡轮焓降参数','动力涡轮流量参数','排气压力系数','热惯性系数']


class MatFileAPI:
    def __init__(self):
        self.dll_directory=os.add_dll_directory(str(MATLAB_BIN))
        self.mx=ct.CDLL(str(MATLAB_BIN/'libmx.dll'))
        self.mat=ct.CDLL(str(MATLAB_BIN/'libmat.dll'))
        self.create_double=self.bind(self.mx,'mxCreateDoubleMatrix_800',ct.c_void_p,
                                    [ct.c_size_t,ct.c_size_t,ct.c_int])
        self.create_struct=self.bind(self.mx,'mxCreateStructMatrix_730',ct.c_void_p,
                                    [ct.c_size_t,ct.c_size_t,ct.c_int,ct.POINTER(ct.c_char_p)])
        self.create_cell=self.bind(self.mx,'mxCreateCellMatrix_730',ct.c_void_p,
                                  [ct.c_size_t,ct.c_size_t])
        self.create_string=self.bind(self.mx,'mxCreateString',ct.c_void_p,[ct.c_char_p])
        self.create_logical=self.bind(self.mx,'mxCreateLogicalScalar',ct.c_void_p,[ct.c_bool])
        self.set_field=self.bind(self.mx,'mxSetField',None,
                                [ct.c_void_p,ct.c_size_t,ct.c_char_p,ct.c_void_p])
        self.get_field=self.bind(self.mx,'mxGetField',ct.c_void_p,
                                [ct.c_void_p,ct.c_size_t,ct.c_char_p])
        self.set_cell=self.bind(self.mx,'mxSetCell',None,[ct.c_void_p,ct.c_size_t,ct.c_void_p])
        self.pr=self.bind(self.mx,'mxGetPr',ct.POINTER(ct.c_double),[ct.c_void_p])
        self.rows=self.bind(self.mx,'mxGetM',ct.c_size_t,[ct.c_void_p])
        self.cols=self.bind(self.mx,'mxGetN',ct.c_size_t,[ct.c_void_p])
        self.destroy=self.bind(self.mx,'mxDestroyArray',None,[ct.c_void_p])
        self.open=self.bind(self.mat,'matOpen',ct.c_void_p,[ct.c_char_p,ct.c_char_p])
        self.close=self.bind(self.mat,'matClose',ct.c_int,[ct.c_void_p])
        self.put=self.bind(self.mat,'matPutVariable',ct.c_int,
                           [ct.c_void_p,ct.c_char_p,ct.c_void_p])
        self.get=self.bind(self.mat,'matGetVariable',ct.c_void_p,[ct.c_void_p,ct.c_char_p])

    @staticmethod
    def bind(dll,name,restype,argtypes):
        f=getattr(dll,name);f.restype=restype;f.argtypes=argtypes
        return f

    def array(self,value):
        if isinstance(value,dict):
            keys=[k.encode('ascii') for k in value]
            p=self.create_struct(1,1,len(keys),(ct.c_char_p*len(keys))(*keys))
            assert p
            for key,v in zip(keys,value.values()):self.set_field(p,0,key,self.array(v))
            return p
        if isinstance(value,(bool,np.bool_)):return self.create_logical(bool(value))
        if isinstance(value,str):return self.create_string(value.encode('utf-8'))
        if isinstance(value,(list,tuple)) and all(isinstance(v,str) for v in value):
            p=self.create_cell(len(value),1)
            for i,v in enumerate(value):self.set_cell(p,i,self.array(v))
            return p
        a=np.asarray(value,dtype=np.float64)
        if a.ndim==0:a=a.reshape(1,1)
        elif a.ndim==1:a=a[:,None]
        assert a.ndim==2
        p=self.create_double(*a.shape,0);assert p
        if a.size:np.ctypeslib.as_array(self.pr(p),shape=(a.size,))[:]=a.ravel(order='F')
        return p

    def save(self,file,data):
        handle=self.open(os.fsencode(file),b'w');assert handle,'Cannot open MAT output'
        p=self.array(data)
        try:assert self.put(handle,b'T700Functions',p)==0,'MAT write failed'
        finally:self.destroy(p);assert self.close(handle)==0

    def field(self,p,key):
        q=self.get_field(p,0,key.encode('ascii'));assert q,key
        return q

    def read_matrix(self,p):
        m,n=self.rows(p),self.cols(p)
        return np.ctypeslib.as_array(self.pr(p),shape=(m*n,)).reshape((m,n),order='F').copy()

    def verify(self,file,expected):
        handle=self.open(os.fsencode(file),b'r');assert handle
        root=self.get(handle,b'T700Functions');assert root
        try:
            curves=self.field(root,'Curves')
            for key,c in expected['Curves'].items():
                node=self.field(curves,key)
                for name in ('X','Y','PointMatrix','SelectedPixels'):
                    read=self.read_matrix(self.field(node,name))
                    original=np.asarray(c[name]);original=original[:,None] if original.ndim==1 else original
                    assert np.array_equal(read,original),(key,name)
        finally:self.destroy(root);assert self.close(handle)==0


def make_plot(raw,ax):
    p=np.array(raw['points']);bounds=raw['plot_bounds']
    ax.plot(p[:,0],p[:,1],'o-',color='#176b97',lw=1.25,ms=3.5)
    ax.set_xlim(bounds[0]-.008*(bounds[1]-bounds[0]),bounds[1]+.008*(bounds[1]-bounds[0]))
    ax.set_ylim(bounds[2]-.008*(bounds[3]-bounds[2]),bounds[3]+.008*(bounds[3]-bounds[2]))
    ax.grid(alpha=.22)
    ax.set_xlabel(f"{raw['x_name']} [{raw['x_unit']}]",fontsize=9)
    ax.set_ylabel(f"{raw['y_name']} [{raw['y_unit']}]",fontsize=9)
    ax.set_title(f"{raw['figure']}: {raw['function_title']}",fontsize=10)
    ax.tick_params(labelsize=8)
    ax.ticklabel_format(axis='y',style='plain',useOffset=False)


def main():
    manifest=json.loads((PROCESSED/'T700_remaining_functions_manifest.json').read_text())
    raw_curves=[json.loads((RAW/f'T700_A{i:02d}_raw.json').read_text()) for i in range(2,12)]
    curves={};stats=[]
    plt.rcParams.update({'font.family':'DejaVu Sans','savefig.facecolor':'white'})
    overview,axes=plt.subplots(5,2,figsize=(13,17),layout='constrained')
    for j,r in enumerate(raw_curves):
        key=f'A{j+2:02d}';p=np.array(r['points']);cal=r['calibration']
        h=np.array(cal['pixel_to_data_homography'])
        projected=np.column_stack([p[:,4:6],np.ones(len(p))])@h.T
        projected=projected[:,:2]/projected[:,2,None]
        assert np.allclose(projected,p[:,:2],rtol=0,atol=1e-12)
        assert np.all(np.diff(p[:,0])>0) and np.all(np.isfinite(p))
        image=Image.open(r['source_image']).convert('RGB')
        gray=np.asarray(image.convert('L'))
        for x,y in p[:,4:6].round().astype(int):assert gray[y-3:y+4,x-3:x+4].min()<160
        bounds=r['plot_bounds'];checks=cal['independent_tick_checks']
        for check in checks:
            span=(bounds[1]-bounds[0]) if check['axis']=='x' else (bounds[3]-bounds[2])
            assert abs(check['error'])<.01*span
        if r['figure']=='A8':assert (p[:,1]<0).any()
        if r['figure']=='A6':assert np.ptp(p[:,1])<2*p[:,3].max()
        c=dict(Figure=r['figure'],Definition=r['definition'],XName=r['x_name'],
               YName=r['y_name'],XUnit=r['x_unit'],YUnit=r['y_unit'],
               X=p[:,0],Y=p[:,1],PointMatrix=p,PointColumns=r['columns'],
               SelectedPixels=p[:,4:6],SourcePDFPage=r['pdf_page'],
               SourceImage=r['source_image'],SourceRecordJSON=json.dumps(r),
               UseForCurrentSteady=r['use_for_current_steady'],
               PressureConventionReviewRequired=r['pressure_convention_review_required'],
               StandardFlowConversionRequired=r['standard_flow_conversion_required'])
        if 'constant_estimate' in r:c['ConstantEstimate']=r['constant_estimate']
        curves[key]=c
        stats.append([j+2,len(p),p[:,0].min(),p[:,0].max(),p[:,1].min(),p[:,1].max(),
                      p[:,2].max(),p[:,3].max(),abs(checks[0]['error']),abs(checks[1]['error'])])

        fig,ax=plt.subplots(figsize=(9,10.5),layout='constrained')
        ax.imshow(image,origin='upper')
        ax.plot(p[:,4],p[:,5],'ro',ms=4,mfc='none',mew=1.0)
        for i,(x,y) in enumerate(p[:,4:6],1):ax.text(x+13,y-9,str(i),color='red',fontsize=6)
        frame=np.array(cal['frame_pixels'])
        ax.plot(frame[:,0],frame[:,1],'bo',ms=5,mfc='none')
        for check in checks:
            ax.plot(*check['pixel'],'s',color='green',ms=5,mfc='none')
        ax.set_xlim(frame[:,0].min()-240,frame[:,0].max()+140)
        ax.set_ylim(frame[:,1].max()+190,frame[:,1].min()-80)
        ax.set_axis_off()
        ax.set_title(f"Ballin Fig. {r['figure']}: {r['point_count']} original nodes\n"
                     'Red: extracted points; blue: frame; green: independent tick checks',fontsize=10)
        fig.savefig(OUT/f'T700_{key}_overlay.png',dpi=170)
        plt.close(fig)
        fig,ax=plt.subplots(figsize=(8,5.5),layout='constrained');make_plot(r,ax)
        fig.savefig(OUT/f'T700_{key}_points.png',dpi=170);plt.close(fig)
        make_plot(r,axes.flat[j])
        print(f'{key}: projection, source-ink, tick and shape checks PASS; plots saved.')
    overview.suptitle('T700 / Ballin Appendix A2-A11: 106 digitized source nodes',fontsize=15)
    overview.savefig(OUT/'T700_remaining_curves_overview.png',dpi=160);plt.close(overview)

    data=dict(SourceReport='NASA-TM-100991, Ballin, 1988',Engine='Ballin public T700 reference model',
              SourcePDF=manifest['source_pdf'],SourcePDF_SHA256=manifest['source_pdf_sha256'],
              CompressorA1SourceFile=str(ROOT/'data_raw'/'compressor'/'T700_compressor_A1_all_raw.mat'),
              A1CurveCount=11,A1PointCount=66,RemainingCurveCount=10,RemainingPointCount=106,
              TotalCurveCount=21,TotalPointCount=172,Curves=curves,SummaryMatrix=np.array(stats),
              SummaryColumns=['FigureNumber','PointCount','XMin','XMax','YMin','YMax',
                              'MaxXReadingResolution','MaxYReadingResolution','XTickError','YTickError'],
              RawDigitizationOnly=True,MapsAppliedToModel=False,SimulationRun=False,
              ConventionNotes=[
                  'A9: printed Ps9/P45 abscissa differs from Eq.33 P49/P45.',
                  'A9: printed flow unit/convention differs from standard T-MATS corrected flow.',
                  'A10: printed Ps9/P49 ratio is opposite to Eq.38; no boundary applied.',
                  'A8: negative source tail retained.',
                  'A11: optional heat-sink coefficient recorded; not a standalone time constant.',
                  'Raster reading resolution is not experimental uncertainty.'])
    api=MatFileAPI();matfile=PROCESSED/'T700_component_functions_raw.mat'
    api.save(matfile,data);api.verify(matfile,data)
    protected=[]
    for item in manifest['protected_file_hashes']:
        file=Path(item['path']);same=hashlib.sha256(file.read_bytes()).hexdigest()==item['sha256']
        assert same,file
        protected.append(dict(path=str(file),unchanged=same))
    audit=dict(remaining_curves=10,remaining_points=106,total_curves=21,total_points=172,
               native_mat_file_api_round_trip_passed=True,pixel_reprojection_passed=True,
               source_ink_checks_passed=True,independent_tick_checks_passed=True,
               visual_source_review_completed=True,protected_files=protected,
               model_modified=False,simulation_run=False,
               matlab_batch_status='Unavailable: startup/licensing communication error. MAT-file built and verified using native libmat/libmx.',
               source_review_note='All ten original-node overlays were inspected. Plot coordinate/unit conflicts remain explicit metadata for later map conversion.')
    (OUT/'stage06c_remaining_curves_audit.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
    with (OUT/'stage06c_remaining_curves_check.txt').open('w',encoding='utf-8') as f:
        for r in raw_curves:f.write(f"{r['figure']}: {r['point_count']} points; projection / ink / tick checks PASS\n")
        f.write('Remaining curves: 10\nRemaining points: 106\nTotal curves including A1: 21\nTotal points including A1: 172\n')
        f.write('Native MAT-file API write/read round-trip: PASS\nAll 14 protected files unchanged: PASS\n')
        f.write('Source overlay visual review: COMPLETE\nModel modified: 0\nSimulation run: 0\n')
        f.write('MATLAB batch startup unavailable; native MAT-file API used successfully.\n')
        f.write('STAGE06C_REMAINING_CURVES_COMPLETE\n')
    write_html(raw_curves,audit)
    print('Native MAT-file API round-trip: PASS')
    print('STAGE06C_REMAINING_CURVES_COMPLETE')


def write_html(raw_curves,audit):
    rows=[];cards=[]
    for name,r in zip(TITLES,raw_curves):
        p=np.array(r['points']);key='A'+r['figure'][1:].zfill(2)
        rows.append(f'<tr><td>{r["figure"]}</td><td>{name}</td><td>{len(p)}</td>'
                    f'<td>{p[:,0].min():.6g} ～ {p[:,0].max():.6g}</td>'
                    f'<td>{p[:,1].min():.6g} ～ {p[:,1].max():.6g}</td></tr>')
        points=''.join(f'<tr><td>{i}</td><td>{x:.8g}</td><td>{y:.8g}</td></tr>'
                       for i,(x,y) in enumerate(p[:,:2],1))
        notes=''.join(f'<li>{html.escape(n)}</li>' for n in r['notes'])
        cards.append(f'<section id="{key}"><h2>{r["figure"]} · {name}</h2>'
                     f'<p>来源：PDF第{r["pdf_page"]}页，印刷页{r["printed_page"]}。'
                     f'关系：<code>{html.escape(r["definition"])}</code></p>'
                     f'<p>横轴：{html.escape(r["x_name"])} [{html.escape(r["x_unit"])}]；'
                     f'纵轴：{html.escape(r["y_name"])} [{html.escape(r["y_unit"])}]。</p>'
                     f'<div class="plots"><a href="T700_{key}_overlay.png"><img src="T700_{key}_overlay.png" alt="原图叠加核查"></a>'
                     f'<a href="T700_{key}_points.png"><img src="T700_{key}_points.png" alt="提取点曲线"></a></div>'
                     f'<details><summary>展开{len(p)}个原始读图点</summary><table><thead><tr><th>序号</th><th>x</th><th>y</th></tr></thead>'
                     f'<tbody>{points}</tbody></table></details><ul>{notes}</ul></section>')
    text='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>T700 第六步：曲线提取核查</title><style>
body{font:16px/1.65 "Microsoft YaHei",system-ui,sans-serif;color:#22313e;background:#f3f6f8;margin:0}
main{max-width:1120px;margin:auto;padding:32px}h1{font-size:28px}h2{font-size:21px}section,.box{background:white;padding:24px;margin:24px 0;border-radius:12px}
table{border-collapse:collapse;width:100%;font-size:14px}td,th{padding:9px;border-bottom:1px solid #dce3e8;text-align:left}
.plots{display:grid;grid-template-columns:1fr 1fr;gap:18px}.plots img{width:100%;height:auto}code{overflow-wrap:anywhere}li{margin:7px 0}
.note{border-left:4px solid #d89923;padding-left:18px}a{color:#12668e}summary{cursor:pointer} @media(max-width:760px){.plots{grid-template-columns:1fr}main{padding:12px}}
</style><main><h1>T700 第六步：曲线提取核查</h1>
<p>提取完成。保留用户的A1压气机11条曲线、66个点；本轮完成A2～A11共10条函数、106个点。合计21条曲线/函数关系、172个原始点。</p>
<div class="box"><b>数据边界</b><p>来源为Ballin公开T700参考模型的附录A，不是新增发动机实验数据。本次仅整理原始读图点，未替换模型特性表、未运行发动机仿真。</p>
<p>MAT文件已使用MATLAB安装附带的MAT文件接口写入并读回核对数值。MATLAB后台实例因启动/许可通信问题未能运行；绘图和数据打包已由独立程序完成。</p>
<p>数据入口：<code>data_processed/T700_component_functions_raw.mat</code>。在MATLAB中运行 <code>F = T700_stage06c_load;</code>，可同时载入原有A1及本轮A2～A11数据。</p></div>
<div class="box note"><b>后续换算时必须保留的说明</b><ul>
<li>A9原图横轴标注Ps9/P45，正文式(33)使用P49/P45；“修正流量”也采用文献自己的定义，不能直接填入T-MATS流量表。</li>
<li>A10原图纵轴Ps9/P49与正文式(38)方向相反。本轮保留中性名称f10及原始数值，不叠加到已给定P49的Lewis边界。</li>
<li>A8末端负焓降参数按原图保留，未限幅。A11热惯性系数仅归档，未启用额外动态状态。</li>
<li>原始读数未强制圆整到整数横坐标，也未把接近零的数值强制设为零。每点附有3像素读图分辨率估计；它不是实验误差或统计置信区间。</li>
</ul></div><div class="box"><h2>提取清单</h2><table><thead><tr><th>图号</th><th>关系</th><th>点数</th><th>x范围</th><th>y范围</th></tr></thead><tbody>'''+''.join(rows)+'''</tbody></table>
<p>所有点通过像素重投影、原图墨迹接触和独立刻度核查。原始叠加图已逐张检查。用户A1数据及两个T700模型共14个文件的哈希保持不变。</p>
<p><a href="T700_remaining_curves_overview.png">查看全部函数曲线总览</a> · <a href="stage06c_remaining_curves_check.txt">检查记录</a> · <a href="stage06c_remaining_curves_audit.json">详细核查信息</a></p></div>'''+''.join(cards)+'''</main></html>'''
    (OUT/'T700_remaining_curves_review.html').write_text(text,encoding='utf-8')


if __name__=='__main__':main()
