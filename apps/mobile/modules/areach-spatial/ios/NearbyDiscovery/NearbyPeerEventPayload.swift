import NearbyInteraction

enum NearbyPeerEventPayload {
    static func base(
        peerId: String,
        identity: NearbyPeerIdentity?,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = ["peerId": peerId]

        if let userId = identity?.userId {
            payload["userId"] = userId
        }

        for (key, value) in extra {
            payload[key] = value
        }
        return payload
    }

    static func update(
        peerId: String,
        identity: NearbyPeerIdentity?,
        nearbyObject: NINearbyObject
    ) -> [String: Any] {
        var payload = base(peerId: peerId, identity: identity)

        if let distance = nearbyObject.distance {
            payload["distance"] = distance
        }
        return payload
    }

    static func lost(
        peerId: String,
        identity: NearbyPeerIdentity?,
        reason: String,
        stillNearby: Bool
    ) -> [String: Any] {
        base(
            peerId: peerId,
            identity: identity,
            extra: [
                "reason": reason,
                "stillNearby": stillNearby,
            ]
        )
    }
}
