import Foundation
import UIKit
import Vision
import ImageIO

public protocol FaceDetectionService {
    func detectFaceCount(in imageData: Data) async throws -> Int
}

public enum FaceDetectionError: LocalizedError {
    case invalidImage
    case detectionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected photo could not be read."
        case .detectionFailed:
            return "Face detection failed. Please try another photo."
        }
    }
}

public struct VisionFaceDetectionService: FaceDetectionService {
    public init() {}

    public func detectFaceCount(in imageData: Data) async throws -> Int {
        guard let image = UIImage(data: imageData) else {
            throw FaceDetectionError.invalidImage
        }
        guard let cgImage = image.cgImage ?? image.cgImageFixed() else {
            throw FaceDetectionError.invalidImage
        }

        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.visionOrientation,
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                // Do not block scan flow on Vision transient failures.
                return 0
            }

            return request.results?.count ?? 0
        }.value
    }
}

private extension UIImage {
    var visionOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        case .upMirrored:
            return .upMirrored
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }

    func cgImageFixed() -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let fixed = renderer.image { _ in draw(at: .zero) }
        return fixed.cgImage
    }
}
