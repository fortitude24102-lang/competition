#ifndef EFINIX_ASSET_CACHE_H
#define EFINIX_ASSET_CACHE_H
#include <stdint.h>
#include <stddef.h>
#include "asset_protocol.h"

typedef struct { uint8_t *data; size_t capacity, length; uint32_t asset_id, expected_crc; int active; uint8_t *backup; size_t committed_length; uint32_t committed_id, committed_crc; } asset_cache;
int asset_cache_begin(asset_cache *c, uint32_t id, size_t length, uint32_t crc);
int asset_cache_write(asset_cache *c, size_t offset, const void *data, size_t length);
int asset_cache_commit(asset_cache *c);
void asset_cache_abort(asset_cache *c);
int asset_cache_valid(const asset_cache *c, uint32_t id, uint32_t crc);
#endif
