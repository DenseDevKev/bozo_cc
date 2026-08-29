public enum BMAPFunctionBlock: UInt8, CaseIterable, Codable, Sendable {
    case productInfo = 0x00
    case settings = 0x01
    case status = 0x02
    case firmwareUpdate = 0x03
    case deviceManagement = 0x04
    case audioManagement = 0x05
    case callManagement = 0x06
    case control = 0x07
    case debug = 0x08
    case notification = 0x09
    case reservedBoseBuild1 = 0x0A
    case reservedBoseBuild2 = 0x0B
    case hearingAssistance = 0x0C
    case dataCollection = 0x0D
    case heartRate = 0x0E
    case peerBud = 0x0F
    case vpa = 0x10
    case wifi = 0x11
    case authentication = 0x12
    case experimental = 0x13
    case cloud = 0x14
    case augmentedReality = 0x15
    case print = 0x16
    case audioModes = 0x1F
}
