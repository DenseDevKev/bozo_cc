import AppKit
import HeadphoneCore
import SwiftUI

@MainActor
final class ProbeRuntime: ObservableObject {
    let model: ProbeViewModel
    private var central: ProbeCentral?

    init() {
        model = ProbeViewModel()
    }

    func startScanning() {
        if let central {
            central.startScanning()
            return
        }

        // Constructing CBCentralManager may prompt for Bluetooth access and invoke its
        // delegate immediately. Keep that work out of SwiftUI view initialization.
        central = ProbeCentral(model: model)
    }

    func stopScanning() {
        central?.stopScanning()
    }

    func connect(idSuffix: String) {
        central?.connect(idSuffix: idSuffix)
    }

    func disconnect() {
        central?.disconnect()
    }

    func refresh() {
        guard let central else {
            model.handle(.error("Press Start Scan before refreshing"))
            return
        }
        central.refresh()
    }

    func setCurrentMode(_ modeID: UInt8) {
        central?.setCurrentMode(modeID)
    }

    func setStandby(_ minutes: UInt8) {
        central?.setStandby(minutes)
    }

    func setSpatialAudio(_ mode: SpatialAudioMode) {
        central?.setSpatialAudio(mode)
    }

    func powerOff() {
        central?.powerOff()
    }
}

struct ProbeRootView: View {
    @StateObject private var runtime = ProbeRuntime()

    var body: some View {
        ProbeView(model: runtime.model, runtime: runtime)
    }
}

struct ProbeView: View {
    @ObservedObject var model: ProbeViewModel
    let runtime: ProbeRuntime
    @State private var showsPowerOffConfirmation = false

    private let standbyValues: [UInt8] = [0, 5, 10, 20, 30, 60, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            HSplitView {
                candidates
                    .frame(minWidth: 250, idealWidth: 290)
                transcript
                    .frame(minWidth: 480)
            }
            safeControls
        }
        .padding(16)
        .frame(minWidth: 860, minHeight: 620)
        .alert("Power Off Headphones?", isPresented: $showsPowerOffConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Power Off", role: .destructive) {
                runtime.powerOff()
            }
        } message: {
            Text("Power Off is sent last. The expected result is an immediate Bluetooth disconnect.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "headphones")
                Text("QC Ultra Protocol Probe")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Start Scan") { runtime.startScanning() }
                Button("Stop Scan") { runtime.stopScanning() }
                Button("Disconnect") { runtime.disconnect() }
                Button("Refresh") { runtime.refresh() }
                Button("Copy Sanitized Session") { copyTranscript() }
            }

            Text(model.state.status)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var candidates: some View {
        GroupBox("Candidates") {
            if model.state.candidates.isEmpty {
                ContentUnavailableView(
                    "No Candidates",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Press Start Scan. The probe checks connected BMAP devices, then runs two bounded scans.")
                )
            } else {
                List(model.state.candidates) { candidate in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(candidate.name)
                            Text("…\(candidate.idSuffix) • \(candidate.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") {
                            runtime.connect(idSuffix: candidate.idSuffix)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var transcript: some View {
        GroupBox("Parsed Responses and Scrubbed Packet Hex") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.state.rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(row.detail)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
                .padding(8)
            }
        }
    }

    private var safeControls: some View {
        GroupBox("Safe Essential Write and Restore Checks") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "I confirm the connected device is my QC Ultra Headphones Gen 1",
                    isOn: Binding(
                        get: { model.state.identityConfirmedForSafeWrites },
                        set: { model.handle(.safeWritesConfirmed($0)) }
                    )
                )
                .disabled(!model.state.canConfirmSafeWrites)

                if !model.state.canConfirmSafeWrites {
                    Text("Writes stay locked until a QC Ultra product response is parsed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Menu("Set Existing Mode") {
                        ForEach(model.state.audioModes) { mode in
                            Button("\(mode.name) (\(mode.id))") {
                                runtime.setCurrentMode(mode.id)
                            }
                        }
                    }
                    .disabled(!model.state.canUseSafeWrites || model.state.audioModes.isEmpty)

                    Menu("Set Standby") {
                        ForEach(standbyValues, id: \.self) { minutes in
                            Button(minutes == 0 ? "Never" : "\(minutes) minutes") {
                                runtime.setStandby(minutes)
                            }
                        }
                    }
                    .disabled(!model.state.canUseSafeWrites)

                    Menu("Set Spatial Audio") {
                        ForEach(SpatialAudioMode.allCases, id: \.rawValue) { mode in
                            Button(ProbeViewModel.State.spatialTitle(mode)) {
                                runtime.setSpatialAudio(mode)
                            }
                        }
                    }
                    .disabled(!model.state.canUseSafeWrites)

                    Spacer()

                    Button("Power Off…", role: .destructive) {
                        showsPowerOffConfirmation = true
                    }
                    .disabled(!model.state.canUseSafeWrites)
                }

                Text("Record each original value first, change one setting, confirm its GET response, and restore it. Power Off must be the final check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyTranscript() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.state.sanitizedTranscript(), forType: .string)
    }
}
