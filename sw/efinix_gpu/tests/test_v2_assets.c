#include "asset_protocol.h"
#include "asset_cache.h"
#include "net_asset_server.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const asset_server *g; static int drop,corrupt;
static int io(void*ctx,const uint8_t*q,size_t qn,uint8_t*r,size_t cap,size_t*n,uint32_t t){
 (void)ctx;(void)t;if(drop){drop=0;return -1;}
 asst_header request; assert(asst_decode(&request,q)==0 && request.type==ASST_GET);
 int result=asset_server_handle_get(g,q,qn,r,cap,n);
 if(!result && corrupt) { r[11]^=0x40; corrupt=0; }
 return result;
}
int main(void){uint8_t data[2050],dst[2050],buf[2050],backup[2050];for(size_t i=0;i<sizeof data;i++)data[i]=(uint8_t)i;asset_server_entry e={7,data,sizeof data};asset_server s={&e,1};g=&s;assert(asset_fetch(io,0,3,7,sizeof data,asst_crc32(data,sizeof data),dst,sizeof dst,20,5)==0);assert(!memcmp(data,dst,sizeof data));asset_cache c={.data=buf,.backup=backup,.capacity=sizeof buf};assert(asset_cache_begin(&c,7,sizeof data,asst_crc32(data,sizeof data))==0);assert(asset_cache_write(&c,0,data,1000)==0);assert(asset_cache_write(&c,1000,data+1000,sizeof data-1000)==0);assert(asset_cache_commit(&c)==0&&asset_cache_valid(&c,7,asst_crc32(data,sizeof data)));assert(asset_cache_begin(&c,7,sizeof data,0)==0);assert(asset_cache_write(&c,0,data,sizeof data)==0);assert(asset_cache_commit(&c)<0&& asset_cache_valid(&c,7,asst_crc32(data,sizeof data)));drop=1;assert(asset_fetch(io,0,3,7,sizeof data,asst_crc32(data,sizeof data),dst,sizeof dst,20,5)==0);
corrupt=1;assert(asset_fetch(io,0,3,7,sizeof data,asst_crc32(data,sizeof data),dst,sizeof dst,20,5)==0);
uint8_t request[32],response[1056];size_t response_len=0;asst_header h={.magic=ASST_MAGIC,.version=1,.type=ASST_GET,.session=3,.asset_id=7,.offset=0,.payload_len=1024,.sequence=0};assert(asst_encode(request,&h)==0);request[23]=ASST_LAST;assert(asset_server_handle_get(&s,request,32,response,sizeof response,&response_len)<0);request[23]=0;request[31]=1;assert(asset_server_handle_get(&s,request,32,response,sizeof response,&response_len)<0);puts("PASS v2 asset server/retry/cache, rejected reply cannot mutate GET");}
