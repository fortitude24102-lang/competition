#include "asset_dma.h"

#ifdef GPU_TEST_BACKEND
uint32_t gpu_io_read(uintptr_t address);
void gpu_io_write(uintptr_t address, uint32_t value);
void gpu_io_fence(void);
#else
static uint32_t gpu_io_read(uintptr_t address) { return *(volatile uint32_t *)address; }
static void gpu_io_write(uintptr_t address, uint32_t value) {
    *(volatile uint32_t *)address=value;
}
static void gpu_io_fence(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
#endif

static uint32_t read_reg(uintptr_t base, uint32_t offset) {
    return gpu_io_read(base+offset);
}
static void write_reg(uintptr_t base, uint32_t offset, uint32_t value) {
    gpu_io_write(base+offset,value);
}

int asset_dma_start(uintptr_t base, const asset_dma_descriptor *d) {
    if (!d || !base || !d->session || !d->max_length ||
        (d->dst_addr & 3u) || (d->expected_offset & 3u) ||
        d->expected_offset >= d->max_length ||
        d->dst_addr < GPU_DENSE_ASSETS ||
        (uint64_t)d->dst_addr+d->max_length > GPU_DDR_END_EXCLUSIVE)
        return ASSET_DMA_ARGUMENT;
    if (read_reg(base,GPU_REG_ASSET_STATUS)&1u) return ASSET_DMA_BUSY;
    write_reg(base,GPU_REG_ASSET_SESSION,d->session);
    write_reg(base,GPU_REG_ASSET_DST_ADDR,d->dst_addr);
    write_reg(base,GPU_REG_ASSET_ID,d->asset_id);
    write_reg(base,GPU_REG_ASSET_EXPECTED_OFFSET,d->expected_offset);
    write_reg(base,GPU_REG_ASSET_EXPECTED_SEQUENCE,d->expected_sequence);
    write_reg(base,GPU_REG_ASSET_MAX_LENGTH,d->max_length);
    gpu_io_fence();
    write_reg(base,GPU_REG_ASSET_CONTROL,1u);
    gpu_io_fence();
    return ASSET_DMA_OK;
}

int asset_dma_poll(uintptr_t base, asset_dma_snapshot *snapshot) {
    if (!base || !snapshot) return ASSET_DMA_ARGUMENT;
    gpu_io_fence();
    snapshot->status=read_reg(base,GPU_REG_ASSET_STATUS);
    snapshot->committed_offset=read_reg(base,GPU_REG_ASSET_COMMITTED_OFFSET);
    snapshot->committed_sequence=read_reg(base,GPU_REG_ASSET_COMMITTED_SEQUENCE);
    snapshot->committed_bytes=read_reg(base,GPU_REG_ASSET_COMMITTED_BYTES);
    snapshot->packet_count=read_reg(base,GPU_REG_ASSET_PACKET_COUNT);
    snapshot->error_count=read_reg(base,GPU_REG_ASSET_ERROR_COUNT);
    snapshot->duplicate_count=read_reg(base,GPU_REG_ASSET_DUPLICATE_COUNT);
    if (snapshot->status & (4u|8u)) return ASSET_DMA_HARDWARE;
    if (snapshot->status & 2u) return ASSET_DMA_OK;
    return ASSET_DMA_BUSY;
}

int asset_dma_wait(uintptr_t base, uint32_t poll_limit, asset_dma_snapshot *snapshot) {
    while (poll_limit--) {
        int result=asset_dma_poll(base,snapshot);
        if (result!=ASSET_DMA_BUSY) return result;
    }
    return ASSET_DMA_TIMEOUT;
}

void asset_dma_abort(uintptr_t base) {
    if (base) {
        write_reg(base,GPU_REG_ASSET_CONTROL,2u);
        gpu_io_fence();
    }
}
