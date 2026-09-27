#ifndef EFINIX_ASSET_DMA_H
#define EFINIX_ASSET_DMA_H
#include <stdint.h>
#include <stddef.h>
#include "gpu_regs.h"

typedef struct {
    uint32_t session, dst_addr, asset_id, expected_offset;
    uint32_t expected_sequence, max_length;
} asset_dma_descriptor;

typedef struct {
    uint32_t status, committed_offset, committed_sequence, committed_bytes;
    uint32_t packet_count, error_count, duplicate_count;
} asset_dma_snapshot;

enum asset_dma_result { ASSET_DMA_OK=0, ASSET_DMA_ARGUMENT=-1,
    ASSET_DMA_BUSY=-2, ASSET_DMA_TIMEOUT=-3, ASSET_DMA_HARDWARE=-4 };

int asset_dma_start(uintptr_t base, const asset_dma_descriptor *descriptor);
int asset_dma_poll(uintptr_t base, asset_dma_snapshot *snapshot);
int asset_dma_wait(uintptr_t base, uint32_t poll_limit, asset_dma_snapshot *snapshot);
void asset_dma_abort(uintptr_t base);
#endif
