import SwiftUI

/// Asks what the user can actually see and smell in the jar.
///
/// This is how a new-starter plan knows whether to hold, skip ahead, stretch,
/// or finish — the calendar alone can't tell, because the same method takes
/// five days in one kitchen and three weeks in another.
struct StarterCheckInSheet: View {
    let step: RevivalFeedStep
    let onSubmit: (StarterCheckInSignals) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var activity: StarterActivityLevel = .nothing
    @State private var smell: StarterSmell = .nothing

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(StarterActivityLevel.allCases) { option in
                        Button {
                            activity = option
                        } label: {
                            choiceRow(
                                title: title(for: option),
                                blurb: blurb(for: option),
                                isSelected: activity == option
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("checkInActivity-\(option.rawValue)")
                        .accessibilityAddTraits(activity == option ? [.isSelected] : [])
                    }
                } header: {
                    Text("How far did it get?")
                } footer: {
                    Text("Be honest about a near miss. Doug would rather add a feed than call a starter ready early.")
                }

                Section {
                    ForEach(StarterSmell.allCases) { option in
                        Button {
                            smell = option
                        } label: {
                            smellRow(option)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("checkInSmell-\(option.rawValue)")
                        .accessibilityAddTraits(smell == option ? [.isSelected] : [])
                    }
                } header: {
                    Text("What does it smell like?")
                } footer: {
                    Text("Smell is the most useful signal there is — it's what separates real yeast activity "
                        + "from the bacterial bloom that mimics it early on.")
                }
                if let watchFor = step.instructionWatchFor, !watchFor.isEmpty {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "eye.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(watchFor)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("What do you see?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log It") {
                        onSubmit(StarterCheckInSignals(activity: activity, smell: smell))
                        dismiss()
                    }
                    .accessibilityIdentifier("checkInSubmit")
                }
            }
        }
    }

    private func smellRow(_ option: StarterSmell) -> some View {
        choiceRow(
            title: title(for: option),
            blurb: blurb(for: option),
            isSelected: smell == option
        )
    }

    private func choiceRow(title: String, blurb: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
    }

    private func title(for option: StarterActivityLevel) -> String {
        switch option {
        case .nothing: "Nothing much"
        case .bubbles: "Bubbles, but no rise"
        case .rose: "It rose"
        case .doubled: "It doubled or more"
        }
    }

    private func blurb(for option: StarterActivityLevel) -> String {
        switch option {
        case .nothing: "Flat and still since the last feed."
        case .bubbles: "You can see bubbles, but it didn't climb the jar."
        case .rose: "Visibly higher, though not quite twice the size."
        case .doubled: "Twice its starting height or more."
        }
    }

    private func title(for option: StarterSmell) -> String {
        switch option {
        case .nothing: "Not much"
        case .cheesyOrFunky: "Cheesy or unpleasant"
        case .yeastyBready: "Yeasty or bready"
        case .sharpVinegar: "Sharp vinegar"
        case .pleasantlySour: "Pleasantly sour"
        }
    }

    private func blurb(for option: StarterSmell) -> String {
        switch option {
        case .nothing: "Wet flour, or nothing you'd notice."
        case .cheesyOrFunky: "Old socks, parmesan, or worse. Very common early on."
        case .yeastyBready: "Like beer, dough, or a bakery."
        case .sharpVinegar: "Harsh and acidic, almost like nail polish."
        case .pleasantlySour: "Tangy, like yoghurt or a good sourdough loaf."
        }
    }
}
