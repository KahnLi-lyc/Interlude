import SwiftUI
import UIKit

// MARK: - Public Modifiers

public extension View {
    /// Shows a loading HUD while `isPresented` is `true`.
    ///
    /// Inside an ``SwiftUICore/View/interludeHost()`` the HUD attaches to that container; otherwise it
    /// uses the global window.
    func interludeLoading(
        isPresented: Binding<Bool>,
        text: String? = nil,
        interaction: Interlude.Interaction = .blocking
    ) -> some View {
        modifier(LoadingModifier(isPresented: isPresented, text: text, interaction: interaction))
    }

    /// Shows a progress HUD while `value` is non-nil and keeps it in sync.
    func interludeProgress(
        _ value: Binding<Double?>,
        style: Interlude.ProgressStyle = .ring,
        text: String? = nil,
        interaction: Interlude.Interaction = .blocking
    ) -> some View {
        modifier(ProgressModifier(value: value, style: style, text: text, interaction: interaction))
    }

    /// Shows the toast in `item` and resets the binding to `nil` when it disappears.
    func interludeToast(_ item: Binding<Interlude.Toast?>) -> some View {
        modifier(ToastModifier(item: item))
    }

    /// Makes this view the host for HUDs and toasts presented by descendants.
    func interludeHost() -> some View {
        modifier(HostModifier())
    }
}

// MARK: - Environment

/// 保存 SwiftUI 局部宿主视图的引用；MainActor 隔离因此可安全放入 Environment。
@MainActor
final class InterludeHostBox {
    weak var view: UIView?
}

private struct InterludeHostKey: EnvironmentKey {
    static let defaultValue: InterludeHostBox? = nil
}

extension EnvironmentValues {
    var interludeHost: InterludeHostBox? {
        get { self[InterludeHostKey.self] }
        set { self[InterludeHostKey.self] = newValue }
    }
}

// MARK: - HostModifier

private struct HostModifier: ViewModifier {
    @State private var box = InterludeHostBox()

    func body(content: Content) -> some View {
        content
            .overlay(HostProbe(box: box))
            .environment(\.interludeHost, box)
    }
}

/// 覆盖在内容之上、自身不拦截触摸的 UIKit 探针；其 bounds 即 SwiftUI 内容区域。
private struct HostProbe: UIViewRepresentable {
    let box: InterludeHostBox

    func makeUIView(context: Context) -> PassthroughLayerView {
        let view = PassthroughLayerView()
        view.backgroundColor = .clear
        box.view = view
        return view
    }

    func updateUIView(_ uiView: PassthroughLayerView, context: Context) {
        box.view = uiView
    }
}

// MARK: - LoadingModifier

private struct LoadingModifier: ViewModifier {
    @Binding var isPresented: Bool
    let text: String?
    let interaction: Interlude.Interaction

    @Environment(\.interludeHost) private var host
    @State private var token: Interlude.Token?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: sync)
            .onChange(of: isPresented) { _ in sync() }
            .onChange(of: text) { newValue in token?.update(text: newValue) }
            .onDisappear { end() }
    }

    private func sync() {
        if isPresented {
            guard token?.isActive != true else { return }
            token = Interlude.loading(text, on: host?.view, interaction: interaction)
        } else {
            end()
        }
    }

    private func end() {
        token?.dismiss()
        token = nil
    }
}

// MARK: - ProgressModifier

private struct ProgressModifier: ViewModifier {
    @Binding var value: Double?
    let style: Interlude.ProgressStyle
    let text: String?
    let interaction: Interlude.Interaction

    @Environment(\.interludeHost) private var host
    @State private var token: Interlude.Token?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: sync)
            .onChange(of: value) { _ in sync() }
            .onChange(of: text) { newValue in token?.update(text: newValue) }
            .onDisappear { end() }
    }

    private func sync() {
        guard let value else {
            end()
            return
        }
        if let token, token.isActive {
            token.update(progress: value)
        } else {
            token = Interlude.progress(value, style: style, text: text, on: host?.view, interaction: interaction)
        }
    }

    private func end() {
        token?.dismiss()
        token = nil
    }
}

// MARK: - ToastModifier

private struct ToastModifier: ViewModifier {
    @Binding var item: Interlude.Toast?

    @Environment(\.interludeHost) private var host
    @State private var presentedID: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: sync)
            .onChange(of: item) { _ in sync() }
    }

    private func sync() {
        guard var toast = item, toast.id != presentedID else { return }
        presentedID = toast.id
        let original = toast.completion
        let identifier = toast.id
        toast.completion = { didTap in
            original?(didTap)
            if item?.id == identifier {
                item = nil
            }
            if presentedID == identifier {
                presentedID = nil
            }
        }
        Interlude.toast(toast, on: host?.view)
    }
}
