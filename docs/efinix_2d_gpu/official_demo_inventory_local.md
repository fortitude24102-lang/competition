# Local official-demo inventory (2026-09-22)

This is a local working note only. It is intentionally uncommitted and unpushed for this task.

## Directly reusable

| Demo | Candidate files | Use | Caveat |
|---|---|---|---|
| `04_Ti60f225_GE_demo/04_Ti60F225_tse_hj_demo_v5` | `rtl/udp_test_top.v`, `rtl/heijin_test/rgmii2gmii_altera/util_gmii_to_rgmii.v`, `rtl/heijin_test/mac/*`, `rtl/heijin_test/arbi/gmii_arbi.v`, `rtl/ge/01_CODE/ge_top.v`, `rtl/ge/01_CODE/mac_top.v`, `rtl/ge/01_CODE/arp_cache.v`, `rtl/ge/01_CODE/crc.v`, `rtl/ge/01_CODE/DC_FIFO.v`, `led_demo.xml`, `led_test.peri.xml`, `led_test.pt.sdc` | Best source for RGMII DDR input/output, GMII 8-bit conversion, 125 MHz clocking, MAC/ARP/IPv4/UDP path and PHY reset/MDIO. | Official top uses a demo-specific `mac_test`/pattern generator and fixed packet flow. Retain vendor bytes; wrap its UDP application boundary rather than modifying it. `udp_rec_data_length` and RAM/application offsets must be checked against the frozen ASST contract. |
| `03_hdmi_tx_demo/hdmi_tx_demo_v2` | `rtl/hdmi_src/*`, `rtl/top.v`, `rtl/reset.v`, `rtl/hdmi_src/timing_gen_xy.v`, generated PLL/serializer IP and `outflow/hdmi_tx.bit/.hex` | Best source for the official HDMI TX/742.5 MHz serializer and 1080p timing. | Do not copy the demo top or color-bar application. Existing project already has the derived HDMI adapter; use the source as an IP/port reference. |
| `08_ti60f225_soc_demo/09_Ti60F225_hardjtag_demo` | Sapphire/DDR3 source tree under `par/ddr_demo_ti60`, memory tests and embedded software | Existing project’s Sapphire RISC-V + DDR3 baseline and physical DDR validation. | Keep the existing project’s official source snapshot; do not replace it with another demo’s DDR netlist. |
| `10_Ti60f225_sc431hai2hdmi_demo` | `rtl/frame_buffer/*`, `ddr_rd_buffer.v`, `ddr_wr_buffer.v`, `dual_clock_fifo.v`, `frame_buffer.v` | Reference for DDR frame-buffer buffering and clock-domain handling. | This is a camera/MIPI pipeline, not the primary HDMI/GPU top; use algorithms only after interface review. |

## Not suitable as the V2 game/network base

`01` is LED/oscillator, `02` is HDMI RX-to-TX loopback, `05` is LVDS, `07/09/11/12` are MIPI/DSI camera/display demos, and `13` is carry-chain. They are useful only for isolated IP or timing references.

## GE extraction boundary

The first extraction set should preserve these files verbatim under `board/efinix_ti60/vendor/ge_udp/`: `udp_test_top.v`, `util_gmii_to_rgmii.v`, `gmii_arbi.v`, the GE `mac_top`/ARP/CRC/DC FIFO sources, and the Efinity project’s GE peripheral XML/SDC. The self-owned wrapper should terminate at an 8-bit GMII/UDP application stream and expose `rx_byte`, `rx_valid`, `rx_last`, `rx_length`, `link`, and `speed`. The official pattern generator and fixed demo destination addresses must not enter the resource-server protocol.

## Game-source audit

README selects `JamesC01/ZombieGardenTD` for logic. I cloned it locally at `D:/FPGA/game_sources/ZombieGardenTD_20260922` for review. Its repository is C under MIT, but its current game is tightly coupled to Raylib (`src/game.c`, `src/plant.c`, `src/zombie.c`, `src/ui.c`) and its README credits art/audio to James Czekaj while warning that older commits contain PopCap placeholder sprites. Therefore only the deterministic rules/state structures may be adapted; its PNG/ASE/audio/fonts are not imported into the FPGA asset package.

For visuals, use a separate CC0 pack after recording the exact asset URL and license. The README’s `Gameboy tower defense sprites` source is CC0; it is suitable for a small RGB565 test package, while `ZombieGardenTD` art is not treated as CC0. The current local `lane_game.c` is a provisional contract model and should not be described as a literal source port until the rule extraction and attribution record are complete.
