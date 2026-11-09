import Foundation
import SpendingDomain
import Vision
import UIKit
import ImageIO

enum VisionOCRService {
    static func recognizeLines(from imageData: Data) async throws -> [OCRLine] {
        // Vision performs synchronously, so run it away from the UI executor.
        // Reading results after perform also avoids resuming an error continuation twice.
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: imageData), let cgImage = image.cgImage else { throw OCRError.invalidImage }
            let orientation: CGImagePropertyOrientation
            switch image.imageOrientation {
            case .up: orientation = .up
            case .down: orientation = .down
            case .left: orientation = .left
            case .right: orientation = .right
            case .upMirrored: orientation = .upMirrored
            case .downMirrored: orientation = .downMirrored
            case .leftMirrored: orientation = .leftMirrored
            case .rightMirrored: orientation = .rightMirrored
            @unknown default: orientation = .up
            }
            // Normalize high-bit-depth screenshots into a Vision-compatible 8-bit buffer.
            guard let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OCRError.invalidImage }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            guard let ocrImage = context.makeImage() else { throw OCRError.invalidImage }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: ocrImage, orientation: orientation, options: [:]).perform([request])
            return (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string
                let box = observation.boundingBox
                return OCRLine(text: text, boundingBox: EvidenceRegion(x: box.origin.x,
                    y: 1 - box.origin.y - box.height, width: box.width, height: box.height), confidence: Double(candidate.confidence))
            }
        }.value
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    var errorDescription: String? { "Could not read the screenshot image for OCR." }
}
