#include "asset_cache.h"
#include <string.h>
#include <stdlib.h>
int asset_cache_begin(asset_cache*c,uint32_t id,size_t n,uint32_t crc){if(!c||!c->data||!n||n>c->capacity)return -1;if(!c->backup)c->backup=(uint8_t*)malloc(c->capacity);if(!c->backup)return -1;memcpy(c->backup,c->data,c->capacity);c->asset_id=id;c->expected_crc=crc;c->length=n;c->active=1;return 0;}
int asset_cache_write(asset_cache*c,size_t off,const void*p,size_t n){if(!c||!c->active||!p||off>c->length||n>c->length-off)return -1;memcpy(c->data+off,p,n);return 0;}
int asset_cache_commit(asset_cache*c){if(!c||!c->active)return -1;if(asst_crc32(c->data,(uint32_t)c->length)!=c->expected_crc){memcpy(c->data,c->backup,c->capacity);c->active=0;return -1;}c->committed_id=c->asset_id;c->committed_crc=c->expected_crc;c->committed_length=c->length;c->active=0;return 0;}
void asset_cache_abort(asset_cache*c){if(c&&c->active){memcpy(c->data,c->backup,c->capacity);c->active=0;}}
int asset_cache_valid(const asset_cache*c,uint32_t id,uint32_t crc){return c&& !c->active&&c->committed_id==id&&c->committed_crc==crc&&asst_crc32(c->data,(uint32_t)c->committed_length)==crc;}
