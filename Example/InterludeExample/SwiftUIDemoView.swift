import Interlude
import SwiftUI

/// SwiftUI 修饰符演示：Binding 驱动的加载、进度与 Toast，以及局部宿主。
struct SwiftUIDemoView: View {
    // MARK: - Private Properties

    @State private var isLoading = false
    @State private var progress: Double?
    @State private var toast: Interlude.Toast?
    @State private var isCardLoading = false

    // MARK: - Body

    var body: some View {
        List {
            Section("Global window") {
                Button("Loading for 1.5s") {
                    isLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isLoading = false }
                }
                Button("Progress 0 → 1") {
                    progress = 0
                    Task {
                        for step in 1 ... 20 {
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            progress = Double(step) / 20
                        }
                        progress = nil
                    }
                }
                Button("Toast") {
                    toast = Interlude.Toast("Hello from SwiftUI", icon: .success)
                }
                Button("Toast with action") {
                    toast = Interlude.Toast(
                        "Draft discarded",
                        title: nil,
                        icon: .system("trash"),
                        action: .init(title: "Undo") { toast = Interlude.Toast("Restored", icon: .success) }
                    )
                }
                Button("async run") {
                    Task {
                        try? await Interlude.run("Fetching", success: "Fetched") {
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    }
                }
            }

            Section("Local host (.interludeHost)") {
                VStack(spacing: 12) {
                    Text("This card is an Interlude host.\nHUDs inside stay inside.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Loading in card") {
                        isCardLoading = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCardLoading = false }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .interludeLoading(isPresented: $isCardLoading, text: "Card")
                .interludeHost()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("SwiftUI")
        .interludeLoading(isPresented: $isLoading, text: "Loading")
        .interludeProgress($progress, style: .ring, text: "Uploading")
        .interludeToast($toast)
    }
}
