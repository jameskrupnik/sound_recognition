package com.jameskrupnik.sound_recognition

import androidx.test.platform.app.InstrumentationRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

/** The clips in `tool/test_audio`, packaged as this test's assets. */
object TestAudio {
  /** 16 kHz mono PCM16 from a RIFF WAV, format checked rather than assumed. */
  fun readWav(name: String): ShortArray {
    val bytes = InstrumentationRegistry.getInstrumentation().context.assets.open(name).use { it.readBytes() }
    val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
    // Walk the chunks: `say` writes a padding chunk before "fmt ", so no
    // field is at a fixed offset.
    var p = 12
    var formatChecked = false
    while (p + 8 <= bytes.size) {
      val id = String(bytes, p, 4, Charsets.US_ASCII)
      val size = buf.getInt(p + 4)
      when (id) {
        "fmt " -> {
          assertEquals("mono", 1, buf.getShort(p + 10).toInt())
          assertEquals("16 kHz", 16_000, buf.getInt(p + 12))
          assertEquals("16-bit", 16, buf.getShort(p + 22).toInt())
          formatChecked = true
        }
        "data" -> {
          assertTrue("fmt before data", formatChecked)
          val out = ShortArray(size / 2)
          buf.position(p + 8)
          buf.slice().order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(out)
          return out
        }
      }
      p += 8 + size + (size and 1)
    }
    error("no data chunk in $name")
  }
}
