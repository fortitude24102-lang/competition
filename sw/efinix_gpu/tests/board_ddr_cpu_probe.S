    .section .text
    .globl _start
_start:
    lui     t0, 0x10
    lui     t1, 0xdeadb
    addi    t1, t1, -273
    sw      t1, 0(t0)
    lui     t2, 0xf8100
    li      t3, 1
    sw      t3, 0x10(t2)
done:
    j       done
