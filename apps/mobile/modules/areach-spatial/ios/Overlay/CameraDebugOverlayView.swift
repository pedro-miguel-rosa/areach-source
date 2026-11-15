#if DEBUG
    import Foundation
    import UIKit

    struct SpatialDebugPhoneMarker {
        let distance: Float?
        let distanceNormalizedResidual: Double?
        let associationConfidence: Double?
        let associationMode: String?
        let renderMode: String?
        let measurementTier: String
        let healthState: String
        let usefulMeasurementAge: CFTimeInterval
        let callbackAge: CFTimeInterval
        let transformAge: CFTimeInterval
        let distanceAge: CFTimeInterval
        let directionAvailable: Bool
        let directionAge: CFTimeInterval
        let peerId: String
        let point: CGPoint
        let userId: String?
    }

    final class CameraDebugOverlayView: UIView {
        private static let skeletonConnections: [([String], [String])] = [
            (["neck"], ["root", "hip", "centerhip"]),
            (["neck"], ["nose", "head"]),
            (["nose", "head"], ["lefteye"]),
            (["nose", "head"], ["righteye"]),
            (["lefteye"], ["leftear"]),
            (["righteye"], ["rightear"]),
            (["lefteye"], ["righteye"]),
            (["neck"], ["leftshoulder"]),
            (["neck"], ["rightshoulder"]),
            (["leftshoulder"], ["leftelbow", "leftforearm", "leftarm"]),
            (["leftelbow", "leftforearm", "leftarm"], ["leftwrist", "lefthand"]),
            (["rightshoulder"], ["rightelbow", "rightforearm", "rightarm"]),
            (["rightelbow", "rightforearm", "rightarm"], ["rightwrist", "righthand"]),
            (["root", "hip", "centerhip"], ["lefthip", "leftupleg", "leftthigh"]),
            (["root", "hip", "centerhip"], ["righthip", "rightupleg", "rightthigh"]),
            (["lefthip", "leftupleg", "leftthigh"], ["leftknee", "leftlowerleg", "leftleg"]),
            (["leftknee", "leftlowerleg", "leftleg"], ["leftankle", "leftfoot"]),
            (
                ["righthip", "rightupleg", "rightthigh"],
                ["rightknee", "rightlowerleg", "rightleg"]
            ),
            (["rightknee", "rightlowerleg", "rightleg"], ["rightankle", "rightfoot"]),
        ]

        private let skeletonLayer = CAShapeLayer()
        private let bodyDiagnosticsLabel = UILabel()
        private var attendeeProfiles: [String: SpatialAttendeeProfile] = [:]
        private var phoneMarkerViews: [String: DebugPhoneMarkerView] = [:]

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false

            skeletonLayer.fillColor = UIColor.systemGreen.cgColor
            skeletonLayer.lineCap = .round
            skeletonLayer.lineWidth = 2
            skeletonLayer.strokeColor = UIColor.systemGreen.cgColor
            layer.addSublayer(skeletonLayer)

            bodyDiagnosticsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            bodyDiagnosticsLabel.textColor = .white
            bodyDiagnosticsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.68)
            bodyDiagnosticsLabel.numberOfLines = 2
            bodyDiagnosticsLabel.adjustsFontSizeToFitWidth = true
            bodyDiagnosticsLabel.minimumScaleFactor = 0.8
            bodyDiagnosticsLabel.layer.cornerRadius = 4
            bodyDiagnosticsLabel.layer.masksToBounds = true
            bodyDiagnosticsLabel.isHidden = true
            addSubview(bodyDiagnosticsLabel)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            skeletonLayer.frame = bounds
            bodyDiagnosticsLabel.frame = CGRect(
                x: 8,
                y: 8,
                width: min(310, max(0, bounds.width - 16)),
                height: 38
            )
        }

        func setAttendeeProfiles(_ profiles: [SpatialAttendeeProfile]) {
            attendeeProfiles = profiles.reduce(into: [:]) { result, profile in
                result[profile.userId] = profile
            }
        }

        func updateSkeleton(detections: [SpatialBodyDetection]) {
            let skeletonPath = CGMutablePath()

            for detection in detections {
                let joints = detection.joints.reduce(into: [String: CGPoint]()) {
                    result,
                    joint in
                    result[Self.normalizeJointName(joint.name)] = joint.point
                }

                for (fromAliases, toAliases) in Self.skeletonConnections {
                    guard
                        let from = Self.findJoint(in: joints, aliases: fromAliases),
                        let to = Self.findJoint(in: joints, aliases: toAliases)
                    else {
                        continue
                    }

                    skeletonPath.move(to: from)
                    skeletonPath.addLine(to: to)
                }

                for joint in detection.joints {
                    skeletonPath.addEllipse(
                        in: CGRect(
                            x: joint.point.x - 2,
                            y: joint.point.y - 2,
                            width: 4,
                            height: 4
                        )
                    )
                }
            }

            skeletonLayer.path = skeletonPath
        }

        func updateBodyDiagnostics(_ diagnostics: SpatialBodyPipelineDiagnostics) {
            bodyDiagnosticsLabel.text = "Bodies: \(diagnostics.rawVisionObservationCount) raw → \(diagnostics.uniqueVisionDetectionCount) unique → \(diagnostics.matcherTrackedBodyCount) tracked\nSuppressed: \(diagnostics.visionDuplicateSuppressionCount) Vision · \(diagnostics.detectorTrackDuplicateSuppressionCount) detector · \(diagnostics.matcherDuplicateTrackSuppressionCount) matcher"
            bodyDiagnosticsLabel.isHidden = false
        }

        func updatePhoneMarkers(_ phoneMarkers: [SpatialDebugPhoneMarker]) {
            let visiblePeerIds = Set(phoneMarkers.map(\.peerId))

            for peerId in Array(phoneMarkerViews.keys)
            where !visiblePeerIds.contains(peerId) {
                phoneMarkerViews[peerId]?.removeFromSuperview()
                phoneMarkerViews.removeValue(forKey: peerId)
            }

            for marker in phoneMarkers {
                let markerView =
                    phoneMarkerViews[marker.peerId] ?? makePhoneMarkerView(for: marker.peerId)
                let attendeeName = marker.userId
                    .flatMap {
                        attendeeProfiles[$0]?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                markerView.update(
                    text: Self.phoneLabel(
                        name: attendeeName,
                        distance: marker.distance,
                        measurementTier: marker.measurementTier,
                        associationMode: marker.associationMode,
                        renderMode: marker.renderMode,
                        confidence: marker.associationConfidence,
                        healthState: marker.healthState,
                        directionAvailable: marker.directionAvailable,
                        directionAge: marker.directionAge
                    ),
                    point: marker.point,
                    viewportBounds: bounds
                )
            }
        }

        func clear() {
            skeletonLayer.path = nil
            bodyDiagnosticsLabel.text = nil
            bodyDiagnosticsLabel.isHidden = true
            phoneMarkerViews.values.forEach { $0.removeFromSuperview() }
            phoneMarkerViews.removeAll()
        }

        private func makePhoneMarkerView(for peerId: String) -> DebugPhoneMarkerView {
            let markerView = DebugPhoneMarkerView()
            addSubview(markerView)
            phoneMarkerViews[peerId] = markerView
            return markerView
        }

        private static func phoneLabel(
            name: String?,
            distance: Float?,
            measurementTier: String,
            associationMode: String?,
            renderMode: String?,
            confidence: Double?,
            healthState: String,
            directionAvailable: Bool,
            directionAge: CFTimeInterval
        ) -> String {
            let attendeeName =
                name.flatMap { $0.isEmpty ? nil : $0 }
                ?? "Nearby phone"

            guard let distance else {
                return attendeeName
            }

            let totalCentimeters = max(0, Int((distance * 100).rounded()))
            let meters = totalCentimeters / 100
            let centimeters = totalCentimeters % 100
            let distanceLabel =
                meters > 0
                ? "\(meters)m \(centimeters)cm"
                : "\(centimeters)cm"

            let modeLabel = associationMode ?? measurementTier
            let renderLabel = renderMode ?? "none"
            let confidenceLabel = confidence.map {
                String(format: "%.2f", $0)
            } ?? "--"
            return [
                attendeeName,
                "Distance: \(distanceLabel)",
                "Mode: \(modeLabel)",
                "Render: \(renderLabel)",
                "Confidence: \(confidenceLabel)",
                "Direction: \(directionAvailable ? "yes" : "no") (\(directionAge.isFinite ? String(format: "%.2f", directionAge) : "--")s)",
                "Health: \(healthState)",
            ].joined(separator: "\n")
        }

        private static func findJoint(
            in joints: [String: CGPoint],
            aliases: [String]
        ) -> CGPoint? {
            for alias in aliases {
                let normalizedAlias = normalizeJointName(alias)

                if let joint = joints.first(where: { $0.key.contains(normalizedAlias) })?.value {
                    return joint
                }
            }

            return nil
        }

        private static func normalizeJointName(_ name: String) -> String {
            name.lowercased().filter(\.isLetter)
        }
    }

    private final class DebugPhoneLabel: UILabel {
        private let textInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 8)

        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: textInsets))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(
                width: size.width + textInsets.left + textInsets.right,
                height: size.height + textInsets.top + textInsets.bottom
            )
        }

        override func sizeThatFits(_ size: CGSize) -> CGSize {
            let textSize = super.sizeThatFits(
                CGSize(
                    width: max(0, size.width - textInsets.left - textInsets.right),
                    height: max(0, size.height - textInsets.top - textInsets.bottom)
                )
            )
            return CGSize(
                width: textSize.width + textInsets.left + textInsets.right,
                height: textSize.height + textInsets.top + textInsets.bottom
            )
        }
    }

    private final class DebugPhoneMarkerView: UIView {
        private let dotView = UIView()
        private let label = DebugPhoneLabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false

            dotView.backgroundColor = .systemBlue
            dotView.layer.borderColor = UIColor.white.cgColor
            dotView.layer.borderWidth = 1
            dotView.layer.cornerRadius = 5
            addSubview(dotView)

            label.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.88)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.layer.cornerRadius = 13
            label.layer.masksToBounds = true
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .left
            label.textColor = .white
            addSubview(label)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(text: String, point: CGPoint, viewportBounds: CGRect) {
            if label.text != text {
                label.text = text
            }

            let maxLabelWidth = min(220, max(140, viewportBounds.width - 32))
            let labelWidth = min(
                maxLabelWidth,
                max(140, ceil(label.intrinsicContentSize.width) + 20)
            )
            let markerWidth = labelWidth + 14
            let textHeight = ceil(
                label.sizeThatFits(
                    CGSize(width: labelWidth, height: .greatestFiniteMagnitude)
                ).height
            )
            let markerHeight = max(46, textHeight + 12)
            let placesLabelOnLeft = point.x + markerWidth > viewportBounds.maxX - 8
            let originX =
                placesLabelOnLeft
                ? point.x - markerWidth + 5
                : point.x - 5
            let originY = min(
                max(point.y - markerHeight / 2, viewportBounds.minY + 8),
                max(viewportBounds.minY + 8, viewportBounds.maxY - markerHeight - 8)
            )

            frame = CGRect(x: originX, y: originY, width: markerWidth, height: markerHeight)
            dotView.frame = CGRect(
                x: placesLabelOnLeft ? labelWidth + 4 : 0,
                y: (markerHeight - 10) / 2,
                width: 10,
                height: 10
            )
            label.frame = CGRect(
                x: placesLabelOnLeft ? 0 : 14,
                y: 2,
                width: labelWidth,
                height: markerHeight - 4
            )
        }
    }
#endif
