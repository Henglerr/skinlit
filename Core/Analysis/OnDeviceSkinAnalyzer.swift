import Foundation
import UIKit
import CoreGraphics

public struct OnDeviceAnalysisResult: Equatable {
    public let score: Double
    public let summary: String
    public let skinTypeDetected: String
    public let criteria: [String: Double]
}

public enum OnDeviceSkinAnalyzerError: LocalizedError {
    case invalidImage
    case processingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected image could not be read."
        case .processingFailed:
            return "The selected image could not be analyzed."
        }
    }
}

public enum OnDeviceSkinAnalyzer {
    public static func analyze(imageData: Data) throws -> OnDeviceAnalysisResult {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OnDeviceSkinAnalyzerError.invalidImage
        }

        guard let stats = computeImageStats(cgImage: cgImage) else {
            throw OnDeviceSkinAnalyzerError.processingFailed
        }

        let saturation = colorSaturation(red: stats.red, green: stats.green, blue: stats.blue)

        let hydration = clamp(
            4.8 + stats.meanLuma * 4.1 - stats.stdLuma * 2.0 + (0.32 - saturation) * 1.2,
            min: 2.5,
            max: 9.8
        )
        let texture = clamp(9.4 - stats.stdLuma * 11.0, min: 2.2, max: 9.8)
        let uniformity = clamp(
            9.2 - stats.stdLuma * 9.5 - abs(stats.red - stats.green) * 2.5,
            min: 2.0,
            max: 9.8
        )
        let luminosity = clamp(3.8 + stats.meanLuma * 5.7 + saturation * 0.6, min: 2.5, max: 9.9)

        let roundedCriteria: [String: Double] = [
            "Hydration": round1(hydration),
            "Texture": round1(texture),
            "Uniformity": round1(uniformity),
            "Luminosity": round1(luminosity)
        ]

        let criteria = criticallyCalibrate(criteria: roundedCriteria)
        let score = round1(criteria.values.reduce(0, +) / Double(criteria.count))
        let skinType = classifySkinType(meanLuma: stats.meanLuma, saturation: saturation, stdLuma: stats.stdLuma)
        let summary = makeSummary(criteria: criteria)

        return OnDeviceAnalysisResult(
            score: score,
            summary: summary,
            skinTypeDetected: skinType,
            criteria: criteria
        )
    }

    private static func computeImageStats(cgImage: CGImage) -> (red: Double, green: Double, blue: Double, meanLuma: Double, stdLuma: Double)? {
        let side = 72

        var rgbaPixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let rgbaContext = CGContext(
            data: &rgbaPixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        rgbaContext.interpolationQuality = .medium
        rgbaContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var redSum = 0.0
        var greenSum = 0.0
        var blueSum = 0.0
        var pixelCount = 0.0
        var index = 0
        while index < rgbaPixels.count {
            redSum += Double(rgbaPixels[index])
            greenSum += Double(rgbaPixels[index + 1])
            blueSum += Double(rgbaPixels[index + 2])
            pixelCount += 1
            index += 4
        }

        let red = (redSum / pixelCount) / 255.0
        let green = (greenSum / pixelCount) / 255.0
        let blue = (blueSum / pixelCount) / 255.0

        var grayPixels = [UInt8](repeating: 0, count: side * side)
        guard let grayContext = CGContext(
            data: &grayPixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        grayContext.interpolationQuality = .medium
        grayContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let normalized = grayPixels.map { Double($0) / 255.0 }
        let meanLuma = normalized.reduce(0, +) / Double(normalized.count)
        let variance = normalized.reduce(0) { partial, value in
            let delta = value - meanLuma
            return partial + delta * delta
        } / Double(normalized.count)
        let stdLuma = sqrt(variance)

        return (red, green, blue, meanLuma, stdLuma)
    }

    private static func colorSaturation(red: Double, green: Double, blue: Double) -> Double {
        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        guard maxChannel > 0 else { return 0 }
        return (maxChannel - minChannel) / maxChannel
    }

    private static func classifySkinType(meanLuma: Double, saturation: Double, stdLuma: Double) -> String {
        let baseType: String
        if saturation > 0.38 && meanLuma > 0.50 {
            baseType = "Oily"
        } else if meanLuma < 0.42 && saturation < 0.28 {
            baseType = "Dry"
        } else {
            baseType = "Combination"
        }

        let secondary = stdLuma > 0.17 ? "Sensitive" : "Balanced"
        return "\(baseType) · \(secondary)"
    }

    private static func makeSummary(criteria: [String: Double]) -> String {
        guard
            let weakest = criteria.min(by: { $0.value < $1.value }),
            let strongest = criteria.max(by: { $0.value < $1.value })
        else {
            return "Analysis complete."
        }

        return "\(strongest.key) is your strongest area. Focus on improving \(weakest.key.lowercased())."
    }

    private static func criticallyCalibrate(criteria: [String: Double]) -> [String: Double] {
        let canonicalNames = ["Hydration", "Texture", "Uniformity", "Luminosity"]
        var firstPass: [String: Double] = [:]

        for name in canonicalNames {
            let raw = clamp(criteria[name] ?? 0, min: 0, max: 10)
            // Expand contrast around 6.0 so good and bad skin separate more clearly.
            var adjusted = 6.0 + (raw - 6.0) * 1.10

            // Penalize weak criteria while keeping healthy skin from being dragged down.
            if adjusted < 6.0 { adjusted -= 0.12 }
            if adjusted < 5.0 { adjusted -= 0.20 }
            if adjusted < 4.0 { adjusted -= 0.30 }

            // Reward clearly strong criteria to better separate good skin.
            if adjusted > 7.5 { adjusted += 0.18 }
            if adjusted > 8.4 { adjusted += 0.22 }
            if adjusted > 9.1 { adjusted += 0.12 }

            firstPass[name] = round1(clamp(adjusted, min: 0, max: 10))
        }

        let values = Array(firstPass.values)
        let weakCount = values.filter { $0 < 6.0 }.count
        let severeCount = values.filter { $0 < 4.5 }.count
        let strongCount = values.filter { $0 >= 7.8 }.count
        let eliteCount = values.filter { $0 >= 8.8 }.count
        let average = values.reduce(0, +) / Double(values.count)
        let minimum = values.min() ?? 0

        var groupShift = 0.0
        if weakCount >= 2 { groupShift -= 0.18 }
        if weakCount >= 3 { groupShift -= 0.24 }
        if severeCount >= 1 { groupShift -= 0.22 }
        if severeCount >= 2 { groupShift -= 0.30 }
        if strongCount >= 3 && weakCount == 0 { groupShift += 0.30 }
        if eliteCount >= 2 && weakCount == 0 { groupShift += 0.22 }
        if minimum >= 7.0 && average >= 7.6 { groupShift += 0.18 }
        if average >= 8.3 && weakCount == 0 { groupShift += 0.15 }
        if minimum >= 6.8 && average >= 7.5 { groupShift += 0.25 }
        if minimum >= 7.2 && average >= 7.9 { groupShift += 0.25 }

        guard groupShift != 0 else { return firstPass }

        var final: [String: Double] = [:]
        for name in canonicalNames {
            let value = firstPass[name] ?? 0
            final[name] = round1(clamp(value + groupShift, min: 0, max: 10))
        }
        return final
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
