"""Installed-source T-MATS thermodynamics and the Ballin A1/A2 compressor map.

This module performs numeric preprocessing only. It does not open a model, run
MATLAB, or write output files. The default source is the installation inspected
for this project. Polynomial coefficients are read from that installation, not
from a second gas-property approximation.

T-MATS units: T [degR], P [psia], h [Btu/lbm], s [Btu/(lbm*degR)].
Source functions: t2hc_TMATS.c, h2tc_TMATS.c, pt2sc_TMATS.c, sp2tc_TMATS.c.
Source equations are replayed including the inverse routines' iteration limits
and tolerances. This is source parity; a native-MEX runtime comparison is separate.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re

import numpy as np


DEFAULT_LIBRARY_ROOT = Path(
    r"C:\Users\xie jinao\AppData\Roaming\MathWorks\MATLAB Add-Ons\Collections\nasa_T-MATS_24b"
)


class ThermoTMATS:
    """Scalar/NumPy-array replay of this project's installed T-MATS C gas tables.

    An explicit library_root may name the collection directory, TMATS_Library,
    or the MEX source directory. Arrays are broadcast using NumPy conventions.
    Both unburned air (FAR=0) and the source's air/stoichiometric-gas mixture
    formulas (FAR>0) are supported. Inputs must be finite, with T/P positive
    and FAR nonnegative. No gas-property or inverse-root fallback is concealed.
    """

    def __init__(self, library_root=None):
        root = Path(library_root) if library_root is not None else DEFAULT_LIBRARY_ROOT
        candidates = (root / 'TMATS_Library' / 'MEX', root / 'MEX', root)
        self.source_dir = next(
            (p for p in candidates if (p / 't2hc_TMATS.c').is_file()), None
        )
        if self.source_dir is None:
            raise FileNotFoundError(f'T-MATS gas-table sources not found below {root}')
        self._tables = {}
        self.source_info = {}
        for name in ('t2hc', 'h2tc', 'pt2sc', 'sp2tc'):
            file = self.source_dir / f'{name}_TMATS.c'
            source = file.read_text(encoding='utf-8')
            arrays = {}
            for typ, key, length, values in re.findall(
                r'\b(int|double)\s+(\w+)\[(\d+)\]\s*=\s*\{([^}]+)\}', source, re.S
            ):
                values = re.sub(r'/\*.*?\*/', '', values, flags=re.S)
                a = np.array([float(v) for v in values.split(',') if v.strip()])
                if len(a) != int(length):
                    raise ValueError(f'{file}: coefficient count mismatch for {key}')
                arrays[key] = a.astype(int) if typ == 'int' else a
            required = ('ITAB', 'TTTAB')
            if not all(k in arrays for k in required):
                raise ValueError(f'{file}: expected table layout not present')
            self._tables[name] = arrays
            self.source_info[name] = {
                'Path': str(file),
                'SHA256': hashlib.sha256(file.read_bytes()).hexdigest(),
                'Function': name,
            }
        self.formula_info = {
            'Enthalpy': 'Cubic air/stoichiometric-gas polynomials and source mole/mass mixture formulas.',
            'Entropy': '(phig*0.5035576347-23.0258509)*Rcas-0.1841304-Rcas*log(P/14.696)',
            'H2TInverse': 'Source secant update; initial T=3.55*h, at most 11 iterations, |h residual| <= 1e-3.',
            'SP2TInverse': 'Source secant update; starts at 1000/1050 R, at least 2 and at most 10 iterations, entropy tolerance 1e-4.',
            'CoefficientTemperatureKnots_R': self._tables['t2hc']['TTTAB'].astype(float).tolist(),
            'EntropyPressureReference_psia': 14.696,
            'NativeMEXParityExecuted': False,
        }

    @staticmethod
    def _broadcast(fn, *values):
        arrays = np.broadcast_arrays(*[np.asarray(v, dtype=float) for v in values])
        out = np.empty(arrays[0].shape, dtype=float)
        for index in np.ndindex(out.shape):
            out[index] = fn(*[float(a[index]) for a in arrays])
        return float(out) if out.ndim == 0 else out

    @staticmethod
    def _mixture(far):
        if not math.isfinite(far) or far < 0:
            raise ValueError('FAR must be finite and nonnegative')
        if far == 0:
            return 4.7642, 0.0, 0.2098988288, 0.0345194683
        zmea = 4.7642 - far * 69.69056873
        zmsp = far * 74.411931335
        tmls = 4.7642 + far * 4.721362582
        zmwtr = tmls / (138.0148721 * (1 + far))
        return zmea, zmsp, 1 / tmls, zmwtr

    @staticmethod
    def _index(temp, tables):
        # C uses fmod, conversion to integer, then the same [1,60] index bounds.
        coarse = 0.01 * (temp - math.fmod(temp, 100))
        index2 = int(coarse) if coarse > 1 else 1
        index = min(index2, 60)
        return int(tables['ITAB'][index - 1]) - 1

    @staticmethod
    def _poly(temp, tables, names):
        i = ThermoTMATS._index(temp, tables)
        dl = temp - tables['TTTAB'][i]
        a, b, c, d = [tables[name][i] for name in names]
        return ((d * dl + c) * dl + b) * dl + a

    def _enthalpy(self, temp, far, table_key='t2hc'):
        zmea, zmsp, tmlsr, zmwtr = self._mixture(far)
        tables = self._tables[table_key]
        h_air = self._poly(temp, tables, ('AHAIR','BHAIR','CHAIR','DHAIR'))
        h_stoich = self._poly(temp, tables, ('AHSTOC','BHSTOC','CHSTOC','DHSTOC')) if far > 0 else 0.0
        return float((h_stoich * zmsp + h_air * zmea) * (tmlsr * zmwtr))

    def _entropy(self, pressure, temp, far, table_key='pt2sc'):
        zmea, zmsp, tmlsr, zmwtr = self._mixture(far)
        tables = self._tables[table_key]
        phi_air = self._poly(temp, tables, ('APAIR','BPAIR','CPAIR','DPAIR'))
        phi_stoich = self._poly(temp, tables, ('APSTOC','BPSTOC','CPSTOC','DPSTOC')) if far > 0 else 0.0
        phi_gas = (phi_stoich * zmsp + phi_air * zmea) * tmlsr
        rcas = 1.98587 * zmwtr
        return float((phi_gas * 0.5035576347 - 23.0258509) * rcas
                     - 0.1841304 - rcas * math.log(pressure / 14.696))

    def t2h(self, T, FAR=0):
        """Enthalpy [Btu/lbm] from T [degR] and FAR."""
        def scalar(temp, far):
            if not math.isfinite(temp) or temp <= 0:
                raise ValueError('Temperature must be finite and positive')
            return self._enthalpy(temp, far)
        return self._broadcast(scalar, T, FAR)

    def pt2s(self, P, T, FAR=0):
        """Entropy [Btu/(lbm*degR)] from P [psia], T [degR], FAR."""
        def scalar(pressure, temp, far):
            if not math.isfinite(pressure) or pressure <= 0:
                raise ValueError('Pressure must be finite and positive')
            if not math.isfinite(temp) or temp <= 0:
                raise ValueError('Temperature must be finite and positive')
            return self._entropy(pressure, temp, far)
        return self._broadcast(scalar, P, T, FAR)

    def h2t(self, h, FAR=0):
        """Temperature [degR], retaining h2tc.c's secant algorithm/tolerance."""
        def scalar(target, far):
            if not math.isfinite(target):
                raise ValueError('Enthalpy must be finite')
            self._mixture(far)
            tg = 3.55 * target
            tgo, hgo, hh, ii = 1.0, 0.282, 99.99, 0
            while abs(hh) > 1e-3 and ii < 11:
                ii += 1
                hg = self._enthalpy(tg, far, 'h2tc')
                hh = target - hg
                if hg == hgo:
                    raise ArithmeticError('h2tc source secant denominator is zero')
                d = (tg - tgo) / (hg - hgo)
                tgo, hgo = tg, hg
                tg = tg + d * hh
            if not math.isfinite(tg) or tg <= 0:
                raise ArithmeticError('h2tc source inverse left the positive-temperature domain')
            return tg
        return self._broadcast(scalar, h, FAR)

    def sp2t(self, s, P, FAR=0):
        """Temperature [degR], retaining sp2tc.c's secant algorithm/tolerance."""
        def scalar(target, pressure, far):
            if not math.isfinite(target):
                raise ValueError('Entropy must be finite')
            if not math.isfinite(pressure) or pressure <= 0:
                raise ValueError('Pressure must be finite and positive')
            self._mixture(far)
            tg, sg, jj = 1000.0, 1000.0, 0
            tg1 = sg1 = None
            while (abs(target - sg) >= 1e-4 and jj < 10) or jj < 2:
                sg = self._entropy(pressure, tg, far, 'sp2tc')
                if jj == 0:
                    sg1, tg1 = sg, tg
                    tg = tg1 + 50
                else:
                    if sg == sg1:
                        raise ArithmeticError('sp2tc source secant denominator is zero')
                    dtds = (tg - tg1) / (sg - sg1)
                    tg1, sg1 = tg, sg
                    tg = tg1 + (target - sg1) * dtds
                jj += 1
            if not math.isfinite(tg) or tg <= 0:
                raise ArithmeticError('sp2tc source inverse left the positive-temperature domain')
            return tg
        return self._broadcast(scalar, s, P, FAR)

    def self_check(self):
        """Check both air and combustion-gas round trips over the source knot range."""
        temperatures = np.array([300,400,500,518.67,700,1000,1400,1900,2500,3100,3700,4500.])
        fars = np.array([0,.01,.025,.04])
        t, f = np.meshgrid(temperatures, fars)
        h = self.t2h(t, f)
        tr_h = self.h2t(h, f)
        hr = self.t2h(tr_h, f)
        worst_s_t = worst_s = 0.0
        for pressure in (14.695951,50.,150.,250.):
            s = self.pt2s(pressure, t, f)
            tr_s = self.sp2t(s, pressure, f)
            sr = self.pt2s(pressure, tr_s, f)
            worst_s_t = max(worst_s_t, float(np.max(abs(tr_s-t))))
            worst_s = max(worst_s, float(np.max(abs(sr-s))))
        h_residual = float(np.max(abs(hr-h)))
        return {
            'TemperatureRange_R': [float(temperatures[0]),float(temperatures[-1])],
            'FARValues': fars.tolist(),
            'PressureValues_psia': [14.695951,50.,150.,250.],
            'T2H_H2T_MaxTemperatureError_R': float(np.max(abs(tr_h-t))),
            'T2H_H2T_MaxEnthalpyResidual_Btu_lbm': h_residual,
            'PT2S_SP2T_MaxTemperatureError_R': worst_s_t,
            'PT2S_SP2T_MaxEntropyResidual_Btu_lbmR': worst_s,
            'WithinSourceInverseResidualTolerances': bool(h_residual <= 1e-3 and worst_s <= 1e-4),
            'NativeMEXParityExecuted': False,
        }


def build_compressor(lines, a2, thermo, constants):
    """Return (HPC, checks) from original A1 short branches and the A2 JSON record.

    lines: list of {'nc_percent':..., 'PRstatic':array, 'Wc':array}, Nc ascending.
    constants: Tstd, Pstd, Kps3, NgDesign; optional T2Reference_R,
               P2Reference_psia, FARReference, PstdBallin, T2Sensitivity_R.

    Map rows correspond to NcVec; columns correspond to RlineVec. Rline=1 is
    the maximum-pressure endpoint; Rline=3 is the minimum-pressure endpoint.
    No horizontal extension, speed extrapolation, or new surge line is inferred.
    """
    required = ('Tstd','Pstd','Kps3','NgDesign')
    if not all(k in constants for k in required):
        raise KeyError('constants must define Tstd, Pstd, Kps3 and NgDesign')
    tstd, pstd, kps3, ng_design = [float(constants[k]) for k in required]
    if not all(math.isfinite(v) and v > 0 for v in (tstd,pstd,kps3,ng_design)):
        raise ValueError('Reference constants must be finite and positive')
    tref = float(constants.get('T2Reference_R', tstd))
    pref = float(constants.get('P2Reference_psia', pstd))
    far = float(constants.get('FARReference', 0.0))
    pstd_ballin = float(constants.get('PstdBallin', 14.696))
    if tref <= 0 or pref <= 0 or pstd_ballin <= 0:
        raise ValueError('Thermodynamic reference pressure/temperature must be positive')
    if len(lines) != 11:
        raise ValueError('Eleven digitized A1 speed lines are required')
    nc_percent = np.array([float(line['nc_percent']) for line in lines])
    expected = np.array([65,80,82,85,87,89,92,94,96,98,100.])
    if not np.array_equal(nc_percent, expected):
        raise ValueError('A1 speed lines must be supplied in original ascending order')
    a2p = np.asarray(a2['points'], dtype=float)
    if a2p.ndim != 2 or a2p.shape[1] < 2 or not np.all(np.diff(a2p[:,0]) > 0):
        raise ValueError('A2 points must have strictly increasing pressure ratios')
    rline = np.linspace(1.,3.,11)
    flow_conversion = pstd / pstd_ballin
    wc_map = np.empty((11,11)); pr_map = np.empty_like(wc_map); eta_map = np.empty_like(wc_map)
    prstatic_map = np.empty_like(wc_map); tau_map = np.empty_like(wc_map)
    limits = np.empty((11,2)); node_rows = []; sensitivity_rows = []
    sensitivity_t = np.asarray(constants.get('T2Sensitivity_R',[507.2,508.,516.7,tref]),dtype=float)
    h_in = thermo.t2h(tref,far)
    s_in = thermo.pt2s(pref,tref,far)
    raw_wc_increase = 0.0

    def eta_at(pressure_ratio, tau, temperature):
        hi = thermo.t2h(temperature,far)
        si = thermo.pt2s(pref,temperature,far)
        tis = thermo.sp2t(si,pref*np.asarray(pressure_ratio),far)
        return (thermo.t2h(tis,far)-hi) / (thermo.t2h(temperature*np.asarray(tau),far)-hi)

    for i,line in enumerate(lines):
        x = np.asarray(line['PRstatic'], dtype=float).reshape(-1)
        w = np.asarray(line['Wc'], dtype=float).reshape(-1)
        if len(x) < 2 or len(x) != len(w) or not np.all(np.isfinite(x)) or not np.all(np.isfinite(w)):
            raise ValueError(f'Invalid A1 data at {nc_percent[i]} percent')
        order = np.argsort(x); x=x[order]; w=w[order]
        if not np.all(np.diff(x)>0) or not np.all(w>0):
            raise ValueError('A1 pressure ratios must be distinct and flows positive')
        if x[0] < a2p[0,0] or x[-1] > a2p[-1,0]:
            raise ValueError('A2 extrapolation would be required; not permitted')
        raw_wc_increase = max(raw_wc_increase,float(np.max(np.diff(w))))
        # A nondecreasing flow here would contradict the chosen short-branch domain.
        if np.any(np.diff(w) > 0):
            raise ValueError(f'Nonmonotone raw Wc at {nc_percent[i]} percent; clean explicitly first')
        limits[i,:] = [x[0],x[-1]]
        xgrid = x[-1] - (rline-1)*.5*(x[-1]-x[0])
        wgrid = np.interp(xgrid,x,w)*flow_conversion
        tau = np.interp(xgrid,a2p[:,0],a2p[:,1])
        pr = xgrid/kps3
        eta = np.asarray(eta_at(pr,tau,tref))
        if not np.all((eta>0)&(eta<=1)):
            raise ValueError('Reconstructed compressor efficiency is outside (0,1]')
        wc_map[i,:]=wgrid;pr_map[i,:]=pr;eta_map[i,:]=eta
        prstatic_map[i,:]=xgrid;tau_map[i,:]=tau

        native_r = 1+2*(x[-1]-x)/(x[-1]-x[0])
        native_pr = x/kps3
        native_tau = np.interp(x,a2p[:,0],a2p[:,1])
        native_eta = np.asarray(eta_at(native_pr,native_tau,tref))
        back_w = np.interp(native_r,rline,wgrid)
        back_pr = np.interp(native_r,rline,pr)
        back_eta = np.interp(native_r,rline,eta)
        ideal_t = thermo.sp2t(s_in,pref*native_pr,far)
        ideal_h = thermo.t2h(ideal_t,far)
        back_t = thermo.h2t(h_in+(ideal_h-h_in)/back_eta,far)
        node_rows.append(np.column_stack([
            np.full(len(x),nc_percent[i]),native_r,x,native_pr,w,w*flow_conversion,
            native_tau,native_eta,back_w-w*flow_conversion,back_pr-native_pr,
            back_eta-native_eta,back_t-tref*native_tau]))
        for temp in sensitivity_t:
            temp_eta = np.asarray(eta_at(native_pr,native_tau,float(temp)))
            temp_hi = thermo.t2h(temp,far)
            temp_si = thermo.pt2s(pref,temp,far)
            temp_tis = thermo.sp2t(temp_si,pref*native_pr,far)
            # Freeze efficiency at the reference map and compare to source A2.
            temp_his = thermo.t2h(temp_tis,far)
            frozen_t = thermo.h2t(temp_hi+(temp_his-temp_hi)/native_eta,far)
            sensitivity_rows.append([nc_percent[i],float(temp),float(np.max(abs(temp_eta-native_eta))),
                                     float(np.max(abs(frozen_t-temp*native_tau))),
                                     float(np.max(abs(frozen_t-temp*native_tau)/(temp*native_tau))*100)])

    nodes = np.vstack(node_rows); sensitivity = np.array(sensitivity_rows)
    roundtrip = thermo.self_check()
    HPC = {
        'NcVec': nc_percent/100., 'RlineVec': rline,
        'WcArray': wc_map, 'PRArray': pr_map, 'EffArray': eta_map,
        's_Nc': ng_design, 's_Wc': 1., 's_PR': 1., 's_eff': 1.,
        'WcMapSurge': wc_map[:,0].copy(), 'PRMapSurge': pr_map[:,0].copy(),
        'Source': 'Ballin NASA-TM-100991, Appendix A1/A2; digitized source data',
        'NcConvention': 'NcVec=N_Gc_percent/100; NcMap=Nmech/sqrt(T2/Tstd)/NgDesign',
        'RlineConvention': 'Rline=1 at largest PR/lowest Wc; Rline=3 at smallest PR/highest Wc',
        'TableOrientation': 'rows=NcVec, columns=RlineVec',
        'ThermoReferenceT2_R': tref, 'ThermoReferenceP2_psia': pref,
        'ThermoReferenceFAR': far, 'EfficiencyFrozenAtReferenceT2': True,
        'StaticToTotalPressureFactor': kps3,
        'BallinToTMATS_WcFactor': flow_conversion,
        'ValidPRstaticByNc': limits,
        'PRstaticArray': prstatic_map, 'TemperatureRatioArray': tau_map,
        'SurgeLineIsProxy': True, 'SurgeLineValidated': False,
        'SurgeMarginForValidation': False,
        'LowPRHorizontalExtensionIncluded': False,
        'MapBoundsMustBeCheckedAtRuntime': True,
        'ThermoImplementation': 'Installed C gas-table source replay; native-MEX runtime parity not executed',
    }
    checks = {
        'Shape': [11,11], 'SourceSpeedPercent': nc_percent,
        'TotalPRRange': [float(pr_map.min()),float(pr_map.max())],
        'WcRange_lbm_s': [float(wc_map.min()),float(wc_map.max())],
        'EfficiencyRange': [float(eta_map.min()),float(eta_map.max())],
        'NativeEfficiencyRange': [float(nodes[:,7].min()),float(nodes[:,7].max())],
        'NativeNodes': nodes,
        'NativeNodeColumns': ['NcPercent','Rline','PRstatic','PRtotal','WcBallin','WcTMATS',
                              'TemperatureRatio','Efficiency','WcBackError','PRBackError',
                              'EfficiencyBackError','TemperatureBackError_R'],
        'SourceNodeCount': len(nodes),
        'MaxBackInterpolationWcError_lbm_s': float(np.max(abs(nodes[:,8]))),
        'MaxBackInterpolationWcError_percent': float(np.max(abs(nodes[:,8])/nodes[:,5])*100),
        'MaxBackInterpolationPRError': float(np.max(abs(nodes[:,9]))),
        'MaxBackInterpolationEfficiencyError': float(np.max(abs(nodes[:,10]))),
        'MaxBackInterpolationTemperatureError_R': float(np.max(abs(nodes[:,11]))),
        'TemperatureSensitivity': sensitivity,
        'TemperatureSensitivityColumns': ['NcPercent','T2_R','MaxAbsEfficiencyDrift',
                                           'MaxFrozenEfficiencyTemperatureError_R',
                                           'MaxFrozenEfficiencyTemperatureError_percent'],
        'MaxTemperatureSensitivityEfficiencyDrift': float(np.max(sensitivity[:,2])),
        'MaxFrozenEfficiencyTemperatureError_R': float(np.max(sensitivity[:,3])),
        'A2ExtrapolationUsed': False, 'SpeedExtrapolationUsedInConstruction': False,
        'LowPRHorizontalExtensionIncluded': False,
        'SurgeLineIsProxy': True, 'SurgeLineValidated': False,
        'RlineWcNondecreasing': bool(np.all(np.diff(wc_map,axis=1)>=0)),
        'RlinePRDecreasing': bool(np.all(np.diff(pr_map,axis=1)<0)),
        'NcStrictlyIncreasing': bool(np.all(np.diff(nc_percent)>0)),
        'RawMaximumWcIncreaseAlongIncreasingPR': raw_wc_increase,
        'ThermoRoundTrip': roundtrip,
        'ThermoSources': thermo.source_info,
        'ThermoFormulas': thermo.formula_info,
        'RuntimeBoundaryBehavior': 'Installed interp2Ac clamps out-of-range inputs and emits only an initial warning; equilibrium acceptance must reject out-of-map states.',
        'Limitations': [
            'A1 digitized short branches only; original horizontal low-PR extensions are not reconstructed here.',
            'Efficiency frozen at reference inlet temperature/FAR; source T3/T2 is reproduced exactly only at that reference before map interpolation.',
            'Between-speed and Rline interpolation is numerical reconstruction, not additional experimental data.',
            'Rline=1 boundary is not an experimentally established surge line.',
        ],
    }
    if not (checks['RlineWcNondecreasing'] and checks['RlinePRDecreasing']
            and checks['NcStrictlyIncreasing'] and roundtrip['WithinSourceInverseResidualTolerances']):
        raise ValueError('Compressor reconstruction quality checks failed')
    return HPC, checks


def _compressor_case_coverage(hpc, strict_hpc, cases, constants):
    """Check supplied operating coordinates; never use them to alter a map.

    Each case is a dict with CaseID, Ng_rpm, T2_R, P2_psia and P3_psia. The
    project's comparison convention treats P3 as total discharge pressure.
    """
    nc_grid = np.asarray(hpc['NcVec'])
    r_grid = np.asarray(hpc['RlineVec'])
    pr_grid = np.asarray(hpc['PRstaticArray'])
    strict_limits = np.asarray(strict_hpc['ValidPRstaticByNc'])
    rows = []
    for case in cases:
        ng = float(case['Ng_rpm']); t2 = float(case['T2_R'])
        p2 = float(case['P2_psia']); p3 = float(case['P3_psia'])
        if not all(math.isfinite(v) and v > 0 for v in (ng,t2,p2,p3)):
            raise ValueError('Coverage-case speeds, temperatures and pressures must be positive')
        nc = ng / math.sqrt(t2/float(constants['Tstd'])) / float(constants['NgDesign'])
        x = float(constants['Kps3']) * p3 / p2
        speed_ok = bool(nc_grid[0] <= nc <= nc_grid[-1])
        covered = strict_ok = False
        r = float('nan')
        if speed_ok:
            line = np.array([np.interp(nc,nc_grid,pr_grid[:,j]) for j in range(len(r_grid))])
            covered = bool(line[-1] <= x <= line[0])
            lo = np.interp(nc,nc_grid,strict_limits[:,0])
            hi = np.interp(nc,nc_grid,strict_limits[:,1])
            strict_ok = bool(lo <= x <= hi)
            if covered:
                r = float(np.interp(x,line[::-1],r_grid[::-1]))
        rows.append([float(case['CaseID']),100*nc,x,r,float(speed_ok),
                     float(covered),float(strict_ok),float(covered and not strict_ok)])
    matrix = np.asarray(rows,dtype=float).reshape((-1,8))
    return {
        'Rows': matrix,
        'Columns': ['CaseID','CorrectedNgPercent','PRstatic','Rline','SpeedInRange',
                    'ExtendedDomainCovered','StrictShortBranchCovered','LowPRExtensionRequired'],
        'CaseCount': len(rows),
        'AllProvidedCasesCovered': bool(len(rows) > 0 and np.all(matrix[:,5] == 1)),
        'UsedToFitOrAdjustMap': False,
        'P3Convention': 'Case P3 is treated as total; PRstatic=Kps3*P3/P2',
        'Purpose': 'Coordinate-domain coverage only, not a performance-error validation.',
    }


def build_compressor_extended(lines, a2, thermo, constants):
    """Add an explicit constant-flow low-PR engineering adaptation to the map.

    The original Figure A1 visibly contains horizontal low-pressure-ratio
    segments. Their exact plateau amplitudes and transition locations were not
    independently digitized in the 66 selected short-branch nodes. This adapter
    estimates each plateau from that line's first selected (lowest-PR) node:
    Wc is constant on PRstatic in [1, first selected PRstatic]. No node is moved
    and no experimental performance values are used to set that estimate.

    Rline 1..2 contains the unchanged strict 11-column short branch; Rline
    2.1..3 contains 10 low-PR plateau columns. Optional constants['LewisCases']
    supplies coverage-only case dicts; see _compressor_case_coverage.
    """
    short, short_checks = build_compressor(lines,a2,thermo,constants)
    rline = np.r_[np.linspace(1.,2.,11),np.linspace(2.1,3.,10)]
    a2p = np.asarray(a2['points'],dtype=float)
    if not a2p[0,0] <= 1.0 <= a2p[-1,0]:
        raise ValueError('A2 does not support PRstatic=1; low-PR adaptation is prohibited')
    kps3 = float(constants['Kps3'])
    tref = float(short['ThermoReferenceT2_R'])
    pref = float(short['ThermoReferenceP2_psia'])
    far = float(short['ThermoReferenceFAR'])
    source_limits = np.asarray(short['ValidPRstaticByNc'])
    if np.any(source_limits[:,0] <= 1):
        raise ValueError('The requested low-PR plateau must start below the selected short branch')
    arrays = {}
    for key in ('WcArray','PRArray','EffArray','PRstaticArray','TemperatureRatioArray'):
        arrays[key] = np.empty((11,21))
        arrays[key][:,:11] = short[key]
    hi = thermo.t2h(tref,far)
    si = thermo.pt2s(pref,tref,far)
    for i,line in enumerate(lines):
        transition = source_limits[i,0]
        x = transition - (rline[11:]-2)*(transition-1.0)
        tau = np.interp(x,a2p[:,0],a2p[:,1])
        pr = x/kps3
        t_is = thermo.sp2t(si,pref*pr,far)
        eta = (thermo.t2h(t_is,far)-hi)/(thermo.t2h(tref*tau,far)-hi)
        if not np.all(np.isfinite(eta)) or not np.all((eta>0)&(eta<=1)):
            raise ValueError('Low-PR adaptation has nonphysical efficiency')
        arrays['WcArray'][i,11:] = short['WcArray'][i,-1]
        arrays['PRArray'][i,11:] = pr
        arrays['EffArray'][i,11:] = eta
        arrays['PRstaticArray'][i,11:] = x
        arrays['TemperatureRatioArray'][i,11:] = tau

    hpc = dict(short)
    hpc.update(arrays)
    hpc['RlineVec'] = rline
    hpc['ValidPRstaticByNc'] = np.column_stack([np.ones(11),source_limits[:,1]])
    hpc['SelectedShortBranchPRstaticByNc'] = source_limits.copy()
    hpc['LowPRExtensionPRstaticByNc'] = np.column_stack([np.ones(11),source_limits[:,0]])
    hpc['EstimatedPlateauWcTMATS'] = short['WcArray'][:,-1].copy()
    hpc['EstimatedPlateauWcBallin'] = hpc['EstimatedPlateauWcTMATS']/short['BallinToTMATS_WcFactor']
    hpc['LowPRHorizontalExtensionIncluded'] = True
    hpc['LowPRExtensionIsEngineeringAdaptation'] = True
    hpc['LowPRExtensionUsesExperimentalPerformanceFit'] = False
    hpc['HighPRExtensionIncluded'] = False
    hpc['RlineConvention'] = (
        '1..2: unchanged short branch, high PR to first selected low-PR node; '
        '2..3: constant-Wc estimated plateau down to PRstatic=1'
    )
    hpc['LowPRExtensionDefinition'] = (
        'Horizontal shape is visible in original Figure A1; amplitude and junction '
        'are estimated from each line\'s first selected short-branch node. '
        'This is an engineering adaptation, not independently digitized new data.'
    )
    same_short = all(np.array_equal(hpc[k][:,:11],short[k]) for k in arrays)
    flow_ok = bool(np.all(np.diff(hpc['WcArray'],axis=1)>=0))
    pressure_ok = bool(np.all(np.diff(hpc['PRArray'],axis=1)<0))
    flat_ok = bool(np.all(hpc['WcArray'][:,11:] == hpc['WcArray'][:,10,None]))
    if not (same_short and flow_ok and pressure_ok and flat_ok):
        raise ValueError('Extended compressor domain checks failed')

    sensitivity = []
    sensitivity_t = np.asarray(constants.get('T2Sensitivity_R',[507.2,508.,516.7,tref]),dtype=float)
    for i,nc in enumerate(np.asarray(short_checks['SourceSpeedPercent'])):
        pr = hpc['PRArray'][i,:]
        tau = hpc['TemperatureRatioArray'][i,:]
        eta_ref = hpc['EffArray'][i,:]
        for temp in sensitivity_t:
            temp_hi = thermo.t2h(temp,far)
            temp_si = thermo.pt2s(pref,temp,far)
            temp_tis = thermo.sp2t(temp_si,pref*pr,far)
            temp_his = thermo.t2h(temp_tis,far)
            eta_actual = (temp_his-temp_hi)/(thermo.t2h(temp*tau,far)-temp_hi)
            frozen_temp = thermo.h2t(temp_hi+(temp_his-temp_hi)/eta_ref,far)
            sensitivity.append([nc,float(temp),float(np.max(abs(eta_actual-eta_ref))),
                                float(np.max(abs(frozen_temp-temp*tau))),
                                float(np.max(abs(frozen_temp-temp*tau)/(temp*tau))*100)])
    sensitivity = np.array(sensitivity)
    native = np.asarray(short_checks['NativeNodes']).copy()
    native[:,1] = (native[:,1]+1)/2
    checks = dict(short_checks)
    checks.update({
        'Shape': [11,21], 'MapGridNodeCount': 231,
        'TotalPRRange': [float(hpc['PRArray'].min()),float(hpc['PRArray'].max())],
        'WcRange_lbm_s': [float(hpc['WcArray'].min()),float(hpc['WcArray'].max())],
        'EfficiencyRange': [float(hpc['EffArray'].min()),float(hpc['EffArray'].max())],
        'NativeNodes': native,
        'LowPRHorizontalExtensionIncluded': True,
        'LowPRExtensionIsEngineeringAdaptation': True,
        'ShortBranchMatchesStrictExactly': same_short,
        'LowPRPlateauIsExactlyConstantWc': flat_ok,
        'RlineWcNondecreasing': flow_ok,
        'RlinePRDecreasing': pressure_ok,
        'HighPRExtensionIncluded': False,
        'PressureBelowOneStaticRatioSupported': False,
        'A2ExtrapolationUsed': False,
        'TemperatureSensitivity': sensitivity,
        'TemperatureSensitivityScope': 'All 231 extended-grid nodes; source-node interpolation checks retain the unchanged strict short branch.',
        'MaxTemperatureSensitivityEfficiencyDrift': float(np.max(sensitivity[:,2])),
        'MaxFrozenEfficiencyTemperatureError_R': float(np.max(sensitivity[:,3])),
        'ShortBranchDomain': source_limits.copy(),
        'ExtendedDomain': hpc['ValidPRstaticByNc'].copy(),
        'PlateauAmplitudeAndJunctionIndependentlyDigitized': False,
        'PlatformSource': hpc['LowPRExtensionDefinition'],
        'ExperimentalPerformanceUsedToAdjustMap': False,
        'Limitations': [
            'Original Figure A1 supports the horizontal shape, but platform amplitude and junction are estimates from the first selected node.',
            'Original 66 nodes are preserved. Added low-PR values are engineering reconstruction, not additional experimental observations.',
            'No upper-pressure or corrected-speed extrapolation is supplied. Reject out-of-domain runtime states even if the installed interpolation clamps.',
            'Efficiency is frozen at the reference temperature/FAR, including the low-efficiency low-PR region.',
            'Rline=1 remains a boundary proxy, not a validated physical surge line.',
        ],
    })
    cases = constants.get('LewisCases',[])
    if cases is None:
        cases = []
    checks['LewisCoverage'] = _compressor_case_coverage(hpc,short,cases,constants)
    return hpc, checks


if __name__ == '__main__':
    gas = ThermoTMATS()
    print(json.dumps(gas.self_check(),indent=2))
