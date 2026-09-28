#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "gpu.h"

static uint32_t regs[64];
static unsigned write_offsets[8], write_values[8], writes, fences;
static const uint32_t *cache_reads;
static unsigned cache_read_count, cache_read_index;
static int cache_controlled;

uint32_t gpu_io_read(uintptr_t address) {
    unsigned offset = (unsigned)(address - GPU_APB_BASE);
    if (offset == GPU_REG_TEXTURE_CACHE_STATUS && cache_controlled &&
        cache_read_index < cache_read_count)
        return cache_reads[cache_read_index++];
    return regs[offset / 4];
}

void gpu_io_write(uintptr_t address, uint32_t value) {
    unsigned offset = (unsigned)(address - GPU_APB_BASE);
    assert(writes < 8);
    write_offsets[writes] = offset;
    write_values[writes++] = value;
    regs[offset / 4] = value;
    if (offset == GPU_REG_TEXTURE_CACHE_CONTROL) {
        cache_controlled = 1;
        cache_read_index = 0;
    }
}

void gpu_io_fence(void) { ++fences; }

static void reset_io(void) {
    writes = fences = cache_read_count = cache_read_index = 0;
    cache_reads = NULL;
    cache_controlled = 0;
    memset(write_offsets, 0, sizeof write_offsets);
    memset(write_values, 0, sizeof write_values);
    memset(regs, 0, sizeof regs);
    regs[GPU_REG_STATUS / 4] = GPU_STATUS_EMPTY;
}

static void set_cache_reads(const uint32_t *values, unsigned count) {
    cache_reads = values;
    cache_read_count = count;
}

int main(void) {
    gpu_device device = {.base = GPU_APB_BASE, .ready = 1};
    static const uint32_t success[] = {
        GPU_TEXTURE_CACHE_STATUS_BUSY,
        GPU_TEXTURE_CACHE_STATUS_BUSY,
        GPU_TEXTURE_CACHE_STATUS_VALID
    };
    reset_io();
    set_cache_reads(success, 3);
    assert(gpu_texture_cache_load(&device, GPU_DENSE_ASSETS, 3104, 3) == 0);
    assert(writes == 3 && fences == 2);
    assert(write_offsets[0] == GPU_REG_TEXTURE_CACHE_BASE);
    assert(write_values[0] == GPU_DENSE_ASSETS);
    assert(write_offsets[1] == GPU_REG_TEXTURE_CACHE_BYTES);
    assert(write_values[1] == 3104);
    assert(write_offsets[2] == GPU_REG_TEXTURE_CACHE_CONTROL);
    assert(write_values[2] == GPU_TEXTURE_CACHE_CONTROL_LOAD);
    assert(cache_read_index == 3);

    static const uint32_t timeout[] = {
        GPU_TEXTURE_CACHE_STATUS_BUSY, GPU_TEXTURE_CACHE_STATUS_BUSY
    };
    reset_io(); set_cache_reads(timeout, 2);
    assert(gpu_texture_cache_load(&device, GPU_DENSE_ASSETS, 32, 2) == GPU_DRIVER_TIMEOUT);
    assert(writes == 3 && cache_read_index == 2);

    static const uint32_t hardware[] = {
        GPU_TEXTURE_CACHE_STATUS_BUSY, GPU_TEXTURE_CACHE_STATUS_ERROR
    };
    reset_io(); set_cache_reads(hardware, 2);
    assert(gpu_texture_cache_load(&device, GPU_DENSE_ASSETS, 32, 3) == GPU_DRIVER_HARDWARE);
    assert(writes == 3 && cache_read_index == 2);

    const struct { uint32_t base, bytes; } invalid[] = {
        {GPU_DENSE_ASSETS + 2u, 4u}, {GPU_DENSE_ASSETS, 0u},
        {GPU_DENSE_ASSETS, 2u}, {GPU_DENSE_ASSETS, 4100u},
        {GPU_DENSE_ASSETS - 4u, 4u}, {GPU_DDR_END_EXCLUSIVE - 4u, 8u},
        {UINT32_C(0xfffffffc), 8u}
    };
    for (unsigned i = 0; i < sizeof invalid / sizeof invalid[0]; ++i) {
        reset_io();
        assert(gpu_texture_cache_load(&device, invalid[i].base, invalid[i].bytes, 1) ==
               GPU_DRIVER_ARGUMENT);
        assert(writes == 0 && fences == 0);
    }
    reset_io();
    assert(gpu_texture_cache_load(NULL, GPU_DENSE_ASSETS, 4, 1) == GPU_DRIVER_ARGUMENT);
    assert(writes == 0);

    reset_io(); device.outstanding = 1;
    assert(gpu_texture_cache_load(&device, GPU_DENSE_ASSETS, 4, 1) == GPU_DRIVER_BUSY);
    assert(writes == 0);
    device.outstanding = 0;
    reset_io(); regs[GPU_REG_STATUS / 4] = 0;
    assert(gpu_texture_cache_load(&device, GPU_DENSE_ASSETS, 4, 1) == GPU_DRIVER_BUSY);
    assert(writes == 0);
    reset_io(); regs[GPU_REG_STATUS / 4] = GPU_STATUS_EMPTY | GPU_STATUS_BUSY;
    assert(gpu_texture_cache_load(&device, GPU_DENSE_ASSETS, 4, 1) == GPU_DRIVER_BUSY);
    assert(writes == 0);
    reset_io(); regs[GPU_REG_TEXTURE_CACHE_STATUS / 4] = GPU_TEXTURE_CACHE_STATUS_BUSY;
    assert(gpu_texture_cache_load(&device, GPU_DENSE_ASSETS, 4, 1) == GPU_DRIVER_BUSY);
    assert(writes == 0);

    reset_io(); regs[GPU_REG_TEXTURE_CACHE_STATUS / 4] = GPU_TEXTURE_CACHE_STATUS_VALID;
    assert(gpu_texture_cache_invalidate(&device) == 0);
    assert(writes == 1 && fences == 2);
    assert(write_offsets[0] == GPU_REG_TEXTURE_CACHE_CONTROL);
    assert(write_values[0] == GPU_TEXTURE_CACHE_CONTROL_INVALIDATE);

    puts("PASS: texture cache driver validation, polling, error, timeout and invalidate");
    return 0;
}
