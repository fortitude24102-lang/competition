#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "assets.h"
#include "framebuffer.h"
#include "game.h"
#include "golden_renderer.h"
#include "hud.h"

static uint32_t regs[32];
static uint8_t frame_a[GPU_FRAME_BYTES], frame_b[GPU_FRAME_BYTES], expected_frame_b[GPU_FRAME_BYTES];
static uint16_t dense_assets[2048];
static int present_pending;
static uint32_t present_destination;
static unsigned fake_vblank_countdown, fake_vblank_events;

static void fake_vblank(void) {
    assert(present_pending);
    assert((regs[GPU_REG_STATUS / 4] & GPU_STATUS_BUSY) != 0);
    assert(regs[GPU_REG_FRONT_BUFFER / 4] != present_destination);
    regs[GPU_REG_FRONT_BUFFER / 4] = present_destination;
    regs[GPU_REG_LAST_DONE / 4] = regs[GPU_REG_TAG / 4] & GPU_TAG_MASK;
    regs[GPU_REG_STATUS / 4] = GPU_STATUS_EMPTY;
    present_pending = 0;
    ++fake_vblank_events;
}

static uint8_t *map_address(uint32_t address, size_t bytes) {
    uint32_t offset;
    if (address >= GPU_FRAMEBUFFER_A && address < GPU_FRAMEBUFFER_A + GPU_FRAME_BYTES) {
        offset = address - GPU_FRAMEBUFFER_A;
        return offset + bytes <= sizeof frame_a ? frame_a + offset : NULL;
    }
    if (address >= GPU_FRAMEBUFFER_B && address < GPU_FRAMEBUFFER_B + GPU_FRAME_BYTES) {
        offset = address - GPU_FRAMEBUFFER_B;
        return offset + bytes <= sizeof frame_b ? frame_b + offset : NULL;
    }
    if (address >= GPU_DENSE_ASSETS && address < GPU_DENSE_ASSETS + sizeof dense_assets) {
        offset = address - GPU_DENSE_ASSETS;
        return offset + bytes <= sizeof dense_assets ? (uint8_t *)dense_assets + offset : NULL;
    }
    return NULL;
}

uint32_t gpu_io_read(uintptr_t address) {
    if (present_pending && fake_vblank_countdown && --fake_vblank_countdown == 0)
        fake_vblank();
    return regs[(address - GPU_APB_BASE) / 4];
}
void gpu_io_fence(void) {}
void gpu_io_write(uintptr_t address, uint32_t value) {
    unsigned offset = (unsigned)(address - GPU_APB_BASE);
    regs[offset / 4] = value;
    if (offset == GPU_REG_CONTROL && (value & GPU_CONTROL_SUBMIT)) {
        unsigned op = regs[GPU_REG_OP / 4] & GPU_OP_MASK;
        unsigned width = regs[GPU_REG_SIZE / 4] & GPU_WIDTH_MASK;
        unsigned height = regs[GPU_REG_SIZE / 4] >> GPU_HEIGHT_SHIFT;
        uint32_t src = regs[GPU_REG_SRC_ADDR / 4], dst = regs[GPU_REG_DST_ADDR / 4];
        uint32_t src_stride = regs[GPU_REG_SRC_STRIDE / 4], dst_stride = regs[GPU_REG_DST_STRIDE / 4];
        if (op == GPU_OP_FILL) {
            uint16_t color = (uint16_t)regs[GPU_REG_COLOR_KEY / 4];
            for (unsigned y = 0; y < height; ++y) {
                uint8_t *row = map_address(dst + y * dst_stride, width * 2u); assert(row);
                for (unsigned x = 0; x < width; ++x) { row[x*2] = (uint8_t)color; row[x*2+1] = color >> 8; }
            }
        } else if (op == GPU_OP_COPY) {
            for (unsigned y = 0; y < height; ++y) {
                uint8_t *from = map_address(src + y * src_stride, width * 2u);
                uint8_t *to = map_address(dst + y * dst_stride, width * 2u);
                assert(from && to); memcpy(to, from, width * 2u);
            }
        } else if (op == GPU_OP_PRESENT) {
            present_pending = 1;
            present_destination = dst;
            regs[GPU_REG_STATUS / 4] = GPU_STATUS_BUSY;
            return;
        }
        regs[GPU_REG_LAST_DONE / 4] = regs[GPU_REG_TAG / 4] & GPU_TAG_MASK;
        regs[GPU_REG_STATUS / 4] = GPU_STATUS_EMPTY;
    }
}

static uint16_t pixel(const uint8_t *frame, unsigned x, unsigned y) {
    unsigned offset = y * GPU_FRAME_WIDTH * 2u + x * 2u;
    return (uint16_t)(frame[offset] | (uint16_t)frame[offset + 1] << 8);
}

int main(void) {
    gpu_device device;
    uint16_t tag;
    memset(regs, 0, sizeof regs);
    regs[GPU_REG_ID / 4] = GPU_ID_VALUE;
    regs[GPU_REG_VERSION / 4] = GPU_VERSION_VALUE;
    regs[GPU_REG_STATUS / 4] = GPU_STATUS_EMPTY;
    regs[GPU_REG_FRONT_BUFFER / 4] = GPU_FRAMEBUFFER_A;
    regs[GPU_REG_BACK_BUFFER / 4] = GPU_FRAMEBUFFER_B;
    assert(gpu_init(&device, GPU_APB_BASE) == 0);

    assert(gpu_assets_upload_dense(dense_assets, sizeof dense_assets / sizeof dense_assets[0]) == GPU_ASSET_WORDS);
    assert(dense_assets[0] == gpu_player_asset.pixels[0]);
    memset(frame_b, 0xa5, sizeof frame_b);
    memset(expected_frame_b, 0xa5, sizeof expected_frame_b);
    golden_surface expected_dst={expected_frame_b,sizeof expected_frame_b,640,480,1280};
    golden_surface expected_src={(uint8_t *)dense_assets,GPU_ASSET_WORDS*2u,8,8,16};
    assert(golden_copy(&expected_dst,10,10,&expected_src,0,0,8,8)==GPU_ERROR_NONE);
    assert(gpu_copy_async(&device, gpu_player_asset.address, GPU_FRAMEBUFFER_B + 10u*1280u + 20u,
        gpu_player_asset.stride_bytes, 1280, gpu_player_asset.width, gpu_player_asset.height, &tag) == 0);
    assert(gpu_wait_tag(&device, tag, 2) == 0);
    assert(golden_crc32(frame_b,sizeof frame_b)==golden_crc32(expected_frame_b,sizeof expected_frame_b));
    assert(memcmp(frame_b,expected_frame_b,sizeof frame_b)==0);

    tag=0x55aa;
    assert(gpu_copy_async(&device,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_B,16,1280,0,8,&tag)==GPU_ERROR_ZERO_SIZE && tag==0x55aa);
    assert(gpu_copy_async(&device,GPU_DENSE_ASSETS+1,GPU_FRAMEBUFFER_B,16,1280,8,8,&tag)==GPU_ERROR_MISALIGNED_ADDRESS && tag==0x55aa);
    assert(gpu_copy_async(&device,GPU_DENSE_ASSETS,GPU_FRAMEBUFFER_B,16,14,8,8,&tag)==GPU_ERROR_STRIDE_TOO_SMALL && tag==0x55aa);
    assert(gpu_copy_async(&device,GPU_FRAMEBUFFER_A,GPU_FRAMEBUFFER_A+2,1280,1280,8,1,&tag)==GPU_ERROR_OVERLAPPING_COPY && tag==0x55aa);
    assert(gpu_copy_async(&device,GPU_DDR_END_EXCLUSIVE-2,GPU_FRAMEBUFFER_B,4,4,2,1,&tag)==GPU_ERROR_ADDRESS_RANGE && tag==0x55aa);
    assert(gpu_copy_async(&device,GPU_DENSE_ASSETS+sizeof dense_assets-2,GPU_FRAMEBUFFER_B,2,2,1,1,&tag)==0);
    assert(gpu_wait_tag(&device,tag,2)==0);

    framebuffer_pair buffers;
    framebuffer_init(&buffers);
    assert(buffers.front == GPU_FRAMEBUFFER_A && buffers.back == GPU_FRAMEBUFFER_B);
    fake_vblank_countdown=4;
    assert(framebuffer_present(&device, &buffers, 2) == 0);
    assert(buffers.front == GPU_FRAMEBUFFER_B && buffers.back == GPU_FRAMEBUFFER_A);
    assert(regs[GPU_REG_FRONT_BUFFER / 4] == GPU_FRAMEBUFFER_B);
    assert(regs[GPU_REG_SIZE / 4] == 0x00010001u && regs[GPU_REG_DST_STRIDE / 4] == 2);
    assert(fake_vblank_events==1);
    assert(gpu_present_async(&device,GPU_FRAMEBUFFER_A,&tag)==0);
    assert(gpu_wait_tag(&device,tag,1)==GPU_DRIVER_TIMEOUT);
    assert(regs[GPU_REG_FRONT_BUFFER / 4]==GPU_FRAMEBUFFER_B && present_pending);
    fake_vblank();
    assert(gpu_wait_tag(&device,tag,1)==0 && regs[GPU_REG_FRONT_BUFFER / 4]==GPU_FRAMEBUFFER_A);

    assert(hud_draw_fps(&device, GPU_FRAMEBUFFER_A, 1280, 4, 4, 60, 0xffff, 2, 2) == 0);
    assert(pixel(frame_a, 4, 4) == 0xffff);
    assert(pixel(frame_a, 6, 6) == 0x0000);
    assert(pixel(frame_a, 12, 4) == 0xffff);
    assert(pixel(frame_a, 14, 8) == 0x0000);

    game_state game;
    game_init(&game);
    assert(game.enemy_count == GAME_MAX_ENEMIES && game.bullet_count == 0);
    for (unsigned frame = 0; frame < 300; ++frame) {
        unsigned input = (frame & 32) ? GAME_INPUT_RIGHT : GAME_INPUT_LEFT;
        if (frame % 9 == 0) input |= GAME_INPUT_FIRE;
        game_step(&game, input, 16);
        assert(game.player.x >= 0 && game.player.x <= (int)(GPU_FRAME_WIDTH - game.player.width));
        assert(game.bullet_count <= GAME_MAX_BULLETS && game.enemy_count <= GAME_MAX_ENEMIES);
    }
    assert(game.tick == 300 && game.bullet_count > 0);
    puts("PASS A/B day9-13 software: sprite copy, fixed DDR layout, present contract, HUD and 300-frame fixed object pool");
    return 0;
}
