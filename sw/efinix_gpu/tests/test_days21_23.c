#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "assets.h"
#include "benchmark.h"
#include "game.h"
#include "hud.h"

static uint32_t regs[64];
static unsigned writes;
static uint32_t stream_hash[2];
static unsigned stream_count[2];
static unsigned qos_mode;
uint64_t gpu_platform_cycles(void) { static uint64_t value; return ++value; }
void gpu_platform_sync(void) {}
void gpu_io_fence(void) {}
uint32_t gpu_io_read(uintptr_t address) { return regs[(address - GPU_APB_BASE) / 4u]; }
void gpu_io_write(uintptr_t address, uint32_t value) {
    unsigned offset = (unsigned)(address - GPU_APB_BASE);
    regs[offset / 4u] = value;
    ++writes;
    if (offset == GPU_REG_QOS_WATERMARKS) qos_mode = (value & GPU_QOS_ADAPTIVE) != 0;
    if (offset == GPU_REG_PERF_CONTROL && (value & GPU_PERF_CONTROL_CLEAR)) {
        regs[GPU_REG_PERF_CYCLES_LO / 4] = 0;
        regs[GPU_REG_PERF_READ_BYTES_LO / 4] = 0;
    }
    if (offset == GPU_REG_CONTROL && (value & GPU_CONTROL_SUBMIT)) {
        uint32_t command_hash = regs[GPU_REG_OP / 4] ^ regs[GPU_REG_SRC_ADDR / 4] ^
            regs[GPU_REG_DST_ADDR / 4] ^ regs[GPU_REG_SIZE / 4] ^
            regs[GPU_REG_SRC_STRIDE / 4] ^ regs[GPU_REG_DST_STRIDE / 4] ^
            regs[GPU_REG_COLOR_KEY / 4] ^ regs[GPU_REG_ALPHA_FLAGS / 4];
        stream_hash[qos_mode] = stream_hash[qos_mode] * 16777619u ^ command_hash;
        ++stream_count[qos_mode];
        ++regs[GPU_REG_PERF_CYCLES_LO / 4];
        if ((regs[GPU_REG_OP / 4] & GPU_OP_MASK) == GPU_OP_COLOR_KEY)
            regs[GPU_REG_PERF_READ_BYTES_LO / 4] += 128;
        if ((regs[GPU_REG_OP / 4] & GPU_OP_MASK) == GPU_OP_SPARSE)
            regs[GPU_REG_PERF_READ_BYTES_LO / 4] += 64;
        regs[GPU_REG_LAST_DONE / 4] = regs[GPU_REG_TAG / 4];
        regs[GPU_REG_STATUS / 4] = GPU_STATUS_EMPTY;
    }
}

int main(void) {
    regs[GPU_REG_ID / 4] = GPU_ID_VALUE;
    regs[GPU_REG_VERSION / 4] = GPU_VERSION_VALUE;
    regs[GPU_REG_STATUS / 4] = GPU_STATUS_EMPTY;
    gpu_device device;
    assert(gpu_init(&device, GPU_APB_BASE) == 0);

    assert(gpu_set_qos(&device, 256, 1536, 1) == 0);
    assert(regs[GPU_REG_QOS_WATERMARKS / 4] == gpu_pack_qos(256, 1536, 1));
    unsigned before = writes;
    assert(gpu_set_qos(&device, 1536, 256, 1) == GPU_DRIVER_ARGUMENT);
    assert(writes == before);
    assert(gpu_set_qos(&device, 1, 4096, 1) == GPU_DRIVER_ARGUMENT);

    regs[GPU_REG_PERF_CYCLES_LO / 4] = 0x76543210u;
    regs[GPU_REG_PERF_CYCLES_HI / 4] = 0xfedcba98u;
    regs[GPU_REG_PERF_STALLS_LO / 4] = 11;
    regs[GPU_REG_PERF_UNDERFLOWS_LO / 4] = 2;
    regs[GPU_REG_PERF_RENDER_GRANTS_LO / 4] = 33;
    regs[GPU_REG_PERF_SCANOUT_GRANTS_LO / 4] = 44;
    gpu_perf_snapshot perf;
    assert(gpu_read_perf_snapshot(&device, &perf) == 0);
    assert(perf.cycles == UINT64_C(0xfedcba9876543210));
    assert(perf.stalls == 11 && perf.underflows == 2);
    assert(perf.render_grants == 33 && perf.scanout_grants == 44);
    assert(regs[GPU_REG_PERF_CONTROL / 4] == GPU_PERF_CONTROL_SNAPSHOT);

    uint16_t tag = 0;
    assert(gpu_sparse_async(&device, GPU_SPARSE_ASSETS, GPU_FRAMEBUFFER_A,
                            1280, 8, 8, &tag) == 0);
    assert(regs[GPU_REG_OP / 4] == GPU_OP_SPARSE);
    assert(regs[GPU_REG_SRC_ADDR / 4] == GPU_SPARSE_ASSETS);
    assert(regs[GPU_REG_DST_STRIDE / 4] == 1280);

    game_state game;
    game_command_stream commands;
    game_init(&game);
    assert(game_build_commands_mode(&game, GPU_FRAMEBUFFER_B, 1, &commands) == 0);
    assert(commands.commands[1].op == GPU_OP_SPARSE);
    assert(commands.commands[1].src_addr == gpu_demo_sparse_asset.address);

    gpu_qos_benchmark_result result = {
        .fixed = {.cpu_cycles = 1000, .render_stalls = 90, .underflows = 4,
                  .render_grants = 70, .scanout_grants = 80, .frame_crc = 0x12345678},
        .adaptive = {.cpu_cycles = 1010, .render_stalls = 100, .underflows = 0,
                     .render_grants = 65, .scanout_grants = 100, .frame_crc = 0x12345678},
        .dense_bytes = 512, .sparse_bytes = 192
    };
    assert(gpu_qos_benchmark_validate(&result) == 0);
    assert(result.adaptive.underflows < result.fixed.underflows);
    result.adaptive.frame_crc++;
    assert(gpu_qos_benchmark_validate(&result) == GPU_DRIVER_HARDWARE);

    gpu_command identical[] = {
        {.op=GPU_OP_FILL,.dst_addr=GPU_FRAMEBUFFER_B,.dst_stride=1280,
         .width_pixels=8,.height_pixels=8,.color=0},
        {.op=GPU_OP_SPARSE,.src_addr=GPU_SPARSE_ASSETS,.dst_addr=GPU_FRAMEBUFFER_B,
         .dst_stride=1280,.width_pixels=8,.height_pixels=8}
    };
    uint8_t frame[128] = {0};
    memset(stream_hash, 0, sizeof stream_hash);
    memset(stream_count, 0, sizeof stream_count);
    assert(gpu_benchmark_qos_compare(&device, identical, 2, 16, frame, sizeof frame,
                                     128, 64, &result) == 0);
    assert(stream_count[0] == 2 && stream_count[1] == 2);
    assert(stream_hash[0] == stream_hash[1]);
    assert(result.fixed.frame_crc == result.adaptive.frame_crc);
    assert(gpu_command_stream_hash(identical,2,2166136261u)==
           gpu_command_stream_hash(identical,2,2166136261u));
    gpu_command changed=identical[1]; changed.dst_addr+=2;
    assert(gpu_command_stream_hash(&changed,1,2166136261u)!=
           gpu_command_stream_hash(&identical[1],1,2166136261u));
    uint64_t previous_underflows = 4;
    assert(benchmark_counter_delta(5, &previous_underflows) == 1);
    assert(previous_underflows == 5);
    assert(benchmark_counter_delta(UINT64_C(70000), &previous_underflows) == UINT16_MAX);

    gpu_command dense_compare[] = {
        {.op=GPU_OP_FILL,.dst_addr=GPU_FRAMEBUFFER_A,.dst_stride=1280,
         .width_pixels=8,.height_pixels=8,.color=0},
        {.op=GPU_OP_COLOR_KEY,.src_addr=GPU_DENSE_ASSETS,.dst_addr=GPU_FRAMEBUFFER_A,
         .src_stride=16,.dst_stride=1280,.width_pixels=8,.height_pixels=8,.color_key=0}
    };
    gpu_command sparse_compare[] = {
        {.op=GPU_OP_FILL,.dst_addr=GPU_FRAMEBUFFER_B,.dst_stride=1280,
         .width_pixels=8,.height_pixels=8,.color=0},
        {.op=GPU_OP_SPARSE,.src_addr=GPU_SPARSE_ASSETS,.dst_addr=GPU_FRAMEBUFFER_B,
         .dst_stride=1280,.width_pixels=8,.height_pixels=8}
    };
    uint8_t dense_frame[128] = {0}, sparse_frame[128] = {0};
    gpu_sparse_benchmark_result sparse_result;
    assert(gpu_benchmark_sparse_compare(&device,dense_compare,sparse_compare,2,16,
        dense_frame,sparse_frame,sizeof dense_frame,128,64,&sparse_result)==0);
    assert(sparse_result.dense_crc==sparse_result.sparse_crc);
    assert(sparse_result.dense.read_bytes==128 && sparse_result.sparse.read_bytes==64);

    hud_metrics metrics = {.fps = 60, .sprite_count = 48, .render_stalls = 9,
        .underflow_count = 0, .qos_adaptive = 1};
    hud_command_stream stream;
    assert(hud_build_metrics(GPU_FRAMEBUFFER_A, 1280, 8, 8, &metrics, &stream) == 0);
    assert(stream.count && stream.count <= HUD_MAX_COMMANDS);

    puts("PASS B days21-23: Sparse submit, QoS guards, 64-bit perf snapshot, comparison contract and HUD");
    return 0;
}
