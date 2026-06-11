package com.odukle.scroller

import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.odukle.scroller/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "muxVideoAudio" -> {
                        val videoPath = call.argument<String>("videoPath")
                        val audioPath = call.argument<String>("audioPath")
                        val outputPath = call.argument<String>("outputPath")

                        if (videoPath == null || outputPath == null) {
                            result.error(
                                "INVALID_ARGUMENTS",
                                "videoPath and outputPath are required",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        try {
                            val success = muxVideoAudio(videoPath, audioPath, outputPath)
                            if (success) {
                                result.success(outputPath)
                            } else {
                                result.error("MUX_FAILED", "Failed to mux video and audio", null)
                            }
                        } catch (e: Exception) {
                            result.error("MUX_EXCEPTION", e.message, e.stackTraceToString())
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Muxes a video file and an optional audio file into a single MP4.
     * If audioPath is null or the file doesn't exist, only the video is copied.
     */
    private fun muxVideoAudio(videoPath: String, audioPath: String?, outputPath: String): Boolean {
        android.util.Log.d("VidredMux", "muxVideoAudio called: video=$videoPath, audio=$audioPath, output=$outputPath")

        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null

        try {
            videoExtractor = MediaExtractor()
            videoExtractor.setDataSource(videoPath)
            android.util.Log.d("VidredMux", "Video tracks: ${videoExtractor.trackCount}")

            // Find video track
            var videoTrackIndex = -1
            var videoFormat: MediaFormat? = null
            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                android.util.Log.d("VidredMux", "Video track $i mime=$mime")
                if (mime.startsWith("video/")) {
                    videoTrackIndex = i
                    videoFormat = format
                    break
                }
            }

            if (videoFormat == null) {
                android.util.Log.e("VidredMux", "No video track found")
                return false
            }

            // Find audio track (if audio file provided)
            var audioTrackIndex = -1
            var audioFormat: MediaFormat? = null
            val hasAudio = audioPath != null && java.io.File(audioPath).exists()
            android.util.Log.d("VidredMux", "hasAudio=$hasAudio")

            if (hasAudio) {
                audioExtractor = MediaExtractor()
                audioExtractor.setDataSource(audioPath!!)
                android.util.Log.d("VidredMux", "Audio tracks: ${audioExtractor.trackCount}")
                for (i in 0 until audioExtractor.trackCount) {
                    val format = audioExtractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                    android.util.Log.d("VidredMux", "Audio track $i mime=$mime")
                    if (mime.startsWith("audio/")) {
                        audioTrackIndex = i
                        audioFormat = format
                        break
                    }
                }
                if (audioFormat == null) {
                    android.util.Log.w("VidredMux", "Audio file provided but no audio track found inside")
                }
            }

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val muxVideoTrack = muxer.addTrack(videoFormat)
            val muxAudioTrack = if (audioFormat != null) muxer.addTrack(audioFormat) else -1
            android.util.Log.d("VidredMux", "muxVideoTrack=$muxVideoTrack, muxAudioTrack=$muxAudioTrack")

            muxer.start()

            // Interleave video and audio samples chronologically
            videoExtractor.selectTrack(videoTrackIndex)
            if (audioExtractor != null && audioTrackIndex >= 0) {
                audioExtractor.selectTrack(audioTrackIndex)
            }

            val buffer = ByteBuffer.allocate(1024 * 1024)
            val bufferInfo = android.media.MediaCodec.BufferInfo()
            var videoSamples = 0
            var audioSamples = 0

            while (true) {
                val hasVideo = videoExtractor.sampleTime != -1L
                val hasAudio = audioExtractor != null && audioTrackIndex >= 0 && audioExtractor.sampleTime != -1L

                if (!hasVideo && !hasAudio) {
                    break
                }

                // Decide which track to write based on the earliest timestamp
                if (hasVideo && (!hasAudio || videoExtractor.sampleTime <= audioExtractor!!.sampleTime)) {
                    buffer.clear()
                    val sampleSize = videoExtractor.readSampleData(buffer, 0)
                    if (sampleSize >= 0) {
                        bufferInfo.set(
                            0,
                            sampleSize,
                            videoExtractor.sampleTime,
                            videoExtractor.sampleFlags
                        )
                        muxer.writeSampleData(muxVideoTrack, buffer, bufferInfo)
                        videoExtractor.advance()
                        videoSamples++
                    } else {
                        videoExtractor.advance()
                    }
                } else if (hasAudio) {
                    buffer.clear()
                    val sampleSize = audioExtractor!!.readSampleData(buffer, 0)
                    if (sampleSize >= 0) {
                        bufferInfo.set(
                            0,
                            sampleSize,
                            audioExtractor.sampleTime,
                            audioExtractor.sampleFlags
                        )
                        muxer.writeSampleData(muxAudioTrack, buffer, bufferInfo)
                        audioExtractor.advance()
                        audioSamples++
                    } else {
                        audioExtractor.advance()
                    }
                }
            }
            android.util.Log.d("VidredMux", "Wrote $videoSamples video samples and $audioSamples audio samples")

            muxer.stop()
            android.util.Log.d("VidredMux", "Mux completed successfully")
            return true
        } catch (e: Exception) {
            android.util.Log.e("VidredMux", "Mux exception: ${e.message}", e)
            return false
        } finally {
            try { videoExtractor?.release() } catch (_: Exception) {}
            try { audioExtractor?.release() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
        }
    }
}
