import SwiftUI

/// Color wheel that keeps a draft until 確認. The close button discards it.
struct ColorDraftPicker: View {
    let title: String
    let initial: Color
    let onConfirm: (Color) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Color
    @State private var confirmed = false

    init(title: String, initial: Color, onConfirm: @escaping (Color) -> Void) {
        self.title = title
        self.initial = initial
        self.onConfirm = onConfirm
        _draft = State(initialValue: initial)
    }

    var body: some View {
        SystemColorPicker(color: $draft) {
            if !confirmed { dismiss() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text(title)
                    .font(.headline)
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("關閉")
                    Spacer()
                    Button("確認") {
                        confirmed = true
                        onConfirm(draft)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.height(Self.sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    /// Short enough that the sheet top, and these buttons, stay below the status bar.
    static let sheetHeight: CGFloat = 520
}

/// Keeps the system picker from forcing the sheet back to full height.
private final class PaletteColorPicker: UIColorPickerViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shortenSheet()
    }

    func shortenSheet() {
        guard let sheet = enclosingSheet() else { return }
        let id = UISheetPresentationController.Detent.Identifier("palette")
        guard sheet.selectedDetentIdentifier != id else { return }
        let detent = UISheetPresentationController.Detent.custom(identifier: id) { _ in
            ColorDraftPicker.sheetHeight
        }
        sheet.detents = [detent]
        sheet.selectedDetentIdentifier = id
    }

    private func enclosingSheet() -> UISheetPresentationController? {
        var current: UIViewController? = self
        while let controller = current {
            if let sheet = controller.presentationController as? UISheetPresentationController {
                return sheet
            }
            current = controller.parent
        }
        return sheetPresentationController
    }
}

private struct SystemColorPicker: UIViewControllerRepresentable {
    @Binding var color: Color
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> PickerHost {
        PickerHost(initial: UIColor(color))
    }

    func updateUIViewController(_ host: PickerHost, context: Context) {
        host.color = $color
        host.onFinish = onFinish
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: PickerHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: min(proposal.height ?? 440, 440))
    }

    final class PickerHost: UIViewController, UIColorPickerViewControllerDelegate {
        private let picker = PaletteColorPicker()
        var color: Binding<Color>?
        var onFinish: () -> Void = {}
        private var hidClose = false

        init(initial: UIColor) {
            super.init(nibName: nil, bundle: nil)
            picker.supportsAlpha = false
            picker.selectedColor = initial
            picker.delegate = self
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(picker)
            picker.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(picker.view)
            NSLayoutConstraint.activate([
                picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                picker.view.topAnchor.constraint(equalTo: view.topAnchor),
                picker.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            picker.didMove(toParent: self)
            view.clipsToBounds = true
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            picker.shortenSheet()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard !hidClose else { return }
            hidClose = hideClose(in: picker.view)
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController,
            didSelect color: UIColor,
            continuously: Bool
        ) {
            self.color?.wrappedValue = Color(uiColor: color)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            onFinish()
        }

        /// ponytail: the embedded picker adds its own close control; ours is the one that discards.
        private func hideClose(in view: UIView) -> Bool {
            var found = false
            if let button = view as? UIButton {
                let label = (button.accessibilityLabel ?? "").lowercased()
                if label.contains("close") || label.contains("關閉") || label.contains("dismiss") {
                    button.isHidden = true
                    button.isAccessibilityElement = false
                    found = true
                }
            }
            for subview in view.subviews where hideClose(in: subview) {
                found = true
            }
            return found
        }
    }
}

#Preview {
    ColorDraftPicker(title: "原型", initial: Color(red: 0.22, green: 0.74, blue: 0.97)) { _ in }
        .preferredColorScheme(.dark)
}
