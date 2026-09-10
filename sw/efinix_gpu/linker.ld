/* Supplement the official Sapphire linker script; framebuffer/assets stay outside the ELF. */
PROVIDE(__gpu_framebuffer_a = 0x02000000);
PROVIDE(__gpu_framebuffer_b = 0x02200000);
PROVIDE(__gpu_dense_assets = 0x02400000);
ASSERT(_end <= __gpu_framebuffer_a, "program overlaps GPU DDR reservations")
ASSERT(_sp <= __gpu_framebuffer_a, "stack overlaps GPU DDR reservations")
