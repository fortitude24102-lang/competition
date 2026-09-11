#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "assets.h"
#include "benchmark.h"
#include "game.h"
#include "hud.h"

static uint32_t regs[32];
static uint16_t queued_tags[GPU_COMMAND_QUEUE_DEPTH];
static unsigned queue_head, queue_count, accepted, completed;
static int allow_completion;
static uint8_t next_completion_error;
static unsigned last_done_read_phase;

uint64_t gpu_platform_cycles(void) { static uint64_t cycles; return ++cycles; }
void gpu_platform_sync(void) {}
void gpu_io_fence(void) {}

static void update_status(void) {
    regs[GPU_REG_STATUS / 4] = queue_count & GPU_STATUS_QUEUE_LEVEL_MASK;
    if (!queue_count) regs[GPU_REG_STATUS / 4] |= GPU_STATUS_EMPTY;
    if (queue_count == GPU_COMMAND_QUEUE_DEPTH) regs[GPU_REG_STATUS / 4] |= GPU_STATUS_FULL;
    if (queue_count) regs[GPU_REG_STATUS / 4] |= GPU_STATUS_BUSY;
    regs[GPU_REG_QUEUE_LEVEL / 4] = queue_count;
}

uint32_t gpu_io_read(uintptr_t address) {
    unsigned offset = (unsigned)(address - GPU_APB_BASE);
    if (offset == GPU_REG_LAST_DONE && allow_completion) {
        if (!last_done_read_phase && queue_count) {
            regs[GPU_REG_LAST_DONE / 4] = queued_tags[queue_head];
            regs[GPU_REG_ERROR / 4] = next_completion_error;
            next_completion_error = 0;
            queue_head = (queue_head + 1u) % GPU_COMMAND_QUEUE_DEPTH;
            --queue_count;
            ++completed;
            update_status();
            last_done_read_phase = 1;
        } else if (last_done_read_phase) {
            last_done_read_phase = 0;
        }
    }
    return regs[offset / 4];
}

void gpu_io_write(uintptr_t address, uint32_t value) {
    unsigned offset = (unsigned)(address - GPU_APB_BASE);
    regs[offset / 4] = value;
    if (offset == GPU_REG_CONTROL && (value & GPU_CONTROL_SUBMIT)) {
        assert(queue_count < GPU_COMMAND_QUEUE_DEPTH);
        queued_tags[(queue_head + queue_count) % GPU_COMMAND_QUEUE_DEPTH] =
            (uint16_t)regs[GPU_REG_TAG / 4];
        ++queue_count;
        ++accepted;
        update_status();
    }
}

static gpu_command fill_command(uint32_t offset) {
    gpu_command command = {
        .op = GPU_OP_FILL,
        .dst_addr = GPU_FRAMEBUFFER_A + offset,
        .dst_stride = 1280,
        .width_pixels = 1,
        .height_pixels = 1,
        .color = 0x1234
    };
    return command;
}

int main(void) {
    regs[GPU_REG_ID / 4] = GPU_ID_VALUE;
    regs[GPU_REG_VERSION / 4] = GPU_VERSION_VALUE;
    update_status();

    gpu_device device;
    assert(gpu_init(&device, GPU_APB_BASE) == 0);

    /* Day 16: the same advanced frame contains both Color Key and Alpha. */
    uint16_t dense[GPU_ASSET_WORDS];
    assert(gpu_assets_upload_dense(dense, GPU_ASSET_WORDS) == GPU_ASSET_WORDS);
    assert(gpu_enemy_asset.address == gpu_player_asset.address + 8u * 8u * 2u);
    game_state game;
    game_init(&game);
    game_command_stream frame;
    assert(game_build_commands(&game, GPU_FRAMEBUFFER_A, &frame) == 0);
    assert(frame.count == 2u + GAME_MAX_ENEMIES);
    assert(frame.commands[0].op == GPU_OP_FILL);
    assert(frame.commands[1].op == GPU_OP_COLOR_KEY);
    for (unsigned i = 0; i < GAME_MAX_ENEMIES; ++i)
        assert(frame.commands[2u + i].op == GPU_OP_ALPHA);

    /* Day 17: 16 accepted commands survive; the 17th reports AGAIN. */
    uint16_t tag = 0;
    for (unsigned i = 0; i < GPU_COMMAND_QUEUE_DEPTH; ++i) {
        gpu_command command = fill_command(i * 2u);
        assert(gpu_try_submit(&device, &command, &tag) == 0);
        assert(tag == i + 1u);
    }
    gpu_command extra = fill_command(64u);
    assert(gpu_try_submit(&device, &extra, &tag) == GPU_DRIVER_AGAIN);
    assert(accepted == GPU_COMMAND_QUEUE_DEPTH && completed == 0);
    allow_completion = 1;
    assert(gpu_submit(&device, &extra, 64, &tag) == 0 && tag == 17u);
    assert(gpu_wait_tag(&device, tag, 128) == 0);
    assert(accepted == 17u && completed == 17u && device.outstanding == 0);

    /* Day 18: both modes consume the exact same command list. */
    gpu_submit_metrics wait_each, batch;
    unsigned accepted_before = accepted;
    assert(gpu_benchmark_submit_stream(&device, frame.commands, frame.count,
        GPU_SUBMIT_WAIT_EACH, 128, &wait_each) == 0);
    assert(accepted - accepted_before == frame.count);
    accepted_before = accepted;
    assert(gpu_benchmark_submit_stream(&device, frame.commands, frame.count,
        GPU_SUBMIT_BATCH, 128, &batch) == 0);
    assert(accepted - accepted_before == frame.count);
    assert(wait_each.command_count == batch.command_count);
    assert(wait_each.wait_count == frame.count && batch.wait_count == 1u);
    assert(batch.queue_high_watermark > 1u);

    /* Day 19: HUD includes all required live fields in a bounded list. */
    hud_metrics hud = {
        .fps = 73, .sprite_count = 17, .cpu_busy_permille = 125,
        .queue_high_watermark = 16, .underflow_count = 2,
        .error_code = 9, .batch_mode = 1
    };
    hud_command_stream overlay;
    assert(hud_build_metrics(GPU_FRAMEBUFFER_A, 1280, 8, 8, &hud, &overlay) == 0);
    assert(overlay.count > 0 && overlay.count <= HUD_MAX_COMMANDS);
    assert(hud_build_metrics(GPU_FRAMEBUFFER_A, 1280, 514, 8, &hud, &overlay) == GPU_DRIVER_ARGUMENT);
    assert(hud_build_metrics(GPU_FRAMEBUFFER_A, 1280, 8, 476, &hud, &overlay) == GPU_DRIVER_ARGUMENT);

    /* Day 20: deterministic 300-frame P5 and stable-60 decision. */
    benchmark_frame_sample samples[BENCHMARK_FRAME_COUNT];
    for (unsigned i = 0; i < BENCHMARK_FRAME_COUNT; ++i)
        samples[i] = (benchmark_frame_sample){.fps = 70, .sprite_count = 48};
    benchmark_run_summary summary;
    assert(benchmark_summarize_run(samples, BENCHMARK_FRAME_COUNT, &summary) == 0);
    assert(summary.p5_fps == 70 && summary.stable_sprite_count == 48);
    for (unsigned i = 0; i < BENCHMARK_FRAME_COUNT; ++i)
        samples[i] = (benchmark_frame_sample){.fps = 60, .sprite_count = 20};
    samples[0] = (benchmark_frame_sample){.fps = 60, .sprite_count = 99};
    assert(benchmark_summarize_run(samples, BENCHMARK_FRAME_COUNT, &summary) == 0);
    assert(summary.p5_fps == 60 && summary.stable_sprite_count == 20);
    for (unsigned i = 0; i < BENCHMARK_FRAME_COUNT; ++i)
        samples[i] = (benchmark_frame_sample){.fps = 70, .sprite_count = 48};
    samples[10].underflow_count = 1;
    assert(benchmark_summarize_run(samples, BENCHMARK_FRAME_COUNT, &summary) == 0);
    assert(summary.stable_sprite_count == 0 && summary.total_underflows == 1);

    /* Completion and error change together: the driver must not sample the
       old error before observing the new LAST_DONE tag. */
    regs[GPU_REG_ERROR / 4] = 0;
    gpu_device error_device;
    assert(gpu_init(&error_device, GPU_APB_BASE) == 0);
    next_completion_error = GPU_ERROR_AXI_RESPONSE;
    assert(gpu_try_submit(&error_device, &extra, &tag) == 0);
    assert(gpu_wait_tag(&error_device, tag, 8) == GPU_DRIVER_HARDWARE);
    assert(error_device.hardware_error == GPU_ERROR_AXI_RESPONSE);

    puts("PASS B days16-20: advanced stream, 16-deep batch tags, mode metrics, HUD, 300-frame summary");
    return 0;
}
