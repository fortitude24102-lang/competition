package gpu

import chisel3._
import chisel3.util._

/** Optional APB producer; templates never change while its batch executes.
  * ponytail: one staging command, reuse the existing16-entry render queue;
  * a deeper frontend FIFO is justified only by measured producer starvation.
  */
class InstanceStream extends Module {
  val io = IO(new Bundle {
    val apb = new ApbSlavePort
    val idle = Input(Bool()) // Actual render/cache idle, excluding this batch lock.
    val hardwareError = Input(UInt(8.W))
    val active = Output(Bool())
    val command = Decoupled(new GpuCommand)
  })
  private val templates = Mem(16, Vec(7, UInt(32.W)))
  private val validTemplates = RegInit(0.U(16.W))
  private val index = RegInit(0.U(4.W))
  private val templateMask = RegInit(0.U(7.W))
  private val words = Reg(Vec(4, UInt(32.W)))
  private val wordMask = RegInit(0.U(4.W))
  private val active = RegInit(false.B)
  private val held = RegInit(false.B)
  private val command = Reg(new GpuCommand)
  private val nextTag = RegInit(0.U(16.W))
  private val lastTag = RegInit(0.U(16.W))
  private val error = RegInit(0.U(8.W))
  private val pending = RegInit(false.B)
  private val address = Reg(UInt(16.W))
  private val write = Reg(Bool())
  private val data = Reg(UInt(32.W))
  when(io.apb.psel && !io.apb.penable) {
    pending := true.B; address := io.apb.paddr; write := io.apb.pwrite; data := io.apb.pwdata
  }
  private val transfer = io.apb.psel && io.apb.penable && pending
  when(transfer) { pending := false.B }
  private val idle = io.idle && !held
  private val templateWrite = address >= 0x410.U && address <= 0x428.U
  private val wordWrite = address >= 0x430.U && address <= 0x43c.U
  private val legal = (address(1,0) === 0.U) &&
    (address === 0x400.U || address === 0x404.U || address === 0x408.U ||
      address === 0x40c.U || templateWrite || wordWrite || address === 0x440.U || address === 0x444.U)
  private val template = templates(words(0)(3,0))
  private val expanded = WireDefault(0.U.asTypeOf(new GpuCommand))
  private val source = template(1).pad(64) + words(2).pad(64)
  expanded.op := template(0)(3,0); expanded.srcAddr := source(31,0)
  expanded.srcStride := template(2); expanded.dstStride := template(3)
  expanded.widthPixels := words(3)(15,0); expanded.heightPixels := words(3)(31,16)
  expanded.dstAddr := words(1); expanded.colorKey := template(6)(15,0)
  expanded.alpha := words(0)(23,16); expanded.tag := nextTag
  private val rows = (expanded.heightPixels - 1.U).pad(64)
  private val span = words(2).pad(64) + rows * template(2).pad(64) + (expanded.widthPixels << 1).pad(64)
  // Full-width metadata is rejected below; legal dimensions fit16bits.
  private val limit = (template(5)(15,0) - 1.U).pad(64) * template(2).pad(64) + (template(4)(15,0) << 1).pad(64)
  private val alpha = template(0) === GpuOpcode.Alpha.U
  private val headerLegal = words(0)(31,24) === 0.U && words(0)(15,8) === alpha.asUInt &&
    words(0)(7,4) === 0.U && (alpha || !words(0)(23,16).orR)
  private val templateLegal = (template(0) === GpuOpcode.Copy.U ||
    template(0) === GpuOpcode.ColorKey.U || alpha) && !template(6)(31,16).orR &&
    !template(2)(0) && !template(3)(0) &&
    template(4) > 0.U && template(4) <= 65535.U && template(5) > 0.U && template(5) <= 65535.U
  private val validator = Module(new CommandValidator)
  validator.io.command := expanded
  private val descriptorLegal = wordMask.andR && validTemplates(words(0)(3,0)) &&
    headerLegal && templateLegal && expanded.widthPixels <= template(4) &&
    expanded.heightPixels <= template(5) && source < (BigInt(1) << 32).U && span <= limit && validator.io.valid
  private val mutable = idle && !active
  private val commit = address === 0x440.U
  private val control = address === 0x408.U
  private val badWrite =
    (address === 0x40c.U && (!mutable || data > 15.U)) ||
    (templateWrite && !mutable) ||
    (address === 0x444.U && (!mutable || data > 65535.U)) ||
    (wordWrite && (!active || io.hardwareError.orR || error.orR)) ||
    (commit && (data =/= 1.U || !active || held || io.hardwareError.orR || error.orR || !descriptorLegal)) ||
    (control && !((data === 1.U && mutable && !io.hardwareError.orR) ||
      (data === 2.U && active && idle) || (data === 4.U && mutable))) ||
    (address === 0x400.U || address === 0x404.U)
  private val rejected = !legal || (write && badWrite)
  io.apb.pready := transfer
  io.apb.pslverror := transfer && rejected
  io.apb.prdata := 0.U
  switch(address) {
    is(0x400.U) { io.apb.prdata := "h494e5331".U }
    is(0x404.U) { io.apb.prdata := Cat(0.U(16.W), error, 0.U(4.W), error.orR,
      idle, active && !held && !error.orR && !io.hardwareError.orR, active) }
    is(0x40c.U) { io.apb.prdata := index }
    is(0x444.U) { io.apb.prdata := lastTag }
  }
  io.active := active
  io.command.valid := held
  io.command.bits := command
  when(io.command.fire) { held := false.B }
  // Template writes and instance commits are disjoint APB addresses. Do not
  // gate RAM WE with descriptor validation: it feeds RAM→multiply→RAM timing.
  when(transfer && write && legal && templateWrite && mutable) {
    val slot = ((address - 0x410.U) >> 2)(2,0)
    val mask = VecInit((0 until 7).map(i => slot === i.U))
    templates.write(index, VecInit(Seq.fill(7)(data)), mask)
    val updated = (templateMask | (1.U(7.W) << slot))(6,0)
    templateMask := updated
    when(updated.andR) { validTemplates := validTemplates | (1.U(16.W) << index) }
  }
  when(transfer && write) {
    when(rejected) { error := GpuError.AddressRange.U }
    .otherwise {
      when(address === 0x40c.U) {
        index := data(3,0); templateMask := 0.U
        validTemplates := validTemplates & ~(1.U(16.W) << data(3,0))
      }
      when(wordWrite) {
        val slot = ((address - 0x430.U) >> 2)(1,0)
        words(slot) := data; wordMask := wordMask | (1.U(4.W) << slot)
      }
      when(address === 0x444.U) { nextTag := data(15,0) }
      when(control) {
        when(data === 1.U) { active := true.B; wordMask := 0.U; error := 0.U }
        when(data === 2.U) { active := false.B; wordMask := 0.U }
        when(data === 4.U) { error := 0.U }
      }
      when(commit) {
        command := expanded; held := true.B; lastTag := nextTag
        nextTag := nextTag + 1.U; wordMask := 0.U
      }
    }
  }
}
