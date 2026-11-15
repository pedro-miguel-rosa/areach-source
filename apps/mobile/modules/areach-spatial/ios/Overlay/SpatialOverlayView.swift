import QuartzCore
import UIKit
import os

final class SpatialOverlayView: UIView, UIGestureRecognizerDelegate {
    private struct MotionState {
        var point: CGPoint
        var targetPoint: CGPoint
        var velocity = CGVector.zero
        var anchorSource: SpatialRenderAnchorSource

        init(
            point: CGPoint,
            anchorSource: SpatialRenderAnchorSource
        ) {
            self.point = point
            targetPoint = point
            self.anchorSource = anchorSource
        }
    }

    private static let maximumPositionSmoothTime: CGFloat = 0.20
    private static let minimumPositionSmoothTime: CGFloat = 0.10
    private static let headClearance: CGFloat = 60
    private static let verticalOrderSwapThreshold: CGFloat = 24
    private static let topicAngles: [CGFloat] = [-135, -45, 135, 45, 90]
    private static let topicRadius: CGFloat = 104
    private static let bubbleBurstDuration: TimeInterval = 0.34
    private static let bubbleParticleImage: CGImage? = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { context in
            UIColor(red: 39 / 255, green: 216 / 255, blue: 108 / 255, alpha: 0.92).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 1, y: 1, width: 8, height: 8))
        }.cgImage
    }()

    var onTargetPress: ((SpatialMatchedTarget, SpatialAttendeeProfile, String) -> Void)?

    private var attendeeProfiles: [String: SpatialAttendeeProfile] = [:]
    private var expandedPeerId: String?
    private var cardCollisionOffsets: [String: CGVector] = [:]
    private var cards: [String: SpatialOverlayCard] = [:]
    private var cardOrder: [String] = []
    private var motionStates: [String: MotionState] = [:]
    private var topicOffsets: [String: CGVector] = [:]
    private var topicViews: [String: SpatialOverlayTopicCard] = [:]
    private var latestTargets: [String: SpatialMatchedTarget] = [:]
    private var visibleTargets: [String: SpatialMatchedTarget] = [:]
    private var targetLossDeadlines: [String: CFTimeInterval] = [:]
    private var removingPeerIds: Set<String> = []
    private var activeBurstLayers: [String: CAEmitterLayer] = [:]
    private var lastAnchorSourceSignpostAt: [String: CFTimeInterval] = [:]
    private var jitterSignpostedPeerIds = Set<String>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = true
        accessibilityViewIsModal = false

        let backgroundTapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleBackgroundTap)
        )
        backgroundTapGesture.cancelsTouchesInView = false
        backgroundTapGesture.delegate = self
        addGestureRecognizer(backgroundTapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAttendeeProfiles(_ profiles: [SpatialAttendeeProfile]) {
        attendeeProfiles = profiles.reduce(into: [:]) { result, profile in
            result[profile.userId] = profile
        }
        updateTargets(Array(latestTargets.values))
    }

    func updateTargets(_ targets: [SpatialMatchedTarget]) {
        let now = CACurrentMediaTime()
        latestTargets = Dictionary(uniqueKeysWithValues: targets.map { ($0.peerId, $0) })
        let incomingTargets = Dictionary(
            uniqueKeysWithValues: targets.compactMap { target in
                attendeeProfiles[target.userId] == nil
                    ? nil
                    : (target.peerId, target)
            }
        )
        var nextVisibleTargets: [String: SpatialMatchedTarget] = [:]
        var retainedMissingTargetCount = 0
        let maximumRetainedMissingTargetCount = max(
            0,
            SpatialRenderTuning.maximumVisibleOverlayCount - incomingTargets.count
        )

        let previousPeerIds = cardOrder
            + visibleTargets.keys.filter { !cardOrder.contains($0) }
        for peerId in previousPeerIds {
            guard let previousTarget = visibleTargets[peerId] else {
                continue
            }

            guard attendeeProfiles[previousTarget.userId] != nil else {
                targetLossDeadlines.removeValue(forKey: peerId)
                beginCardRemoval(for: peerId)
                continue
            }

            if let target = incomingTargets[peerId] {
                nextVisibleTargets[peerId] = target
                targetLossDeadlines.removeValue(forKey: peerId)
                cancelCardRemoval(for: peerId)
            } else if let deadline = targetLossDeadlines[peerId], now >= deadline {
                targetLossDeadlines.removeValue(forKey: peerId)
                beginCardRemoval(for: peerId)
            } else if retainedMissingTargetCount
                >= maximumRetainedMissingTargetCount
            {
                // A visibility replacement is intentional, not a transient
                // sensor gap. Do not let retained cards exceed the global
                // three-card cap while new selected cards enter.
                targetLossDeadlines.removeValue(forKey: peerId)
                beginCardRemoval(for: peerId)
            } else {
                targetLossDeadlines[peerId] = targetLossDeadlines[peerId]
                    ?? now + SpatialRenderTuning.maximumTransientTargetOutputGap
                nextVisibleTargets[peerId] = previousTarget
                retainedMissingTargetCount += 1
            }
        }

        for target in targets where incomingTargets[target.peerId] != nil {
            cancelCardRemoval(for: target.peerId)
            targetLossDeadlines.removeValue(forKey: target.peerId)

            if motionStates[target.peerId] == nil {
                motionStates[target.peerId] = MotionState(
                    point: target.screenPoint,
                    anchorSource: target.anchorSource
                )
            }

            if cards[target.peerId] == nil {
                let card = SpatialOverlayCard()
                card.onPress = { [weak self, weak card] in
                    guard let self, let card, let cardTarget = card.target,
                        let cardProfile = card.profile
                    else {
                        return
                    }

                    let action: String
                    if cardProfile.askMeAbout.isEmpty || self.expandedPeerId == cardTarget.peerId {
                        action = "open_details"
                    } else {
                        self.expandedPeerId = cardTarget.peerId
                        action = "open_topics"
                        self.updateCardContent()
                        self.setNeedsLayout()
                    }

                    self.onTargetPress?(cardTarget, cardProfile, action)
                }
                addSubview(card)
                cards[target.peerId] = card
                cardOrder.append(target.peerId)
                card.animateBubbleIn()
            } else if !cardOrder.contains(target.peerId) {
                cardOrder.append(target.peerId)
            }

            nextVisibleTargets[target.peerId] = target
        }

        visibleTargets = nextVisibleTargets

        let visibleTargetIds = Set(visibleTargets.keys)
        for topicId in Array(topicViews.keys)
        where !visibleTargetIds.contains(topicId.components(separatedBy: "::").first ?? "") {
            topicViews[topicId]?.removeFromSuperview()
            topicViews.removeValue(forKey: topicId)
            topicOffsets.removeValue(forKey: topicId)
        }

        if let expandedPeerId, !visibleTargetIds.contains(expandedPeerId) {
            self.expandedPeerId = nil
        }

        updateCardContent()
        setNeedsLayout()
    }

    /// Used only when the camera session or authenticated peer set is being
    /// deliberately cleared. Normal matcher/display-link gaps go through
    /// updateTargets(_:) so an established card can retain its motion state.
    func clearTargetsImmediately() {
        latestTargets.removeAll()
        targetLossDeadlines.removeAll()

        let peerIds = Set(cards.keys).union(visibleTargets.keys)
        visibleTargets.removeAll()
        expandedPeerId = nil

        for topicId in Array(topicViews.keys) {
            topicViews[topicId]?.removeFromSuperview()
            topicViews.removeValue(forKey: topicId)
            topicOffsets.removeValue(forKey: topicId)
        }

        for peerId in peerIds {
            beginCardRemoval(for: peerId)
        }

        updateCardContent()
        setNeedsLayout()
    }

    func updateProjectedTargets(_ targets: [SpatialMatchedTarget]) {
        latestTargets = Dictionary(
            uniqueKeysWithValues: targets.map { ($0.peerId, $0) }
        )
        let projectedTargets = targets.filter {
            attendeeProfiles[$0.userId] != nil
        }
        let projectedTargetIds = Set(projectedTargets.map(\.peerId))

        guard projectedTargetIds == Set(visibleTargets.keys) else {
            updateTargets(targets)
            return
        }

        for target in projectedTargets {
            visibleTargets[target.peerId] = target
            cards[target.peerId]?.target = target
            targetLossDeadlines.removeValue(forKey: target.peerId)
            cancelCardRemoval(for: target.peerId)
            if motionStates[target.peerId] == nil {
                motionStates[target.peerId] = MotionState(
                    point: target.screenPoint,
                    anchorSource: target.anchorSource
                )
            }
        }

    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let interval = SpatialPerformance.signposter.beginInterval(
            "Overlay layout"
        )
        defer {
            SpatialPerformance.signposter.endInterval(
                "Overlay layout",
                interval
            )
        }

        var placedFrames: [CGRect] = []
        var cardFrames: [String: CGRect] = [:]
        updateCardOrder()
        let sortedTargets = cardOrder.compactMap { visibleTargets[$0] }

        for target in sortedTargets {
            guard let card = cards[target.peerId] else {
                continue
            }

            let screenPoint =
                motionStates[target.peerId]?.point
                ?? target.screenPoint
            let size = card.intrinsicContentSize
            let maxLeft = max(12, bounds.width - size.width - 12)
            let maxTop = max(12, bounds.height - size.height - 12)
            let left = Self.clamp(
                screenPoint.x - size.width / 2,
                12,
                maxLeft
            )
            var top = Self.clamp(
                screenPoint.y - size.height - Self.headClearance,
                12,
                maxTop
            )
            var frame = CGRect(x: left, y: top, width: size.width, height: size.height)

            for placedFrame in placedFrames
            where frame.intersects(placedFrame.insetBy(dx: 0, dy: -8)) {
                top = Self.clamp(placedFrame.maxY + 8, 12, maxTop)
                frame.origin.y = top
            }

            card.frame = frame
            let idealCenter = Self.cardCenter(
                for: screenPoint,
                size: size,
                collisionOffset: .zero,
                bounds: bounds
            )
            cardCollisionOffsets[target.peerId] = CGVector(
                dx: frame.midX - idealCenter.x,
                dy: frame.midY - idealCenter.y
            )
            placedFrames.append(frame)
            cardFrames[target.peerId] = frame
        }

        layoutTopicViews(
            for: sortedTargets,
            cardFrames: cardFrames,
            placedFrames: placedFrames,
            overlayAlpha: expandedPeerId.flatMap { cards[$0]?.alpha }
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle
        else {
            return
        }

        for card in cards.values {
            card.updateAppearance()
        }

        for topicView in topicViews.values {
            topicView.updateAppearance()
        }
    }

    private func updateCardContent() {
        for target in visibleTargets.values {
            guard
                let card = cards[target.peerId],
                let profile = attendeeProfiles[target.userId]
            else {
                continue
            }

            card.configure(
                target: target,
                profile: profile,
                expanded: expandedPeerId == target.peerId
            )
        }
    }

    private func updateCardOrder() {
        cardOrder.removeAll { visibleTargets[$0] == nil }

        for peerId in visibleTargets.keys where !cardOrder.contains(peerId) {
            cardOrder.append(peerId)
        }

        guard cardOrder.count > 1 else {
            return
        }

        var didSwap = true

        while didSwap {
            didSwap = false

            for index in 0..<(cardOrder.count - 1) {
                let upperPeerId = cardOrder[index]
                let lowerPeerId = cardOrder[index + 1]

                guard
                    let upperTarget = visibleTargets[upperPeerId],
                    let lowerTarget = visibleTargets[lowerPeerId]
                else {
                    continue
                }

                let upperY =
                    motionStates[upperPeerId]?.point.y
                    ?? upperTarget.screenPoint.y
                let lowerY =
                    motionStates[lowerPeerId]?.point.y
                    ?? lowerTarget.screenPoint.y

                if lowerY + Self.verticalOrderSwapThreshold < upperY {
                    cardOrder.swapAt(index, index + 1)
                    didSwap = true
                }
            }
        }
    }

    /// Called by AReachSpatialView's single display tick. Keeping this state
    /// machine here preserves the existing card/topic motion without creating
    /// a second CADisplayLink.
    @discardableResult
    func renderTick(
        timestamp: CFTimeInterval,
        duration: CFTimeInterval
    ) -> Bool {
        expireTransientTargetLosses(at: timestamp)
        let elapsed = min(
            duration,
            1 / 15
        )
        var didMove = false
        // Keep presenting while a target exists.  The projected world anchor
        // can move when the viewer's AR camera moves even if Vision has not
        // produced a new body observation yet.
        let needsAnotherFrame = !visibleTargets.isEmpty
            || !targetLossDeadlines.isEmpty

        for (peerId, target) in visibleTargets {
            var motion =
                motionStates[peerId]
                ?? MotionState(
                    point: target.screenPoint,
                    anchorSource: target.anchorSource
                )
            let anchorUpdate = SpatialRenderAnchorStabilityPolicy.update(
                current: motion.targetPoint,
                raw: target.screenPoint,
                previousSource: motion.anchorSource,
                source: target.anchorSource,
                elapsed: CGFloat(elapsed)
            )
            if anchorUpdate.sourceChanged {
                let lastSignpostAt = lastAnchorSourceSignpostAt[peerId] ?? 0
                if timestamp - lastSignpostAt >= 0.5 {
                    lastAnchorSourceSignpostAt[peerId] = timestamp
                    SpatialPerformance.signposter.emitEvent(
                        "Render anchor source changed",
                        "Peer: \(peerId.prefix(8), privacy: .public), source: \(target.anchorSource.rawValue, privacy: .public)"
                    )
                }
            }
            if anchorUpdate.suppressedJitter,
                jitterSignpostedPeerIds.insert(peerId).inserted
            {
                SpatialPerformance.signposter.emitEvent(
                    "Render anchor jitter suppressed",
                    "Peer: \(peerId.prefix(8), privacy: .public)"
                )
            }
            motion.targetPoint = anchorUpdate.point
            motion.anchorSource = target.anchorSource
            let deltaX = motion.targetPoint.x - motion.point.x
            let deltaY = motion.targetPoint.y - motion.point.y
            let movementDistance = hypot(deltaX, deltaY)

            if movementDistance <= SpatialRenderTuning.renderAnchorDeadZone {
                motion.velocity = .zero
                motionStates[peerId] = motion
                continue
            }

            let smoothTime = Self.positionSmoothTime(
                for: movementDistance
            )
            let horizontalMotion = Self.smoothPosition(
                current: motion.point.x,
                target: motion.targetPoint.x,
                velocity: motion.velocity.dx,
                elapsed: CGFloat(elapsed),
                smoothTime: smoothTime
            )
            let verticalMotion = Self.smoothPosition(
                current: motion.point.y,
                target: motion.targetPoint.y,
                velocity: motion.velocity.dy,
                elapsed: CGFloat(elapsed),
                smoothTime: smoothTime
            )
            motion.point = CGPoint(
                x: horizontalMotion.position,
                y: verticalMotion.position
            )
            motion.velocity = CGVector(
                dx: horizontalMotion.velocity,
                dy: verticalMotion.velocity
            )
            motionStates[peerId] = motion
            didMove = true
        }

        if didMove {
            renderCachedPositions()
        }

        if !needsAnotherFrame {
            return false
        }

        _ = timestamp
        return true
    }

    private func expireTransientTargetLosses(at timestamp: CFTimeInterval) {
        let expiredPeerIds = targetLossDeadlines.compactMap { peerId, deadline in
            deadline <= timestamp ? peerId : nil
        }
        guard !expiredPeerIds.isEmpty else {
            return
        }

        for peerId in expiredPeerIds {
            targetLossDeadlines.removeValue(forKey: peerId)
            guard visibleTargets.removeValue(forKey: peerId) != nil else {
                continue
            }

            beginCardRemoval(for: peerId)
            if expandedPeerId == peerId {
                expandedPeerId = nil
            }
        }

        updateCardContent()
        setNeedsLayout()
    }

    private func layoutTopicViews(
        for targets: [SpatialMatchedTarget],
        cardFrames: [String: CGRect],
        placedFrames: [CGRect],
        overlayAlpha: CGFloat?
    ) {
        var activeTopicIds = Set<String>()

        for target in targets where target.peerId == expandedPeerId {
            guard let profile = attendeeProfiles[target.userId] else {
                continue
            }

            for index in profile.askMeAbout.prefix(5).indices {
                activeTopicIds.insert("\(target.peerId)::\(index)")
            }
        }

        for topicId in Array(topicViews.keys) where !activeTopicIds.contains(topicId) {
            topicViews[topicId]?.removeFromSuperview()
            topicViews.removeValue(forKey: topicId)
            topicOffsets.removeValue(forKey: topicId)
        }

        guard let expandedPeerId else {
            return
        }

        guard
            let target = targets.first(where: { $0.peerId == expandedPeerId }),
            let profile = attendeeProfiles[target.userId],
            let cardFrame = cardFrames[target.peerId]
        else {
            return
        }

        var occupiedFrames = placedFrames

        for (index, topic) in profile.askMeAbout.prefix(5).enumerated() {
            let topicId = "\(target.peerId)::\(index)"
            let topicView = topicViews[topicId] ?? makeTopicView(for: topicId)
            topicView.configure(text: topic)
            topicView.frame = Self.topicFrame(
                around: cardFrame,
                angle: Self.topicAngles[index % Self.topicAngles.count],
                radius: Self.topicRadius,
                size: topicView.intrinsicContentSize,
                placedFrames: &occupiedFrames,
                bounds: bounds
            )
            topicView.alpha = overlayAlpha ?? 1
            topicView.isHidden = false
            topicOffsets[topicId] = CGVector(
                dx: topicView.center.x - cardFrame.midX,
                dy: topicView.center.y - cardFrame.midY
            )
            occupiedFrames.append(topicView.frame)
        }
    }

    private func renderCachedPositions() {
        var renderedCardFrames: [String: CGRect] = [:]

        for peerId in cardOrder {
            guard
                let target = visibleTargets[peerId],
                let card = cards[peerId]
            else {
                continue
            }

            let screenPoint =
                motionStates[peerId]?.point
                ?? target.screenPoint
            let size =
                card.bounds.size == .zero
                ? card.intrinsicContentSize
                : card.bounds.size
            card.center = Self.cardCenter(
                for: screenPoint,
                size: size,
                collisionOffset: cardCollisionOffsets[peerId] ?? .zero,
                bounds: bounds
            )
            renderedCardFrames[peerId] = card.frame
        }

        guard
            let expandedPeerId,
            let cardFrame = renderedCardFrames[expandedPeerId]
        else {
            return
        }

        for (topicId, topicView) in topicViews
        where topicId.hasPrefix("\(expandedPeerId)::") {
            guard let offset = topicOffsets[topicId] else {
                continue
            }

            let size =
                topicView.bounds.size == .zero
                ? topicView.intrinsicContentSize
                : topicView.bounds.size
            topicView.center = Self.clampedCenter(
                CGPoint(
                    x: cardFrame.midX + offset.dx,
                    y: cardFrame.midY + offset.dy
                ),
                size: size,
                bounds: bounds
            )
        }
    }

    private func makeTopicView(for topicId: String) -> SpatialOverlayTopicCard {
        let topicView = SpatialOverlayTopicCard()
        addSubview(topicView)
        topicViews[topicId] = topicView
        return topicView
    }

    private func beginCardRemoval(for peerId: String) {
        guard
            let card = cards[peerId],
            removingPeerIds.insert(peerId).inserted
        else {
            return
        }

        let burstPoint = card.layer.presentation()?.position ?? card.center
        let burstLayer = makeBubbleBurstLayer(at: burstPoint)
        activeBurstLayers[peerId] = burstLayer
        layer.addSublayer(burstLayer)

        card.animateBubbleOut { [weak self, weak card] in
            guard let self, let card, self.removingPeerIds.remove(peerId) != nil else {
                return
            }

            self.activeBurstLayers.removeValue(forKey: peerId)?.removeFromSuperlayer()

            guard self.cards[peerId] === card else {
                return
            }

            self.cards.removeValue(forKey: peerId)
            self.cardCollisionOffsets.removeValue(forKey: peerId)
            self.cardOrder.removeAll { $0 == peerId }
            self.motionStates.removeValue(forKey: peerId)
            self.lastAnchorSourceSignpostAt.removeValue(forKey: peerId)
            self.jitterSignpostedPeerIds.remove(peerId)
            card.removeFromSuperview()
        }
    }

    private func cancelCardRemoval(for peerId: String) {
        guard removingPeerIds.remove(peerId) != nil else {
            return
        }

        activeBurstLayers.removeValue(forKey: peerId)?.removeFromSuperlayer()
        cards[peerId]?.cancelBubbleOut()
    }

    private func makeBubbleBurstLayer(at point: CGPoint) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        emitter.emitterSize = .zero
        emitter.renderMode = .additive

        let bubble = CAEmitterCell()
        bubble.contents = Self.bubbleParticleImage
        bubble.birthRate = 80
        bubble.lifetime = 0.55
        bubble.lifetimeRange = 0.16
        bubble.velocity = 88
        bubble.velocityRange = 54
        bubble.emissionRange = .pi * 2
        bubble.scale = 0.26
        bubble.scaleRange = 0.16
        bubble.alphaSpeed = -1.8
        bubble.yAcceleration = 42
        bubble.spinRange = .pi
        emitter.emitterCells = [bubble]
        emitter.birthRate = 0

        let burst = CAKeyframeAnimation(keyPath: "birthRate")
        burst.values = [0, 1, 0]
        burst.keyTimes = [0, 0.12, 1]
        burst.duration = Self.bubbleBurstDuration
        burst.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn)
        ]
        emitter.add(burst, forKey: "bubbleBurst")

        return emitter
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard expandedPeerId != nil else {
            return false
        }

        var touchedView = touch.view
        while let view = touchedView, view !== self {
            if view is SpatialOverlayCard {
                return false
            }

            touchedView = view.superview
        }

        return true
    }

    @objc private func handleBackgroundTap() {
        guard expandedPeerId != nil else {
            return
        }

        expandedPeerId = nil
        updateCardContent()
        setNeedsLayout()
    }

    private static func cardCenter(
        for screenPoint: CGPoint,
        size: CGSize,
        collisionOffset: CGVector,
        bounds: CGRect
    ) -> CGPoint {
        clampedCenter(
            CGPoint(
                x: screenPoint.x + collisionOffset.dx,
                y: screenPoint.y - size.height / 2 - headClearance
                    + collisionOffset.dy
            ),
            size: size,
            bounds: bounds
        )
    }

    private static func clampedCenter(
        _ center: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        let minimumX = 12 + size.width / 2
        let minimumY = 12 + size.height / 2

        return CGPoint(
            x: clamp(
                center.x,
                minimumX,
                max(minimumX, bounds.width - 12 - size.width / 2)
            ),
            y: clamp(
                center.y,
                minimumY,
                max(minimumY, bounds.height - 12 - size.height / 2)
            )
        )
    }

    private static func topicFrame(
        around cardFrame: CGRect,
        angle: CGFloat,
        radius: CGFloat,
        size: CGSize,
        placedFrames: inout [CGRect],
        bounds: CGRect
    ) -> CGRect {
        let radians = angle * .pi / 180
        let center = CGPoint(
            x: cardFrame.midX + cos(radians) * radius,
            y: cardFrame.midY + sin(radians) * radius
        )
        let maxLeft = max(12, bounds.width - size.width - 12)
        let maxTop = max(12, bounds.height - size.height - 12)
        var frame = CGRect(
            x: clamp(center.x - size.width / 2, 12, maxLeft),
            y: clamp(center.y - size.height / 2, 12, maxTop),
            width: size.width,
            height: size.height
        )

        for placedFrame in placedFrames where frame.intersects(placedFrame.insetBy(dx: -4, dy: -4))
        {
            frame.origin.y = clamp(placedFrame.maxY + 6, 12, maxTop)
        }

        return frame
    }

    private static func clamp(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), max(minimum, maximum))
    }

    private static func smoothPosition(
        current: CGFloat,
        target: CGFloat,
        velocity: CGFloat,
        elapsed: CGFloat,
        smoothTime: CGFloat
    ) -> (position: CGFloat, velocity: CGFloat) {
        let frequency = 2 / smoothTime
        let frameResponse = frequency * elapsed
        let decay =
            1
            / (1
                + frameResponse
                + 0.48 * frameResponse * frameResponse
                + 0.235 * frameResponse * frameResponse * frameResponse)
        let displacement = current - target
        let momentum = (velocity + frequency * displacement) * elapsed
        var nextVelocity = (velocity - frequency * momentum) * decay
        var nextPosition = target + (displacement + momentum) * decay

        if (target - current) * (nextPosition - target) > 0 {
            nextPosition = target
            nextVelocity = 0
        }

        return (nextPosition, nextVelocity)
    }

    private static func positionSmoothTime(
        for movementDistance: CGFloat
    ) -> CGFloat {
        let responsiveness = min(
            1,
            movementDistance / SpatialRenderTuning.renderAnchorResponsiveDistance
        )

        return maximumPositionSmoothTime
            - (maximumPositionSmoothTime - minimumPositionSmoothTime)
            * responsiveness
    }
}
