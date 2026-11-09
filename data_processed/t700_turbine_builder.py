"""Reference-condition adapters from Ballin A7--A10 to ordinary T-MATS maps.

Repeated Nc rows are interface support rows, not measured turbine speed lines.
The maps freeze inlet temperature, FAR and (for the FPT flow) an exhaust factor.
No model, cooling routing, source samples, or experimental cases are modified.
"""
from __future__ import annotations

import math
import numpy as np


def _number(constants, name, default=None):
    value = constants.get(name, default)
    if value is None:
        raise KeyError(f"Missing turbine-builder constant: {name}")
    value = float(value)
    if not math.isfinite(value):
        raise ValueError(f"Non-finite turbine-builder constant: {name}")
    return value


def _source(curves, key):
    data = np.asarray(curves[key]["points"], dtype=float)
    if data.ndim != 2 or data.shape[1] < 2 or len(data) < 2:
        raise ValueError(f"{key}: expected original [x,y,...] point rows")
    x, y = data[:, 0], data[:, 1]
    if not np.isfinite(data[:, :2]).all() or not (np.diff(x) > 0).all():
        raise ValueError(f"{key}: source abscissae must be finite and increasing")
    return x, y


def _interp(x, source, label):
    xp, yp = source
    q = np.asarray(x, dtype=float)
    tolerance = 1e-12 * max(1., abs(xp[0]), abs(xp[-1]))
    if np.any(q < xp[0] - tolerance) or np.any(q > xp[-1] + tolerance):
        raise ValueError(f"{label}: source-domain extrapolation is not permitted")
    return np.interp(q, xp, yp)


def _positive_limit(source, low, high):
    """Positive-energy interval connected to the low-ratio end."""
    xp, _ = source
    knots = np.unique(np.r_[low, xp[(xp > low) & (xp < high)], high])
    values = _interp(knots, source, "energy positive-domain check")
    if values[0] <= 0:
        raise ValueError("Low pressure-ratio end has no positive source work")
    for j in range(1, len(knots)):
        if values[j] <= 0:
            root = knots[j-1] - values[j-1] * (
                knots[j]-knots[j-1]) / (values[j]-values[j-1])
            return float(root-max(1e-9, 1e-7*(high-low))), float(root)
    return float(high), None


def _scalar(result):
    a = np.asarray(result, dtype=float)
    if a.size != 1 or not np.isfinite(a).all():
        raise ValueError("Thermodynamic function returned a non-finite scalar")
    return float(a.reshape(-1)[0])


def _ideal_drop(thermo, temperature, far, pressure, pr):
    inlet_h = _scalar(thermo.t2h(float(temperature), float(far)))
    inlet_s = _scalar(thermo.pt2s(float(pressure), float(temperature), float(far)))
    result = []
    for ratio in np.atleast_1d(pr):
        ideal_t = _scalar(thermo.sp2t(inlet_s, float(pressure/ratio), float(far)))
        result.append(inlet_h-_scalar(thermo.t2h(ideal_t, float(far))))
    result = np.asarray(result)
    if not (result > 0).all():
        raise ValueError("Non-positive ideal turbine enthalpy drop")
    return result


def _relative_error(predicted, actual, floor_fraction=0.):
    predicted, actual = np.asarray(predicted), np.asarray(actual)
    denominator = np.maximum(abs(actual), float(floor_fraction)*np.max(abs(actual)))
    error = (predicted-actual)/np.maximum(denominator, np.finfo(float).tiny)
    return dict(MaxAbsPercent=float(100*np.max(abs(error))),
                RMSPercent=float(100*np.sqrt(np.mean(error*error))))


def _component(kind, source_energy, source_flow, thermo, values, nc_rows,
               reference_f10, ratio_mode, reference_pr):
    is_gt = kind == "HPT"
    temperature = values["T41"] if is_gt else values["T45"]
    pressure = values["P41"] if is_gt else values["P45"]
    far = values["FARgt"] if is_gt else values["FARpt"]
    design_n = values["NgDesign"] if is_gt else values["NpDesign"]
    mechanical_n = values["NgTrim"] if is_gt else values["NpTrim"]
    theta = values["a"]*temperature+values["b"]
    low, high = float(source_energy[0][0]), float(source_energy[0][-1])
    if not is_gt:
        multiplier = reference_f10 if ratio_mode == "figure_ambient" else 1.
        low = max(low, multiplier*source_flow[0][0])
        high = min(high, multiplier*source_flow[0][-1])
    if not low < high:
        raise ValueError(f"{kind}: energy/flow source domains do not intersect")
    high, energy_zero = _positive_limit(source_energy, low, high)
    mathematical_positive_high = high
    if not is_gt and values["FPTMinimumPR"] > 0:
        high = min(high, 1./values["FPTMinimumPR"])
    if not low < high:
        raise ValueError(f"{kind}: no common positive-work source domain")
    ratios = np.linspace(1./high, 1./low, values["GridCount"])
    original_r = source_energy[0]
    original_r = original_r[(original_r >= low) & (original_r <= high)]
    additions = list(1./original_r)
    if not is_gt:
        multiplier = reference_f10 if ratio_mode == "figure_ambient" else 1.
        rf = source_flow[0]*multiplier
        additions.extend(1./rf[(rf >= low) & (rf <= high)])
    if ratios[0] <= reference_pr <= ratios[-1]:
        additions.append(reference_pr)
    ratios = np.unique(np.r_[ratios, additions])

    def source_at(pr, temp, f10=reference_f10):
        r = 1./np.asarray(pr)
        thermal = values["a"]*float(temp)+values["b"]
        dh = thermal*_interp(r, source_energy, f"{kind} energy")
        if is_gt:
            wf = np.full_like(r, values["KWGT"], dtype=float)
        else:
            rf = r/f10 if ratio_mode == "figure_ambient" else r
            wf = _interp(rf, source_flow, "FPT flow")
        wc = wf*values["Pstd"]*math.sqrt(temp/values["Tstd"])/math.sqrt(thermal)
        return wc, dh

    wc, dh = source_at(ratios, temperature)
    ideal = _ideal_drop(thermo, temperature, far, pressure, ratios)
    efficiency = dh/ideal
    admissible = (efficiency > 0) & (efficiency <= 1.)
    if not admissible.all():
        # Restrict the derived adapter; never silently clip source efficiency.
        indices = np.flatnonzero(admissible)
        if not len(indices):
            raise ValueError(f"{kind}: no physical reference-efficiency interval")
        groups = np.split(indices, np.flatnonzero(np.diff(indices) != 1)+1)
        preferred = [g for g in groups if ratios[g[0]] <= reference_pr <= ratios[g[-1]]]
        chosen = max(preferred or groups, key=len)
        if len(chosen) < 3:
            raise ValueError(f"{kind}: physical reference-efficiency domain too short")
        excluded = ratios[~admissible].tolist()
        ratios, wc, dh, ideal, efficiency = (
            a[chosen] for a in (ratios, wc, dh, ideal, efficiency))
    else:
        excluded = []
    if not ratios[0] <= reference_pr <= ratios[-1]:
        raise ValueError(f"{kind}: the reference trim PR is outside the derived map domain")
    # Resolve curved eta(PR) near the low-work limit rather than clipping it.
    # The target uses a 1%-of-full-scale denominator floor, so an almost-zero
    # source enthalpy drop does not demand unbounded relative accuracy.
    initial_grid_count = len(ratios)
    refinement_passes = 0
    for refinement_passes in range(9):
        middle = .5*(ratios[:-1]+ratios[1:])
        expected_wcm, expected_dhm = source_at(middle, temperature)
        ideal_m = _ideal_drop(thermo, temperature, far, pressure, middle)
        read_wcm = np.interp(middle, ratios, wc)
        read_dhm = np.interp(middle, ratios, efficiency)*ideal_m
        floor = .01*max(float(np.max(abs(dh))), np.finfo(float).tiny)
        bad = (abs(read_dhm-expected_dhm) >
               .001*np.maximum(abs(expected_dhm), floor))
        bad |= abs(read_wcm-expected_wcm) > .001*abs(expected_wcm)
        if not bad.any() or refinement_passes == 8:
            break
        ratios = np.unique(np.r_[ratios, middle[bad]])
        wc, dh = source_at(ratios, temperature)
        ideal = _ideal_drop(thermo, temperature, far, pressure, ratios)
        efficiency = dh/ideal
        if not ((efficiency > 0) & (efficiency <= 1.)).all():
            raise ValueError(f"{kind}: adaptive reference efficiency became nonphysical")
    scale_n = design_n/math.sqrt(temperature/values["Tstd"])
    meta = dict(
        Source="Ballin NASA-TM-100991, equations 25-38 / Appendix A",
        Adapter="Frozen temperature and FAR; no-cooling single-component reference",
        ReferenceTemperature_R=float(temperature), ReferencePressure_psia=float(pressure),
        ReferenceFAR=float(far), ReferenceMechanicalSpeed_rpm=float(mechanical_n),
        ReferenceCorrectedSpeed_rpm=float(mechanical_n/math.sqrt(temperature/values["Tstd"])),
        ReferenceNcMap=float(mechanical_n/design_n),
        ReferencePR=float(reference_pr), ReferenceTheta=float(theta),
        NcRowsRepeated=True, MeasuredSpeedSurfaceAvailable=False,
        NcGridCoverageIsNotPhysicalValidation=True, CoolingEnabledInReference=False,
        SourceRatio="P45/P41" if is_gt else "P49/P45 for energy",
        FlowRatioMode="choked_GGT" if is_gt else ratio_mode,
        FrozenExhaustFactor=float(reference_f10),
        DomainPolicy=("Source common positive-work domain" if is_gt or values["FPTMinimumPR"] <= 0
                      else f"Ordinary positive-work adapter requires PR >= {values['FPTMinimumPR']:g}"),
        MinimumPRPolicy=float(values["FPTMinimumPR"]) if not is_gt else 0.,
        MathematicalPositiveEnergyUpperRatio=float(mathematical_positive_high),
        AdaptedEnergyUpperRatio=float(high),
        RawNegativeEnergyTailPreserved=True,
        SourceEnergyZeroExists=energy_zero is not None,
        SourceEnergyZeroRatio=float(energy_zero) if energy_zero is not None else 0.,
        Generated=True, WholeEngineValidated=False)
    if not is_gt:
        meta["AmbientFlowInterpretation"] = (
            "Figure A9 Ps9/P45 and Novikov PDF43 Eq2.40; Ballin Eq33 differs")
        meta["FlowRatioFrozenCoupling"] = (
            "r_flow=(1/PR)/f10Ref; f10 depends on GGT speed, not FPT Nc")
        meta["FPTSpeedAssumption"] = (
            "Speed effect neglected near governed design speed; repeated rows do not validate low speed")
    component = dict(NcVec=nc_rows.tolist(), PRVec=ratios.tolist(),
                     WcArray=np.tile(wc, (len(nc_rows), 1)).tolist(),
                     EffArray=np.tile(efficiency, (len(nc_rows), 1)).tolist(),
                     s_Nc=float(scale_n), s_Wc=1., s_PR=1., s_eff=1., Meta=meta)

    # No coolant; the same T-MATS thermal calls are used in reconstruction.
    midpoint = .5*(ratios[:-1]+ratios[1:])
    expected_wc, expected_dh = source_at(midpoint, temperature)
    map_wc = np.interp(midpoint, ratios, wc)
    map_eff = np.interp(midpoint, ratios, efficiency)
    map_dh = map_eff*_ideal_drop(thermo, temperature, far, pressure, midpoint)
    check = dict(
        ReferenceStateSource="Ballin Appendix B Table B.1 trim 1, PDF67",
        MapShape=[len(nc_rows), len(ratios)],
        PRRange=[float(ratios[0]), float(ratios[-1])],
        WcRange_lbm_s=[float(wc.min()), float(wc.max())],
        EfficiencyRange=[float(efficiency.min()), float(efficiency.max())],
        ExcludedPRDueToReferenceEfficiency=excluded,
        DomainPolicy=meta["DomainPolicy"],
        ExcludedSourceEnergyTailPoints=[
            [float(x),float(y)] for x,y in zip(*source_energy) if x > high],
        ExcludedPositiveEnergyRatioInterval=(
            [float(high),float(mathematical_positive_high)]
            if high < mathematical_positive_high else []),
        InitialPRGridCount=int(initial_grid_count),
        AdaptiveRefinementPasses=int(refinement_passes),
        MidpointErrorTargetPercent=.1,
        RawNegativeTailNotClipped=True,
        ReferenceNodeWcMaxAbsError=float(np.max(abs(wc-source_at(ratios, temperature)[0]))),
        ReferenceNodeDhMaxAbsError_Btu_lbm=float(np.max(abs(efficiency*ideal-dh))),
        MidpointWcError=_relative_error(map_wc, expected_wc),
        MidpointDhError=_relative_error(map_dh, expected_dh, .01),
        MidpointDhMaxAbsError_Btu_lbm=float(np.max(abs(map_dh-expected_dh))),
        MidpointDhMaxFullScalePercent=float(
            100*np.max(abs(map_dh-expected_dh))/np.max(abs(dh))),
        RelativeDhErrorDenominatorFloor="1 percent of maximum source enthalpy drop",
        SensitivityIsSampledNotExperimentalValidation=True)
    if ratios[0] <= reference_pr <= ratios[-1]:
        rwc, rdh = source_at([reference_pr], temperature)
        ri = _ideal_drop(thermo, temperature, far, pressure, [reference_pr])[0]
        mass = rwc[0]*pressure/values["Pstd"]/math.sqrt(temperature/values["Tstd"])
        power = mass*rdh[0]*1.414853
        inlet_h = _scalar(thermo.t2h(temperature, far))
        check["ReferencePoint"] = dict(
            PR=float(reference_pr), CorrectedFlow_lbm_s=float(rwc[0]),
            ActualFlow_lbm_s=float(mass), DeltaH_Btu_lbm=float(rdh[0]),
            InletEnthalpy_Btu_lbm=float(inlet_h),
            OutletEnthalpy_Btu_lbm=float(inlet_h-rdh[0]),
            IdealEnthalpyDrop_Btu_lbm=float(ri),
            Efficiency=float(rdh[0]/ri), Power_hp=float(power),
            Torque_lbf_ft=float(5252.113*power/mechanical_n),
            OutletTemperature_R=_scalar(thermo.h2t(inlet_h-rdh[0], far)))
    sweep_pr = np.linspace(ratios[0], ratios[-1], values["SensitivityCount"])
    sweeps = []
    cases = [("temperature", temperature*q, far, reference_f10) for q in (.85, 1., 1.15)]
    cases += [("FAR", temperature, q, reference_f10) for q in
              sorted(set([max(0., far-.005), far, far+.005]))]
    if not is_gt and ratio_mode == "figure_ambient":
        cases += [("exhaust_factor", temperature, far, f) for f in values["F10Sweep"]]
    for parameter, temp, local_far, f10 in cases:
        pr = sweep_pr.copy()
        if not is_gt:
            rf = (1./pr)/f10 if ratio_mode == "figure_ambient" else 1./pr
            pr = pr[(rf >= source_flow[0][0]) & (rf <= source_flow[0][-1])]
        if not len(pr):
            sweeps.append(dict(Parameter=parameter, Temperature_R=float(temp),
                               FAR=float(local_far), ExhaustFactor=float(f10), SampleCount=0,
                               Note="No common source domain; no extrapolation performed"))
            continue
        target_wc, target_dh = source_at(pr, temp, f10)
        calculated_wc = np.interp(pr, ratios, wc)
        calculated_dh = np.interp(pr, ratios, efficiency)*_ideal_drop(
            thermo, temp, local_far, pressure, pr)
        sweeps.append(dict(Parameter=parameter, Temperature_R=float(temp),
                           FAR=float(local_far), ExhaustFactor=float(f10),
                           SampleCount=len(pr), ExcludedSampleCount=len(sweep_pr)-len(pr),
                           CorrectedFlowError=_relative_error(calculated_wc, target_wc),
                           EnthalpyDropError=_relative_error(calculated_dh, target_dh, .01)))
    check["SeparateParameterSensitivitySweeps"] = sweeps
    check["CombinedParameterCornersNotClaimed"] = True
    return component, check


def build_turbines(curves, thermo, constants):
    """Return (HPT, FPT, checks) as serializable dictionaries and lists.

    Ordinary T-MATS standard-day corrected values, normalized Nc rows, and unity
    pressure/flow/efficiency scalars are used. Only the speed scalar is nonunity.
    """
    energy_gt = _source(curves, "A07")
    energy_pt = _source(curves, "A08")
    flow_pt = _source(curves, "A09")
    exhaust = _source(curves, "A10")
    values = dict(
        Tstd=_number(constants, "Tstd", 518.67),
        Pstd=_number(constants, "Pstd", 14.695951),
        NgDesign=_number(constants, "NgDesign", 44700.),
        NpDesign=_number(constants, "NpDesign", 20900.),
        NgTrim=_number(constants, "TrimNg", 41638.),
        NpTrim=_number(constants, "TrimNp", 20895.),
        T41=_number(constants, "TrimT41", 2292.),
        T45=_number(constants, "TrimT45", 1632.),
        P41=_number(constants, "TrimP41", 174.28),
        P45=_number(constants, "TrimP45", 37.42),
        KWGT=_number(constants, "KWGT", .0876),
        a=_number(constants, "KTH_a", .0018326),
        b=_number(constants, "KTH_b", .0856),
        GridCount=int(_number(constants, "TurbinePRGridCount", 81)),
        SensitivityCount=int(_number(constants, "TurbineSensitivityCount", 41)))
    minimum_pr = constants.get("FPTMinimumPR",1.25)
    values["FPTMinimumPR"] = 0. if minimum_pr is None else float(minimum_pr)
    if not math.isfinite(values["FPTMinimumPR"]) or values["FPTMinimumPR"] < 0:
        raise ValueError("FPTMinimumPR must be None, zero or a finite positive ratio")
    if 0 < values["FPTMinimumPR"] <= 1:
        raise ValueError("A positive FPTMinimumPR must exceed one")
    if values["GridCount"] < 10 or values["SensitivityCount"] < 5:
        raise ValueError("Turbine adapter grids are too short")
    theta_gt = values["a"]*values["T41"]+values["b"]
    core_flow = values["KWGT"]*values["P41"]/math.sqrt(theta_gt)
    fuel = _number(constants, "TrimFuel_lb_h", 476.3)/3600.
    derived_far = fuel/(core_flow-fuel)
    values["FARgt"] = _number(constants, "FARref", derived_far)
    values["FARpt"] = _number(constants, "FPTFARref", values["FARgt"])
    if min(values["FARgt"], values["FARpt"]) < 0:
        raise ValueError("Reference FAR must be nonnegative")
    t2 = _number(constants, "TrimT2", values["Tstd"])
    ngc_percent = 100*values["NgTrim"]/math.sqrt(t2/values["Tstd"])/values["NgDesign"]
    f10ref = float(_interp(ngc_percent, exhaust, "A10 reference exhaust factor"))
    if f10ref < 1.:
        raise ValueError("A10 factor must follow Eq.38 P49/Ps9, greater than one")
    values["F10Sweep"] = sorted(set([float(exhaust[1].min()), f10ref, float(exhaust[1].max())]))
    rows = np.asarray(constants.get("TurbineNcVec", [.50, .65, .80, .90, 1., 1.10, 1.20]), dtype=float)
    if rows.ndim != 1 or len(rows) < 2 or not (np.diff(rows) > 0).all():
        raise ValueError("Normalized turbine Nc rows must increase")
    gt, gt_checks = _component("HPT", energy_gt, None, thermo, values, rows,
                               f10ref, "choked_GGT", values["P41"]/values["P45"])
    pr_pt = values["P45"]/(values["Pstd"]*f10ref)
    pt, pt_checks = _component("FPT", energy_pt, flow_pt, thermo, values, rows,
                               f10ref, "figure_ambient", pr_pt)
    ratio = np.asarray(pt["PRVec"])
    factor = values["Pstd"]*math.sqrt(values["T45"]/values["Tstd"])/math.sqrt(
        values["a"]*values["T45"]+values["b"])
    alt_mask = (1./ratio >= flow_pt[0][0]) & (1./ratio <= flow_pt[0][-1])
    alt_ratio = ratio[alt_mask]
    alternative = factor*_interp(1./alt_ratio, flow_pt, "A9 equation alternative")
    primary = np.asarray(pt["WcArray"])[0, alt_mask]
    pt_checks["EquationAlternative"] = dict(
        Interpretation="Ballin Eq.33 P49/P45 instead of Figure A9 Ps9/P45",
        PRVec=alt_ratio.tolist(), StandardWc_lbm_s=alternative.tolist(),
        DifferenceFromFigureAmbient=_relative_error(alternative, primary),
        AlternativeNotAppliedToPrimaryMap=True)
    checks = dict(
        HPT=gt_checks, FPT=pt_checks,
        ReferenceConstants={k: v for k, v in values.items() if k != "F10Sweep"},
        DerivedGGTReferenceFAR=float(derived_far), ReferenceFARWasProvided="FARref" in constants,
        ReferenceFuelFlow_lbm_s=float(fuel),
        FPTFARIsSameAsGGTUnlessProvided="FPTFARref" not in constants,
        CorrectedGasGeneratorPercent=float(ngc_percent), FrozenExhaustFactor=float(f10ref),
        ReferenceP49_psia=float(values["Pstd"]*f10ref),
        SourcePressureConventionConflictPreserved=True,
        SourceFlowUnitConventionConversionExplicit=True,
        ModelCoolingRoutingNotImplementedByBuilder=True,
        SourceKH45NotAppliedToTMATSAbsoluteEnthalpy=True,
        WholeEngineConvergenceChecked=False, ExperimentalCalibrationPerformed=False,
        Notes=[
            "Both adapters freeze inlet temperature and FAR at documented reference values.",
            "FPT also freezes f10, which depends on GGT speed, not FPT Nc.",
            "Nc rows are repeated support rows, not measured turbine speed lines.",
            "Reference and sensitivity checks are for uncooled single components only.",
            "Standard T-MATS exit mixing is not Ballin's empirical H45=0.9623*H44.",
            "No source extrapolation or negative-tail clipping was used."])
    return gt, pt, checks
