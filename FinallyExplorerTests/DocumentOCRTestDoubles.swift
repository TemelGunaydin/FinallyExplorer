import CoreGraphics
import Foundation
@testable import FinallyExplorer

actor RecordingDocumentTextRecognizer: DocumentTextRecognizing {
    private(set) var calls = 0
    private(set) var dimensions: [CGSize] = []
    let text: String
    let gate: FolderComparisonTestGate?
    let error: DocumentQuestionError?

    init(text: String = "The payment deadline is 30 September 2026.", gate: FolderComparisonTestGate? = nil,
         error: DocumentQuestionError? = nil) {
        self.text = text; self.gate = gate; self.error = error
    }

    func recognize(_ image: CGImage) async throws -> String {
        calls += 1
        dimensions.append(CGSize(width: image.width, height: image.height))
        if let gate { await gate.pause() }
        if let error { throw error }
        return text
    }
}

actor DocumentReadProgressRecorder {
    private(set) var values: [DocumentReadProgress] = []
    func record(_ value: DocumentReadProgress) { values.append(value) }
}
