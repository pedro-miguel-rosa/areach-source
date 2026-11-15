/// Treat attendee distances as current briefly after an NI measurement. The
/// longer display window is only for a clearly marked last measurement while
/// a peer waits for its next turn in the small ranging pool.
export const PEER_DISTANCE_FRESH_MS = 4500;
export const PEER_DISTANCE_DISPLAY_RETENTION_MS = 90_000;
