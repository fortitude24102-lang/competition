#ifndef PROBE_WIDTH
#define PROBE_WIDTH 1
#endif
#ifndef PROBE_HEIGHT
#define PROBE_HEIGHT 1
#endif
#ifndef PROBE_STRIDE
#define PROBE_STRIDE (PROBE_WIDTH * 2)
#endif
#ifndef PROBE_ADDR_HI
#define PROBE_ADDR_HI 0x02000
#endif
#ifndef PROBE_ADDR_LO
#define PROBE_ADDR_LO 0
#endif

    .section .text
    .globl _start
_start:
    lui     t0, 0xf8100
    li      t6, 1
    sw      t6, 0x10(t0)

    lui     t1, PROBE_ADDR_HI
    addi    t1, t1, PROBE_ADDR_LO
    sw      t1, 0x18(t0)

    li      t2, ((PROBE_HEIGHT << 16) | PROBE_WIDTH)
    sw      t2, 0x1c(t0)

    li      t3, PROBE_STRIDE
    sw      t3, 0x24(t0)
    li      t4, 0x1234
    sw      t4, 0x28(t0)
    li      t5, 1
    sw      t5, 0x30(t0)
    fence   iorw, iorw
    sw      t5, 0x0c(t0)
    fence   iorw, iorw

    li      t4, 10000
poll:
    lw      s0, 0x08(t0)
    lw      s1, 0x34(t0)
    lw      s2, 0x38(t0)
    beq     s1, t5, snapshot
    addi    t4, t4, -1
    bnez    t4, poll

snapshot:
    sw      t5, 0x4c(t0)
    lw      s3, 0x50(t0)
    lw      s4, 0x58(t0)
    lw      s5, 0x68(t0)
    lw      s6, 0x70(t0)

done:
    j       done
