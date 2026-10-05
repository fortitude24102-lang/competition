#ifndef NET_CONTROL_H
#define NET_CONTROL_H
#include <stdint.h>
#include "gpu_regs.h"
#include "v3_control_protocol.h"

typedef struct {
    uint32_t session, sequence, action_sequence, age_ms;
    uint16_t keys;
    uint8_t connected;
} nc_input;

/* Wire order is explicit in the serializer; no structure memcpy to packets. */
typedef struct {
    uint32_t firmware_build_id, resource_epoch, simulation_tick;
    uint32_t requested_sprites, visible_sprites, gpu_full_frame_fps_x100;
    uint32_t cpu_full_frame_fps_x100, pre_present_us, gpu_busy_us;
    uint32_t command_build_us, submit_blocked_us, background_copy_us;
    uint32_t render_read_bytes, render_write_bytes, texture_cache_bytes;
    uint32_t scanout_underflow_delta, gpu_error_delta, missed_vblank_delta;
    uint32_t asset_retry_delta, control_drop_delta, input_age_ms;
    uint32_t status_flags, p95_work_us, present_wait_us;
    uint32_t alpha_commands, alpha_pixels, key_commands;
} nc_telemetry;

enum { NC_ERROR_ARGUMENT = -1, NC_ERROR_UNAVAILABLE = -2,
       NC_ERROR_HARDWARE = -3 };

typedef struct {
    uintptr_t base;
    nc_input input;
    nc_telemetry pending_telemetry;
    uint32_t received_ms, hello_sequence, retired_session;
    uint32_t ack_session, ack_sequence, snapshot_id;
    uint32_t last_publish_ms, publish_interval_ms;
    uint32_t rejected_packets;
    uint8_t ready, ack_pending, telemetry_pending, published;
} nc_device;

/* apb_base is the GPU block base. Zero selects GPU_APB_BASE.
   Initialization discards up to four pre-existing RX records.
   Return <0 on error, 0 without progress, >0 on progress (init returns 0).
   now_ms and RX_AGE_MS use the same 1ms GPU-clock timebase, modulo 2^32.
   publish_interval_ms may be set by the caller; values below 100 clamp to 100.
   A NULL telemetry pointer flushes a queued ACK/latest snapshot only. */
int nc_init(nc_device *device, uintptr_t apb_base);
int nc_poll(nc_device *device, uint32_t now_ms, nc_input *input);
int nc_try_publish(nc_device *device, const nc_telemetry *telemetry, uint32_t now_ms);
#endif
