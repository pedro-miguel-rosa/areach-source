struct NearbyPeerIdentity {
    let credential: String
    let eventScope: String
    let publicKey: String?
    let userId: String?

    func resolving(userId: String, publicKey: String) -> NearbyPeerIdentity {
        NearbyPeerIdentity(
            credential: credential,
            eventScope: eventScope,
            publicKey: publicKey,
            userId: userId
        )
    }
}
