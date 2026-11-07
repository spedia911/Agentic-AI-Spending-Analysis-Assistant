import Foundation
import SpendingDomain

#if canImport(Vision)
import Vision
import UIKit

enum VisionOCRService {
    static func recognizeLines(from imageData: Data) async throws -> [OCRLine] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [OCRLine] = observations.compactMap { observation in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    let box = observation.boundingBox
                    return OCRLine(
                        text: text,
                        boundingBox: EvidenceRegion(
                            x: box.origin.x,
                            y: 1 - box.origin.y - box.size.height,
                            width: box.size.width,
                            height: box.size.height
                        )
                    )
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    var errorDescription: String? { "Could not read the screenshot image for OCR." }
}
#else
enum VisionOCRService {
    static func recognizeLines(from imageData: Data) async throws -> [OCRLine] {
        []
    }
}
#endif
