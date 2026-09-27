#include "asset_protocol.h"
#include <assert.h>
#include <stdio.h>
int main(void){uint8_t b[32];asst_header a={.magic=ASST_MAGIC,.version=1,.type=ASST_DATA,.session=7,.asset_id=9,.offset=16,.payload_len=4,.flags=ASST_LAST,.sequence=2};a.payload_crc32=asst_crc32("abcd",4);assert(asst_encode(b,&a)==0);asst_header z;assert(asst_decode(&z,b)==0);assert(z.session==7&&z.offset==16&&z.sequence==2);assert(asst_crc32("123456789",9)==UINT32_C(0xcbf43926));b[0]=0;assert(asst_decode(&z,b)<0);puts("PASS asset protocol");}
