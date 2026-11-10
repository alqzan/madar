import UIKit

/// Presents the system share sheet from the foreground scene's topmost view controller.
/// Replaces the former privacy-window presenter; there is no lock to coordinate with.
@MainActor enum MadarSharePresenter {
    struct Unavailable: Error {}
    static func present(items: [Any]) throws {
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
    }
    static func present(file: URL) throws { try present(items: [file]) }
}
