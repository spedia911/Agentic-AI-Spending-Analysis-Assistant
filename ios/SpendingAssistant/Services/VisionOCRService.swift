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
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:]).perform([request])
            return (request.results ?? []).compactMap { observation -> OCRLine? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return OCRLine(text: text, boundingBox: EvidenceRegion(x: box.origin.x,
                    y: 1 - box.origin.y - box.height, width: box.width, height: box.height))
            }
        }.value
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    var errorDescription: String? { "Could not read the screenshot image for OCR." }
}
