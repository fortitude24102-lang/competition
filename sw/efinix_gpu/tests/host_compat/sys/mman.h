#ifndef EFINIX_HOST_MMAN_H
#define EFINIX_HOST_MMAN_H
#ifdef _WIN32
#include <windows.h>
#include <stddef.h>
#include <stdio.h>
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 1
#define MAP_ANONYMOUS 2
#define MAP_FIXED_NOREPLACE 4
#define MAP_FAILED ((void *)-1)
static inline void *mmap(void *address,size_t bytes,int prot,int flags,int fd,size_t offset) {
 (void)prot; (void)flags; (void)fd; (void)offset;
 void *p=VirtualAlloc(address,bytes,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);
 if(p!=address) {
  MEMORY_BASIC_INFORMATION info;
  VirtualQuery(address,&info,sizeof info);
  fprintf(stderr,"fixed test mapping failed: error=%lu address=%p allocation=%p state=%lu region=%lu\n",
   GetLastError(),address,info.AllocationBase,info.State,(unsigned long)info.RegionSize);
  if(p) VirtualFree(p,0,MEM_RELEASE);
  return MAP_FAILED;
 }
 return p;
}
static inline int munmap(void *address,size_t bytes) {
 (void)bytes; return VirtualFree(address,0,MEM_RELEASE)?0:-1;
}
#else
#include_next <sys/mman.h>
#endif
#endif
