// Generator : SpinalHDL dev    git head : 4a21ab4cca95b35fbb12189077e7609e7b40dbb9
// Component : Interrupt

`timescale 1ns/1ps

module apb3_top (
  input      [31:0]   apb_paddr,
  input      [0:0]    apb_psel,
  input               apb_penable,
  output              apb_pready,
  input               apb_pwrite,
  input      [31:0]   apb_pwdata,
  output     [31:0]   apb_prdata,
  output              apb_pslverror,
  output              sig,
  input               clk,
  input               reset
);

  wire                factory_readErrorFlag;
  wire                factory_writeErrorFlag;
  wire                factory_askWrite;
  wire                factory_askRead;
  wire                factory_doWrite;
  wire                factory_doRead;
  reg                 _zz_sig;

  assign factory_readErrorFlag = 1'b0;
  assign factory_writeErrorFlag = 1'b0;
  assign apb_pready = 1'b1;
  assign apb_prdata = 32'h0;
  assign factory_askWrite = ((apb_psel[0] && apb_penable) && apb_pwrite);
  assign factory_askRead = ((apb_psel[0] && apb_penable) && (! apb_pwrite));
  assign factory_doWrite = (((apb_psel[0] && apb_penable) && apb_pready) && apb_pwrite);
  assign factory_doRead = (((apb_psel[0] && apb_penable) && apb_pready) && (! apb_pwrite));
  assign apb_pslverror = ((factory_doWrite && factory_writeErrorFlag) || (factory_doRead && factory_readErrorFlag));
  assign sig = _zz_sig;
  always @(posedge clk) begin
    case(apb_paddr)
      32'h0 : begin
        if(factory_doWrite) begin
          _zz_sig <= apb_pwdata[0];
        end
      end
      default : begin
      end
    endcase
  end


endmodule
