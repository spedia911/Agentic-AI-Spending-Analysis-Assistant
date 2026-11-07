import Foundation
import SpendingDomain

/// Availability-gated adapters. On unsupported OS/devices these no-op / return nil.
protocol OnDeviceStructurer: Sendable {
    func structure(ocrText: String, sourceDocumentId: String, fileName: String) async throws -> ScreenshotExtractionResult?
}

protocol OnDeviceCategoryClassifier: CategoryClassifier {}

struct NoopStructurer: OnDeviceStructurer {
    func structure(ocrText: String, sourceDocumentId: String, fileName: String) async throws -> ScreenshotExtractionResult? {
        nil
    }
}

/// Placeholder for Apple Foundation Models integration.
/// When Foundation Models are available at runtime, replace the body with LanguageModelSession calls.
struct FoundationModelStructurer: OnDeviceStructurer {
    func structure(ocrText: String, sourceDocumentId: String, fileName: String) async throws -> ScreenshotExtractionResult? {
        #if canImport(FoundationModels)
        // Progressive enhancement hook: compile against FoundationModels when the SDK is present.
        // Until linked, fall through to nil so heuristics / AI import remain the path.
        return nil
        #else
        return nil
        #endif
    }
}

struct FoundationModelCategoryClassifier: OnDeviceCategoryClassifier {
    func classify(_ input: CategoryClassificationInput) async throws -> CategoryClassificationDecision {
        #if canImport(FoundationModels)
        throw ClassifierUnavailable.notLinked
        #else
        throw ClassifierUnavailable.notAvailable
        #endif
    }
}

enum ClassifierUnavailable: Error, LocalizedError {
    case notAvailable
    case notLinked
    var errorDescription: String? {
        switch self {
        case .notAvailable: return "On-device category model is not available on this device."
        case .notLinked: return "Foundation Models SDK is not linked in this build."
        }
    }
}

enum OnDeviceAIFactory {
    static func makeStructurer(enabled: Bool) -> any OnDeviceStructurer {
        enabled ? FoundationModelStructurer() : NoopStructurer()
    }

    static func makeClassifier(enabled: Bool) -> (any CategoryClassifier)? {
        enabled ? FoundationModelCategoryClassifier() : nil
    }
}
