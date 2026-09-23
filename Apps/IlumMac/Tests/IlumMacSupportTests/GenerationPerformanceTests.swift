import Foundation
import XCTest
import IlumCore
@testable import IlumMacSupport

final class GenerationPerformanceTests: XCTestCase {
    func testMultipleCallsUseWeightedGenerationRateAndKeepFirstVisibleText() {
        var report = GenerationPerformance(model: "qwen3:4b", mode: "fast")
        report.recordFirstText(after: 2)
        report.recordFirstText(after: 9)
        report.record(.init(requestSeconds: 4, generationSeconds: 1, generatedTokens: 10))
        report.record(.init(requestSeconds: 8, generationSeconds: 3, generatedTokens: 90))
        report.finish(.completed, after: 15)
        XCTAssertEqual(report.firstTextSeconds, 2)
        XCTAssertEqual(report.generatedTokensPerSecond, 25)
        XCTAssertEqual(report.elapsedSeconds, 15)
        XCTAssertEqual(report.outcome, .completed)
        XCTAssertTrue(report.report.contains("Measured completed model calls: 2"))
    }

    func testPartialMissingMetricsDoNotReportMisleadingRate() {
        var report = GenerationPerformance(model: "test", mode: "thinking")
        report.record(.init(requestSeconds: 5, generationSeconds: 1, generatedTokens: 10))
        report.record(.init(requestSeconds: 7))
        report.finish(.failed, after: 15)
        XCTAssertNil(report.generatedTokensPerSecond)
        XCTAssertTrue(report.summary.contains("Failed"))
        XCTAssertTrue(report.report.contains("Model loading: unavailable"))
    }

    func testCancelledPermissionContinuationIsASeparateMeasurement() {
        var previous = GenerationPerformance(model: "small", mode: "fast")
        previous.recordFirstText(after: 1)
        previous.finish(.awaitingPermission, after: 3)
        var continuation = GenerationPerformance(model: "small", mode: "fast")
        continuation.finish(.cancelled, after: 2)
        XCTAssertEqual(previous.outcome, .awaitingPermission)
        XCTAssertEqual(continuation.outcome, .cancelled)
        XCTAssertNil(continuation.firstTextSeconds)
        XCTAssertTrue(continuation.calls.isEmpty)
        XCTAssertNil(continuation.generatedTokensPerSecond)
    }

    func testZeroAndNonfiniteDurationsCannotProduceInfiniteRates() {
        let zero = ModelResponseMetrics(requestSeconds: 1, generationSeconds: 0, generatedTokens: 20)
        XCTAssertNil(zero.generatedTokensPerSecond)
        let invalid = ModelResponseMetrics(requestSeconds: 1, loadSeconds: -.infinity, generationSeconds: .nan, generatedTokens: -1)
        XCTAssertNil(invalid.loadSeconds)
        XCTAssertNil(invalid.generationSeconds)
        XCTAssertNil(invalid.generatedTokens)
    }
}

@MainActor
final class ModelPreferencesTests: XCTestCase {
    func testSavedModelSurvivesRecreationAndIsScopedToEndpoint() async throws {
        let suite = "IlumPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = URL(string: "http://127.0.0.1:11434/api/chat")!
        let second = URL(string: "http://127.0.0.1:11435/api/chat")!
        ModelPreferences(defaults: defaults).setModel("qwen3:4b", for: first)
        let reopened = ModelPreferences(defaults: defaults)
        XCTAssertEqual(reopened.model(for: first), "qwen3:4b")
        XCTAssertNil(reopened.model(for: second))
        reopened.setModel("llama3.2:3b", for: second)
        XCTAssertEqual(reopened.model(for: first), "qwen3:4b")
        reopened.setModel(nil, for: first)
        XCTAssertNil(reopened.model(for: first))
        XCTAssertEqual(reopened.model(for: second), "llama3.2:3b")
    }
}
