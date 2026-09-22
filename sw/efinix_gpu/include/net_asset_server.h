#ifndef EFINIX_NET_ASSET_SERVER_H
#define EFINIX_NET_ASSET_SERVER_H
#include <stdint.h>
#include <stddef.h>
#include "asset_protocol.h"
typedef struct { uint32_t id; const uint8_t *data; size_t length; } asset_server_entry;
typedef struct { const asset_server_entry *entries; size_t count; } asset_server;
int asset_server_handle_get(const asset_server *s,const uint8_t *request,size_t request_len,uint8_t *response,size_t response_cap,size_t *response_len);
typedef int (*asset_io_exchange)(void *ctx,const uint8_t *request,size_t request_len,uint8_t *response,size_t response_cap,size_t *response_len,uint32_t timeout_ms);
int asset_fetch(asset_io_exchange io,void *ctx,uint32_t session,uint32_t asset_id,size_t total,uint32_t full_crc,uint8_t *dst,size_t dst_cap,uint32_t timeout_ms,unsigned retries);
#endif
