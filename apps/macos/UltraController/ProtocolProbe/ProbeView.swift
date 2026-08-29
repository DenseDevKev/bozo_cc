import AppKit
import HeadphoneCore
import SwiftUI

struct ProbeRootView: View {
    @StateObject private var model: ProbeViewModel
    @StateObject private var central: ProbeCentral

    init() {
        let model = ProbeViewModel()
        _model = StateObject(wrappedValue: model)
        _central = StateObject(wrappedValue: ProbeCentral(model: model))
    }

    var body: some View {
        ProbeView(model: model, central: central)
    }
}

struct ProbeView: View {
    @ObservedObject var model: ProbeViewModel
    @ObservedObject var central: ProbeCentral
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
                central.powerOff()
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
                Button("Start Scan") { central.startScanning() }
                Button("Stop Scan") { central.stopScanning() }
                Button("Disconnect") { central.disconnect() }
                Button("Refresh") { central.refresh() }
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
                    description: Text("The probe checks connected BMAP devices, then runs two bounded scans.")
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
                            central.connect(idSuffix: candidate.idSuffix)
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
                    ForEach(Array(model.state.rows.enumerated()), id: \.offset) { _, row in
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
                                central.setCurrentMode(mode.id)
                            }
                        }
                    }
                    .disabled(!model.state.canUseSafeWrites || model.state.audioModes.isEmpty)

                    Menu("Set Standby") {
                        ForEach(standbyValues, id: \.self) { minutes in
                            Button(minutes == 0 ? "Never" : "\(minutes) minutes") {
                                central.setStandby(minutes)
                            }
                        }
                    }
                    .disabled(!model.state.canUseSafeWrites)

                    Menu("Set Spatial Audio") {
                        ForEach(SpatialAudioMode.allCases, id: \.rawValue) { mode in
                            Button(ProbeViewModel.State.spatialTitle(mode)) {
                                central.setSpatialAudio(mode)
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
