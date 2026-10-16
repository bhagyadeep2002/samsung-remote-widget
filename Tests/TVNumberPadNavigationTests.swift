import XCTest

final class TVNumberPadNavigationTests: XCTestCase {
    func testFirstDigitNavigatesFromSixWithoutSendingDirectNumberKey() throws {
        var navigation = TVNumberPadNavigation()
        let steps = try navigation.steps(for: .key(.digit1))
        XCTAssertEqual(steps.map(\.key), [.numberPad] + Array(repeating: .left, count: 5) + [.select])
        XCTAssertEqual(navigation.cursor, 0)
        XCTAssertEqual(steps.first?.delayAfter, .milliseconds(400))
        XCTAssertTrue(steps.allSatisfy { $0.key.digit == nil })
    }

    func testRepeatedDigitsAndZeroTrackTheLastSelectedColumn() throws {
        var navigation = TVNumberPadNavigation()
        _ = try navigation.steps(for: .key(.digit1))
        XCTAssertEqual(try navigation.steps(for: .key(.digit1)).map(\.key), [.select])
        XCTAssertEqual(try navigation.steps(for: .key(.digit0)).map(\.key),
                       Array(repeating: .right, count: 9) + [.select])
        XCTAssertEqual(try navigation.steps(for: .key(.digit6)).map(\.key),
                       Array(repeating: .left, count: 4) + [.select])
    }

    func testDeleteIsAfterZeroAndDoesNotWrapAcrossTeletextButton() throws {
        var navigation = TVNumberPadNavigation()
        _ = try navigation.steps(for: .key(.digit0))
        XCTAssertEqual(try navigation.steps(for: .deleteNumber).map(\.key), [.right, .select])
        XCTAssertEqual(try navigation.steps(for: .key(.digit1)).map(\.key),
                       Array(repeating: .left, count: 10) + [.select])
    }

    func testDoneUsesTopRowAndNextEntryReopensAtSix() throws {
        var navigation = TVNumberPadNavigation()
        _ = try navigation.steps(for: .key(.digit9))
        XCTAssertEqual(try navigation.steps(for: .finishNumberEntry).map(\.key), [.up, .select])
        XCTAssertNil(navigation.cursor)
        XCTAssertEqual(try navigation.steps(for: .key(.digit6)).map(\.key), [.numberPad, .select])
    }

    func testOpeningAlreadyOpenPadDoesNotToggleItClosed() throws {
        var navigation = TVNumberPadNavigation()
        XCTAssertEqual(try navigation.steps(for: .showNumberPad).map(\.key), [.numberPad])
        XCTAssertTrue(try navigation.steps(for: .showNumberPad).isEmpty)
        XCTAssertEqual(try navigation.steps(for: .hideNumberPad).map(\.key), [.back])
        XCTAssertTrue(try navigation.steps(for: .hideNumberPad).isEmpty)
    }

    func testRestartRestoresInitialSixAndOtherControlsDismissOverlay() throws {
        var navigation = TVNumberPadNavigation()
        _ = try navigation.steps(for: .key(.digit2))
        XCTAssertEqual(try navigation.steps(for: .restartNumberPad).map(\.key), [.back, .numberPad])
        XCTAssertEqual(navigation.cursor, 5)
        XCTAssertEqual(try navigation.steps(for: .key(.volumeUp)).map(\.key), [.back, .volumeUp])
        XCTAssertNil(navigation.cursor)
    }

    func testInterruptedEntryRequiresExplicitRecovery() throws {
        var navigation = TVNumberPadNavigation()
        _ = try navigation.steps(for: .showNumberPad)
        navigation.invalidate()
        XCTAssertThrowsError(try navigation.steps(for: .key(.digit5)))
        XCTAssertThrowsError(try navigation.steps(for: .finishNumberEntry))
        _ = try navigation.steps(for: .restartNumberPad)
        XCTAssertEqual(try navigation.steps(for: .key(.digit5)).map(\.key), [.left, .select])
    }

    func testRapidDigitWaitsForPreviousNavigationToComplete() async throws {
        let sender = CapturingSender(blockFirst: true)
        let session = TVRemoteControlSession { try await sender.send($0) }
        let first = Task { try await session.perform(.key(.digit1)) }
        await sender.waitUntilFirstStarted()
        let second = Task { try await session.perform(.key(.digit0)) }
        await sender.release()
        try await first.value
        try await second.value
        let batches = await sender.batches
        XCTAssertEqual(batches, [
            [.numberPad] + Array(repeating: .left, count: 5) + [.select],
            Array(repeating: .right, count: 9) + [.select]
        ])
    }

    func testFailedSequenceIsNotReplayedOrUsedAsKnownCursorState() async throws {
        let sender = CapturingSender(failFirst: true)
        let session = TVRemoteControlSession { try await sender.send($0) }
        do {
            try await session.perform(.key(.digit1))
            XCTFail("Expected a failed sequence")
        } catch { }
        do {
            try await session.perform(.key(.digit2))
            XCTFail("Unknown TV focus must require restart")
        } catch { XCTAssertTrue(error is TVNumberPadError) }
        let afterFailure = await sender.batches
        XCTAssertEqual(afterFailure.count, 1)
        try await session.perform(.restartNumberPad)
        try await session.perform(.key(.digit2))
        let afterRecovery = await sender.batches
        XCTAssertEqual(afterRecovery[1], [.back, .numberPad])
        XCTAssertEqual(afterRecovery[2], Array(repeating: .left, count: 4) + [.select])
    }
}

private actor CapturingSender {
    private(set) var batches: [[SamsungRemoteKey]] = []
    private let blockFirst: Bool
    private let failFirst: Bool
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(blockFirst: Bool = false, failFirst: Bool = false) {
        self.blockFirst = blockFirst
        self.failFirst = failFirst
    }

    func send(_ steps: [TVRemoteStep]) async throws {
        batches.append(steps.map(\.key))
        let isFirst = batches.count == 1
        startedContinuation?.resume()
        startedContinuation = nil
        if isFirst && blockFirst && !released {
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        if isFirst && failFirst { throw URLError(.networkConnectionLost) }
    }

    func waitUntilFirstStarted() async {
        if batches.isEmpty { await withCheckedContinuation { startedContinuation = $0 } }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
