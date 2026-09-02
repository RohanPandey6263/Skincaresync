import SwiftUI

/// Skin type (exactly one) and concerns (zero or more) at the top of Routine.
/// Rendered as ruled rows inside the plain list.
struct SkinProfileSection: View {
    @Environment(RoutineStore.self) private var store

    var body: some View {
        SectionHeaderRow(number: "01", eyebrow: "Profile", title: "Skin profile",
                         description: "Rosacea and eczema raise every conflict to high severity; the skin type can adjust individual rules.")
            .swissRow()

        Picker(selection: Binding(get: { store.draft.profile.skinType }, set: { store.setSkinType($0) })) {
            ForEach(SkinType.allCases) { type in
                Text(type.label).tag(type)
            }
        } label: {
            Text("Skin type").eyebrowStyle(color: Palette.ink)
        }
        .pickerStyle(.navigationLink)
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: Metrics.touchTarget + 8)
        .swissRow()

        Rule().swissRow()

        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("Concerns").eyebrowStyle(color: Palette.ink)
                Spacer()
                Text(store.draft.profile.concerns.isEmpty ? "Optional" : "\(store.draft.profile.concerns.count) selected")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.secondary)
            }
            FlowLayout(spacing: Spacing.s) {
                ForEach(Concern.allCases) { concern in
                    ChipToggle(title: concern.label, isOn: Binding(
                        get: { store.draft.profile.concerns.contains(concern) },
                        set: { store.setConcern(concern, selected: $0) }
                    ))
                }
            }
        }
        .padding(Spacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Concerns")
        .swissRow()

        Rule().swissRow()
    }
}
