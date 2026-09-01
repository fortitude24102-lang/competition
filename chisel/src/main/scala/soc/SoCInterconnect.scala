package soc

import chisel3._
import cpu.CoreBusIO

class SoCInterconnect extends Module {
  val io = IO(new Bundle {
    val cpuImem = new SocBusTargetIO
    val cpuDmem = new SocBusTargetIO

    val ramImem = new CoreBusIO
    val ramDmem = new CoreBusIO
    val timer = new CoreBusIO
    val uart = new CoreBusIO
    val gpio = new CoreBusIO
    val accelerator = new CoreBusIO
    val externalImem = new CoreBusIO
    val externalDmem = new CoreBusIO
  })

  private val targetNone = 0.U(4.W)
  private val targetRam = 1.U(4.W)
  private val targetTimer = 2.U(4.W)
  private val targetUart = 3.U(4.W)
  private val targetGpio = 4.U(4.W)
  private val targetAccelerator = 5.U(4.W)
  private val targetExternal = 6.U(4.W)
  private val targetError = 15.U(4.W)

  private val masters = Seq(
    io.ramImem,
    io.ramDmem,
    io.timer,
    io.uart,
    io.gpio,
    io.accelerator,
    io.externalImem,
    io.externalDmem
  )

  masters.foreach { master =>
    master.req.valid := false.B
    master.req.bits := 0.U.asTypeOf(master.req.bits)
    master.resp.ready := false.B
  }

  private def connectRequest(cpu: SocBusTargetIO, master: CoreBusIO, enable: Bool): Unit = {
    master.req.valid := cpu.req.valid && enable
    master.req.bits := cpu.req.bits
  }

  private def routeResponse(cpu: SocBusTargetIO, master: CoreBusIO, enable: Bool): Unit = {
    when(enable) {
      cpu.resp.valid := master.resp.valid
      cpu.resp.bits := master.resp.bits
      master.resp.ready := cpu.resp.ready
    }
  }

  private val imemActive = RegInit(false.B)
  private val imemTarget = RegInit(targetNone)
  private val imemDecoded = WireDefault(targetError)
  when(MemoryMap.isBootRam(io.cpuImem.req.bits.addr)) {
    imemDecoded := targetRam
  }.elsewhen(MemoryMap.isExternal(io.cpuImem.req.bits.addr)) {
    imemDecoded := targetExternal
  }

  io.cpuImem.req.ready := false.B
  io.cpuImem.resp.valid := false.B
  io.cpuImem.resp.bits.rdata := 0.U
  io.cpuImem.resp.bits.error := true.B

  when(!imemActive) {
    connectRequest(io.cpuImem, io.ramImem, imemDecoded === targetRam)
    connectRequest(io.cpuImem, io.externalImem, imemDecoded === targetExternal)
    when(imemDecoded === targetRam) {
      io.cpuImem.req.ready := io.ramImem.req.ready
    }.elsewhen(imemDecoded === targetExternal) {
      io.cpuImem.req.ready := io.externalImem.req.ready
    }.otherwise {
      io.cpuImem.req.ready := true.B
    }

    when(io.cpuImem.req.fire) {
      imemActive := true.B
      imemTarget := imemDecoded
    }
  }.otherwise {
    routeResponse(io.cpuImem, io.ramImem, imemTarget === targetRam)
    routeResponse(io.cpuImem, io.externalImem, imemTarget === targetExternal)
    when(imemTarget === targetError) {
      io.cpuImem.resp.valid := true.B
    }
    when(io.cpuImem.resp.fire) {
      imemActive := false.B
      imemTarget := targetNone
    }
  }

  private val dmemActive = RegInit(false.B)
  private val dmemTarget = RegInit(targetNone)
  private val dmemDecoded = WireDefault(targetError)
  when(MemoryMap.isBootRam(io.cpuDmem.req.bits.addr)) {
    dmemDecoded := targetRam
  }.elsewhen(MemoryMap.isTimer(io.cpuDmem.req.bits.addr)) {
    dmemDecoded := targetTimer
  }.elsewhen(MemoryMap.isUart(io.cpuDmem.req.bits.addr)) {
    dmemDecoded := targetUart
  }.elsewhen(MemoryMap.isGpio(io.cpuDmem.req.bits.addr)) {
    dmemDecoded := targetGpio
  }.elsewhen(MemoryMap.isAccelerator(io.cpuDmem.req.bits.addr)) {
    dmemDecoded := targetAccelerator
  }.elsewhen(MemoryMap.isExternal(io.cpuDmem.req.bits.addr)) {
    dmemDecoded := targetExternal
  }

  io.cpuDmem.req.ready := false.B
  io.cpuDmem.resp.valid := false.B
  io.cpuDmem.resp.bits.rdata := 0.U
  io.cpuDmem.resp.bits.error := true.B

  when(!dmemActive) {
    connectRequest(io.cpuDmem, io.ramDmem, dmemDecoded === targetRam)
    connectRequest(io.cpuDmem, io.timer, dmemDecoded === targetTimer)
    connectRequest(io.cpuDmem, io.uart, dmemDecoded === targetUart)
    connectRequest(io.cpuDmem, io.gpio, dmemDecoded === targetGpio)
    connectRequest(io.cpuDmem, io.accelerator, dmemDecoded === targetAccelerator)
    connectRequest(io.cpuDmem, io.externalDmem, dmemDecoded === targetExternal)
    when(dmemDecoded === targetRam) {
      io.cpuDmem.req.ready := io.ramDmem.req.ready
    }.elsewhen(dmemDecoded === targetTimer) {
      io.cpuDmem.req.ready := io.timer.req.ready
    }.elsewhen(dmemDecoded === targetUart) {
      io.cpuDmem.req.ready := io.uart.req.ready
    }.elsewhen(dmemDecoded === targetGpio) {
      io.cpuDmem.req.ready := io.gpio.req.ready
    }.elsewhen(dmemDecoded === targetAccelerator) {
      io.cpuDmem.req.ready := io.accelerator.req.ready
    }.elsewhen(dmemDecoded === targetExternal) {
      io.cpuDmem.req.ready := io.externalDmem.req.ready
    }.otherwise {
      io.cpuDmem.req.ready := true.B
    }

    when(io.cpuDmem.req.fire) {
      dmemActive := true.B
      dmemTarget := dmemDecoded
    }
  }.otherwise {
    routeResponse(io.cpuDmem, io.ramDmem, dmemTarget === targetRam)
    routeResponse(io.cpuDmem, io.timer, dmemTarget === targetTimer)
    routeResponse(io.cpuDmem, io.uart, dmemTarget === targetUart)
    routeResponse(io.cpuDmem, io.gpio, dmemTarget === targetGpio)
    routeResponse(io.cpuDmem, io.accelerator, dmemTarget === targetAccelerator)
    routeResponse(io.cpuDmem, io.externalDmem, dmemTarget === targetExternal)
    when(dmemTarget === targetError) {
      io.cpuDmem.resp.valid := true.B
    }
    when(io.cpuDmem.resp.fire) {
      dmemActive := false.B
      dmemTarget := targetNone
    }
  }
}
