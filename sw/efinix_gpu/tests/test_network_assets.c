#include "network_assets.h"
#include "asset_dma.h"
#include "asset_protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint32_t regs[0x240/4];
static uint8_t resource[2051],memory[2051];
static uint64_t ticks;
static unsigned sent,restarts,aborts;
enum { NORMAL,DROP_FIRST,FAIL_FIRST,DROP_ALL,BAD_FILE,WRONG_PROGRESS,LATE_FINAL };
static unsigned fault;
uint64_t gpu_platform_cycles(void) { ticks+=10000; return ticks; }
void gpu_platform_sync(void) {}
void gpu_io_fence(void) {}
uint32_t network_asset_crc(uint32_t address,uint32_t bytes) {
 assert(address==GPU_DENSE_ASSETS && bytes==sizeof memory);
 return asst_crc32(memory,bytes);
}
uint32_t gpu_io_read(uintptr_t address) {
 assert(address>=GPU_APB_BASE && address<GPU_APB_BASE+sizeof regs);
 if(fault==LATE_FINAL && address==GPU_APB_BASE+GPU_REG_ASSET_COMMITTED_OFFSET &&
    regs[GPU_REG_ASSET_COMMITTED_OFFSET/4]==sizeof resource)
  regs[GPU_REG_ASSET_STATUS/4]=2;
 return regs[(address-GPU_APB_BASE)/4];
}
void gpu_io_write(uintptr_t address,uint32_t value) {
 unsigned offset=(unsigned)(address-GPU_APB_BASE);
 assert(offset<sizeof regs);
 regs[offset/4]=value;
 if(offset==GPU_REG_ASSET_CONTROL) {
  if(value==1) {
   ++restarts;
   regs[GPU_REG_ASSET_STATUS/4]=1;
   regs[GPU_REG_ASSET_COMMITTED_OFFSET/4]=regs[GPU_REG_ASSET_EXPECTED_OFFSET/4];
   regs[GPU_REG_ASSET_COMMITTED_SEQUENCE/4]=regs[GPU_REG_ASSET_EXPECTED_SEQUENCE/4];
  } else if(value==2) { ++aborts; regs[GPU_REG_ASSET_STATUS/4]=8; }
 }
 if(offset==NET_REG_CONTROL) {
  uint8_t header[32]; asst_header h;
  for(unsigned i=0;i<32;i++) header[i]=(uint8_t)(regs[(NET_REG_TX_DATA+i/4*4)/4]>>(i%4*8));
  assert(asst_decode(&h,header)==0);
  assert(value==1 && h.type==ASST_GET && h.session==123 && h.asset_id==7);
  assert(!h.payload_crc32 && !(h.flags&~ASST_RETRY));
  assert(h.offset+h.payload_len<=sizeof resource);
  assert(h.sequence==h.offset/1024);
  ++sent;
  if(sent==2 && (fault==DROP_FIRST || fault==FAIL_FIRST)) assert(h.flags==ASST_RETRY);
  regs[NET_REG_STATUS/4]=10; /* Ready, actual TX complete. */
  if(fault==DROP_ALL || (fault==DROP_FIRST && sent==1)) return;
  if(fault==FAIL_FIRST && sent==1) { regs[GPU_REG_ASSET_STATUS/4]=5; return; }
  memcpy(memory+h.offset,resource+h.offset,h.payload_len);
  if(fault==BAD_FILE) memory[0]^=1;
  regs[GPU_REG_ASSET_COMMITTED_OFFSET/4]=h.offset+h.payload_len;
  regs[GPU_REG_ASSET_COMMITTED_SEQUENCE/4]=h.sequence+1;
  if(fault==WRONG_PROGRESS) regs[GPU_REG_ASSET_COMMITTED_OFFSET/4]++;
  regs[GPU_REG_ASSET_STATUS/4]=h.offset+h.payload_len==sizeof resource ? 2:1;
  if(fault==LATE_FINAL) regs[GPU_REG_ASSET_STATUS/4]=1;
 }
}
static void reset(unsigned mode) {
 memset(regs,0,sizeof regs); memset(memory,0,sizeof memory);
 regs[NET_REG_ID/4]=NET_ID; regs[NET_REG_STATUS/4]=8;
 ticks=0; sent=0; restarts=0; aborts=0; fault=mode;
}
static int fetch(network_asset_report *r) {
 return network_asset_fetch(GPU_APB_BASE,100000000,123,7,GPU_DENSE_ASSETS,
  sizeof resource,asst_crc32(resource,sizeof resource),r);
}
int main(void) {
 for(unsigned i=0;i<sizeof resource;i++) resource[i]=(uint8_t)(i*37+9);
 network_asset_report r;
 reset(NORMAL);
 assert(!network_configure(GPU_APB_BASE,0xc0a80002,0xc0a80003,8080,8080));
 assert(regs[NET_REG_PORTS/4]==0x1f901f90);
 assert(fetch(&r)==NETWORK_OK && r.requests==3 && r.retries==0);
 assert(r.committed_bytes==sizeof resource && !memcmp(resource,memory,sizeof resource));
 reset(DROP_FIRST); assert(fetch(&r)==0 && r.requests==4 && r.retries==1);
 reset(FAIL_FIRST); assert(fetch(&r)==0 && restarts==2 && aborts==1);
 reset(DROP_ALL); assert(fetch(&r)==NETWORK_TIMEOUT);
 assert(sent==6 && r.retries==5 && r.committed_bytes==0 && aborts==6);
 reset(BAD_FILE); assert(fetch(&r)==NETWORK_CRC);
 reset(LATE_FINAL); assert(fetch(&r)==NETWORK_OK && sent==3);
 reset(WRONG_PROGRESS); assert(fetch(&r)!=NETWORK_OK);
 reset(NORMAL); regs[NET_REG_ID/4]=0;
 assert(fetch(&r)==NETWORK_UNAVAILABLE && sent==0);
 reset(NORMAL);
 assert(network_asset_fetch(GPU_APB_BASE,100000000,0,7,GPU_DENSE_ASSETS,4,0,&r)==NETWORK_ARGUMENT);
 assert(network_asset_fetch(GPU_APB_BASE,100000000,123,7,GPU_FRAMEBUFFER_A,4,0,&r)==NETWORK_ARGUMENT);
 assert(network_asset_fetch(GPU_APB_BASE,100000000,123,7,0xfffffffcu,8,0,&r)==NETWORK_ARGUMENT);
 assert(sent==0);
 puts("PASS network client: GET byte order, tail, retries, DMA restart, bounds, full CRC, bounded failure");
}
