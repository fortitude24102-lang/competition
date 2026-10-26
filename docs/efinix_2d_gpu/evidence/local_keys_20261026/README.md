# Five-way local controller, 2026-10-26

The new BIT and normal firmware were loaded through JTAG. Directions select the yellow menu card; MID starts the selected level. During play, directions move and MID holds FIRE. Contacts must be released before a fresh menu confirmation. SET/RST are unused. With the local capability present, physical keys own normal game input; web START/MENU commands remain available. The performance challenge still uses its existing web owner and lease. Terminal measurement probes retain network input.

J28 wiring on the QSE-to-header adapter:

| Module | J28 | FPGA GPIO | Ball |
| --- | --- | --- | --- |
| COM | 35 GND | Ground | — |
| UP | 32 | GPIOL_11 | C5 |
| DWN | 34 | GPIOL_09 | A4 |
| LFT | 37 | GPIOL_04 | B3 |
| RHT | 38 | GPIOL_10 | B5 |
| MID | 39 | GPIOL_06 | C3 |

All five pins are input-only, 3.3V LVCMOS with weak pullups. Two flip-flops synchronize each contact; C debounces for 20ms. STATUS bit21 advertises the controller; bits31:27 expose pressed UP/DOWN/LEFT/RIGHT/MID as mask bits0..4. Existing STATUS bits0..20 and every other register are preserved. The applied timing exception covers only the five external contacts to their five first-stage synchronizers.

Validation:

- RTL synchronization/polarity/status-isolation test passes. Controller tests pass with both 512 and 1024 object capacity and UBSan, including boot bounce, held MID, opposing directions, menu re-entry, six-card bounds and performance isolation.
- Full `test-v3-integration.ps1 -SoftwareOnly -ShapeLut` passes. Menu tests verify yellow selection and both framebuffer caches, including failed redraw invalidation.
- Physical build `D:/efinity_builds/local_keys_20261026_r2` completed all four phases. XLR54549, RAM186, DSP38; all16 final setup/hold relationships have strictly positive slack. Core setup +0.296ns, hold +0.026ns.
- Routed mailbox coverage remains 1488 data, two request and two acknowledgement paths; maximum delays 1.118ns, 0.684ns and 1.002ns, each below 8ns. Five first and five second local synchronizers are present in mapped RTL.
- COM9 UART reports `LOCAL_KEYS,present=1,debounce_ms=20`. Real board HTTP/UDP qualification passed six START/MENU transitions with matching acknowledgements and telemetry snapshots, with zero reported underflow/error deltas. A JTAG STATUS read returned `0x003ef020`: capability present and all five contacts released. The debugger was resumed after the read.
- The user subsequently confirmed physical operation as “非常正常”. Automated six-tier START/MENU checks use web commands; physical selection/movement/fire confirmation comes from the user's hands-on report.

BIT SHA256: `a98148a59541161874a5f8685c5338b3742b6e553c4ba2d3718f3d25a7c98436`.

BIN SHA256: `70addf7858d5dd6cbd9cf29ae1ed7212b36c72b0554aa08f11efbbe7dc847ea3` (`normal-r2`, build20261015, 1024 objects, CopyAhead/LogicCopy/FrameList/HudDirect/ShapeLut/ReplayCrcNibble/ReplaySealBudget/PerformanceChallenge, board192.168.1.3, peer192.168.1.2).

The selected generated GPU RTL is unchanged from Copy-prefetch source `0a0b96f1a83947ef14d6fc8bf93c82636f0ed682c12fa09dd564880d369d569a`. This controller changes board RTL, peripheral configuration and SDC, so earlier 238-file hardware identity gates are not claimed for this configuration. The 161-file snapshot was captured after build launch, around completion; it is not a prebuild freeze. Source stability and selected GPU hashes were checked afterward. The initial snapshot checker had a Python tuple/list comparison defect; the correction audit verifies its original and final captured inputs were identical. The first physical attempt failed peripheral XML child ordering; r2 fixes that ordering. No Flash or release bundle was written.

Raw logs, compiled BIT/BIN, selected input snapshots, source copies and reports are retained in `evidence.zip`; the adjacent SHA256 file identifies the archive. Four preexisting user files were verified unchanged.

Final board state supersedes the preliminary archive's running-state assumption: the JTAG memory-read debugger accepted `resume`, but a subsequent fresh-session check did not recover communication. The same new BIN was reloaded and the six-tier START/MENU check passed again (`board-final-r2`, terminal exit0). A separate HTTP-only fresh-session check then passed in MENU with acknowledged ownership and zero underflow/error deltas; ownership was released afterward. No debugger was connected after this final recovery. These final records are retained in `recovery.zip` with its adjacent SHA256. The cause of the debugger resume behavior is not attributed to the controller firmware. The user later confirmed physical controls normal; this adjacent README updates the earlier pending-confirmation notes inside the immutable archives.
