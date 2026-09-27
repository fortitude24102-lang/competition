#include "net_asset_server.h"
#include <string.h>
int asset_server_handle_get(const asset_server *s,const uint8_t *q,size_t qn,
 uint8_t *out,size_t cap,size_t *on) {
 asst_header h;
 const asset_server_entry *entry=NULL;
 if(on) *on=0;
 if(!s || !s->entries || !q || !out || !on || qn!=32 || asst_decode(&h,q) ||
    h.type!=ASST_GET || !h.payload_len || (h.flags&~ASST_RETRY) || h.payload_crc32)
  return -1;
 for(size_t i=0;i<s->count;i++) if(s->entries[i].id==h.asset_id) entry=&s->entries[i];
 if(!entry || !entry->data || h.offset>entry->length || h.payload_len>entry->length-h.offset)
  return -2;
 size_t n=h.payload_len;
 int last=h.offset+n==entry->length;
 if(!last && (n&3u)) return -1;
 if(cap<32+n) return -3;
 h.type=ASST_DATA; h.flags=last?ASST_LAST:0;
 h.payload_crc32=asst_crc32(entry->data+h.offset,(uint32_t)n);
 if(asst_encode(out,&h)) return -1;
 memcpy(out+32,entry->data+h.offset,n);
 *on=32+n;
 return 0;
}
int asset_fetch(asset_io_exchange io,void *ctx,uint32_t session,uint32_t id,
 size_t total,uint32_t crc,uint8_t *dst,size_t cap,uint32_t timeout,unsigned retries) {
 if(!io || !dst || !total || total>cap || total>UINT32_MAX) return -1;
 size_t off=0;
 uint32_t seq=0;
 uint8_t req[32],resp[1056];
 while(off<total) {
  uint16_t ask=(uint16_t)(total-off>ASST_MAX_PAYLOAD?ASST_MAX_PAYLOAD:total-off);
  asst_header request={.magic=ASST_MAGIC,.version=ASST_VERSION,.type=ASST_GET,
   .session=session,.asset_id=id,.offset=(uint32_t)off,.payload_len=ask,.sequence=seq};
  unsigned attempt=0;
  for(;;) {
   asst_header response;
   size_t rn=0;
   request.flags=attempt?ASST_RETRY:0;
   if(asst_encode(req,&request)) return -1;
   /* Never decode an untrusted reply over the request: a rejected reply must
    * not change the next GET's type, session, offset, length or sequence. */
   if(!io(ctx,req,sizeof req,resp,sizeof resp,&rn,timeout) && rn==32u+ask &&
      !asst_decode(&response,resp) && response.type==ASST_DATA &&
      !(response.flags&ASST_RETRY) && response.session==session &&
      response.asset_id==id && response.offset==off && response.sequence==seq &&
      response.payload_len==ask && !!(response.flags&ASST_LAST)==(off+ask==total) &&
      response.payload_crc32==asst_crc32(resp+32,ask)) {
    memcpy(dst+off,resp+32,ask);
    off+=ask; ++seq;
    break;
   }
   if(attempt==retries) return -2;
   ++attempt;
  }
 }
 return asst_crc32(dst,(uint32_t)total)==crc?0:-3;
}
