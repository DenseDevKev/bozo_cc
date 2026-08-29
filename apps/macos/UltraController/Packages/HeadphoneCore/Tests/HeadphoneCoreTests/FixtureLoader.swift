import Foundation

struct FixtureManifest: Decodable {
    let schemaVersion: Int
    let fixtures: [String]
}

struct PacketFixture: Decodable {
    struct Expected: Decodable {
        let functionBlock: UInt8
        let function: UInt8
        let `operator`: UInt8
        let payloadHex: String
    }

    let name: String
    let direction: String
    let wireHex: String
    let expected: Expected
}

enum FixtureHexError: Error, Equatable {
    case oddLength(Int)
    case invalidByte(String)
}

enum FixtureLoader {
    static func repositoryRoot(filePath: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: String(describing: filePath))
        for _ in 0..<8 {
            url.deleteLastPathComponent()
        }
        return url
    }

    static func data(named name: String) throws -> Data {
        let url = repositoryRoot()
            .appendingPathComponent("fixtures/bmap", isDirectory: true)
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(named: name))
    }
}

extension String {
    func fixtureHexBytes() throws -> [UInt8] {
        guard count.isMultiple(of: 2) else {
            throw FixtureHexError.oddLength(count)
        }

        var result: [UInt8] = []
        result.reserveCapacity(count / 2)
        var index = startIndex

        while index < endIndex {
            let next = self.index(index, offsetBy: 2)
            let pair = String(self[index..<next])
            guard let byte = UInt8(pair, radix: 16) else {
                throw FixtureHexError.invalidByte(pair)
            }
            result.append(byte)
            index = next
        }

        return result
    }
}
