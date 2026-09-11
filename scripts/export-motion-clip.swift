import AVFoundation
import Foundation

// Trim Simulator video without changing playback speed or rendering a mock interface.
let arguments = CommandLine.arguments
guard arguments.count == 5, let start = Double(arguments[3]), let duration = Double(arguments[4]) else {
    fatalError("Usage: swift export-motion-clip.swift input.mp4 output.mp4 startSeconds durationSeconds")
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Output already exists") }
Task {
    do {
        let asset = AVURLAsset(url: input)
        let length = try await asset.load(.duration).seconds
        guard start >= 0, duration > 0, start + duration <= length,
              let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            fatalError("Invalid export range")
        }
        exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        duration: CMTime(seconds: duration, preferredTimescale: 600))
        try await exporter.export(to: output, as: .mp4)
        print("Exported \(output.lastPathComponent): \(duration)s from \(start)s of \(length)s")
        exit(0)
    } catch {
        fputs("\(error)\n", stderr)
        exit(1)
    }
}
dispatchMain()
