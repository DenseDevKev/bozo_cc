import SwiftUI

@MainActor
final class HeadphoneViewModel: ObservableObject {
    @Published var state = HeadphoneState()
    @Published var statusMessage: String? = "Connecting..."

    private var client: IpcClient?
    private var readTask: Task<Void, Never>?

    init() {
        Task { connect() }
    }

    var menuBarTitle: String {
        if let pct = state.battery.first?.percentage {
            return "\(pct)%"
        }
        return "--"
    }

    var currentModeName: String? {
        guard let idx = state.audioModeIndex else { return nil }
        return state.audioModes.first(where: { $0.modeIndex == idx })?.name
    }

    func connect() {
        readTask?.cancel()
        client = nil
        Task {
            do {
                try await DaemonManager.ensureDaemon()
            } catch {
                statusMessage = error.localizedDescription
                return
            }

            guard let ipc = IpcClient() else {
                statusMessage = "Failed to connect to daemon socket"
                return
            }
            self.client = ipc
            statusMessage = "Connected to daemon"
            ipc.send(.getState)

            readTask = Task {
                for await response in ipc.responses {
                    handleResponse(response)
                }
                self.statusMessage = "Disconnected from daemon"
            }
        }
    }

    func setAudioMode(_ index: UInt8) {
        client?.send(.setAudioMode(modeIndex: index))
    }

    func setStandbyTimer(_ minutes: UInt8) {
        client?.send(.setStandbyTimer(minutes: minutes))
    }

    func powerOff() {
        client?.send(.powerOff)
    }

    func reconnect() {
        client?.send(.reconnect)
    }

    // MARK: - Private

    private func handleResponse(_ response: IpcResponse) {
        switch response {
        case .state(let s):
            state = s
            statusMessage = nil
        case .stateUpdate(let update):
            applyUpdate(update)
        case .error(let msg):
            statusMessage = msg
        case .ok:
            break
        }
    }

    private func applyUpdate(_ update: StateUpdate) {
        switch update {
        case .connection(let connected):
            state.connected = connected
        case .battery(let info):
            state.battery = info
        case .cnc(let cnc):
            state.cnc = cnc
        case .audioMode(let idx):
            state.audioModeIndex = idx
        case .audioModeDiscovered(let info):
            if let i = state.audioModes.firstIndex(where: { $0.modeIndex == info.modeIndex }) {
                state.audioModes[i] = info
            } else {
                state.audioModes.append(info)
                state.audioModes.sort { $0.modeIndex < $1.modeIndex }
            }
        case .standbyTimer(let min):
            state.standbyTimerMinutes = min
        case .productName(let name):
            state.productName = name
        }
    }
}
