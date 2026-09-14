import AVFoundation
import CoreML
import Foundation
import Vision

enum LipVideoInput {
    enum InputError: LocalizedError {
        case invalidVideo, tooLong, tooShort, multipleFaces, insufficientFace, invalidImage
        var errorDescription: String? {
            switch self {
            case .invalidVideo: return "This video could not be read. Choose a standard video file."
            case .tooLong: return "Choose a clip no longer than 10 seconds."
            case .tooShort: return "The clip is too short. Include at least 16 video frames."
            case .multipleFaces: return "Use a video with just one person visible."
            case .insufficientFace: return "Keep your face visible and well lit throughout the clip."
            case .invalidImage: return "A video frame could not be processed. Try another clip."
            }
        }
    }

    struct Prepared {
        let video: MLMultiArray
        let detectedFrames: Int
    }

    static func sampleTimes(duration: Double, frameRate: Double) throws -> [Double] {
        guard duration.isFinite, duration > 0, frameRate.isFinite, frameRate > 0, frameRate <= 240 else { throw InputError.invalidVideo }
        guard duration <= 10 else { throw InputError.tooLong }
        let frames = Int((duration * frameRate).rounded(.down))
        guard frames >= 16 else { throw InputError.tooShort }
        return (0..<16).map { Double(Int(Double($0 * (frames - 1)) / 15)) / frameRate }
    }

    /// AVFoundation decodes images only. No audio track is read or uploaded.
    static func prepare(url: URL) async throws -> Prepared {
        try Task.checkCancellation()
        guard url.isFileURL else { throw InputError.invalidVideo }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw InputError.invalidVideo }
        let duration = try await asset.load(.duration).seconds
        let fps = try await Double(track.load(.nominalFrameRate))
        let times = try sampleTimes(duration: duration, frameRate: fps)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        defer { generator.cancelAllCGImageGeneration() }
        let tensor = try MLMultiArray(shape: LipVisualModel.inputShape.map(NSNumber.init), dataType: .float32)
        let values = tensor.dataPointer.assumingMemoryBound(to: Float.self)
        var previous: CGRect?
        var detected = 0
        for (index, seconds) in times.enumerated() {
            try Task.checkCancellation()
            let image = try await withTaskCancellationHandler {
                try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 60_000)).image
            } onCancel: {
                generator.cancelAllCGImageGeneration()
            }
            let request = VNDetectFaceRectanglesRequest()
            try VNImageRequestHandler(cgImage: image).perform([request])
            let faces = request.results ?? []
            guard faces.count <= 1 else { throw InputError.multipleFaces }
            if let face = faces.first {
                detected += 1
                let box = face.boundingBox
                if let old = previous {
                    previous = CGRect(x: old.minX * 0.75 + box.minX * 0.25,
                                      y: old.minY * 0.75 + box.minY * 0.25,
                                      width: old.width * 0.75 + box.width * 0.25,
                                      height: old.height * 0.75 + box.height * 0.25)
                } else { previous = box }
            }
            let box = previous ?? CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            let pixels = try rgbPixels(image: image, normalizedFace: box)
            let plane = 224 * 224
            for pixel in 0..<plane {
                for channel in 0..<3 {
                    values[index * 3 * plane + channel * plane + pixel] = Float(pixels[pixel * 4 + channel])
                }
            }
        }
        guard detected >= 8 else { throw InputError.insufficientFace }
        return Prepared(video: tensor, detectedFrames: detected)
    }

    /// Vision bounds are bottom-left normalized; CGImage crop coordinates are
    /// top-left pixels. Keep the whole face with a small margin, as the prototype.
    static func cropRect(face: CGRect, width: Int, height: Int) throws -> CGRect {
        guard width > 0, height > 0, face.width > 0, face.height > 0,
              [face.minX, face.minY, face.width, face.height].allSatisfy(\.isFinite) else { throw InputError.invalidImage }
        let centerX = face.midX * Double(width)
        let centerY = (1 - face.midY) * Double(height)
        let side = max(face.width * Double(width), face.height * Double(height)) * 1.22
        let rect = CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { throw InputError.invalidImage }
        return rect
    }

    static func rgbPixels(image: CGImage, normalizedFace: CGRect) throws -> [UInt8] {
        let rect = try cropRect(face: normalizedFace, width: image.width, height: image.height)
        guard let cropped = image.cropping(to: rect) else { throw InputError.invalidImage }
        var bytes = [UInt8](repeating: 0, count: 224 * 224 * 4)
        try bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: 224, height: 224,
                bitsPerComponent: 8, bytesPerRow: 224 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { throw InputError.invalidImage }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 224, height: 224))
        }
        return bytes
    }
}
