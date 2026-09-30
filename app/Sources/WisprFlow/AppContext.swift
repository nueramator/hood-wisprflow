import AppKit

/// Reports what app is focused, so the cleanup pass can adapt tone/format
/// (formal for Mail, casual for Slack, code-aware for a terminal/editor).
enum AppContext {
    static func frontmostAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "an application"
    }

    static func frontmostBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }
}
