import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.odukle.scroller/media",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "muxVideoAudio":
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String,
              let outputPath = args["outputPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENTS",
                              message: "videoPath and outputPath are required",
                              details: nil))
          return
        }
        let audioPath = args["audioPath"] as? String
        self?.muxVideoAudio(videoPath: videoPath,
                            audioPath: audioPath,
                            outputPath: outputPath,
                            result: result)
      case "nativeLog":
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String else {
          result(nil)
          return
        }
        NSLog("[FlutterNativeLog] %@", message)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func muxVideoAudio(videoPath: String,
                             audioPath: String?,
                             outputPath: String,
                             result: @escaping FlutterResult) {
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    let composition = AVMutableComposition()

    guard let videoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      result(FlutterError(code: "MUX_FAILED",
                          message: "Could not add video track",
                          details: nil))
      return
    }

    do {
      let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first!
      try videoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoAsset.duration),
        of: sourceVideoTrack,
        at: .zero
      )
    } catch {
      result(FlutterError(code: "MUX_FAILED",
                          message: "Could not insert video: \(error.localizedDescription)",
                          details: nil))
      return
    }

    // Add audio if provided
    if let audioPath = audioPath, FileManager.default.fileExists(atPath: audioPath) {
      let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
      if let audioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ) {
        do {
          if let sourceAudioTrack = audioAsset.tracks(withMediaType: .audio).first {
            let duration = min(videoAsset.duration, audioAsset.duration)
            try audioTrack.insertTimeRange(
              CMTimeRange(start: .zero, duration: duration),
              of: sourceAudioTrack,
              at: .zero
            )
          }
        } catch {
          // Audio insertion failed, continue with video-only
        }
      }
    }

    guard let exportSession = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      result(FlutterError(code: "MUX_FAILED",
                          message: "Could not create export session",
                          details: nil))
      return
    }

    // Remove existing file
    try? FileManager.default.removeItem(atPath: outputPath)

    exportSession.outputURL = URL(fileURLWithPath: outputPath)
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = false

    exportSession.exportAsynchronously {
      switch exportSession.status {
      case .completed:
        result(outputPath)
      case .failed:
        result(FlutterError(code: "MUX_FAILED",
                            message: exportSession.error?.localizedDescription ?? "Unknown error",
                            details: nil))
      case .cancelled:
        result(FlutterError(code: "MUX_CANCELLED",
                            message: "Export was cancelled",
                            details: nil))
      default:
        result(FlutterError(code: "MUX_FAILED",
                            message: "Unexpected export status: \(exportSession.status.rawValue)",
                            details: nil))
      }
    }
  }
}
