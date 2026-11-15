#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Presents the system share sheet from the foreground scene's topmost view controller.
/// Replaces the former privacy-window presenter; there is no lock to coordinate with.
@MainActor enum MadarSharePresenter {
    struct Unavailable: Error {}
    static func present(items: [Any]) throws {
        #if os(iOS)
        guard !items.isEmpty,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              var top = window.rootViewController else { throw Unavailable() }
        while let presented = top.presentedViewController { top = presented }
        let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad presents the sheet as a popover and crashes without an anchor.
        share.popoverPresentationController?.sourceView = top.view
        share.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(share, animated: true)
        #else
        guard !items.isEmpty, let window = NSApp.keyWindow ?? NSApp.mainWindow, let view = window.contentView else { throw Unavailable() }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
        #endif
    }
    static func present(file: URL) throws { try present(items: [file]) }
}
