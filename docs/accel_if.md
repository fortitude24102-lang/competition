# Video Accelerator Interface

`VideoAccelTop` is an external Verilog module. Its port names and widths are frozen so the RTL implementation can be replaced without modifying Chisel or software.

| Direction | Port | Width | Meaning |
|---|---|---:|---|
| input | `clock` | 1 | SoC clock |
| input | `reset` | 1 | Active-high synchronous reset |
| input | `pixel_in` | 24 | RGB888, `[23:16]=R`, `[15:8]=G`, `[7:0]=B` |
| input | `pixel_in_valid` | 1 | Input pixel valid |
| output | `pixel_out` | 24 | Processed RGB888 pixel |
| output | `pixel_out_valid` | 1 | Output pixel valid |
| input | `enable` | 1 | Accelerator enable |
| input | `mode` | 2 | 0 bypass, 1 gray, 2 threshold, 3 reserved |
| input | `threshold` | 8 | Gray threshold |
| input | `bypass` | 1 | Forces passthrough when set |
| output | `busy` | 1 | Processing activity status |
| output | `frame_done` | 1 | One-cycle completion indication in the Demo stub |

The first Demo version uses the SoC clock only and has no CDC. A future clock-domain boundary must be added outside this interface with an explicit CDC design.
