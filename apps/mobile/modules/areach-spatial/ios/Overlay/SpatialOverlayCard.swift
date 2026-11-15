import UIKit
import QuartzCore

final class SpatialOverlayCard: UIControl {
    private static let bubbleAppearDuration: TimeInterval = 0.42
    private static let bubbleDisappearDuration: TimeInterval = 0.30

    var onPress: (() -> Void)?
    var target: SpatialMatchedTarget?
    var profile: SpatialAttendeeProfile?

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    private let tintView = UIView()
    private let presenceHalo = UIView()
    private let presenceDot = UIView()
    private let nameLabel = UILabel()
    private let headlineLabel = UILabel()
    private let distanceLabel = UILabel()
    private var isExpanded = false
    private var shadowBounds = CGRect.zero
    private var isAnimatingRemoval = false
    private var removalCompletion: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        layer.borderColor = SpatialOverlayColors.border.cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 16
        layer.shadowColor = SpatialOverlayColors.shadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowOpacity = 0.24
        layer.shadowRadius = 14

        blurView.isUserInteractionEnabled = false
        blurView.layer.cornerRadius = layer.cornerRadius - 1
        blurView.clipsToBounds = true
        addSubview(blurView)

        tintView.backgroundColor = SpatialOverlayColors.surface
        tintView.isUserInteractionEnabled = false
        blurView.contentView.addSubview(tintView)

        presenceHalo.backgroundColor = SpatialOverlayColors.presenceHalo
        presenceHalo.layer.cornerRadius = 8
        presenceHalo.isUserInteractionEnabled = false
        addSubview(presenceHalo)

        presenceDot.backgroundColor = SpatialOverlayColors.accent
        presenceDot.layer.cornerRadius = 4
        presenceDot.isUserInteractionEnabled = false
        addSubview(presenceDot)

        nameLabel.font = SpatialOverlayFonts.name
        nameLabel.textColor = SpatialOverlayColors.text
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        headlineLabel.font = SpatialOverlayFonts.secondary
        headlineLabel.textColor = SpatialOverlayColors.textSecondary
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.lineBreakMode = .byTruncatingTail
        headlineLabel.isHidden = true
        addSubview(headlineLabel)

        distanceLabel.font = SpatialOverlayFonts.secondary
        distanceLabel.textColor = SpatialOverlayColors.accent
        distanceLabel.adjustsFontForContentSizeCategory = true
        distanceLabel.lineBreakMode = .byTruncatingTail
        distanceLabel.isHidden = true
        addSubview(distanceLabel)

        addTarget(self, action: #selector(handlePress), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let maximumWidth: CGFloat =
            traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 280 : 220
        let minimumWidth: CGFloat =
            traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 160 : 132
        let labelWidths = [nameLabel, headlineLabel, distanceLabel]
            .filter { !$0.isHidden }
            .map { ceil($0.intrinsicContentSize.width) }
        let contentWidth = labelWidths.max() ?? 0
        let width = min(maximumWidth, max(minimumWidth, contentWidth + 45))

        var height: CGFloat = 24 + ceil(nameLabel.font.lineHeight)

        if !headlineLabel.isHidden {
            height += 3 + ceil(headlineLabel.font.lineHeight)
        }

        if !distanceLabel.isHidden {
            height += 2 + ceil(distanceLabel.font.lineHeight)
        }

        return CGSize(width: width, height: max(56, height))
    }

    func configure(
        target: SpatialMatchedTarget,
        profile: SpatialAttendeeProfile,
        expanded: Bool
    ) {
        self.target = target
        self.profile = profile
        let headline = profile.headline.isEmpty ? nil : profile.headline
        let distance = target.distance.map {
            "\($0 < 1 ? "<1" : String(format: "%.0f", $0))m away"
        }
        let nextAccessibilityLabel =
            profile.headline.isEmpty
            ? profile.name
            : "\(profile.name), \(profile.headline)"
        let nextAccessibilityHint =
            profile.askMeAbout.isEmpty || expanded
            ? "Open attendee details"
            : "Show conversation topics"
        let nextAccessibilityValue =
            expanded
            ? "Ask me about: \(profile.askMeAbout.joined(separator: ", "))"
            : nil

        if nameLabel.text != profile.name {
            nameLabel.text = profile.name
            invalidateIntrinsicContentSize()
        }

        if headlineLabel.text != headline {
            headlineLabel.text = headline
            headlineLabel.isHidden = headline == nil
            invalidateIntrinsicContentSize()
        }

        if distanceLabel.text != distance {
            distanceLabel.text = distance
            distanceLabel.isHidden = distance == nil
            invalidateIntrinsicContentSize()
        }

        if accessibilityLabel != nextAccessibilityLabel {
            accessibilityLabel = nextAccessibilityLabel
        }

        if accessibilityHint != nextAccessibilityHint {
            accessibilityHint = nextAccessibilityHint
        }

        if accessibilityValue != nextAccessibilityValue {
            accessibilityValue = nextAccessibilityValue
        }

        if isExpanded != expanded {
            isExpanded = expanded
            updateAppearance()
        }
    }

    func updateAppearance() {
        backgroundColor = .clear
        layer.borderColor =
            (isExpanded ? SpatialOverlayColors.successBorder : SpatialOverlayColors.border).cgColor
        layer.shadowColor = SpatialOverlayColors.shadow.cgColor
        tintView.backgroundColor = SpatialOverlayColors.surface
        presenceHalo.backgroundColor = SpatialOverlayColors.presenceHalo
        presenceDot.backgroundColor = SpatialOverlayColors.accent
        nameLabel.textColor = SpatialOverlayColors.text
        headlineLabel.textColor = SpatialOverlayColors.textSecondary
        distanceLabel.textColor = SpatialOverlayColors.accent
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        blurView.frame = bounds.insetBy(dx: 1, dy: 1)
        tintView.frame = blurView.bounds

        let contentWidth = max(0, bounds.width - 45)
        var top: CGFloat = 12
        let nameHeight = ceil(nameLabel.font.lineHeight)

        presenceHalo.frame = CGRect(
            x: 10,
            y: top + max(0, (nameHeight - 16) / 2),
            width: 16,
            height: 16
        )
        presenceDot.frame = CGRect(
            x: 14, y: top + max(0, (nameHeight - 8) / 2), width: 8, height: 8)
        nameLabel.frame = CGRect(x: 31, y: top, width: contentWidth, height: nameHeight)
        top += nameHeight

        if !headlineLabel.isHidden {
            top += 3
            let headlineHeight = ceil(headlineLabel.font.lineHeight)
            headlineLabel.frame = CGRect(x: 31, y: top, width: contentWidth, height: headlineHeight)
            top += headlineHeight
        }

        if !distanceLabel.isHidden {
            top += 2
            distanceLabel.frame = CGRect(
                x: 31,
                y: top,
                width: contentWidth,
                height: ceil(distanceLabel.font.lineHeight)
            )
        }

        if shadowBounds != bounds {
            shadowBounds = bounds
            layer.shadowPath =
                UIBezierPath(
                    roundedRect: bounds,
                    cornerRadius: layer.cornerRadius
                ).cgPath
        }
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.78 : 1
        }
    }

    func animateBubbleIn() {
        isAnimatingRemoval = false
        removalCompletion = nil
        layer.removeAllAnimations()

        UIView.performWithoutAnimation {
            alpha = 0
            transform = CGAffineTransform(scaleX: 0.68, y: 0.68)
        }

        let haloScale = CAKeyframeAnimation(keyPath: "transform.scale")
        haloScale.values = [0.60, 1.28, 1.0]
        haloScale.keyTimes = [0, 0.62, 1]
        haloScale.duration = Self.bubbleAppearDuration
        haloScale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        presenceHalo.layer.add(haloScale, forKey: "bubbleHaloScale")

        let haloOpacity = CAKeyframeAnimation(keyPath: "opacity")
        haloOpacity.values = [0, 1, 1]
        haloOpacity.keyTimes = [0, 0.48, 1]
        haloOpacity.duration = Self.bubbleAppearDuration
        haloOpacity.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        presenceHalo.layer.add(haloOpacity, forKey: "bubbleHaloOpacity")

        UIView.animateKeyframes(
            withDuration: Self.bubbleAppearDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .calculationModeCubic]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.68) {
                self.alpha = 1
                self.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.62, relativeDuration: 0.38) {
                self.transform = .identity
            }
        }
    }

    func animateBubbleOut(completion: @escaping () -> Void) {
        guard !isAnimatingRemoval else { return }

        isAnimatingRemoval = true
        isUserInteractionEnabled = false
        removalCompletion = completion

        UIView.animateKeyframes(
            withDuration: Self.bubbleDisappearDuration,
            delay: 0,
            options: [.beginFromCurrentState, .calculationModeCubic]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.55) {
                self.alpha = 0.12
                self.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.45, relativeDuration: 0.55) {
                self.alpha = 0
                self.transform = CGAffineTransform(scaleX: 1.28, y: 1.28)
            }
        } completion: { [weak self] _ in
            guard let self, self.isAnimatingRemoval else { return }

            self.isAnimatingRemoval = false
            self.isUserInteractionEnabled = true
            let completion = self.removalCompletion
            self.removalCompletion = nil
            completion?()
        }
    }

    func cancelBubbleOut() {
        guard isAnimatingRemoval else { return }

        isAnimatingRemoval = false
        removalCompletion = nil
        layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            alpha = 1
            transform = .identity
            isUserInteractionEnabled = true
        }
    }

    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)

        if previousTraitCollection?.preferredContentSizeCategory
            != traitCollection.preferredContentSizeCategory
        {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    @objc private func handlePress() {
        onPress?()
    }
}

final class SpatialOverlayTopicCard: UIView {
    private let topicLabel = UILabel()
    private var shadowBounds = CGRect.zero

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = SpatialOverlayColors.surface
        layer.borderColor = SpatialOverlayColors.successBorder.cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 12
        layer.shadowColor = SpatialOverlayColors.shadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 12

        topicLabel.font = SpatialOverlayFonts.topic
        topicLabel.textColor = SpatialOverlayColors.text
        topicLabel.textAlignment = .center
        topicLabel.adjustsFontForContentSizeCategory = true
        topicLabel.lineBreakMode = .byTruncatingTail
        topicLabel.numberOfLines = 1
        addSubview(topicLabel)

        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let maximumLabelWidth: CGFloat =
            traitCollection
                .preferredContentSizeCategory.isAccessibilityCategory ? 188 : 132
        let labelSize = topicLabel.sizeThatFits(
            CGSize(width: maximumLabelWidth, height: topicLabel.font.lineHeight)
        )
        let width = min(labelSize.width + 32, maximumLabelWidth + 32)

        return CGSize(width: width, height: max(42, ceil(topicLabel.font.lineHeight) + 20))
    }

    func configure(text: String) {
        guard topicLabel.text != text else {
            return
        }

        topicLabel.text = text
        accessibilityLabel = text
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func updateAppearance() {
        backgroundColor = SpatialOverlayColors.surface
        layer.borderColor = SpatialOverlayColors.successBorder.cgColor
        layer.shadowColor = SpatialOverlayColors.shadow.cgColor
        topicLabel.textColor = SpatialOverlayColors.text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        topicLabel.frame = bounds.insetBy(dx: 16, dy: 0)

        if shadowBounds != bounds {
            shadowBounds = bounds
            layer.shadowPath =
                UIBezierPath(
                    roundedRect: bounds,
                    cornerRadius: layer.cornerRadius
                ).cgPath
        }
    }

    override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)

        if previousTraitCollection?.preferredContentSizeCategory
            != traitCollection.preferredContentSizeCategory
        {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }
}

private enum SpatialOverlayColors {
    static let accent = UIColor(red: 39 / 255, green: 216 / 255, blue: 108 / 255, alpha: 1)
    static let border = UIColor(red: 88 / 255, green: 234 / 255, blue: 139 / 255, alpha: 0.6)
    static let presenceHalo = accent.withAlphaComponent(0.12)
    static let shadow = UIColor.black
    static let successBorder = UIColor(red: 39 / 255, green: 216 / 255, blue: 108 / 255, alpha: 0.9)
    static let surface = UIColor(red: 8 / 255, green: 22 / 255, blue: 13 / 255, alpha: 0.78)
    static let text = UIColor(red: 244 / 255, green: 250 / 255, blue: 245 / 255, alpha: 1)
    static let textSecondary = UIColor(red: 221 / 255, green: 239 / 255, blue: 225 / 255, alpha: 1)
}

private enum SpatialOverlayFonts {
    static let name = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
        for: .systemFont(ofSize: 15, weight: .semibold)
    )
    static let secondary = UIFontMetrics(forTextStyle: .caption1).scaledFont(
        for: .systemFont(ofSize: 12, weight: .regular)
    )
    static let topic = UIFontMetrics(forTextStyle: .caption1).scaledFont(
        for: .systemFont(ofSize: 12, weight: .medium)
    )
}
