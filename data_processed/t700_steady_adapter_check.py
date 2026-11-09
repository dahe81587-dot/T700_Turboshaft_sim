"""Independent steady component-chain replay of installed ordinary T-MATS code.

This evaluates the requested adapter topology, not an mdl/slx or Simulink solver.
Sources: Compressor_TMATS_body.c, Burner_TMATS_body.c, Turbine_TMATS_body.c,
interp2Ac_TMATS.c, and Lib_Turbo_Shaft_TMATS.mdl. iDesign is off-design,
ConfigNPSS=0, fractional bleeds enabled, GGT third-bleed injection at exit.
"""
from __future__ import annotations

import math
import numpy as np

PSTD = 14.695951
TSTD = 518.67
BTU_SEC_TO_HP = 1.414853
HP_RPM_TO_TORQUE = 5252.113


def _f(x):
    value = float(np.asarray(x).reshape(-1)[0])
    if not math.isfinite(value):
        raise ValueError("Non-finite thermodynamic result")
    return value


def _stream(w, h, t, p, far):
    values = [w, h, t, p, far]
    if not all(math.isfinite(float(v)) for v in values):
        raise ValueError("Non-finite gas-path station")
    if w <= 0 or t <= 0 or p <= 0 or far < 0:
        raise ValueError("Non-positive mass flow, temperature or pressure, or negative FAR")
    return dict(W=float(w), H=float(h), T=float(t), P=float(p), FAR=float(far),
                W_lbm_s=float(w), h_Btu_lbm=float(h), T_R=float(t), P_psia=float(p))


def _table(component, xname, yname, zname, x, y):
    """The same boundary clamping and bilinear ordering as interp2Ac."""
    xv = np.asarray(component[xname], dtype=float).reshape(-1)
    yv = np.asarray(component[yname], dtype=float).reshape(-1)
    z = np.asarray(component[zname], dtype=float)
    if len(xv) < 2 or len(yv) < 2 or z.shape != (len(yv), len(xv)):
        raise ValueError(f"Map dimensions do not match {xname}/{yname}: {zname}")
    if not (np.diff(xv) > 0).all() or not (np.diff(yv) > 0).all():
        raise ValueError("Map axes are not strictly increasing")
    clamped = bool(x < xv[0] or x > xv[-1] or y < yv[0] or y > yv[-1])
    xx = float(np.clip(x, xv[0], xv[-1]))
    yy = float(np.clip(y, yv[0], yv[-1]))
    i = int(np.clip(np.searchsorted(xv, xx, side="right")-1, 0, len(xv)-2))
    j = int(np.clip(np.searchsorted(yv, yy, side="right")-1, 0, len(yv)-2))
    fx = (xx-xv[i])/(xv[i+1]-xv[i])
    fy = (yy-yv[j])/(yv[j+1]-yv[j])
    z1 = z[j, i]+fx*(z[j, i+1]-z[j, i])
    z2 = z[j+1, i]+fx*(z[j+1, i+1]-z[j+1, i])
    value = float(z1+fy*(z2-z1))
    if not math.isfinite(value):
        raise ValueError("Non-finite map interpolation")
    return value, dict(InRange=not clamped, InterpolationClamped=clamped,
                       XInput=float(x), YInput=float(y),
                       XRange=[float(xv[0]), float(xv[-1])],
                       YRange=[float(yv[0]), float(yv[-1])],
                       XAxis=xname, YAxis=yname)


def _compressor(c, inlet, rline, speed, thermo):
    wi, ti, pi, far = (inlet[k] for k in ("W", "T", "P", "FAR"))
    hi = _f(thermo.t2h(ti, far))
    si = _f(thermo.pt2s(pi, ti, far))
    theta, delta = ti/TSTD, pi/PSTD
    wc_in = wi*math.sqrt(theta)/delta
    nc = speed/math.sqrt(theta)
    nc_map = nc/float(c["s_Nc"])
    wc, info = _table(c, "RlineVec", "NcVec", "WcArray", rline, nc_map)
    pr_map, _ = _table(c, "RlineVec", "NcVec", "PRArray", rline, nc_map)
    eff_map, _ = _table(c, "RlineVec", "NcVec", "EffArray", rline, nc_map)
    pr = 1+float(c["s_PR"])*(pr_map-1)
    eff = eff_map*float(c["s_eff"])
    if pr <= 1 or eff <= 0:
        raise ValueError("Non-physical compressor pressure ratio or efficiency")
    po = pi*pr
    ideal_t = _f(thermo.sp2t(si, po, far))
    ideal_h = _f(thermo.t2h(ideal_t, far))
    ho = hi+(ideal_h-hi)/eff
    to = _f(thermo.h2t(ho, far))
    frac = np.asarray(c["BleedFractions"], dtype=float).reshape(-1)
    hfrac = np.asarray(c["BleedEnthalpyFractions"], dtype=float).reshape(-1)
    pfrac = np.asarray(c["BleedPressureFractions"], dtype=float).reshape(-1)
    if len(frac) != 3 or len(hfrac) != 3 or len(pfrac) != 3:
        raise ValueError("This replay topology requires exactly three fractional bleeds")
    if (frac < 0).any() or frac.sum() >= 1:
        raise ValueError("Invalid fractional-bleed mass fractions")
    bleeds = []
    bleed_power = 0.
    for wf, hf, pf in zip(frac, hfrac, pfrac):
        wb, hb, pb = wi*wf, hi+hf*(ho-hi), pi+pf*(po-pi)
        # Zero-flow branches have no effect; their thermal fields stay defined.
        tb = _f(thermo.h2t(hb, far))
        bleeds.append(dict(W=float(wb), H=float(hb), T=float(tb), P=float(pb), FAR=float(far)))
        bleed_power += wb*(hb-ho)*BTU_SEC_TO_HP
    power_before_bleed = wi*(hi-ho)*BTU_SEC_TO_HP
    power = power_before_bleed-bleed_power
    torque = HP_RPM_TO_TORQUE*power/speed
    output = _stream(wi-wi*frac.sum(), ho, to, po, far)
    diag = dict(Torque=float(torque), Power_hp=float(power), Efficiency=float(eff),
                PR=float(pr), Nc=float(nc), NcMap=float(nc_map),
                WcInput=float(wc_in), WcCalculated=float(wc*float(c["s_Wc"])),
                FlowError=float((wc_in-wc*float(c["s_Wc"]))/wc_in),
                BleedPower_hp=float(bleed_power), PowerBeforeBleed_hp=float(power_before_bleed))
    return output, bleeds, diag, info


def _burner(c, inlet, wf, thermo):
    wi, ti, pi, far = (inlet[k] for k in ("W", "T", "P", "FAR"))
    hi = _f(thermo.t2h(ti, far))
    wo = wi+wf
    # Copy Burner_TMATS_body.c literally; FARin=0 in the requested inlet.
    fo = (wi*far+wf)/(wi*(1-far))
    ho = (wi*hi+wf*float(c["LHV"])*float(c["Eff"]))/wo
    to = _f(thermo.h2t(ho, fo))
    po = pi*(1-float(c["dP"]))
    return _stream(wo, ho, to, po, fo)


def _turbine(c, inlet, pr, speed, thermo, rear_cool=None):
    wi, ti, pi, fi = (inlet[k] for k in ("W", "T", "P", "FAR"))
    hi = _f(thermo.t2h(ti, fi))
    # Third bleed enters at the exit (T_CoolFlwPos_M=1): stage-1 flow unchanged.
    wcool = 0. if rear_cool is None else float(rear_cool["W"])
    fcool = 0. if rear_cool is None else float(rear_cool["FAR"])
    hcool = 0. if rear_cool is None else _f(thermo.t2h(rear_cool["T"], fcool))
    wo = wi+wcool
    mf_in = fi*wi/(1+fi)
    mf_cool = fcool*wcool/(1+fcool)
    fo = (mf_in+mf_cool)/(wi/(1+fi)+wcool-mf_cool)
    hstage = hi
    tstage = _f(thermo.h2t(hstage, fi))
    sstage = _f(thermo.pt2s(pi, tstage, fi))
    theta, delta = ti/TSTD, pi/PSTD
    nc = speed/math.sqrt(theta)
    nc_map = nc/float(c["s_Nc"])
    pr_map = 1+(pr-1)/float(c["s_PR"])
    wcmap, info = _table(c, "PRVec", "NcVec", "WcArray", pr_map, nc_map)
    effmap, _ = _table(c, "PRVec", "NcVec", "EffArray", pr_map, nc_map)
    eff = effmap*float(c["s_eff"])
    if pr <= 1 or eff <= 0:
        raise ValueError("Non-physical turbine pressure ratio or efficiency")
    po = pi/pr
    # The installed C implementation uses FARout for the ideal-outlet calls,
    # including rear cooling. Keep this behavior rather than silently repairing it.
    ideal_t = _f(thermo.sp2t(sstage, po, fo))
    ideal_h = _f(thermo.t2h(ideal_t, fo))
    actual_drop = (hstage-ideal_h)*eff
    power = actual_drop*wi*BTU_SEC_TO_HP
    hcore = hstage-actual_drop
    ho = (hcore*wi+hcool*wcool)/wo
    to = _f(thermo.h2t(ho, fo))
    torque = HP_RPM_TO_TORQUE*power/speed
    wcin = wi*math.sqrt(theta)/delta
    wc_calc = wcmap*float(c["s_Wc"])
    output = _stream(wo, ho, to, po, fo)
    core = _stream(wi, hcore, _f(thermo.h2t(hcore, fi)), po, fi)
    diag = dict(Torque=float(torque), Power_hp=float(power), Efficiency=float(eff),
                PR=float(pr), PRMap=float(pr_map), Nc=float(nc), NcMap=float(nc_map),
                WcInput=float(wcin), WcCalculated=float(wc_calc),
                FlowError=float((wcin-wc_calc)/wcin), ActualEnthalpyDrop=float(actual_drop),
                RearCoolMassFlow=float(wcool), RearCoolEnthalpy=float(hcool))
    return output, core, diag, info


def evaluate_ss(params, x, boundary, thermo):
    """Return physical station data, four normalized errors and two rpm/s rates.

    x = [W_in, Rline, PR_gt, PR_pt, Ng_rpm, Np_rpm].
    Invalid thermal/physical states return Residual=None, never fabricated zeros.
    Interpolation outside a map is clamped like C and explicitly marked invalid.
    """
    try:
        x = np.asarray(x, dtype=float).reshape(-1)
        if len(x) != 6 or not np.isfinite(x).all():
            raise ValueError("x must contain six finite values")
        w, rline, prg, prp, ng, np_ = map(float, x)
        if min(w, ng, np_) <= 0 or min(prg, prp) <= 1:
            raise ValueError("Flow/speeds must be positive and turbine PRs exceed one")
        t2, p2 = float(boundary["T2_R"]), float(boundary["P2_psia"])
        wf, load = float(boundary["Wf"]), float(boundary["Qload"])
        target = float(boundary["P49_psia"])
        far2 = float(boundary.get("FAR2", 0.))
        if min(t2, p2, target) <= 0 or wf < 0:
            raise ValueError("Invalid inlet/exhaust boundary or negative fuel flow")
        jg, jp = float(params["Shaft"]["Jg"]), float(params["Shaft"]["Jp"])
        if min(jg, jp) <= 0:
            raise ValueError("Shaft inertias must be positive, in slug*ft^2")
        s2 = _stream(w, _f(thermo.t2h(t2, far2)), t2, p2, far2)
        s3, bleeds, comp, comp_range = _compressor(params["HPC"], s2, rline, ng, thermo)
        s41 = _burner(params["Burner"], s3, wf, thermo)
        s45, s44, gt, gt_range = _turbine(params["HPT"], s41, prg, ng, thermo, bleeds[2])
        s49, _, pt, pt_range = _turbine(params["FPT"], s45, prp, np_, thermo)
        tg = comp["Torque"]+gt["Torque"]
        tp = pt["Torque"]-load
        ng_dot, np_dot = 60*tg/(2*math.pi*jg), 60*tp/(2*math.pi*jp)
        residual = [(s49["P"]-target)/target, comp["FlowError"],
                    gt["FlowError"], pt["FlowError"], ng_dot, np_dot]
        ranges = dict(HPC=comp_range, HPT=gt_range, FPT=pt_range)
        in_range = all(v["InRange"] for v in ranges.values())
        mass_error = s49["W"]-(s2["W"]+wf-bleeds[0]["W"]-bleeds[1]["W"])
        fuel_out = s49["W"]*s49["FAR"]/(1+s49["FAR"])
        fuel_in = s2["W"]*far2/(1+far2)+wf
        bleed_fuel = sum(b["W"]*b["FAR"]/(1+b["FAR"]) for b in bleeds[:2])
        stations = dict(s2=s2, s3=s3, s41=s41, s44=s44, s45=s45, s49=s49)
        return dict(X=x.tolist(), Residual=list(map(float,residual)),
                    ResidualOrder=["P49_error","Compressor_flow_error","GGT_flow_error",
                                   "FPT_flow_error","Ng_dot_rpm_s","Np_dot_rpm_s"],
                    Stations=stations, Bleeds=bleeds, Components=dict(HPC=comp,HPT=gt,FPT=pt),
                    Torques=dict(Compressor=comp["Torque"],GGT=gt["Torque"],FPT=pt["Torque"],
                                 Load=-load,NetNg=float(tg),NetNp=float(tp)),
                    MapRanges=ranges, AllMapInputsInRange=in_range,
                    MassBalanceError_lbm_s=float(mass_error),
                    FuelBalanceError_lbm_s=float(fuel_out-fuel_in+bleed_fuel),
                    NumericalEvaluationSucceeded=True, Valid=in_range,
                    SourceReplayOnly=True, SimulinkRun=False,
                    DiagnosticSurgeMarginNotReproduced=True)
    except (ValueError,KeyError,IndexError,TypeError,ZeroDivisionError,OverflowError,
            FloatingPointError) as exc:
        return dict(X=np.asarray(x).reshape(-1).tolist(), Residual=None,
                    NumericalEvaluationSucceeded=False,Valid=False,
                    AllMapInputsInRange=False,Error=f"{type(exc).__name__}: {exc}",
                    SourceReplayOnly=True,SimulinkRun=False)


def _default_bounds(params, boundary):
    comp = params["HPC"]
    theta = float(boundary["T2_R"])/TSTD
    delta = float(boundary["P2_psia"])/PSTD
    corrected_flow = np.asarray(comp["WcArray"])*float(comp["s_Wc"])
    actual_flow = corrected_flow*delta/math.sqrt(theta)
    ng = np.asarray(comp["NcVec"])*float(comp["s_Nc"])*math.sqrt(theta)
    hp, fp = params["HPT"], params["FPT"]
    prg = 1+float(hp["s_PR"])*(np.asarray(hp["PRVec"])-1)
    prp = 1+float(fp["s_PR"])*(np.asarray(fp["PRVec"])-1)
    lo = np.array([max(.01,.5*actual_flow.min()), min(comp["RlineVec"]),
                   prg.min(),prp.min(),ng.min(),100.])
    hi = np.array([2*actual_flow.max(),max(comp["RlineVec"]),
                   prg.max(),prp.max(),ng.max(),100000.])
    return lo,hi


def solve_ss(params, x0, boundary, thermo, max_iter=100, tolerances=None, bounds=None):
    """Bounded, scaled finite-difference Newton/line-search solve; no SciPy.

    A small clamped-map residual is not successful convergence. The returned
    Converged flag requires all six tolerances AND all map inputs in range.
    """
    tol = np.asarray(tolerances if tolerances is not None else
                     [1e-7,1e-7,1e-7,1e-7,1e-3,1e-3],dtype=float)
    if tol.ndim == 0:
        tol = np.full(6,float(tol))
    if tol.shape != (6,) or not (tol>0).all():
        raise ValueError("tolerances must be a positive scalar or six-vector")
    lo,hi = _default_bounds(params,boundary)
    if bounds is not None:
        if isinstance(bounds,dict):
            lo,hi = np.array(bounds["lower"],float),np.array(bounds["upper"],float)
        else:
            pair = np.asarray(bounds,float)
            if pair.shape == (2,6):lo,hi=pair
            elif pair.shape == (6,2):lo,hi=pair[:,0],pair[:,1]
            else:raise ValueError("bounds must contain lower/upper six-vectors")
    if not (hi>lo).all():
        raise ValueError("Steady solver bounds have no positive span")
    margin = 1e-11*(hi-lo)
    lower,upper = lo+margin,hi-margin
    x = np.clip(np.asarray(x0,float).reshape(6),lower,upper)
    scale = np.array([max(abs(x[0]),5),max(hi[1]-lo[1],1),
                      max(abs(x[2]),1),max(abs(x[3]),1),
                      max(abs(x[4]),30000),max(abs(x[5]),20000)])
    current = evaluate_ss(params,x,boundary,thermo)
    if current["Residual"] is None:
        return dict(X=x.tolist(),Residual=None,Converged=False,JacFailed=False,
                    Iterations=0,ExitReason="InvalidInitialState",Evaluation=current,
                    SourceReplayOnly=True,SimulinkRun=False,History=[])
    tq = current["Torques"]
    torque_scale_g = max(abs(tq["Compressor"]),abs(tq["GGT"]),1.)
    torque_scale_p = max(abs(tq["FPT"]),abs(float(boundary["Qload"])),1.)
    row_scale = np.array([1,1,1,1,
        60*torque_scale_g/(2*math.pi*float(params["Shaft"]["Jg"])),
        60*torque_scale_p/(2*math.pi*float(params["Shaft"]["Jp"]))])
    history=[];jac_failed=False;reason="MaximumIterations";used_lstsq=False
    condition=0.;best=current;best_x=x.copy()
    best_merit=float(np.linalg.norm(np.asarray(current["Residual"])/row_scale))
    converged=False
    for iteration in range(int(max_iter)+1):
        residual=np.asarray(current["Residual"],float)
        scaled=residual/row_scale
        merit=float(np.linalg.norm(scaled))
        history.append(dict(Iteration=iteration,X=x.tolist(),Residual=residual.tolist(),
                            ScaledNorm=merit,AllMapInputsInRange=current["AllMapInputsInRange"]))
        if merit<best_merit:
            best_merit=merit;best=current;best_x=x.copy()
        if np.all(abs(residual)<=tol):
            if current["AllMapInputsInRange"]:
                converged=True;reason="ResidualsAndMapRangesSatisfied"
            else:
                reason="ResidualsMetButOutsideMap"
            break
        if iteration==int(max_iter):
            break
        jac=np.empty((6,6))
        for j in range(6):
            dx=1e-4*scale[j]
            plus=x.copy();minus=x.copy()
            plus[j]=min(upper[j],x[j]+dx)
            minus[j]=max(lower[j],x[j]-dx)
            ep=evaluate_ss(params,plus,boundary,thermo)
            em=evaluate_ss(params,minus,boundary,thermo)
            if ep["Residual"] is not None and em["Residual"] is not None and plus[j]>minus[j]:
                jac[:,j]=(np.asarray(ep["Residual"])-np.asarray(em["Residual"])) \
                    /row_scale/((plus[j]-minus[j])/scale[j])
            elif ep["Residual"] is not None and plus[j]>x[j]:
                jac[:,j]=(np.asarray(ep["Residual"])-residual)/row_scale/((plus[j]-x[j])/scale[j])
            elif em["Residual"] is not None and minus[j]<x[j]:
                jac[:,j]=(residual-np.asarray(em["Residual"]))/row_scale/((x[j]-minus[j])/scale[j])
            else:
                jac[:,j]=np.nan
        if not np.isfinite(jac).all():
            jac_failed=True;reason="FiniteDifferenceJacobianFailed";break
        condition=float(np.linalg.cond(jac))
        try:
            step=np.linalg.solve(jac,-scaled)
        except np.linalg.LinAlgError:
            used_lstsq=True
            step,_,rank,_=np.linalg.lstsq(jac,-scaled,rcond=1e-12)
            if rank<6:
                jac_failed=True
        accepted=False
        # If Newton has no merit-decreasing bounded step, try damped least squares.
        steps=[step]
        for damping in (1e-5,1e-3,.1,10.,1000.):
            try:steps.append(-np.linalg.solve(jac.T@jac+damping*np.eye(6),jac.T@scaled))
            except np.linalg.LinAlgError:pass
        for direction in steps:
            largest=float(np.max(abs(direction)))
            if largest>.35:direction=direction*(.35/largest)
            dx=direction*scale
            alpha=1.
            for j in range(6):
                if dx[j]>0:alpha=min(alpha,.995*(upper[j]-x[j])/dx[j])
                elif dx[j]<0:alpha=min(alpha,.995*(lower[j]-x[j])/dx[j])
            for _ in range(20):
                if alpha<1e-12:break
                candidate=x+alpha*dx
                evaluated=evaluate_ss(params,candidate,boundary,thermo)
                if evaluated["Residual"] is not None:
                    trial=float(np.linalg.norm(np.asarray(evaluated["Residual"])/row_scale))
                    range_ok=not current["AllMapInputsInRange"] or evaluated["AllMapInputsInRange"]
                    if range_ok and trial<merit*(1-1e-4*alpha):
                        x=candidate;current=evaluated;accepted=True;break
                alpha*=.5
            if accepted:break
        if not accepted:
            reason="BoundedLineSearchNoProgress";break
    if not converged:
        current=best;x=best_x
    final_residual=current["Residual"]
    return dict(X=x.tolist(),Residual=final_residual,Converged=bool(converged),
                JacFailed=bool(jac_failed),Iterations=len(history)-1,ExitReason=reason,
                JacobianCondition=condition,UsedLeastSquares=used_lstsq,
                ResidualTolerances=tol.tolist(),ResidualScaling=row_scale.tolist(),
                BoundsLower=lo.tolist(),BoundsUpper=hi.tolist(),
                AllMapInputsInRange=current.get("AllMapInputsInRange",False),
                Evaluation=current,History=history,
                SourceReplayOnly=True,SimulinkRun=False)
