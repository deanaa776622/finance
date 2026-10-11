import SwiftUI

/// Presents the system color wheel. 確認 applies; close and swipe discard.
/// ponytail: a child picker never updates its color — it has to be presented.
struct ColorDraftPresenter: UIViewControllerRepresentable {
    var title: String?
    var initial: Color
    var onConfirm: (Color) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> Host {
        let host = Host()
        host.onAppear = { [weak host] in
            guard let host else { return }
            context.coordinator.sync(host)
        }
        return host
    }

    func updateUIViewController(_ host: Host, context: Context) {
        let coordinator = context.coordinator
        coordinator.title = title
        coordinator.initial = initial
        coordinator.onConfirm = onConfirm
        coordinator.onCancel = onCancel
        coordinator.sync(host)
    }

    final class Host: UIViewController {
        var onAppear: (() -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onAppear?()
        }
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate, UISheetPresentationControllerDelegate {
        var title: String?
        var initial: Color = .clear
        var onConfirm: (Color) -> Void = { _ in }
        var onCancel: () -> Void = {}

        private weak var host: Host?
        private weak var picker: UIColorPickerViewController?
        private weak var nav: UINavigationController?
        private var showing = false
        private var finished = false
        private var picked: UIColor?
        private var queued = false

        func sync(_ host: Host) {
            self.host = host
            guard title != nil, !showing, !queued else { return }
            queued = true
            DispatchQueue.main.async { [weak self, weak host] in
                guard let self, let host else { return }
                self.queued = false
                self.present(from: host)
            }
        }

        private func present(from host: Host) {
            guard let title, !showing, let presenter = Self.presenter(host), presenter.presentedViewController == nil else { return }
            showing = true
            finished = false
            picked = nil
            let wheel = PaletteColorPicker()
            wheel.supportsAlpha = false
            wheel.selectedColor = UIColor(initial)
            wheel.delegate = self
            wheel.title = title
            let close = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                style: .plain,
                target: self,
                action: #selector(cancel)
            )
            close.accessibilityLabel = "關閉"
            wheel.navigationItem.leftBarButtonItem = close
            wheel.navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "確認",
                style: .done,
                target: self,
                action: #selector(confirm)
            )
            picker = wheel
            let nav = UINavigationController(rootViewController: wheel)
            self.nav = nav
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                let detent = UISheetPresentationController.Detent.custom(identifier: Self.detent) { _ in Self.height }
                sheet.detents = [detent]
                sheet.selectedDetentIdentifier = Self.detent
                sheet.prefersGrabberVisible = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                sheet.delegate = self
            }
            presenter.present(nav, animated: true)
        }

        /// The background host is often off-window. Present from the sheet already on screen.
        private static func presenter(_ host: Host) -> UIViewController? {
            if host.view.window != nil { return host }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            let window = windows.first(where: \.isKeyWindow) ?? windows.first
            var top = window?.rootViewController
            while let next = top?.presentedViewController { top = next }
            return top
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController,
            didSelect color: UIColor,
            continuously: Bool
        ) {
            picked = color
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            let already = finished
            finish(apply: false)
            if !already { dismissWheel() }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            showing = false
            finish(apply: false)
        }

        @objc private func confirm() {
            finish(apply: true)
            dismissWheel()
        }

        @objc private func cancel() {
            finish(apply: false)
            dismissWheel()
        }

        private func finish(apply: Bool) {
            guard !finished else { return }
            finished = true
            if apply { onConfirm(Self.srgb(chosen())) } else { onCancel() }
        }

        private func dismissWheel() {
            guard let nav else {
                showing = false
                return
            }
            nav.dismiss(animated: true) { [weak self] in
                self?.showing = false
            }
        }

        /// Delegate color wins. The wheel's selectedColor stays put when it is embedded.
        private func chosen() -> UIColor {
            if let picked { return picked }
            return picker?.selectedColor ?? UIColor(initial)
        }

        private static let detent = UISheetPresentationController.Detent.Identifier("palette")
        private static let height: CGFloat = 560

        private static func srgb(_ color: UIColor) -> Color {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let converted = color.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
                  let c = converted.components, c.count >= 3 else {
                return Color(uiColor: color)
            }
            return Color(red: c[0], green: c[1], blue: c[2])
        }
    }
}

/// Keeps the wheel sheet from jumping back to full height, above the status bar.
private final class PaletteColorPicker: UIColorPickerViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let sheet = navigationController?.sheetPresentationController else { return }
        let id = UISheetPresentationController.Detent.Identifier("palette")
        guard sheet.selectedDetentIdentifier != id else { return }
        sheet.detents = [.custom(identifier: id) { _ in 560 }]
        sheet.selectedDetentIdentifier = id
        sheet.prefersGrabberVisible = true
    }
}
