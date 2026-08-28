package cpu

final class TestMemory(words: Seq[BigInt]) {
  def readWord(address: BigInt): BigInt = {
    val index = (address / 4).toInt
    if (index >= 0 && index < words.length) words(index) else BigInt("00000013", 16)
  }
}
