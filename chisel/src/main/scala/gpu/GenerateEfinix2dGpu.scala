package gpu

import circt.stage.ChiselStage
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.{Files, Path}
import java.security.MessageDigest
import scala.jdk.CollectionConverters._

object GenerateEfinix2dGpu extends App {
  // Build-time A/B switch; the old software register ABI is unchanged.
  private val legacyCopy = args.contains("--legacy-copy")
  private val instances = args.contains("--instances")
  private val lists = args.contains("--frame-lists")
  private val keyPrefetch = args.contains("--key-prefetch")
  private val stripes = args.contains("--stripe-scratchpad")
  private val burstBuffer = args.contains("--copy-burst-buffer")
  private val scanoutPipeline = args.contains("--scanout-word-pipeline")
  private val keyTrim = args.contains("--key-row-trim")
  private val transform = args.contains("--transform-blit")
  private val alphaPipeline = args.contains("--alpha-pipeline")
  private val axiDiagnostics = args.contains("--axi-diagnostics")
  private val keyWritePipeline = args.contains("--key-write-pipeline")
  private val extendedArena = args.contains("--extended-list-arena")
  private val smallCopyPrefetch = args.contains("--small-copy-prefetch")
  private val writeCredits = if(args.contains("--four-write-credits")) 4 else 2
  private val alphaRowPrefetch = args.contains("--alpha-row-prefetch")
  private val alphaEarlyPrefetch = args.contains("--alpha-early-prefetch")
  private val wideCopy = args.contains("--wide-copy-dma")
  require(!extendedArena || lists, "Extended list arena requires frame lists")
  require(!keyTrim || keyPrefetch, "Key row trim requires Key prefetch")
  ChiselStage.emitSystemVerilogFile(new Efinix2dGpuTop(!legacyCopy, instances,lists,keyPrefetch,stripes,burstBuffer,scanoutPipeline,keyTrim,transform,alphaPipeline,axiDiagnostics,keyWritePipeline,extendedArena,smallCopyPrefetch,writeCredits,alphaRowPrefetch,wideCopy,alphaEarlyPrefetch),
    args.filterNot(a => Set("--legacy-copy", "--instances", "--frame-lists", "--key-prefetch", "--stripe-scratchpad", "--copy-burst-buffer", "--scanout-word-pipeline", "--key-row-trim", "--transform-blit", "--alpha-pipeline", "--axi-diagnostics", "--key-write-pipeline", "--extended-list-arena", "--small-copy-prefetch", "--four-write-credits", "--alpha-row-prefetch", "--wide-copy-dma", "--alpha-early-prefetch")(a)))
  private val targetIndex=args.indexOf("--target-dir")
  private val target=if(targetIndex>=0)java.nio.file.Path.of(args(targetIndex+1)) else java.nio.file.Path.of(".")
  private val features = Seq(
    "copyStream" -> (!legacyCopy).toString, "instances" -> instances.toString,
    "frameLists" -> lists.toString, "keyPrefetch" -> keyPrefetch.toString,
    "stripeScratchpad" -> stripes.toString, "copyBurstBuffer" -> burstBuffer.toString,
    "scanoutWordPipeline" -> scanoutPipeline.toString, "keyRowTrim" -> keyTrim.toString,
    "transformBlit" -> transform.toString, "alphaPipeline" -> alphaPipeline.toString,
    "axiDiagnostics" -> axiDiagnostics.toString, "keyWritePipeline" -> keyWritePipeline.toString,
    "extendedListArena" -> extendedArena.toString, "smallCopyPrefetch" -> smallCopyPrefetch.toString,
    "writeCredits" -> writeCredits.toString, "alphaRowPrefetch" -> alphaRowPrefetch.toString,
    "wideCopyDma" -> wideCopy.toString, "alphaEarlyPrefetch" -> alphaEarlyPrefetch.toString)
  private def hex(bytes: Array[Byte]): String = bytes.map("%02x".format(_)).mkString
  private def fields(entries: Seq[(String, String)]): String =
    entries.map { case (key, value) => s"\"$key\":$value" }.mkString("{", ",", "}")
  private val sourceDigest = MessageDigest.getInstance("SHA-256")
  private val sources = Files.walk(Path.of("src/main/scala/gpu"))
  try sources.iterator.asScala.filter(p => p.toString.endsWith(".scala")).toSeq.sortBy(_.toString).foreach { p =>
    sourceDigest.update(p.toString.replace('\\', '/').getBytes(UTF_8))
    sourceDigest.update(0.toByte)
    sourceDigest.update(Files.readAllBytes(p))
  } finally sources.close()
  private val rtlHashes = Files.readAllLines(target.resolve("filelist.f")).asScala.map(_.trim)
    .filter(_.nonEmpty).sorted.map { name =>
      name -> s"\"${hex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(target.resolve(name))))}\""
    }.toSeq
  Files.writeString(target.resolve("gpu-build.json"), fields(Seq(
    "schemaVersion" -> "2", "wideCopyDma" -> wideCopy.toString,
    "sourceSha256" -> s"\"${hex(sourceDigest.digest())}\"",
    "features" -> fields(features), "rtlSha256" -> fields(rtlHashes))))
}
