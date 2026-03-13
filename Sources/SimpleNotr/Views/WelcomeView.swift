import SwiftUI

struct WelcomeView: View {
    @Binding var showVaultPicker: Bool

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 14) {
                Image(systemName: "note.text")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Color.accentColor)

                Text("SimpleNotr")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Text("Secure, local-first note taking.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                Button {
                    showVaultPicker = true
                } label: {
                    Label("Open Vault Folder", systemImage: "folder.badge.plus")
                        .frame(width: 230)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Text("A vault is any folder on your Mac.\nNotes are saved as plain **.txt** and **.md** files.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            HStack(spacing: 24) {
                featurePill(icon: "lock.shield", label: "No external requests")
                featurePill(icon: "doc.plaintext", label: "Plain files on disk")
                featurePill(icon: "arrow.triangle.branch", label: "Git-friendly")
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func featurePill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }
}
