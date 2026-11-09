import Foundation

/// Where a diff viewer opens, from the Git tab or `cmux diff` (`diffViewer.placement`).
///
/// A split beside a terminal narrows it, and text a program already printed at
/// the narrower width stays that way after the split closes; ``tab`` and
/// ``existingPane`` never change the terminal's width.
public enum DiffViewerPlacement: String, CaseIterable, Sendable, SettingCodable {
    /// Uses the pane to the right of the focused one, creating a split when there is none.
    case split
    /// Opens a tab in the focused pane.
    case tab
    /// Reuses another open pane, preferring the one to the right, and never
    /// creates a split; with a single pane it opens a tab.
    case existingPane
}
