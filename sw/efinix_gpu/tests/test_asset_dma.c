#include "asset_dma.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint32_t registers[0x140/4];
static uint32_t writes;
uint32_t gpu_io_read(uintptr_t address) {
    return registers[(address-GPU_APB_BASE)/4];
}
void gpu_io_write(uintptr_t address, uint32_t value) {
    registers[(address-GPU_APB_BASE)/4]=value;
    ++writes;
}
void gpu_io_fence(void) {}

int main(void) {
    asset_dma_descriptor d={.session=3,.dst_addr=GPU_DENSE_ASSETS,
        .asset_id=7,.expected_offset=0,.expected_sequence=0,.max_length=2050};
    asset_dma_snapshot snapshot;
    assert(asset_dma_start(GPU_APB_BASE,&d)==ASSET_DMA_OK);
    assert(writes==7);
    assert(registers[GPU_REG_ASSET_SESSION/4]==3);
    assert(registers[GPU_REG_ASSET_CONTROL/4]==1);
    registers[GPU_REG_ASSET_STATUS/4]=1;
    assert(asset_dma_poll(GPU_APB_BASE,&snapshot)==ASSET_DMA_BUSY);
    assert(asset_dma_wait(GPU_APB_BASE,2,&snapshot)==ASSET_DMA_TIMEOUT);
    registers[GPU_REG_ASSET_STATUS/4]=2;
    registers[GPU_REG_ASSET_COMMITTED_OFFSET/4]=2050;
    registers[GPU_REG_ASSET_COMMITTED_BYTES/4]=2050;
    registers[GPU_REG_ASSET_PACKET_COUNT/4]=3;
    assert(asset_dma_wait(GPU_APB_BASE,2,&snapshot)==ASSET_DMA_OK);
    assert(snapshot.committed_bytes==2050 && snapshot.packet_count==3);
    registers[GPU_REG_ASSET_STATUS/4]=4;
    assert(asset_dma_poll(GPU_APB_BASE,&snapshot)==ASSET_DMA_HARDWARE);
    registers[GPU_REG_ASSET_STATUS/4]=0;
    d.dst_addr=GPU_FRAMEBUFFER_A;
    assert(asset_dma_start(GPU_APB_BASE,&d)==ASSET_DMA_ARGUMENT);
    d.dst_addr=GPU_DDR_END_EXCLUSIVE-2048;
    assert(asset_dma_start(GPU_APB_BASE,&d)==ASSET_DMA_ARGUMENT);
    d.dst_addr=GPU_DENSE_ASSETS;
    d.expected_offset=2;
    assert(asset_dma_start(GPU_APB_BASE,&d)==ASSET_DMA_ARGUMENT);
    asset_dma_abort(GPU_APB_BASE);
    assert(registers[GPU_REG_ASSET_CONTROL/4]==2);
    puts("PASS asset DMA descriptor/status/bounds/abort");
}
