T700 Simulation Data Inspector view repair
Date: 2026-11-16
MATLAB verified: R2024a Update 9

Cause reproduced:
The composite signal names contain an embedded newline between "While Iterator" and "Subsystem".
A freshly saved view with literal newlines failed to restore all four error signals in the same MATLAB session.
Encoding those embedded newlines as XML character references (&#10;) restored all four signals.
An ordinary directly logged scalar signal did not exhibit the failure.

Changes:
- Patched Error, Gas and shaft view files in the parent result folder.
- Corrected the shaft view Qload reference to the directly logged BC_Qload signal present in the saved run.
- Preserved the original view files under before_20261116_180901.
- Added model/T700_save_view.m and model/T700_escape_view_newlines.m.
- Did not edit T700_Dyn.mdl or the full simulation data session.

Future view saves:
Add the model folder to the MATLAB path, then run T700_save_view.
Choose the view filename in its save dialog. This saves the current view and applies the newline-preservation fix.
The native Save Current View command can reintroduce the unescaped newlines.
Full data sessions should still be saved using the SDI sidebar Save Session command.

Verification:
Fresh independent MATLAB session: Error 4/4, Gas 8/8, shaft 6/6 signals restored.
After clearing only the independent test session and reimporting the original saved data: all three views passed again with different signal IDs.
Saved-session metadata confirmed every restored signal was assigned to its expected subplot in both cycles.
The new save helper passed immediate save/load round trips for the shaft and error views.
The existing user MATLAB session was not cleared or reconfigured.
See verification_report.json and verification.log for results.
