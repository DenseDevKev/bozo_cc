import Foundation

public enum AudioModeMessages {
    private static let allFunction: UInt8 = 0x01
    private static let capabilitiesFunction: UInt8 = 0x02
    private static let currentFunction: UInt8 = 0x03
    private static let configurationFunction: UInt8 = 0x06

    public static func queryAll() -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioModes,
            function: allFunction,
            operator: .get
        )
    }

    public static func queryCapabilities() -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioModes,
            function: capabilitiesFunction,
            operator: .get
        )
    }

    public static func queryCurrent() -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioModes,
            function: currentFunction,
            operator: .get
        )
    }

    public static func queryConfiguration(index: UInt8) -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioModes,
            function: configurationFunction,
            operator: .get,
            payload: [index]
        )
    }

    public static func setCurrent(
        index: UInt8,
        playVoicePrompt: Bool = false
    ) -> BMAPPacket {
        BMAPPacket(
            functionBlock: .audioModes,
            function: currentFunction,
            operator: .start,
            payload: [index, playVoicePrompt ? 1 : 0]
        )
    }

    public static func parseAll(_ packet: BMAPPacket) throws -> [UInt8] {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .audioModes,
            function: allFunction
        )

        guard !packet.payload.isEmpty else {
            throw BMAPResponseError.malformedPayload(
                expected: "one or more audio-mode indexes",
                actual: 0
            )
        }
        return packet.payload
    }

    public static func parseCapabilities(
        _ packet: BMAPPacket
    ) throws -> AudioModeCapabilities {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .audioModes,
            function: capabilitiesFunction
        )

        guard packet.payload.count >= 6 else {
            throw BMAPResponseError.malformedPayload(
                expected: "at least six audio-mode capability bytes",
                actual: packet.payload.count
            )
        }

        let flags = packet.payload[5]
        return AudioModeCapabilities(
            boseModeCount: packet.payload[0],
            userModeCount: packet.payload[1],
            supportsCNC: flags & 0b0000_0001 != 0,
            supportsAutoCNC: flags & 0b0000_0010 != 0,
            supportsSpatialAudio: flags & 0b0000_0100 != 0,
            supportsWindBlock: flags & 0b0000_1000 != 0,
            supportsFavorites: flags & 0b0001_0000 != 0,
            supportsANCToggle: flags & 0b0010_0000 != 0,
            minimumFavoriteCount: packet.payload.count > 6 ? packet.payload[6] : nil
        )
    }

    public static func parseCurrent(_ packet: BMAPPacket) throws -> UInt8 {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .audioModes,
            function: currentFunction
        )

        guard packet.payload.count == 1, let index = packet.payload.first else {
            throw BMAPResponseError.malformedPayload(
                expected: "exactly one current-mode index byte",
                actual: packet.payload.count
            )
        }
        return index
    }

    public static func parseConfiguration(_ packet: BMAPPacket) throws -> AudioMode {
        try BMAPResponseValidator.validateStatus(
            packet,
            functionBlock: .audioModes,
            function: configurationFunction
        )

        guard packet.payload.count >= 48 else {
            throw BMAPResponseError.malformedPayload(
                expected: "a 48-byte QC Ultra mode configuration",
                actual: packet.payload.count
            )
        }

        let payload = packet.payload
        let nameField = Array(payload[6..<38])
        let terminator = nameField.firstIndex(of: 0) ?? nameField.endIndex
        let nameBytes = Array(nameField[..<terminator])
        guard let decodedName = String(bytes: nameBytes, encoding: .utf8) else {
            throw BMAPResponseError.invalidUTF8(field: "audioModeName")
        }

        let promptID = payload[2]
        let name = decodedName.isEmpty || decodedName == "None"
            ? promptNames[promptID] ?? decodedName
            : decodedName
        let mutableMask = payload[41]

        let autoCNC = mutableMask & 0b0000_0010 != 0
            ? try BMAPResponseValidator.parseBoolean(
                payload[43],
                field: "autoCNCEnabled"
            )
            : nil

        let spatialMode: SpatialAudioMode?
        if mutableMask & 0b0000_0100 != 0 {
            guard let parsed = SpatialAudioMode(rawValue: payload[44]) else {
                throw BMAPResponseError.unsupportedValue(
                    field: "spatialAudioMode",
                    value: payload[44]
                )
            }
            spatialMode = parsed
        } else {
            spatialMode = nil
        }

        let windBlock = mutableMask & 0b0000_1000 != 0
            ? try BMAPResponseValidator.parseBoolean(
                payload[46],
                field: "windBlockEnabled"
            )
            : nil

        let ancEnabled = mutableMask & 0b0001_0000 != 0
            ? try BMAPResponseValidator.parseBoolean(
                payload[47],
                field: "ancEnabled"
            )
            : nil

        return AudioMode(
            id: payload[0],
            promptID: promptID,
            isUserConfigurable: try BMAPResponseValidator.parseBoolean(
                payload[3],
                field: "isUserConfigurable"
            ),
            isUserConfigured: try BMAPResponseValidator.parseBoolean(
                payload[4],
                field: "isUserConfigured"
            ),
            isFavorite: try BMAPResponseValidator.parseBoolean(
                payload[5],
                field: "isFavorite"
            ),
            name: name,
            mutableFieldMask: mutableMask,
            cncLevel: mutableMask & 0b0000_0001 != 0 ? payload[42] : nil,
            autoCNCEnabled: autoCNC,
            spatialAudioMode: spatialMode,
            windBlockEnabled: windBlock,
            ancEnabled: ancEnabled,
            opaqueReservedBytes: [payload[38], payload[39], payload[40], payload[45]],
            rawPayload: payload
        )
    }

    private static let promptNames: [UInt8: String] = [
        1: "Quiet", 2: "Aware", 3: "Transparent", 4: "Transparency",
        5: "Masking", 6: "Comfort", 7: "Commute", 8: "Outdoor",
        9: "Workout", 10: "Home", 11: "Work", 12: "Music",
        13: "Focus", 14: "Relax", 15: "Flight", 16: "Airport",
        17: "Driving", 18: "Training", 19: "Gym", 20: "Run",
        21: "Walk", 22: "Hike", 23: "Talk", 24: "Call",
        25: "Whisper", 26: "Hearing", 27: "Learn", 28: "Podcast",
        29: "Audiobook", 30: "Calm", 31: "Sleep", 32: "Meditate",
        33: "Yoga", 34: "Immersion", 35: "Stereo", 36: "Cinema",
    ]
}
