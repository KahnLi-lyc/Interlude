import Interlude
import SwiftUI
import UIKit

/// 演示入口：每一行触发一个 API 场景。
final class DemoListViewController: UITableViewController {
    // MARK: - Types

    private struct Demo {
        let title: String
        let subtitle: String?
        let action: @MainActor (DemoListViewController) -> Void
    }

    private struct Section {
        let title: String
        let demos: [Demo]
    }

    // MARK: - Private Properties

    private lazy var sections = makeSections()
    private var persistentToast: Interlude.Toast.Handle?
    private var downloadProgress: Progress?

    // MARK: - Initialization

    init() {
        super.init(style: .insetGrouped)
        title = "Interlude"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Theme",
            menu: makeThemeMenu()
        )
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].demos.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let demo = sections[indexPath.section].demos[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = demo.title
        content.secondaryText = demo.subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        sections[indexPath.section].demos[indexPath.row].action(self)
    }

    // MARK: - Private Methods

    private func makeSections() -> [Section] {
        [makeHUDSection(), makeToastSection(), makeAsyncSection(), makeSwiftUISection()]
    }

    private func makeHUDSection() -> Section {
        Section(title: "HUD", demos: [
            Demo(title: "Loading → success", subtitle: "grace 0.15s, blocking, 1.5s later finish") { _ in
                let token = Interlude.loading("Saving…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    token.finish(.success("Saved"))
                }
            },
            Demo(title: "Fast task", subtitle: "Ends within grace: nothing flashes") { _ in
                let token = Interlude.loading()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    token.dismiss()
                }
            },
            Demo(title: "Passthrough loading", subtitle: "Scroll while it shows") { _ in
                let token = Interlude.loading("Refreshing", interaction: .passthrough)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { token.dismiss() }
            },
            Demo(title: "Ring progress", subtitle: "update(progress:) from a background thread") { _ in
                let token = Interlude.progress(text: "Uploading", detail: "0 / 100")
                DispatchQueue.global().async {
                    for step in 1 ... 100 {
                        Thread.sleep(forTimeInterval: 0.02)
                        token.update(progress: Double(step) / 100)
                        token.update(detail: "\(step) / 100")
                    }
                    token.finish(.success("Uploaded"))
                }
            },
            Demo(title: "Bar progress + Progress binding", subtitle: "token.observe(Progress)") { controller in
                let progress = Progress(totalUnitCount: 50)
                controller.downloadProgress = progress
                let token = Interlude.progress(progress, style: .bar, text: "Downloading")
                token.onCancel {
                    progress.cancel()
                    controller.downloadProgress = nil
                }
                controller.tick(progress, token: token)
            },
            Demo(title: "Text HUD", subtitle: "Auto dismiss after textDuration") { _ in
                Interlude.text("Copied to clipboard")
            },
            Demo(title: "Results", subtitle: "success / error / info / image") { _ in
                Interlude.show(.success("Done"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { Interlude.show(.error("Failed")) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { Interlude.show(.info("Heads up")) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
                    Interlude.show(.image(UIImage(systemName: "heart.fill")!, "Liked"))
                }
            },
            Demo(title: "Custom view", subtitle: "Any UIView in place of the indicator") { _ in
                let image = UIImageView(image: UIImage(systemName: "sparkles"))
                image.tintColor = .systemYellow
                image.contentMode = .scaleAspectFit
                let token = Interlude.custom(image, text: "Thinking…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { token.dismiss() }
            },
            Demo(title: "Timeout", subtitle: "3s timeout → error result") { _ in
                Interlude.loading("Waiting for server", timeout: 3).onTimeout {
                    print("timed out")
                }
            },
            Demo(title: "Cancel button", subtitle: "onCancel forces blocking") { _ in
                Interlude.loading("Exporting").onCancel {
                    Interlude.toast("Cancelled", icon: .info)
                }
            },
            Demo(title: "Two concurrent tokens", subtitle: "Latest wins, previous restored") { _ in
                let first = Interlude.loading("First")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let second = Interlude.progress(0.3, text: "Second")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { second.dismiss() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { first.finish(.success("First done")) }
                }
            },
            Demo(title: "Local host", subtitle: "HUD and toasts attached to a view") { controller in
                controller.navigationController?.pushViewController(LocalHostViewController(), animated: true)
            },
            Demo(title: "dismissAll()", subtitle: "Emergency cleanup") { _ in
                Interlude.dismissAll()
            }
        ])
    }

    private func makeToastSection() -> Section {
        Section(title: "Toast", demos: [
            Demo(title: "Bottom message", subtitle: "Default position & duration") { _ in
                Interlude.toast("Message sent")
            },
            Demo(title: "Icons", subtitle: "success / error / info / warning") { _ in
                Interlude.toast("Saved", icon: .success, position: .top)
                Interlude.toast("Failed", icon: .error, position: .top)
                Interlude.toast("Update available", icon: .info, position: .top)
            },
            Demo(title: "Title + action", subtitle: "Undo button") { _ in
                Interlude.toast(
                    "The message was removed from this chat.",
                    title: "Message deleted",
                    icon: .system("trash"),
                    action: .init(title: "Undo") { Interlude.toast("Restored", icon: .success) },
                    duration: .long
                )
            },
            Demo(title: "Persistent + Handle", subtitle: "Tap again to dismiss") { controller in
                if let handle = controller.persistentToast, handle.isVisible {
                    handle.dismiss()
                    controller.persistentToast = nil
                } else {
                    controller.persistentToast = Interlude.toast(
                        "You're offline",
                        icon: .warning,
                        duration: .persistent
                    )
                }
            },
            Demo(title: "Center", subtitle: "Toast at the centre") { _ in
                Interlude.toast("Centered", position: .center)
            },
            Demo(title: "Custom view", subtitle: "Toast.custom(view)") { _ in
                let label = UILabel()
                label.text = "🎉 Custom toast"
                label.font = .preferredFont(forTextStyle: .headline)
                label.textColor = .white
                let container = UIView()
                container.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                    label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                    label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
                ])
                Interlude.toast(.custom(container))
            },
            Demo(title: "Policy: queue", subtitle: "Three toasts one after another") { _ in
                Interlude.configure { $0.toast.policy = .queue }
                Interlude.toast("First")
                Interlude.toast("Second")
                Interlude.toast("Third") { _ in
                    Interlude.configure { $0.toast.policy = .stack(maximum: 3) }
                }
            },
            Demo(title: "Policy: replace", subtitle: "Only the newest stays") { _ in
                Interlude.configure { $0.toast.policy = .replace }
                Interlude.toast("First")
                Interlude.toast("Second") { _ in
                    Interlude.configure { $0.toast.policy = .stack(maximum: 3) }
                }
            },
            Demo(title: "Keyboard avoidance", subtitle: "Bottom toasts move above the keyboard") { controller in
                controller.navigationController?.pushViewController(KeyboardViewController(), animated: true)
            },
            Demo(title: "dismissAllToasts()", subtitle: nil) { _ in
                Interlude.dismissAllToasts()
            }
        ])
    }

    private func makeAsyncSection() -> Section {
        Section(title: "async / await", demos: [
            Demo(title: "Interlude.run success", subtitle: "Result shown after the operation") { _ in
                Task {
                    try await Interlude.run("Syncing", success: "Synced") {
                        try await Task.sleep(nanoseconds: 1_200_000_000)
                    }
                }
            },
            Demo(title: "Interlude.run failure", subtitle: "Error mapped to result text") { _ in
                Task {
                    try? await Interlude.run("Paying") {
                        try await Task.sleep(nanoseconds: 800_000_000)
                        throw NSError(
                            domain: "Demo",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Card declined"]
                        )
                    }
                }
            },
            Demo(title: "Interlude.run cancellable", subtitle: "Cancel button cancels the Task") { _ in
                Task {
                    try? await Interlude.run("Long task", cancellable: true) {
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                    }
                }
            },
            Demo(title: "Interlude.run with Progress", subtitle: "Bar style") { _ in
                Task {
                    try? await Interlude
                        .run("Compressing", style: .bar, totalUnitCount: 20, success: "Compressed") { progress in
                            for step in 1 ... 20 {
                                try await Task.sleep(nanoseconds: 80_000_000)
                                progress.completedUnitCount = Int64(step)
                            }
                        }
                }
            }
        ])
    }

    private func makeSwiftUISection() -> Section {
        Section(title: "SwiftUI", demos: [
            Demo(title: "SwiftUI modifiers", subtitle: "interludeLoading / Progress / Toast / Host") { controller in
                controller.navigationController?.pushViewController(
                    UIHostingController(rootView: SwiftUIDemoView()),
                    animated: true
                )
            }
        ])
    }

    private func makeThemeMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Automatic") { _ in Interlude.theme = .automatic },
            UIAction(title: "Dark") { _ in Interlude.theme = .dark },
            UIAction(title: "Light") { _ in Interlude.theme = .light },
            UIAction(title: "Brand (solid, zoom)") { _ in
                var theme = Interlude.Theme.dark
                theme.background = .solid(UIColor(red: 0.16, green: 0.35, blue: 0.95, alpha: 0.95))
                theme.cornerRadius = 20
                theme.animation = .zoom
                theme.toast.background = .solid(UIColor(red: 0.16, green: 0.35, blue: 0.95, alpha: 0.95))
                Interlude.theme = theme
            }
        ])
    }

    private func tick(_ progress: Progress, token: Interlude.Token) {
        guard !progress.isCancelled else { return }
        progress.completedUnitCount += 1
        if progress.completedUnitCount >= progress.totalUnitCount {
            token.finish(.success("Downloaded"))
            downloadProgress = nil
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.tick(progress, token: token)
        }
    }
}
