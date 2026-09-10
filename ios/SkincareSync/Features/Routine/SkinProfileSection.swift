import SwiftUI

/// Skin type (exactly one) and concerns (zero or more) at the top of Routine.
struct SkinProfileSection: View {
    @Environment(RoutineStore.self) private var store

    var body: some View {
        Section {
            Picker("Skin type", selection: Binding(
                get: { store.draft.profile.skinType },
                set: { store.setSkinType($0) }
            )) {
                ForEach(SkinType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.navigationLink)
            .foregroundStyle(Palette.forest)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Concerns")
                    .foregroundStyle(Palette.forest)
                FlowLayout(spacing: Spacing.s) {
                    ForEach(Concern.allCases) { concern in
                        ChipToggle(title: concern.label, isOn: Binding(
                            get: { store.draft.profile.concerns.contains(concern) },
                            set: { store.setConcern(concern, selected: $0) }
                        ))
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Concerns")
        } header: {
            Text("Skin profile")
                .font(Typography.heading)
                .foregroundStyle(Palette.forest)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("Rosacea and eczema raise every conflict to high severity; the skin type can adjust individual rules.")
        }
    }
}
