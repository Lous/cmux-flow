import AppKit
import CmuxAppKitSupportUI
import UniformTypeIdentifiers

final class FileExplorerCellView: NSTableCellView {
    private let iconView = CmuxResolvedIconImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let loadingIndicator = NSProgressIndicator()
    /// Right-aligned git letter (M, A, D, R, U) for files and a dot for folders, as in VS Code.
    private let statusBadgeLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    var onHover: ((Bool) -> Void)?
    private var nameLabelTrailingToBadgeConstraint: NSLayoutConstraint!
    /// Git decoration currently drawn, so redecorating an unchanged row is free.
    private var appliedGitDecoration: GitDecoration?
    private var hasNodeError = false

    /// What a row's git decoration depends on.
    private struct GitDecoration: Equatable {
        let status: GitFileStatus?
        let isDirectory: Bool
        let style: FileExplorerStyle
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!
    private var iconToTextConstraint: NSLayoutConstraint!
    private var loadingWidthConstraint: NSLayoutConstraint!

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isHidden = true
        loadingIndicator.setAccessibilityIdentifier("FileExplorerLoadingIndicator")

        statusBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBadgeLabel.alignment = .right
        statusBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(statusBadgeLabel)
        addSubview(loadingIndicator)

        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 16)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 16)
        iconToTextConstraint = nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4)
        loadingWidthConstraint = loadingIndicator.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            iconToTextConstraint,
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            loadingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingWidthConstraint,
            loadingIndicator.heightAnchor.constraint(equalToConstant: 12),

            // The loading indicator is zero-width when idle, so the badge then
            // sits at the trailing edge.
            statusBadgeLabel.trailingAnchor.constraint(equalTo: loadingIndicator.leadingAnchor, constant: -4),
            statusBadgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        nameLabelTrailingToBadgeConstraint = nameLabel.trailingAnchor.constraint(
            equalTo: statusBadgeLabel.leadingAnchor,
            constant: 0
        )
        nameLabelTrailingToBadgeConstraint.isActive = true
    }

    func configure(with node: FileExplorerNode, gitStatus: GitFileStatus? = nil) {
        assert(Thread.isMainThread, "AppKit image updates must run on the main thread")
        let style = FileExplorerStyle.current
        nameLabel.stringValue = node.name
        nameLabel.font = style.nameFont
        iconWidthConstraint.constant = style.iconSize
        iconHeightConstraint.constant = style.iconSize
        iconToTextConstraint.constant = style.iconToTextSpacing

        if style == .finder {
            // Native Finder icon pixels miss 3:1 in light mode; use their masks with the dynamic palette tint.
            if node.isDirectory {
                iconView.apply(CmuxResolvedIconRequest(
                    source: .image(NSWorkspace.shared.icon(for: .folder)),
                    size: NSSize(width: style.iconSize, height: style.iconSize),
                    tintColor: style.folderIconTint
                ))
            } else {
                let pathExtension = (node.name as NSString).pathExtension
                iconView.apply(CmuxResolvedIconRequest(
                    source: .image(NSWorkspace.shared.icon(for: UTType(filenameExtension: pathExtension) ?? .data)),
                    size: NSSize(width: style.iconSize, height: style.iconSize),
                    tintColor: style.fileIconTint
                ))
            }
        } else {
            if node.isDirectory {
                iconView.apply(CmuxResolvedIconRequest(
                    source: .systemSymbol(name: "folder.fill", accessibilityDescription: nil),
                    size: NSSize(width: style.iconSize, height: style.iconSize),
                    tintColor: style.folderIconTint,
                    symbolWeight: style.iconWeight
                ))
            } else {
                iconView.apply(CmuxResolvedIconRequest(
                    source: .systemSymbol(name: "doc", accessibilityDescription: nil),
                    size: NSSize(width: style.iconSize, height: style.iconSize),
                    tintColor: style.fileIconTint,
                    symbolWeight: style.iconWeight
                ))
            }
        }

        if node.isLoading {
            loadingWidthConstraint.constant = 12
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
        } else {
            loadingWidthConstraint.constant = 0
            loadingIndicator.isHidden = true
            loadingIndicator.stopAnimation(nil)
        }

        hasNodeError = node.error != nil
        if let error = node.error {
            nameLabel.textColor = .systemRed
            nameLabel.toolTip = error
        } else {
            nameLabel.toolTip = node.path
        }
        // A reused cell may hold another node's decoration; always repaint here.
        appliedGitDecoration = nil
        updateGitDecoration(gitStatus: gitStatus, isDirectory: node.isDirectory)
    }

    /// Repaints only the git color and status badge, leaving the icon alone.
    /// Cheap enough to run over every visible row when git status changes; a
    /// row whose decoration is unchanged returns immediately.
    func updateGitDecoration(gitStatus: GitFileStatus?, isDirectory: Bool) {
        let style = FileExplorerStyle.current
        let decoration = GitDecoration(status: hasNodeError ? nil : gitStatus, isDirectory: isDirectory, style: style)
        guard decoration != appliedGitDecoration else { return }
        appliedGitDecoration = decoration
        if !hasNodeError {
            nameLabel.textColor = decoration.status.map { style.gitColor(for: $0) } ?? .labelColor
        }
        configureStatusBadge(gitStatus: decoration.status, isDirectory: isDirectory, style: style)
    }

    private func configureStatusBadge(gitStatus: GitFileStatus?, isDirectory: Bool, style: FileExplorerStyle) {
        guard let gitStatus else {
            statusBadgeLabel.stringValue = ""
            statusBadgeLabel.setAccessibilityLabel(nil)
            if nameLabelTrailingToBadgeConstraint.constant != 0 {
                nameLabelTrailingToBadgeConstraint.constant = 0
            }
            return
        }
        let letter: String
        switch gitStatus {
        case .modified: letter = "M"
        case .added: letter = "A"
        case .deleted: letter = "D"
        case .renamed: letter = "R"
        case .untracked: letter = "U"
        }
        statusBadgeLabel.stringValue = isDirectory ? "\u{2022}" : letter
        let badgeSize = max(style.nameFont.pointSize - 1.5, 9)
        if statusBadgeLabel.font?.pointSize != badgeSize {
            statusBadgeLabel.font = .monospacedSystemFont(ofSize: badgeSize, weight: .semibold)
        }
        statusBadgeLabel.textColor = style.gitColor(for: gitStatus)
        statusBadgeLabel.setAccessibilityLabel(letter)
        if nameLabelTrailingToBadgeConstraint.constant != -6 {
            nameLabelTrailingToBadgeConstraint.constant = -6
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}
