
`ifdef      X8 
  `define   X7 
`endif 

`ifdef      X7 
  `define   X6 
`endif 

`ifdef      X6
  `define   X5 
`endif 

`ifdef      X5 
  `define   X4 
`endif 

`ifdef      X4 
  `define   X3 
`endif 

`ifdef      X3 
  `define   X2 
`endif 

`ifdef      X8
  `define   Axi_Chnanel_Num   8 
`else 
  `ifdef    X7
    `define   Axi_Chnanel_Num   7 
  `else 
    `ifdef    X6
      `define   Axi_Chnanel_Num   6 
    `else 
      `ifdef    X5
        `define   Axi_Chnanel_Num   5
      `else 
        `ifdef    X4
          `define   Axi_Chnanel_Num   4 
        `else 
          `ifdef    X3
            `define   Axi_Chnanel_Num   3 
          `else 
            `ifdef    X2
              `define   Axi_Chnanel_Num   2 
            `endif 
          `endif
        `endif 
      `endif  
    `endif
  `endif 
`endif
