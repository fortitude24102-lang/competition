#ifndef EFINIX_NETWORK_ASSETS_H
#define EFINIX_NETWORK_ASSETS_H
#include <stdint.h>
#include <stddef.h>

/* Board-side Ethernet registers share the Sapphire GPU APB window. */
enum {
 NET_REG_ID=0x0200, NET_REG_STATUS=0x0204, NET_REG_CONTROL=0x0208,
 NET_REG_LOCAL_IP=0x020c, NET_REG_PEER_IP=0x0210, NET_REG_PORTS=0x0214,
 NET_REG_RX_ERRORS=0x0218, NET_REG_TX_COUNT=0x021c, NET_REG_TX_DATA=0x0220
};
#define NET_ID UINT32_C(0x4e455431)
#define NET_RESPONSE_TIMEOUT_MS 20u
#define NET_TX_TIMEOUT_MS 100u
#define NET_MAX_RETRIES 5u
enum network_result {
 NETWORK_OK=0, NETWORK_ARGUMENT=-20, NETWORK_UNAVAILABLE=-21,
 NETWORK_TIMEOUT=-22, NETWORK_HARDWARE=-23, NETWORK_CRC=-24
};
typedef struct {
 uint32_t committed_bytes, requests, retries;
 uint64_t elapsed_ticks;
} network_asset_report;

int network_configure(uintptr_t base,uint32_t local_ip,uint32_t peer_ip,
                      uint16_t local_port,uint16_t peer_port);
/* DDR destination is unavailable to rendering until this returns NETWORK_OK.
 * Packet CRC is enforced by the RX parser before DMA; CPU checks whole-file CRC.
 * The timer frequency describes gpu_platform_cycles(), which uses CLINT ticks. */
int network_asset_fetch(uintptr_t base,uint32_t timer_hz,uint32_t session,
 uint32_t asset_id,uint32_t destination,uint32_t bytes,uint32_t crc32,
 network_asset_report *report);
int network_assets_load(uintptr_t base,uint32_t session);
#endif
