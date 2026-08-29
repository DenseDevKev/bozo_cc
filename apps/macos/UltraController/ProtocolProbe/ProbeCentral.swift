@preconcurrency import CoreBluetooth
import Combine
import Dispatch
import Foundation
import HeadphoneCore

final class ProbeCentral: NSObject, ObservableObject {
    private enum ScanPhase {
        case idle
        case filtered
        case unfiltered
    }

    private struct QueuedPacket {
        let packet: BMAPPacket
        let summary: String
    }

    private static let serviceUUID = CBUUID(string: "FEBE")
    private static let secureUUID = CBUUID(string: "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8")
    private static let unsecureUUID = CBUUID(string: "D417C028-9818-4354-99D1-2AC09D074591")

    private let model: ProbeViewModel
    private var central: CBCentralManager!
    private var candidatesBySuffix: [String: CBPeripheral] = [:]
    private var selectedPeripheral: CBPeripheral?
    private var selectedCharacteristic: CBCharacteristic?
    private var selectedWriteType: CBCharacteristicWriteType = .withResponse
    private var reassembler = BLEReassembler()
    private var scanPhase = ScanPhase.idle
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var queuedPackets: [QueuedPacket] = []
    private var isDrainingPackets = false
    private var packetDrainWorkItem: DispatchWorkItem?
    private var latestAudioSettings: AudioSettings?
    private var pendingSpatialAudioMode: SpatialAudioMode?

    init(model: ProbeViewModel) {
        self.model = model
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    deinit {
        scanTimeoutWorkItem?.cancel()
        packetDrainWorkItem?.cancel()
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            model.handle(.error("Bluetooth is not powered on"))
            return
        }

        stopScanning(report: false)
        candidatesBySuffix.removeAll()
        model.handle(.scanReset)

        let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
        for peripheral in connected {
            registerCandidate(peripheral, name: peripheral.name, rssi: 0)
        }

        beginFilteredScan()
    }

    func stopScanning() {
        stopScanning(report: true)
    }

    func connect(idSuffix: String) {
        guard let peripheral = candidatesBySuffix[idSuffix] else {
            model.handle(.error("The selected Bluetooth candidate is no longer available"))
            return
        }

        stopScanning(report: false)
        clearPacketQueue()
        clearLiveAudioState()
        selectedCharacteristic = nil
        selectedPeripheral = peripheral
        peripheral.delegate = self
        model.handle(.safeWritesConfirmed(false))
        model.handle(.connecting(peripheral.name ?? "Bluetooth device"))
        central.connect(peripheral)
    }

    func disconnect() {
        clearPacketQueue()
        clearLiveAudioState()
        guard let selectedPeripheral else {
            model.handle(.disconnected("No device is connected"))
            return
        }
        central.cancelPeripheralConnection(selectedPeripheral)
    }

    func refresh() {
        guard selectedCharacteristic != nil else {
            model.handle(.error("Connect and wait for the BMAP channel before refreshing"))
            return
        }
        enqueueInitialQueries()
    }

    func setCurrentMode(_ id: UInt8) {
        guard requireSafeWrites() else { return }
        enqueue(AudioModeMessages.setCurrent(index: id), summary: "Set current mode \(id)")
        enqueue(AudioModeMessages.queryCurrent(), summary: "Confirm current mode")
        enqueue(AudioSettingsMessages.query(), summary: "Refresh live audio settings")
    }

    func setStandby(_ minutes: UInt8) {
        guard requireSafeWrites() else { return }
        enqueue(StandbyMessages.set(minutes: minutes), summary: "Set standby \(minutes)")
        enqueue(StandbyMessages.query(), summary: "Confirm standby")
    }

    func setSpatialAudio(_ mode: SpatialAudioMode) {
        guard requireSafeWrites() else { return }

        // AudioModes SettingsConfig is a five-byte read/modify/write register.
        // Read it immediately before the write so changing immersive audio cannot
        // overwrite the active CNC, ActiveSense, wind-block, or ANC values.
        pendingSpatialAudioMode = mode
        enqueue(
            AudioSettingsMessages.query(),
            summary: "Read live audio settings before spatial change"
        )
    }

    func powerOff() {
        guard requireSafeWrites() else { return }
        enqueue(PowerMessages.powerOff(), summary: "Power off")
    }

    private func requireSafeWrites() -> Bool {
        guard model.state.canUseSafeWrites else {
            model.handle(.error("Safe writes require a connected QC Ultra identity and explicit confirmation"))
            return false
        }
        return true
    }

    private func beginFilteredScan() {
        scanPhase = .filtered
        model.handle(.bluetooth("Scanning for the BMAP service…"))
        central.scanForPeripherals(withServices: [Self.serviceUUID])
        scheduleScanTimeout(after: 5) { [weak self] in
            self?.finishFilteredScan()
        }
    }

    private func finishFilteredScan() {
        guard scanPhase == .filtered else { return }
        central.stopScan()

        if candidatesBySuffix.isEmpty {
            beginUnfilteredScan()
        } else {
            scanPhase = .idle
            model.handle(.scanStopped("Select a discovered candidate"))
        }
    }

    private func beginUnfilteredScan() {
        scanPhase = .unfiltered
        model.handle(.bluetooth("Filtered scan was empty; trying a bounded name-hint scan…"))
        central.scanForPeripherals(withServices: nil)
        scheduleScanTimeout(after: 5) { [weak self] in
            self?.finishUnfilteredScan()
        }
    }

    private func finishUnfilteredScan() {
        guard scanPhase == .unfiltered else { return }
        central.stopScan()
        scanPhase = .idle

        if candidatesBySuffix.isEmpty {
            model.handle(.error("No BMAP candidate was found in either scan window"))
        } else {
            model.handle(.scanStopped("Select a discovered candidate"))
        }
    }

    private func scheduleScanTimeout(after seconds: TimeInterval, action: @escaping () -> Void) {
        scanTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem(block: action)
        scanTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    private func stopScanning(report: Bool) {
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil
        central?.stopScan()
        scanPhase = .idle
        if report {
            model.handle(.scanStopped("Scan stopped"))
        }
    }

    private func registerCandidate(_ peripheral: CBPeripheral, name: String?, rssi: Int) {
        let suffix = Self.identifierSuffix(peripheral.identifier)
        candidatesBySuffix[suffix] = peripheral
        model.handle(.discovered(
            name: name ?? peripheral.name ?? "Bluetooth device",
            idSuffix: suffix,
            rssi: rssi
        ))
    }

    private static func identifierSuffix(_ identifier: UUID) -> String {
        String(identifier.uuidString.replacingOccurrences(of: "-", with: "").suffix(4))
            .uppercased()
    }

    private static func nameLooksLikeBose(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("bose") || name.contains("adjuster")
    }

    private func enqueueInitialQueries() {
        let initialQueries: [(BMAPPacket, String)] = [
            (ProductMessages.queryName(), "Query product name"),
            (BatteryMessages.query(), "Query battery"),
            (AudioModeMessages.queryCapabilities(), "Query mode capabilities"),
            (AudioModeMessages.queryCurrent(), "Query current mode"),
            (StandbyMessages.query(), "Query standby"),
            (AudioSettingsMessages.query(), "Query live audio settings"),
            // GetAll is a START command that emits a multi-frame STATUS burst.
            // Keep it last so no later startup request collides with that burst.
            (AudioModeMessages.querySnapshot(), "Start AudioModes snapshot"),
        ]

        for (packet, summary) in initialQueries {
            enqueue(packet, summary: summary)
        }
    }

    private func enqueue(_ packet: BMAPPacket, summary: String) {
        queuedPackets.append(QueuedPacket(packet: packet, summary: summary))
        drainPacketQueueIfNeeded()
    }

    private func drainPacketQueueIfNeeded() {
        guard !isDrainingPackets, !queuedPackets.isEmpty else { return }
        isDrainingPackets = true
        let queued = queuedPackets.removeFirst()
        writeNow(queued.packet, summary: queued.summary)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isDrainingPackets = false
            self.drainPacketQueueIfNeeded()
        }
        packetDrainWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func clearPacketQueue() {
        packetDrainWorkItem?.cancel()
        packetDrainWorkItem = nil
        queuedPackets.removeAll()
        isDrainingPackets = false
    }

    private func clearLiveAudioState() {
        latestAudioSettings = nil
        pendingSpatialAudioMode = nil
    }

    private func writeNow(_ packet: BMAPPacket, summary: String) {
        guard
            let selectedPeripheral,
            let selectedCharacteristic,
            selectedPeripheral.state == .connected
        else {
            model.handle(.error("The BMAP channel is not ready"))
            return
        }

        do {
            let packetBytes = try packet.encoded()
            let segments = try BLESegmenter.segment(packetBytes)
            model.handle(.packet(
                direction: .sent,
                summary: summary,
                hex: Self.hex(packetBytes)
            ))

            for segment in segments {
                selectedPeripheral.writeValue(
                    Data(segment),
                    for: selectedCharacteristic,
                    type: selectedWriteType
                )
            }
        } catch {
            model.handle(.error("Could not encode or send \(summary): \(error)"))
        }
    }

    private func processNotification(_ bytes: [UInt8]) {
        do {
            guard let completeBytes = try reassembler.feed(bytes) else { return }
            for packet in try BMAPPacket.decodeMany(completeBytes) {
                processPacket(packet)
            }
        } catch {
            model.handle(.error("Could not decode a BMAP notification: \(error)"))
        }
    }

    private func processPacket(_ packet: BMAPPacket) {
        let packetBytes = (try? packet.encoded()) ?? []
        model.handle(.packet(
            direction: .received,
            summary: Self.packetSummary(packet),
            hex: Self.hex(packetBytes)
        ))

        if packet.operator == .error {
            let code = packet.payload.first ?? 0
            let detail = packet.payload.count > 1
                ? " detail 0x\(String(format: "%02X", packet.payload[1]))"
                : ""
            let address = String(
                format: "0x%02X/0x%02X",
                packet.functionBlock.rawValue,
                packet.function
            )
            model.handle(.error(
                "Device error 0x\(String(format: "%02X", code)) at \(address)\(detail)"
            ))
            return
        }

        do {
            switch (packet.functionBlock, packet.function) {
            case (.settings, 0x02) where packet.operator == .status:
                model.handle(.identity(try ProductMessages.parseName(packet)))

            case (.status, 0x02) where packet.operator == .status:
                model.handle(.battery(try BatteryMessages.parse(packet)))

            case (.audioModes, 0x02) where packet.operator == .status:
                model.handle(.capabilities(try AudioModeMessages.parseCapabilities(packet)))

            case (.audioModes, 0x03) where packet.operator == .status:
                model.handle(.currentMode(try AudioModeMessages.parseCurrent(packet)))

            case (.audioModes, 0x06) where packet.operator == .status:
                model.handle(.modeConfiguration(try AudioModeMessages.parseConfiguration(packet)))

            case (.audioModes, 0x0A) where packet.operator == .status:
                let settings = try AudioSettingsMessages.parse(packet)
                latestAudioSettings = settings
                model.handle(.spatialAudio(settings.spatialAudioMode))
                applyPendingSpatialAudioChange(using: settings)

            case (.settings, 0x04) where packet.operator == .status:
                model.handle(.standby(try StandbyMessages.parse(packet)))

            default:
                // START acknowledgements and unimplemented snapshot fields are
                // retained in the packet transcript but are not parsed as state.
                break
            }
        } catch {
            model.handle(.error("Strict parser rejected \(Self.packetSummary(packet)): \(error)"))
        }
    }

    private func applyPendingSpatialAudioChange(using current: AudioSettings) {
        guard let requestedMode = pendingSpatialAudioMode else { return }
        pendingSpatialAudioMode = nil

        let updated = current.replacingSpatialAudioMode(requestedMode)
        enqueue(
            AudioSettingsMessages.set(updated),
            summary: "Set spatial audio while preserving live audio settings"
        )
        enqueue(AudioSettingsMessages.query(), summary: "Confirm live audio settings")
    }

    private static func packetSummary(_ packet: BMAPPacket) -> String {
        String(
            format: "0x%02X/0x%02X %@",
            packet.functionBlock.rawValue,
            packet.function,
            String(describing: packet.operator)
        )
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}

extension ProbeCentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            model.handle(.bluetooth("Bluetooth powered on"))
            startScanning()
        case .poweredOff:
            model.handle(.error("Bluetooth is powered off"))
        case .unauthorized:
            model.handle(.error("Bluetooth permission is denied"))
        case .unsupported:
            model.handle(.error("This Mac does not support CoreBluetooth"))
        case .resetting:
            model.handle(.bluetooth("Bluetooth is resetting"))
        case .unknown:
            model.handle(.bluetooth("Bluetooth state is unknown"))
        @unknown default:
            model.handle(.error("Bluetooth reported an unknown state"))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisesBMAP = advertisedServices.contains(Self.serviceUUID)

        guard scanPhase == .filtered || advertisesBMAP || Self.nameLooksLikeBose(advertisedName ?? peripheral.name) else {
            return
        }

        registerCandidate(
            peripheral,
            name: advertisedName ?? peripheral.name,
            rssi: RSSI.intValue
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        model.handle(.connected(peripheral.name ?? "Bluetooth device"))
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        model.handle(.error(error?.localizedDescription ?? "Bluetooth connection failed"))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        clearPacketQueue()
        clearLiveAudioState()
        selectedCharacteristic = nil
        selectedPeripheral = nil
        reassembler = BLEReassembler()
        model.handle(.disconnected(
            error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected"
        ))
    }
}

extension ProbeCentral: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            model.handle(.error("Service discovery failed: \(error.localizedDescription)"))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            model.handle(.error("The candidate does not expose the BMAP service"))
            central.cancelPeripheralConnection(peripheral)
            return
        }

        peripheral.discoverCharacteristics(
            [Self.secureUUID, Self.unsecureUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            model.handle(.error("Characteristic discovery failed: \(error.localizedDescription)"))
            return
        }

        let characteristics = service.characteristics ?? []
        let secure = characteristics.first(where: {
            $0.uuid == Self.secureUUID && Self.isControlCharacteristic($0)
        })
        let unsecure = characteristics.first(where: {
            $0.uuid == Self.unsecureUUID && Self.isControlCharacteristic($0)
        })

        guard let selected = secure ?? unsecure else {
            model.handle(.error("No notify-and-write BMAP characteristic is available"))
            return
        }

        selectedCharacteristic = selected
        selectedWriteType = selected.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.setNotifyValue(true, for: selected)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            model.handle(.error("Could not enable BMAP notifications: \(error.localizedDescription)"))
            return
        }

        guard characteristic.uuid == selectedCharacteristic?.uuid, characteristic.isNotifying else {
            return
        }
        let channel = characteristic.uuid == Self.secureUUID ? "Secure" : "Unsecure"
        let write = selectedWriteType == .withResponse
            ? "write with response"
            : "write without response"
        model.handle(.channelReady("\(channel) • notify • \(write)"))
        enqueueInitialQueries()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            model.handle(.error("BMAP notification failed: \(error.localizedDescription)"))
            return
        }

        guard characteristic.uuid == selectedCharacteristic?.uuid,
              let data = characteristic.value else {
            return
        }
        processNotification([UInt8](data))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            model.handle(.error("A BMAP write failed: \(error.localizedDescription)"))
        }
    }

    private static func isControlCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        characteristic.properties.contains(.notify) &&
            (characteristic.properties.contains(.write) ||
                characteristic.properties.contains(.writeWithoutResponse))
    }
}
