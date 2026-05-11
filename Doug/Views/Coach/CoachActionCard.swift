import SwiftUI

struct CoachActionCard: View {
    let actions: [CoachActionProposal]
    let selections: Set<UUID>
    let resolved: Bool
    let dismissed: Bool
    let onToggle: (UUID) -> Void
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Proposed changes")
                .font(.subheadline.bold())

            ForEach(actions) { action in
                actionRow(action)
            }

            if !resolved {
                HStack(spacing: 12) {
                    Button(action: onApply) {
                        Text("Apply")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButtonStyle(prominent: true)
                    .disabled(selections.isEmpty)

                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButtonStyle()
                }
            } else {
                Text(dismissed ? "Changes dismissed" : "Changes applied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(DougTheme.warmParchment)
        .clipShape(.rect(cornerRadius: 16))
    }

    private func actionRow(_ action: CoachActionProposal) -> some View {
        Button {
            if !resolved { onToggle(action.id) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: resolved || selections.contains(action.id)
                    ? "checkmark.square.fill"
                    : "square")
                    .foregroundStyle(resolved ? .secondary : DougTheme.sourdoughBrown)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.displaySummary)
                        .font(.subheadline)
                    if !action.reason.isEmpty {
                        Text(action.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(resolved)
    }
}
