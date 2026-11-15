import Foundation
import NearbyInteraction

enum NearbyDiscoveryTokenCodec {
    private struct DiscoveryTokenMessage: Codable {
        let discoveryToken: String
    }

    static func encode(_ token: NIDiscoveryToken) throws -> Data {
        let tokenData = try NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        )
        let message = DiscoveryTokenMessage(
            discoveryToken: tokenData.base64EncodedString()
        )

        return try JSONEncoder().encode(message)
    }

    static func decode(_ data: Data) throws -> NIDiscoveryToken? {
        let message = try JSONDecoder().decode(
            DiscoveryTokenMessage.self,
            from: data
        )
        let tokenData = Data(base64Encoded: message.discoveryToken)

        guard let tokenData else {
            return nil
        }

        return try NSKeyedUnarchiver.unarchivedObject(
            ofClass: NIDiscoveryToken.self,
            from: tokenData
        )
    }
}
