#ifndef EFINIX_ASSET_PROTOCOL_H
#define EFINIX_ASSET_PROTOCOL_H
#include <stdint.h>
#define ASST_MAGIC UINT32_C(0x41535354)
#define ASST_VERSION 1u
#define ASST_HEADER_BYTES 32u
#define ASST_MAX_PAYLOAD 1024u
enum asst_type { ASST_GET=1, ASST_DATA=2, ASST_ERROR=3 };
enum asst_flags { ASST_LAST=1, ASST_RETRY=2 };
typedef struct { uint32_t magic,session,asset_id,offset,sequence,payload_crc32; uint16_t version,type,payload_len,flags; } asst_header;
uint32_t asst_crc32(const void *data, uint32_t length);
int asst_encode(uint8_t out[32], const asst_header *h);
int asst_decode(asst_header *h, const uint8_t in[32]);
#endif
