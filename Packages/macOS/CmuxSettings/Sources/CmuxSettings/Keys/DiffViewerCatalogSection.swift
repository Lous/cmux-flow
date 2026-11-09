import Foundation

/// Settings under the dotted-id prefix `diffViewer.*` that the app reads.
///
/// `diffViewer.defaultLayout` is read by the `cmux diff` CLI straight from
/// cmux.json, so it has no key here.
public struct DiffViewerCatalogSection: SettingCatalogSection {
    /// Where diff viewers open; see ``DiffViewerPlacement``.
    ///
    /// Defaults to ``DiffViewerPlacement/split``, cmux's established behavior.
    public let placement = DefaultsKey<DiffViewerPlacement>(
        id: "diffViewer.placement",
        defaultValue: .split,
        userDefaultsKey: "diffViewer.placement"
    )

    /// Creates the diff viewer settings section with its default keys.
    public init() {}
}
