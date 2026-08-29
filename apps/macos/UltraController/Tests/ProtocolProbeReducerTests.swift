import XCTest
import HeadphoneCore

final class ProtocolProbeReducerTests: XCTestCase {
    func testProbeEventsProduceReadableRows() {
        var state = ProbeViewModel.State()
        state.reduce(.discovered(name: "QC Ultra", idSuffix: "0001", rssi: -42))
        state.reduce(.battery([
            BatteryComponent(id: 0, percentage: 85, remainingMinutes: 300),
        ]))

        XCTAssertEqual(state.rows.map(\.title), ["Discovered", "Battery"])
        XCTAssertEqual(state.rows.map(\.detail), ["QC Ultra • …0001 • −42 dBm", "85% • 300 min"])
    }

    func testCandidateEventsReplaceExistingCandidateByIdentifierSuffix() {
        var state = ProbeViewModel.State()
        state.reduce(.discovered(name: "QC Ultra", idSuffix: "0001", rssi: -60))
        state.reduce(.discovered(name: "Renamed", idSuffix: "0001", rssi: -40))

        XCTAssertEqual(state.candidates, [
            ProbeCandidate(name: "Renamed", idSuffix: "0001", rssi: -40),
        ])
        XCTAssertEqual(state.rows.count, 2)
    }

    func testErrorEventIsReadableAndFinite() {
        var state = ProbeViewModel.State()
        state.reduce(.error("Bluetooth unavailable"))

        XCTAssertEqual(state.status, "Bluetooth unavailable")
        XCTAssertEqual(state.rows.last, ProbeRow(title: "Error", detail: "Bluetooth unavailable"))
    }

    func testSanitizedTranscriptContainsNoFullPeripheralIdentifier() {
        var state = ProbeViewModel.State()
        state.reduce(.discovered(name: "QC Ultra", idSuffix: "0001", rssi: -42))
        state.reduce(.packet(direction: .received, summary: "Status/Battery", hex: "0202030455012C00"))

        let transcript = state.sanitizedTranscript()
        XCTAssertTrue(transcript.contains("…0001"))
        XCTAssertFalse(transcript.contains("123E4567-E89B-12D3-A456-426614174000"))
        XCTAssertTrue(transcript.contains("0202030455012C00"))
    }
}
