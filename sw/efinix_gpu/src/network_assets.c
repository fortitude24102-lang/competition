#include "network_assets.h"
#include "asset_dma.h"
#include "asset_protocol.h"
#include "asset_catalog.h"
#include "benchmark.h"

#ifdef GPU_TEST_BACKEND
uint32_t gpu_io_read(uintptr_t address);
void gpu_io_write(uintptr_t address,uint32_t value);
void gpu_io_fence(void);
uint32_t network_asset_crc(uint32_t address,uint32_t bytes);
#define NETWORK_TIMER_HZ 100000000u
#else
#include "bsp.h"
static uint32_t gpu_io_read(uintptr_t address) { return *(volatile uint32_t *)address; }
static void gpu_io_write(uintptr_t address,uint32_t value) { *(volatile uint32_t *)address=value; }
static void gpu_io_fence(void) { __asm__ volatile("fence iorw,iorw" ::: "memory"); }
static uint32_t network_asset_crc(uint32_t address,uint32_t bytes) {
 return asst_crc32((const void *)(uintptr_t)address,bytes);
}
#define NETWORK_TIMER_HZ BSP_CLINT_HZ
#endif

#ifndef NETWORK_LOCAL_IP
#define NETWORK_LOCAL_IP UINT32_C(0xc0a80002)
#endif
#ifndef NETWORK_PEER_IP
#define NETWORK_PEER_IP UINT32_C(0xc0a80003)
#endif
#define NETWORK_PORT 8080u

static uint32_t read_reg(uintptr_t base,uint32_t reg) { return gpu_io_read(base+reg); }
static void write_reg(uintptr_t base,uint32_t reg,uint32_t v) { gpu_io_write(base+reg,v); }
static uint64_t ticks_for_ms(uint32_t hz,unsigned ms) { return ((uint64_t)hz*ms+999u)/1000u; }

int network_configure(uintptr_t base,uint32_t local_ip,uint32_t peer_ip,
 uint16_t local_port,uint16_t peer_port) {
 if(!base || !local_ip || !peer_ip || !local_port || !peer_port) return NETWORK_ARGUMENT;
 if(read_reg(base,NET_REG_ID)!=NET_ID) return NETWORK_UNAVAILABLE;
 if(read_reg(base,NET_REG_STATUS)&1u) return NETWORK_HARDWARE;
 write_reg(base,NET_REG_LOCAL_IP,local_ip);
 write_reg(base,NET_REG_PEER_IP,peer_ip);
 write_reg(base,NET_REG_PORTS,((uint32_t)peer_port<<16)|local_port);
 gpu_io_fence();
 return NETWORK_OK;
}

static int stop_dma(uintptr_t base,uint32_t hz) {
 if(!(read_reg(base,GPU_REG_ASSET_STATUS)&1u)) return NETWORK_OK;
 asset_dma_abort(base);
 uint64_t start=gpu_platform_cycles();
 do {
  if(!(read_reg(base,GPU_REG_ASSET_STATUS)&1u)) return NETWORK_OK;
 } while(gpu_platform_cycles()-start<ticks_for_ms(hz,NET_RESPONSE_TIMEOUT_MS));
 return NETWORK_TIMEOUT;
}

static int send_get(uintptr_t base,uint32_t hz,const asst_header *request) {
 uint8_t header[ASST_HEADER_BYTES];
 if(asst_encode(header,request)) return NETWORK_ARGUMENT;
 uint64_t start=gpu_platform_cycles();
 uint32_t status;
 do {
  status=read_reg(base,NET_REG_STATUS);
  if(!(status&1u) && (status&8u)) break;
 } while(gpu_platform_cycles()-start<ticks_for_ms(hz,NET_TX_TIMEOUT_MS));
 if((status&1u) || !(status&8u)) return NETWORK_TIMEOUT;
 for(unsigned i=0;i<ASST_HEADER_BYTES;i+=4) {
  uint32_t word=(uint32_t)header[i]|((uint32_t)header[i+1]<<8)|
   ((uint32_t)header[i+2]<<16)|((uint32_t)header[i+3]<<24);
  write_reg(base,NET_REG_TX_DATA+i,word);
 }
 gpu_io_fence();
 write_reg(base,NET_REG_CONTROL,1);
 gpu_io_fence();
 start=gpu_platform_cycles();
 do {
  status=read_reg(base,NET_REG_STATUS);
  if(!(status&1u)) {
   if(status&4u) return NETWORK_HARDWARE;
   if(status&2u) return NETWORK_OK;
  }
 } while(gpu_platform_cycles()-start<ticks_for_ms(hz,NET_TX_TIMEOUT_MS));
 return NETWORK_TIMEOUT;
}

int network_asset_fetch(uintptr_t base,uint32_t hz,uint32_t session,
 uint32_t id,uint32_t destination,uint32_t bytes,uint32_t crc,
 network_asset_report *report) {
 if(!report) return NETWORK_ARGUMENT;
 *report=(network_asset_report){0};
 if(!base || !hz || !session || !bytes || (destination&3u) ||
    destination<GPU_DENSE_ASSETS || (uint64_t)destination+bytes>GPU_DDR_END_EXCLUSIVE)
  return NETWORK_ARGUMENT;
 if(read_reg(base,NET_REG_ID)!=NET_ID) return NETWORK_UNAVAILABLE;
 uint64_t begin=gpu_platform_cycles();
 asset_dma_descriptor descriptor={.session=session,.dst_addr=destination,
  .asset_id=id,.max_length=bytes};
 int result=asset_dma_start(base,&descriptor);
 if(result) return NETWORK_HARDWARE;
 uint32_t offset=0,sequence=0;
 while(offset<bytes) {
  uint16_t length=(uint16_t)(bytes-offset>ASST_MAX_PAYLOAD ? ASST_MAX_PAYLOAD : bytes-offset);
  int accepted=0;
  for(unsigned attempt=0;attempt<=NET_MAX_RETRIES;attempt++) {
   if(attempt) ++report->retries;
   /* Timeout can also leave a partial DMA packet pending (e.g. a link-domain
    * reset). Drain on every retry before replaying this same block. Late data
    * can safely overwrite the same unconfirmed block, never the next one. */
   uint32_t status=read_reg(base,GPU_REG_ASSET_STATUS);
   if(attempt || (status&(4u|8u)) || !(status&1u)) {
    result=stop_dma(base,hz);
    if(result) goto finished;
    descriptor.expected_offset=offset;
    descriptor.expected_sequence=sequence;
    if(asset_dma_start(base,&descriptor)) { result=NETWORK_HARDWARE; goto finished; }
   }
   asst_header request={.magic=ASST_MAGIC,.version=ASST_VERSION,.type=ASST_GET,
    .session=session,.asset_id=id,.offset=offset,.payload_len=length,
    .flags=attempt?ASST_RETRY:0,.sequence=sequence};
   ++report->requests;
   result=send_get(base,hz,&request);
   if(result) continue;
   uint64_t response_start=gpu_platform_cycles();
   result=NETWORK_TIMEOUT;
   do {
    asset_dma_snapshot snapshot;
    int state=asset_dma_poll(base,&snapshot);
    if(state==ASSET_DMA_HARDWARE) { result=NETWORK_HARDWARE; break; }
    /* offset and sequence are separate APB reads: wait for both, never infer
     * acceptance from a single read that could straddle packet commit. */
    if(snapshot.committed_offset==offset+length && snapshot.committed_sequence==sequence+1u) {
     int last=offset+length==bytes;
     /* LAST may commit after the first STATUS read but before progress reads. */
     uint32_t committed_status=read_reg(base,GPU_REG_ASSET_STATUS);
     if((committed_status&(4u|8u)) || !!(committed_status&2u)!=last) {
      result=NETWORK_HARDWARE; break;
     }
     offset+=length; ++sequence;
     report->committed_bytes=offset;
     accepted=1; result=NETWORK_OK;
     break;
    }
    if(snapshot.committed_offset>offset+length || snapshot.committed_sequence>sequence+1u) {
     result=NETWORK_HARDWARE; break;
    }
   } while(gpu_platform_cycles()-response_start<ticks_for_ms(hz,NET_RESPONSE_TIMEOUT_MS));
   if(accepted) break;
  }
  if(!accepted) goto finished;
 }
 gpu_platform_sync();
 result=network_asset_crc(destination,bytes)==crc ? NETWORK_OK : NETWORK_CRC;
finished:
 if(result!=NETWORK_OK) {
  int stopped=stop_dma(base,hz);
  if(stopped) result=stopped;
 }
 report->elapsed_ticks=gpu_platform_cycles()-begin;
 return result;
}

int network_assets_load(uintptr_t base,uint32_t session) {
 static const struct { uint32_t id,address,bytes,crc; } files[]={
  {ASSET_ID_SCENE,ASSET_SCENE_ADDR,ASSET_SCENE_BYTES,ASSET_SCENE_CRC},
  {ASSET_ID_FLOWER,ASSET_FLOWER_ADDR,ASSET_FLOWER_BYTES,ASSET_FLOWER_CRC},
  {ASSET_ID_ZOMBIE_WALK1,ASSET_ZOMBIE_WALK1_ADDR,ASSET_ZOMBIE_WALK1_BYTES,ASSET_ZOMBIE_WALK1_CRC},
  {ASSET_ID_ZOMBIE_WALK2,ASSET_ZOMBIE_WALK2_ADDR,ASSET_ZOMBIE_WALK2_BYTES,ASSET_ZOMBIE_WALK2_CRC}
 };
 int result=network_configure(base,NETWORK_LOCAL_IP,NETWORK_PEER_IP,NETWORK_PORT,NETWORK_PORT);
 if(result) return result;
 for(unsigned i=0;i<sizeof files/sizeof files[0];i++) {
  network_asset_report report;
  result=network_asset_fetch(base,NETWORK_TIMER_HZ,session,files[i].id,files[i].address,
   files[i].bytes,files[i].crc,&report);
#ifndef GPU_TEST_BACKEND
  bsp_printf("ASSET,id=%d,bytes=%d,requests=%d,retries=%d,ms=%d,result=%d\r\n",
   files[i].id,report.committed_bytes,report.requests,report.retries,
   (uint32_t)(report.elapsed_ticks/(NETWORK_TIMER_HZ/1000u)),result);
#endif
  if(result) return result;
 }
 return NETWORK_OK;
}
