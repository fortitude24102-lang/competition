# Video Accelerator Interface

`VideoAccelTop` is an external Verilog module. Its port names and widths form the replaceable RTL contract so an algorithm implementation can change without modifying Chisel or software.

| Direction | Port | Width | Meaning |
|---|---|---:|---|
| input | `clock` | 1 | SoC clock |
| input | `reset` | 1 | Active-high synchronous reset |
| input | `pixel_in` | 24 | RGB888, `[23:16]=R`, `[15:8]=G`, `[7:0]=B` |
| input | `pixel_in_valid` | 1 | Input pixel valid |
| output | `pixel_in_ready` | 1 | Input can be accepted this cycle |
| input | `pixel_in_start_of_frame` | 1 | First beat of a frame |
| input | `pixel_in_end_of_line` | 1 | Last beat of a line |
| input | `pixel_in_end_of_frame` | 1 | Last beat of a frame |
| output | `pixel_out` | 24 | Processed RGB888 pixel |
| output | `pixel_out_valid` | 1 | Output pixel valid |
| input | `pixel_out_ready` | 1 | Downstream can accept output this cycle |
| output | `pixel_out_start_of_frame` | 1 | Propagated first-beat marker |
| output | `pixel_out_end_of_line` | 1 | Propagated line-end marker |
| output | `pixel_out_end_of_frame` | 1 | Propagated frame-end marker |
| input | `enable` | 1 | Accelerator enable |
| input | `mode` | 2 | 0 bypass, 1 gray, 2 threshold, 3 reserved |
| input | `threshold` | 8 | Gray threshold |
| input | `bypass` | 1 | Forces passthrough when set |
| output | `busy` | 1 | An output beat is pending |
| output | `frame_done` | 1 | Pulses when an accepted output carries end-of-frame |

An input transfers only when `pixel_in_valid && pixel_in_ready`; an output transfers only when `pixel_out_valid && pixel_out_ready`. Output data and markers remain stable while valid is asserted and ready is deasserted. The one-entry output register accepts one beat per cycle when the downstream does not stall.

The Demo uses the SoC clock only and has no CDC. A future clock-domain boundary must be added outside this interface with an explicit CDC design. An AXI4-Stream adapter belongs outside this module and maps its handshake and boundary markers to the selected board flow.
