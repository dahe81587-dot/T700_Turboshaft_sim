"""Digitize Ballin Appendix A2-A11 from the local source raster, without a model run.

Requires NumPy, Pillow and pypdfium2. Pixel seeds identify the visible original
cross markers, not assumed engineering values. Every final point is refined on
the raster; coordinates are calibrated from the printed graph frame. Raw images,
pixel selections, calibration, uncertainty estimates and conventions are kept.
Run T700_stage06c_pack_and_check in MATLAB afterwards to build MAT and QA plots.
"""
from __future__ import annotations

import csv
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter, ImageDraw
import pypdfium2 as pdfium

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / 'data_raw' / 'component_functions'
RESULTS = ROOT / 'results' / 'component_functions'
PDF = ROOT / 'sources' / 'A_high_fidelity_real-time_simulation_of_a_small_tu.pdf'


def spec(fig, title, definition, frame, bounds, seeds, x_name, y_name,
         x_unit='1', y_unit='1', checks=(), notes=(), steady=True):
    return dict(figure=fig, title=title, definition=definition,
                frame_seed_1p6=frame, bounds=bounds, marker_seeds_1p6=seeds,
                x_name=x_name, y_name=y_name, x_unit=x_unit, y_unit=y_unit,
                independent_tick_checks_1p6=checks, notes=list(notes),
                use_for_current_steady=steady)


# Frame corners: lower-left, lower-right, upper-left, upper-right, at scale 1.6.
# Bounds: x minimum, x maximum, y minimum, y maximum. Numeric labels can be
# aligned inward at frame ends: use the tick stroke, not the label's text centre.
SPECS = [
    spec(2, 'Compressor temperature ratio', 'T3/T2 = f2(Ps3/P2)',
         [[227,1011],[866,1014],[227,112],[866,114]], [0,20,1.1,3.0],
         [[259,913],[291,846],[322,788],[354,735],[386,688],[418,646],
          [450,609],[482,575],[513,544],[545,514],[577,489],[609,462],
          [641,438],[672,411],[705,383],[737,353],[769,320],[801,286],
          [833,248],[865,204]], 'Ps3_over_P2', 'T3_over_T2',
         checks=[['x',545,10],['y',587,2.0]]),
    spec(3, 'Seal-pressurization bleed fraction', 'B1 = f3(NGc_percent)',
         [[179,1025],[818,1027],[179,119],[818,122]], [65,100,-.02,.12],
         [[179,190],[417,191],[435,195],[454,209],[472,234],[490,264],
          [508,318],[526,420],[544,573],[581,812],[600,883],[618,897],
          [817,898]], 'NGc_percent', 'B1', '%',
         checks=[['x',454,80],['y',573,.05]]),
    spec(4, 'Power-turbine-balance bleed fraction', 'B2 = f4(WA2c)',
         [[241,1010],[880,1013],[241,112],[880,114]], [3,12,.0088,.0108],
         [[241,215],[383,921],[879,924]], 'WA2c', 'B2', 'lbm/s',
         checks=[['x',454,6],['y',472,.0100]],
         notes=['Piecewise linear: retain both endpoints and the original breakpoint.']),
    spec(5, 'Impeller leakage and turbine-cooling bleed fraction', 'B3 = f5(WA2c)',
         [[191,1022],[828,1026],[191,126],[828,129]], [3,12,.077,.086],
         [[191,215],[566,267],[828,938]], 'WA2c', 'B3', 'lbm/s',
         checks=[['x',546,8],['y',424,.083]],
         notes=['Piecewise linear: retain both endpoints and the original breakpoint.']),
    spec(6, 'Combustor efficiency', 'eta_b = f6(FAR)',
         [[232,1011],[872,1015],[232,115],[872,117]], [.010,.020,.88,1.10],
         [[232,588],[871,589]], 'FAR', 'eta_b',
         checks=[['x',490.4,.014],['y',526,1.00]],
         notes=['The original curve is constant. Store endpoint readings and their mean.',
                'The labelled FAR range is 0.010 to 0.020; endpoint text is aligned inward.']),
    spec(7, 'Gas-generator-turbine energy parameter',
         'DeltaH_GT/theta41 = f7(P45/P41)',
         [[175,1013],[812,1027],[184,113],[818,114]], [.20,.35,20,52.5],
         [[183,234],[244,453],[265,488],[285,510],[307,533],[813,897]],
         'P45_over_P41', 'DeltaH_GT_over_theta41', '1', 'Btu/lbm',
         checks=[['x',384,.25],['y',533,37.5]],
         notes=['theta41 is the squared-critical-velocity ratio in equation 25.',
                'The abscissa is outlet/inlet pressure, not the usual expansion ratio.']),
    spec(8, 'Power-turbine energy parameter',
         'DeltaH_PT/theta45 = f8(P49/P45)',
         [[233,1012],[873,1015],[226,112],[864,114]], [.30,.85,-5,40],
         [[228,237],[286,309],[344,383],[403,453],[461,512],[519,570],
          [578,628],[636,686],[694,746],[752,807],[812,872],[870,939]],
         'P49_over_P45', 'DeltaH_PT_over_theta45', '1', 'Btu/lbm',
         checks=[['x',519,.55],['y',519,20]],
         notes=['theta45 is defined by equation 31.',
                'The negative tail is present in the source and is not clipped.']),
    spec(9, 'Power-turbine flow parameter',
         'W45c_Ballin = W45*sqrt(theta45)/P45 = f9(P49/P45)',
         [[179,1024],[818,1026],[179,120],[818,123]], [.30,.85,.25,.39],
         [[180,235],[208,235],[237,238],[266,242],[295,248],[325,258],
          [354,269],[383,282],[412,298],[441,315],[470,334],[499,349],
          [527,374],[557,405],[585,444],[614,490],[643,541],[672,598],
          [701,658],[730,726],[759,797],[788,870],[817,947]],
         'pressure_ratio_f9_as_plotted', 'W45c_Ballin', '1', 'lbm/(s*psia) from Eq.34',
         checks=[['x',470,.55],['y',505,.33]],
         notes=['The printed ordinate unit is LBM/SEC; retain this original label as provenance.',
                'The printed abscissa reads Ps9/P45, while Eq.33 uses P49/P45; preserve the numerical ratio pending model conversion.',
                'Equation 34 multiplies this parameter by dimensional P45 and divides by sqrt(theta45).',
                'Do not copy these values directly into a standard T-MATS corrected-flow map.']),
    spec(10, 'Exhaust pressure factor', 'f10(NGc_percent) = P49/Ps9 by Eq.38',
         [[231,1005],[869,1008],[232,110],[872,113]], [65,100,1.01,1.14],
         [[232,219],[322,262],[341,274],[433,453],[479,530],[533,663],
          [605,824],[623,868],[641,896],[659,914],[686,933],[704,935],
          [722,929],[759,886],[797,846],[825,777],[861,641],[872,626]],
         'NGc_percent', 'exhaust_pressure_factor_f10', '%',
         checks=[['x',505,80],['y',522,1.08]], steady=False,
         notes=['The figure ordinate reads Ps9/P49, opposite to equation 38 and values greater than one.',
                'Store the numerical f10 curve and interpret P49=Ps9*f10 according to Eq.38.',
                'Reference only: do not add this boundary to Lewis cases with prescribed P49.']),
    spec(11, 'Station-4.1 heat-sink coefficient', 'tau41_sign = f_hs(NGc_percent)',
         [[181,1012],[817,1015],[181,117],[817,120]], [65,100,3.5,8.0],
         [[182,913],[273,913],[365,564],[455,475],[546,216],[817,217]],
         'NGc_percent', 'tau41_sign', '%', 'as used in Eq.53',
         checks=[['x',455,80],['y',514,6.0]], steady=False,
         notes=['Optional heat-sink data, not enabled in either model by this extraction.',
                'This is a coefficient in Eq.53; do not treat it as a standalone time constant.']),
]


def fit_edge(gray, p0, p1, horizontal):
    """Fit the printed border while rejecting tick intersections and scan specks."""
    pts = []
    a, b = np.array(p0)*2.5, np.array(p1)*2.5
    for t in np.linspace(.025,.975,220):
        guess = a*(1-t)+b*t
        if horizontal:
            x = int(round(guess[0])); y = int(round(guess[1]))
            band = np.arange(max(0,y-20), min(gray.shape[0],y+21))
            ink = band[gray[band,x] < 125]
            if len(ink): pts.append([x,float(np.median(ink))])
        else:
            x = int(round(guess[0])); y = int(round(guess[1]))
            band = np.arange(max(0,x-20), min(gray.shape[1],x+21))
            ink = band[gray[y,band] < 125]
            if len(ink): pts.append([y,float(np.median(ink))])
    pts = np.array(pts)
    for _ in range(4):
        coef = np.polyfit(pts[:,0],pts[:,1],1)
        residual = pts[:,1]-np.polyval(coef,pts[:,0])
        keep = abs(residual) <= max(2.,3*np.median(abs(residual)))
        pts = pts[keep]
    return coef, float(np.sqrt(np.mean((pts[:,1]-np.polyval(coef,pts[:,0]))**2)))


def intersection(horizontal, vertical):
    m,b = horizontal; n,c = vertical
    x = (n*b+c)/(1-n*m)
    return [x,m*x+b]


def graph_frame(gray, seeds):
    bl,br,tl,tr = seeds
    top,rt = fit_edge(gray,tl,tr,True)
    bottom,rb = fit_edge(gray,bl,br,True)
    left,rl = fit_edge(gray,tl,bl,False)
    right,rr = fit_edge(gray,tr,br,False)
    corners = np.array([intersection(bottom,left),intersection(bottom,right),
                        intersection(top,left),intersection(top,right)])
    return corners, dict(top=top,bottom=bottom,left=left,right=right), max(rt,rb,rl,rr)


def homography(pixels, targets):
    # Normalize raster coordinates to avoid ill-conditioned pixel equations.
    q = np.asarray(pixels)/np.array([2440.,3168.])
    a=[]; b=[]
    for (x,y),(u,v) in zip(q,targets):
        a.extend([[x,y,1,0,0,0,-u*x,-u*y],[0,0,0,x,y,1,-v*x,-v*y]])
        b.extend([u,v])
    h = np.append(np.linalg.solve(a,b),1).reshape(3,3)
    return h @ np.diag([1/2440.,1/3168.,1.])


def transform(pixels, h):
    p = np.atleast_2d(pixels)
    q = np.column_stack([p,np.ones(len(p))]) @ h.T
    return q[:,:2]/q[:,2,None]


def refine_marker(dilated, seed):
    """Locate both diagonals of a visible original x marker near its visual seed."""
    cx,cy = np.rint(np.array(seed)*2.5).astype(int)
    best=None
    for y in range(cy-13,cy+14):
        for x in range(cx-13,cx+14):
            arms=[]
            for sx,sy in ((1,1),(-1,1),(1,-1),(-1,-1)):
                arms.append(np.mean([dilated[y+sy*k,x+sx*k] for k in range(3,12)]))
            score = float(sum(arms)+3*min(arms)-.0015*((x-cx)**2+(y-cy)**2))
            if best is None or score>best[0]: best=(score,x,y,min(arms))
    return [float(best[1]),float(best[2])], float(best[3])


def tick_check(gray, edges, h, check):
    axis,guess,value = check
    guess = round(guess*2.5)
    scores=[]
    for pos in range(guess-14,guess+15):
        if axis=='x':
            edge=np.polyval(edges['bottom'],pos)
            indices=np.rint(edge-np.arange(3,25)).astype(int)
            score=np.sum(gray[indices,pos]<130)
        else:
            edge=np.polyval(edges['left'],pos)
            indices=np.rint(edge+np.arange(3,25)).astype(int)
            score=np.sum(gray[pos,indices]<130)
        scores.append(score)
    score=np.array(scores); positions=np.arange(guess-14,guess+15)
    winners=positions[score>=max(2,.85*score.max())]
    assert len(winners), f'Independent tick not found: {check}'
    pos=float(np.median(winners))
    pixel=[pos,float(np.polyval(edges['bottom'],pos))] if axis=='x' else \
          [float(np.polyval(edges['left'],pos)),pos]
    reading=transform(pixel,h)[0][0 if axis=='x' else 1]
    return dict(axis=axis,expected=value,pixel=pixel,reading=float(reading),
                error=float(reading-value),ink_score=int(score.max()))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    RAW.mkdir(parents=True,exist_ok=True); RESULTS.mkdir(parents=True,exist_ok=True)
    doc=pdfium.PdfDocument(str(PDF)); outputs=[]
    source_hash=digest(PDF)
    for cfg in SPECS:
        fig=cfg['figure']; stem=f'T700_A{fig:02d}'
        image_file=RAW/f'Ballin_A{fig:02d}_original.png'
        if not image_file.exists(): doc[fig+54].render(scale=4).to_pil().save(image_file)
        image=Image.open(image_file).convert('RGB')
        assert image.size==(2440,3168)
        gray=np.asarray(image.convert('L'))
        corners,edges,edge_rms=graph_frame(gray,cfg['frame_seed_1p6'])
        x0,x1,y0,y1=cfg['bounds']
        target=np.array([[x0,y0],[x1,y0],[x0,y1],[x1,y1]])
        h=homography(corners,target)
        dilated=np.asarray(Image.fromarray(gray).filter(ImageFilter.MinFilter(3)))<140
        found=[refine_marker(dilated,seed) for seed in cfg['marker_seeds_1p6']]
        selected=np.array([p for p,_ in found]); supports=np.array([s for _,s in found])
        xy=transform(selected,h)
        uncertainty=np.zeros_like(xy)
        # A conservative 3-raster-pixel reading resolution, not experimental uncertainty.
        for shift in ([3,0],[-3,0],[0,3],[0,-3]):
            uncertainty=np.maximum(uncertainty,abs(transform(selected+shift,h)-xy))
        checks=[tick_check(gray,edges,h,c) for c in cfg['independent_tick_checks_1p6']]
        span=[float(np.ptp(transform(corners,h)[:,i])) for i in (0,1)]
        for c in checks:
            assert abs(c['error']) < .01*span[0 if c['axis']=='x' else 1], (fig,c)
        assert np.all(np.isfinite(xy)) and np.all(np.diff(xy[:,0])>0), fig
        assert min(supports)>=.4, (fig,supports.tolist())
        rows=np.column_stack([xy,uncertainty,selected])
        raw=dict(schema_version=1,figure=f'A{fig}',function_title=cfg['title'],
                 definition=cfg['definition'],source_report='NASA-TM-100991, Ballin, 1988',
                 source_pdf=str(PDF),source_pdf_sha256=source_hash,
                 pdf_page=fig+55,printed_page=fig+41,source_image=str(image_file),
                 source_image_sha256=digest(image_file),image_size=[3168,2440],
                 x_name=cfg['x_name'],y_name=cfg['y_name'],x_unit=cfg['x_unit'],
                 y_unit=cfg['y_unit'],notes=cfg['notes'],
                 use_for_current_steady=cfg['use_for_current_steady'],
                 method='Raster digitization at original plotted cross markers; no curve fitting',
                 point_count=len(rows),points=rows.tolist(),
                 plot_bounds=cfg['bounds'],
                 columns=['x','y','x_reading_resolution','y_reading_resolution','pixel_x','pixel_y'],
                 calibration=dict(frame_pixels=corners.tolist(),
                                  frame_border_rms_px=edge_rms,
                                  pixel_to_data_homography=h.tolist(),
                                  independent_tick_checks=checks),
                 marker_arm_support=supports.tolist(),
                 reading_resolution_note='Estimated effect of 3 raster pixels; not experimental error or a confidence interval',
                 simulation_run=False,model_modified=False,
                 created_local=datetime.now(timezone(timedelta(hours=8))).isoformat(timespec='seconds'))
        raw['pressure_convention_review_required'] = fig in (9,10)
        raw['standard_flow_conversion_required'] = fig==9
        if fig==9:
            raw['original_x_ratio_label']='Ps9/P45'
            raw['original_y_unit_label']='LBM/SEC'
            raw['equation_x_ratio']='P49/P45 (Eq.33); not yet applied to a model'
        if fig==10:
            raw['original_y_ratio_label']='Ps9/P49'
            raw['equation_y_ratio']='P49/Ps9 (Eq.38); not yet applied to a model'
        if fig==6:
            raw['constant_estimate']=float(np.mean(xy[:,1]))
        (RAW/f'{stem}_raw.json').write_text(json.dumps(raw,indent=2),encoding='utf-8')
        with (RAW/f'{stem}_raw.csv').open('w',newline='',encoding='utf-8-sig') as f:
            writer=csv.writer(f);writer.writerow(raw['columns']);writer.writerows(rows)
        # A small quick-look overlay is for source review before MATLAB packaging.
        preview=image.copy(); draw=ImageDraw.Draw(preview)
        for i,(x,y) in enumerate(selected,1):
            draw.ellipse((x-10,y-10,x+10,y+10),outline=(220,20,40),width=3)
            draw.text((x+13,y-12),str(i),fill=(220,20,40),stroke_width=1)
        for x,y in corners:draw.ellipse((x-10,y-10,x+10,y+10),outline=(0,90,220),width=3)
        preview.thumbnail((976,1268))
        preview.save(RESULTS/f'{stem}_source_review.png')
        outputs.append(dict(figure=f'A{fig}',point_count=len(rows),
                            x_range=[float(xy[:,0].min()),float(xy[:,0].max())],
                            y_range=[float(xy[:,1].min()),float(xy[:,1].max())],
                            max_tick_error=[max(abs(c['error']) for c in checks if c['axis']==a) for a in ('x','y')],
                            source_json=str(RAW/f'{stem}_raw.json')))
        print(f'{stem}: {len(rows)} points, x={xy[0,0]:.7g}..{xy[-1,0]:.7g}, '
              f'y={xy[:,1].min():.7g}..{xy[:,1].max():.7g}, '
              f'min marker support={min(supports):.3f}')
    protected = sorted((ROOT/'data_raw'/'compressor').glob('*.mat'))
    protected += [ROOT/'model'/'T700_SS.mdl',ROOT/'model'/'T700_Dyn.mdl']
    manifest=dict(source_pdf=str(PDF),source_pdf_sha256=source_hash,curves=outputs,
                  curve_count=10,point_count=sum(c['point_count'] for c in outputs),
                  compressor_A1_user_data_preserved=True,model_modified=False,
                  simulation_run=False,extraction_complete=True,
                  protected_file_hashes=[dict(path=str(p),sha256=digest(p)) for p in protected])
    dest=ROOT/'data_processed'/'T700_remaining_functions_manifest.json'
    dest.write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('T700_REMAINING_FUNCTIONS_RASTER_EXTRACTION_COMPLETE')


if __name__=='__main__':
    main()
