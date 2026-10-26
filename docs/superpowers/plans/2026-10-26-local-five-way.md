# Five-way local control

Use the connected J28 pins32/34/37/38/39 as active-low UP/DOWN/LEFT/RIGHT/MID with weak3.3V pullups. Preserve onboard KEY1/KEY2. Synchronize the five inputs and overlay pressed bits31:27 plus capability bit21 only on the existing safe GPU STATUS read; generated GPU RTL is unchanged.

Normal firmware debounces20ms, selects the six menu cards with directions, starts with MID, and maps MID to held FIRE in play. Require release at startup/menu entry; retain original runtime neutral handshake. Keep network command acknowledgements and performance-owner lease logic, and disable local control in terminal performance probes. Highlight selection in both framebuffer caches.

- [x] Observe new RTL and controller tests fail, implement, then pass.
- [x] Run software/menu and board input/CDC/timing/resource checks.
- [x] Build a fresh BIT/BIN, JTAG only, verify real status and released menu; request manual directions/fire confirmation.
