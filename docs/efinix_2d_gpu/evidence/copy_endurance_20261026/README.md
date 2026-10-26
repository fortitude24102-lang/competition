# Copy-prefetch endurance, completed before five-way control

The ordinary 1024-object workload completed108000 frames on the Copy-prefetch BIT, with work mean8745us, maximum14076us and wall maximum16639us. Work misses, late presents, scanout underflows and GPU errors were all zero. Visible objects remained1006..1016 and Alpha commands130..131. The600-input recording sealed with CRC `a7bd652f`,256-word budget and offset9836. Both observed maxima are below the strict16666us budget.

The recorded execution handle61876 terminated with exit0. The raw capture contains exactly one newline-complete successful STOP and one complete108000-frame summary. The historical post-run238-input verification and final normal six-tier START/MENU test both passed before the controller edits. These are completed measurements, not a currently running process.

Exact artifacts:

| Artifact | SHA256 |
| --- | --- |
| Copy-prefetch BIT | `de149efdc78e1dded2c0e070efe52cd8e5e70fdc52e577dd7061c94902c72879` |
| Long108000-frame BIN | `ab85b3d6c273b72b4064e2b6ffddec68378879b40565207c51c905adcd2bcf2b` |
| Reproduced3600-frame control BIN | `d731f59769989ee44b49a08709acfeab57cc4bc0d9dad4995ad07185c494d1f6` |
| Restored normal BIN | `6000d1559cccaa91b340e2881db2afaed5c693cac2aa2e863f0340edb9c50b3c` |

The full physical configuration and Copy-prefetch implementation are retained separately in `../wide_copy_prefetch_20261026/evidence.zip`, SHA256 `8050b0d0519b5f07f9fd713e291102194c85ab15b90e9e1db2d9faa06ac46d4e`. This supplement includes exact executable artifacts and raw logs, with a verified per-entry inventory. The archive's adjacent SHA256 identifies this supplement.

Scope: this run predates the five-way controller and subsequent CPU path-arithmetic candidate. It proves the stated older BIT/BIN combination only. The currently selected controller BIT is a different artifact, and these long-run numbers must not be attributed to it.

An additional offline profile of12000 neutral game steps found position computation on1710 steps, with at most6 calls per step;10290 steps made no calls. This rejects an eager three-emitter cache for every step as unnecessary extra work on this trace. The profile source and output are retained for future optimization decisions.
