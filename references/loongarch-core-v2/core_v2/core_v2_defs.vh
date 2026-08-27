`ifndef CPU5_CORE_V2_DEFS_VH
`define CPU5_CORE_V2_DEFS_VH

`define V2_ALU_ADD   4'h0
`define V2_ALU_SUB   4'h1
`define V2_ALU_AND   4'h2
`define V2_ALU_OR    4'h3
`define V2_ALU_XOR   4'h4
`define V2_ALU_NOR   4'h5
`define V2_ALU_SLT   4'h6
`define V2_ALU_SLTU  4'h7
`define V2_ALU_SLL   4'h8
`define V2_ALU_SRA   4'h9
`define V2_ALU_SRL   4'ha

`define V2_UOP_NONE    4'h0
`define V2_UOP_ALU     4'h1
`define V2_UOP_BRANCH  4'h2
`define V2_UOP_STORE   4'h3
`define V2_UOP_LOAD    4'h4
`define V2_UOP_MUL     4'h5
`define V2_UOP_DIV     4'h6
`define V2_UOP_CSR     4'h7
`define V2_UOP_SYSTEM  4'h8

`define V2_IMM_NONE    3'h0
`define V2_IMM_SI12    3'h1
`define V2_IMM_UI12    3'h2
`define V2_IMM_UI5     3'h3
`define V2_IMM_SI20    3'h4
`define V2_IMM_OFFS16  3'h5
`define V2_IMM_OFFS26  3'h6

`define V2_BR_NONE    3'h0
`define V2_BR_EQ      3'h1
`define V2_BR_NE      3'h2
`define V2_BR_LT      3'h3
`define V2_BR_GE      3'h4
`define V2_BR_LTU     3'h5
`define V2_BR_GEU     3'h6
`define V2_BR_ALWAYS  3'h7

`define V2_MEM_BYTE  2'h0
`define V2_MEM_HALF  2'h1
`define V2_MEM_WORD  2'h2

`define V2_REDIRECT_NONE       3'h0
`define V2_REDIRECT_BRANCH     3'h1
`define V2_REDIRECT_INTERRUPT  3'h2
`define V2_REDIRECT_EXCEPTION  3'h3
`define V2_REDIRECT_ERTN       3'h4
`define V2_REDIRECT_IBAR       3'h5

`define V2_CSR_CRMD    14'h000
`define V2_CSR_PRMD    14'h001
`define V2_CSR_ECFG    14'h004
`define V2_CSR_ESTAT   14'h005
`define V2_CSR_ERA     14'h006
`define V2_CSR_BADV    14'h007
`define V2_CSR_EENTRY  14'h00c
`define V2_CSR_CPUID   14'h020
`define V2_CSR_SAVE0   14'h030
`define V2_CSR_SAVE1   14'h031
`define V2_CSR_SAVE2   14'h032
`define V2_CSR_SAVE3   14'h033
`define V2_CSR_TID     14'h040
`define V2_CSR_TCFG    14'h041
`define V2_CSR_TVAL    14'h042
`define V2_CSR_TICLR   14'h044
`define V2_CSR_LLBCTL  14'h060
`define V2_CSR_DMW0    14'h180
`define V2_CSR_DMW1    14'h181

`define V2_ECODE_INT   6'h00
`define V2_ECODE_ADE   6'h08
`define V2_ECODE_ALE   6'h09
`define V2_ECODE_SYS   6'h0b
`define V2_ECODE_BRK   6'h0c
`define V2_ECODE_INE   6'h0d

`define V2_CSR_OP_NONE      2'h0
`define V2_CSR_OP_READ      2'h1
`define V2_CSR_OP_WRITE     2'h2
`define V2_CSR_OP_EXCHANGE  2'h3

`endif
