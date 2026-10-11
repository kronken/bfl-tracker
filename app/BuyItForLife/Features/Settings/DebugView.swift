import SwiftUI

/// Hidden tools, opened by tapping the version in Settings seven times.
struct DebugView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Onboarding")
                        Button {
                            dismiss()
                            // Let this sheet close before onboarding covers the screen.
                            Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                AppRouter.shared.replayOnboarding = true
                            }
                        } label: {
                            Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.secondary)
                        Text("Shows the welcome flow again. Your items and settings are kept; anything you choose or add during the replay is saved as usual. Close it any time with ×.")
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                            .padding(.horizontal, 4)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Build")
                        VStack(spacing: 0) {
                            FormRow(label: "Version") { Text(SettingsView.version).foregroundStyle(.textSecondary) }
                            RowDivider()
                            FormRow(label: "Build") { Text(Self.build).foregroundStyle(.textSecondary) }
                        }
                        .foregroundStyle(.textPrimary)
                        .card(padding: nil)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(.appBackground)
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(.textPrimary)
                }
            }
        }
        .presentationBackground(.appBackground)
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
