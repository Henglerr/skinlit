import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Preprocesses a raw selfie for optimal LLM skin analysis.
///
/// Pipeline (runs off the main thread):
///   1. Try face detection via Vision  →  crop to face region + 55% padding
///      (fallback: keep full image if detection fails)
///   2. Resize with preserved aspect ratio to a 1024px max dimension
///   3. JPEG encode at 0.88 quality
///
/// Research basis:
///  • GPT-4 Vision / Claude 3.5 process images at 512-px tiles; 1024px gives two
///    tiles of detail without hitting token limits or upload timeouts.
///  • Cropping to the face eliminates background clutter that causes the model
///    to allocate attention tokens to non-skin regions, improving accuracy.
///  • JPEG 0.88 keeps file size under 300 KB (typical selfie → ~180 KB) while
///    preserving pore-level detail the LLM needs.
public enum FaceImageProcessor {

    public enum ProcessorError: LocalizedError {
        case processingFailed

        public var errorDescription: String? {
            switch self {
            case .processingFailed:
                return "Could not process this image. Please try a different photo."
            }
        }
    }

    // MARK: - Public API

    /// Process a raw UIImage into a face-focused JPEG without color inflation.
    public static func process(_ image: UIImage) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            // Normalize orientation first so Vision and downstream processing
            // see upright pixels from camera/library sources.
            guard let cgImage = image.cgImageFixed() ?? image.cgImage else {
                throw ProcessorError.processingFailed
            }

            // Do not block the user if face-crop fails here; a stricter face
            // validation still happens right before analysis.
            let cropped = Self.cropToFaceIfPossible(cgImage) ?? UIImage(cgImage: cgImage)
            let resized = Self.resizePreservingAspect(cropped, maxDimension: 1024)
            guard let jpeg = resized.jpegData(compressionQuality: 0.88) else {
                throw ProcessorError.processingFailed
            }
            return jpeg
        }.value
    }

    /// Create a lightly normalized variant of a previously processed face crop.
    /// This gives the LLM an exposure-compensated view without changing geometry.
    public static func normalizedVariant(from imageData: Data) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw ProcessorError.processingFailed
        }

        let enhanced = autoEnhance(image)
        let resized = resizePreservingAspect(enhanced, maxDimension: 1024)
        guard let jpeg = resized.jpegData(compressionQuality: 0.88) else {
            throw ProcessorError.processingFailed
        }
        return jpeg
    }

    // MARK: - Private Stages

    /// Detect face bounding box and return a cropped CGImage with expansion margin.
    private static func cropToFaceIfPossible(_ source: CGImage) -> UIImage? {
        var detectedBounds: CGRect = .null
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNDetectFaceRectanglesRequest { request, _ in
            defer { semaphore.signal() }
            guard let results = request.results as? [VNFaceObservation],
                  let best = results.max(by: { $0.confidence < $1.confidence })
            else { return }
            // Vision uses normalised coords (0-1, origin bottom-left)
            detectedBounds = best.boundingBox
        }
        request.preferBackgroundProcessing = true

        let handler = VNImageRequestHandler(cgImage: source, options: [:])
        try? handler.perform([request])
        semaphore.wait()

        guard !detectedBounds.isNull else { return nil }

        // Convert from normalised Vision coords → pixel coords
        let w = CGFloat(source.width)
        let h = CGFloat(source.height)
        let faceRect = CGRect(
            x:      detectedBounds.origin.x * w,
            y:      (1 - detectedBounds.origin.y - detectedBounds.height) * h,
            width:  detectedBounds.width  * w,
            height: detectedBounds.height * h
        )

        // Expand by 55% on each side so forehead, jaw, and cheeks are fully included
        let padding: CGFloat = 0.55
        let expanded = faceRect.insetBy(
            dx: -faceRect.width  * padding,
            dy: -faceRect.height * padding
        )

        // Make it square (important for consistent LLM input)
        let side = max(expanded.width, expanded.height)
        let square = CGRect(
            x: expanded.midX - side / 2,
            y: expanded.midY - side / 2,
            width:  side,
            height: side
        ).intersection(CGRect(x: 0, y: 0, width: w, height: h))

        let cropped = source.cropping(to: square) ?? source
        return UIImage(cgImage: cropped)
    }

    /// Apply auto white-balance + contrast normalisation with CoreImage.
    private static func autoEnhance(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let ci = CIImage(cgImage: cgImage)

        // 1. Auto levels — adjusts exposure, saturation, WB towards sRGB neutral
        let autoFilters = ci.autoAdjustmentFilters()
        var result = ci
        for filter in autoFilters {
            filter.setValue(result, forKey: kCIInputImageKey)
            if let output = filter.outputImage { result = output }
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        if let rendered = context.createCGImage(result, from: result.extent) {
            return UIImage(cgImage: rendered)
        }
        return image
    }

    /// Resize to a max dimension while keeping aspect ratio intact.
    private static func resizePreservingAspect(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let sourceSize = image.size
        let longestSide = max(sourceSize.width, sourceSize.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

// MARK: - UIImage helper

private extension UIImage {
    /// Handles images with non-standard orientations (selfie from camera).
    func cgImageFixed() -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let fixed = renderer.image { _ in draw(at: .zero) }
        return fixed.cgImage
    }
}
