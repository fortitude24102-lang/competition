package gpu

import chisel3._
import chisel3.util._

/** Candidate-only, stopped-window counters; none of these signals controls AXI. */
class AxiDiagnosticRegs extends Module {
  val io = IO(new Bundle {
    val apb = new ApbSlavePort
    val events = Input(Vec(16, Bool()))
  })
  private val enabled = RegInit(false.B)
  private val counts = RegInit(VecInit(Seq.fill(16)(0.U(32.W))))
  private val pending = RegInit(false.B)
  private val address = Reg(UInt(16.W))
  private val write = Reg(Bool())
  private val data = Reg(UInt(32.W))
  private val transfer = io.apb.psel && io.apb.penable && pending
  private val control = address === 0x604.U
  private val counter = address >= 0x610.U && address <= 0x64c.U && address(1, 0) === 0.U
  private val legal = address === 0x600.U || control || counter
  private val controlWrite = transfer && write && control && data(31, 2) === 0.U
  when(io.apb.psel && !io.apb.penable) {
    address := io.apb.paddr; write := io.apb.pwrite; data := io.apb.pwdata; pending := true.B
  }.elsewhen(transfer) { pending := false.B }
  io.apb.pready := transfer
  io.apb.pslverror := transfer && (!legal || (write && (!control || data(31, 2) =/= 0.U)))
  io.apb.prdata := 0.U
  when(address === 0x600.U) { io.apb.prdata := "h41585046".U }
  when(control) { io.apb.prdata := enabled }
  when(counter) { io.apb.prdata := counts(((address - 0x610.U) >> 2)(3, 0)) }
  when(controlWrite) { enabled := data(0) }
  for (i <- 0 until 16) {
    when(controlWrite && data(1)) { counts(i) := 0.U }
      .elsewhen(enabled && io.events(i)) { counts(i) := counts(i) + 1.U }
  }
}
