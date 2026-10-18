package gpu

import chisel3._
import chisel3.util._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

/** Exercise actual AW/W/B handshakes, including the writer's committed request. */
class KeyRowTrimHarness(trim: Boolean) extends Module {
  private val key = Module(new CachedKeyStream(trimTransparentRows = trim))
  private val writer = Module(new AxiWriteEngine)
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val readRequest = Decoupled(new AxiReadRequest)
    val readData = Flipped(Decoupled(new AxiReadBeat))
    val readDone = Input(Bool())
    val readError = Input(Bool())
    val aw = Decoupled(new Axi4Address)
    val w = Decoupled(new Axi4WriteData)
    val b = Flipped(Decoupled(new Axi4WriteResponse))
    val pixels = Output(UInt(2.W))
    val completion = Decoupled(new GpuCompletion)
  })
  key.io.command <> io.command
  io.readRequest <> key.io.readRequest
  key.io.readData <> io.readData
  key.io.readDone := io.readDone
  key.io.readError := io.readError
  writer.io.request <> key.io.writeRequest
  writer.io.data <> key.io.writeData
  key.io.writeDone := writer.io.done
  key.io.writeError := writer.io.error
  io.aw <> writer.io.axiAw
  io.w <> writer.io.axiW
  writer.io.axiB <> io.b
  io.pixels := key.io.wordPixelsDone
  io.completion <> key.io.completion
}

class KeyRowTrimSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("cached Key row trimming on the AXI bus") {
    val key = 0xbeef
    val mixed = Seq(
      Seq.fill(8)(key),
      Seq(key, key, 0x1111, 0x1212, key, key, key, key),
      Seq(key, key, 0x2121, key, key, 0x2222, key, key),
      Seq(key, key, key, key, key, key, key, 0x3131))
    for ((trim, empty, failRead, failWrite, width, height) <- Seq(
      (true, true, false, false, 8, 4), (true, false, false, false, 8, 4),
      (false, false, false, false, 8, 4), (true, false, true, false, 8, 4),
      (true, false, false, true, 8, 4), (true, true, false, false, 16, 16),
      (true, false, false, false, 16, 16))) {
      it(s"preserves phased ${width}x$height pixels trim=$trim empty=$empty R-error=$failRead B-error=$failWrite") {
        simulate(new KeyRowTrimHarness(trim)) { d =>
          val src = 0x02a00000L; val dst = 0x02000102L
          // Error cases begin with a nonempty row so a write is committed before the error.
          val stride = width*2 + 2
          val rows = if (empty) Seq.fill(height)(Seq.fill(width)(key))
            else if (width == 16) Seq.fill(height)(Seq.tabulate(width)(0x1000 + _))
            else if (failRead || failWrite) mixed.tail :+ mixed.head else mixed
          val pixels = rows.flatten
          val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0xa5)
          d.io.command.valid.poke(false); d.io.completion.ready.poke(false)
          d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          d.io.command.bits.op.poke(GpuOpcode.ColorKey)
          d.io.command.bits.srcAddr.poke(src); d.io.command.bits.dstAddr.poke(dst)
          d.io.command.bits.srcStride.poke(width*2); d.io.command.bits.dstStride.poke(stride)
          d.io.command.bits.widthPixels.poke(width); d.io.command.bits.heightPixels.poke(height)
          d.io.command.bits.colorKey.poke(key); d.io.command.bits.tag.poke(91)
          d.io.readRequest.ready.poke(true); d.io.readData.valid.poke(false)
          d.io.readData.bits.poke(0.U.asTypeOf(new AxiReadBeat))
          d.io.readDone.poke(false); d.io.readError.poke(false)
          d.io.aw.ready.poke(false); d.io.w.ready.poke(false)
          d.io.b.valid.poke(false); d.io.b.bits.id.poke(0); d.io.b.bits.resp.poke(0)
          d.reset.poke(true); d.clock.step(2); d.reset.poke(false)
          // A second command proves row buffers, range state, and completions reset.
          for (commandIndex <- 0 until (if (failRead || failWrite) 1 else 2)) {
            var submitted = false; var readLeft = 0; var received = 0; var reads = 0; var readHeld = false
            var readDone = false; var responseDelay = -1; var writesLeft = 0
            var writeAddress = 0L; var processed = 0; var wCount = 0; var bCount = 0
            var complete = false; var cycles = 0
            var heldAw = Option.empty[(BigInt, BigInt)]
            var heldW = Option.empty[(BigInt, BigInt, Boolean)]
            val requests = collection.mutable.ArrayBuffer.empty[(Long, Int)]
            val strobes = collection.mutable.ArrayBuffer.empty[Int]
            val random = new scala.util.Random(20261018L + commandIndex)
            while (!complete && cycles < 1200) {
              d.io.command.valid.poke(!submitted)
              val sourceValid = readLeft > 0 && (readHeld || random.nextInt(4) != 0)
              d.io.readData.valid.poke(sourceValid)
              val word = if (readLeft > 0) pixels(received*2).toLong | (pixels(received*2+1).toLong << 16) else 0L
              d.io.readData.bits.data.poke(word); d.io.readData.bits.address.poke(src + received*4)
              d.io.readData.bits.last.poke(readLeft == 1)
              d.io.readDone.poke(readDone); d.io.readError.poke(readDone && failRead)
              // Hold AW until all source data/error arrived; committed W must still finish.
              d.io.aw.ready.poke(cycles > 90 && random.nextBoolean())
              d.io.w.ready.poke(random.nextInt(5) > 1)
              d.io.b.valid.poke(responseDelay == 0)
              d.io.b.bits.resp.poke(if (failWrite && bCount == 0) 2 else 0)
              val cmd = d.io.command.valid.peek().litToBoolean && d.io.command.ready.peek().litToBoolean
              val ar = d.io.readRequest.valid.peek().litToBoolean
              val r = d.io.readData.valid.peek().litToBoolean && d.io.readData.ready.peek().litToBoolean
              val awValid = d.io.aw.valid.peek().litToBoolean
              val wValid = d.io.w.valid.peek().litToBoolean
              val awBits = (d.io.aw.bits.addr.peek().litValue, d.io.aw.bits.len.peek().litValue)
              val wBits = (d.io.w.bits.data.peek().litValue, d.io.w.bits.strb.peek().litValue,
                d.io.w.bits.last.peek().litToBoolean)
              heldAw.foreach { expected => awValid shouldBe true; awBits shouldBe expected }
              heldW.foreach { expected => wValid shouldBe true; wBits shouldBe expected }
              val aw = awValid && d.io.aw.ready.peek().litToBoolean
              val w = wValid && d.io.w.ready.peek().litToBoolean
              val b = responseDelay == 0 && d.io.b.ready.peek().litToBoolean
              heldAw = if (awValid && !aw) Some(awBits) else None
              heldW = if (wValid && !w) Some(wBits) else None
              processed += d.io.pixels.peek().litValue.toInt
              if (ar) {
                reads += 1; d.io.readRequest.bits.bytes.expect(width*height*2); d.io.readRequest.bits.address.expect(src)
                readLeft = width*height/2
              }
              if (aw) {
                writesLeft shouldBe 0
                writeAddress = awBits._1.toLong; writesLeft = awBits._2.toInt + 1
                requests += ((writeAddress, writesLeft))
                // The entire source row must already be reserved before an AW promise.
                received should be >= width/2
                if (trim) processed should be >= width
              }
              if (w) {
                writesLeft should be > 0
                for (lane <- 0 until 4 if ((wBits._2.toInt >> lane) & 1) != 0)
                  memory(writeAddress + lane) = ((wBits._1 >> (lane*8)) & 255).toInt
                writeAddress += 4; writesLeft -= 1; wCount += 1; strobes += wBits._2.toInt
                wBits._3 shouldBe (writesLeft == 0)
                if (writesLeft == 0) responseDelay = 20
              }
              complete = d.io.completion.valid.peek().litToBoolean
              if (complete) {
                d.io.completion.bits.tag.expect(91)
                d.io.completion.bits.error.expect(if (failRead || failWrite) GpuError.AxiResponse else GpuError.None)
                writesLeft shouldBe 0; responseDelay shouldBe -1
              }
              d.clock.step(); cycles += 1
              if (cmd) submitted = true
              readHeld = sourceValid && !r
              readDone = false
              if (r) { received += 1; readLeft -= 1; if (readLeft == 0) readDone = true }
              if (b) { responseDelay = -1; bCount += 1 }
              else if (responseDelay > 0) responseDelay -= 1
            }
            complete shouldBe true; reads shouldBe 1; received shouldBe width*height/2
            bCount shouldBe requests.size
            if (failRead || failWrite) { requests.size shouldBe 1; processed shouldBe width }
            else {
              processed shouldBe width*height // Includes transparent words and entire empty rows.
              val expected = if (empty) Seq.empty else if (width == 16)
                (0 until height).map(y => ((dst + y*stride) & ~3L, if (y % 2 == 0) 9 else 8))
                else if (trim)
                Seq((0x02000118L, 1), (0x02000128L, 3), (0x02000144L, 1))
                else Seq((0x02000100L, 5), (0x02000114L, 4), (0x02000124L, 5), (0x02000138L, 4))
              requests.toSeq shouldBe expected
              wCount shouldBe (if (empty) 0 else if (width == 16) 136 else if (trim) 5 else 18)
              if (trim && !empty && width == 8) strobes.toSeq shouldBe Seq(15, 12, 0, 3, 12)
            }
            val checkedRows = if (failRead || failWrite) 1 else height
            for (y <- 0 until checkedRows; x <- -1 to width) {
              val address = dst + y*stride + x*2
              val expected = if (x >= 0 && x < width && rows(y)(x) != key) rows(y)(x) else 0xa5a5
              (memory(address) | (memory(address+1) << 8)) shouldBe expected
            }
            d.clock.step(3); d.io.completion.valid.expect(true)
            d.io.command.valid.poke(false); d.io.completion.ready.poke(true); d.clock.step()
            d.io.completion.ready.poke(false); d.io.command.ready.expect(true)
          }
        }
      }
    }
  }
}
