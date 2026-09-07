#include "soc.h"
#include "gpu.h"
_Static_assert(GPU_APB_BASE == IO_APB_SLAVE_0_INPUT, "official APB base");
_Static_assert(GPU_APB_BYTES == IO_APB_SLAVE_0_INPUT_SIZE, "official APB size");
_Static_assert(SYSTEM_PLIC_USER_INTERRUPT_A_INTERRUPT == 16, "official IRQ");
_Static_assert(SYSTEM_CLINT_HZ == 100000000, "official clock");
_Static_assert(sizeof(void *) == 4, "RV32 ABI required");
uint32_t sapphire_contract_probe(void) { return gpu_pack_size(640, 480); }
