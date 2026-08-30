//
//  NearbyDecisionGate.swift
//  FinallyExplorer
//

import Foundation

nonisolated final class NearbyDecisionGate<Value: Sendable>: @unchecked Sendable {
    private let stream: AsyncStream<Value>
    private let continuation: AsyncStream<Value>.Continuation

    init() {
        var capturedContinuation: AsyncStream<Value>.Continuation?
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            capturedContinuation = $0
        }
        continuation = capturedContinuation!
    }

    func resolve(_ value: Value) {
        continuation.yield(value)
        continuation.finish()
    }

    func wait() async -> Value? {
        for await value in stream {
            return value
        }
        return nil
    }

    func cancel() {
        continuation.finish()
    }
}
