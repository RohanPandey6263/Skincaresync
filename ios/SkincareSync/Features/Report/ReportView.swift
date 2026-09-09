import SwiftUI

struct ReportView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let report: AnalysisReport
    private let presentation: ReportPresentation

    init(report: AnalysisReport) {
        self.report = report
        presentation = ReportPresentation(result: report.result)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                summary
                ForEach(presentation.sections) { section in
                    sectionView(section)
                }
                details
                Text(ReportPresentation.disclaimer)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .cardGutter()
                    .padding(.bottom, Spacing.xxl)
            }
            .padding(.top, Spacing.m)
        }
        .background(Palette.page)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Verdict

    /// The hero: one card carrying the verdict and the three counts.
    private var summary: some View {
        let tone = presentation.status.presentation
        let isConflict = presentation.status == .conflict
        return VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: tone.symbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(isConflict ? Palette.accentText : Palette.cocoa)
                        .accessibilityHidden(true)
                    SectionLabel("00", "Verdict")
                }
                Text(presentation.summaryTitle)
                    .headlineStyle(Typography.display, color: isConflict ? Palette.accentText : Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Checked for \(report.profile.summary). \(report.generatedAt.formatted(date: .abbreviated, time: .shortened)).")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            // Three counts, three tiles. Stacked at accessibility sizes so no
            // label has to break inside a word.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.s) {
                    statCell("Conflicts", report.result.conflicts.count, accent: report.result.conflicts.count > 0)
                    statCell("Cautions", report.result.cautions.count, accent: false)
                    statCell("Synergies", report.result.synergies.count, accent: false)
                }
            } else {
                HStack(spacing: Spacing.s) {
                    statCell("Conflicts", report.result.conflicts.count, accent: report.result.conflicts.count > 0)
                    statCell("Cautions", report.result.cautions.count, accent: false)
                    statCell("Synergies", report.result.synergies.count, accent: false)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.l)
        .softCard()
        .cardGutter()
    }

    private func statCell(_ label: String, _ value: Int, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("\(value)")
                .font(Typography.numeral)
                .foregroundStyle(accent ? Palette.accentText : Palette.ink)
            Text(label).eyebrowStyle(color: Palette.secondary)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent ? Palette.wash(Palette.accent) : Palette.surfaceAlt,
                    in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.lowercased())")
    }

    // MARK: Sections

    private func sectionView(_ section: ReportSection) -> some View {
        let tone = section.kind.presentation
        return VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(section.kind.number)
                    .eyebrowStyle(color: Palette.cocoa)
                    .accessibilityHidden(true)
                HStack(alignment: .center, spacing: Spacing.s + 2) {
                    Text(section.kind.title)
                        .headlineStyle(Typography.groupHeading)
                    TagPill(text: "\(section.count)", tone: tone, filled: section.kind == .conflicts && section.count > 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(section.kind.title), \(section.count)")
                .accessibilityAddTraits(.isHeader)
                Text(section.kind.blurb)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.secondary)
            }
            .cardGutter()
            .padding(.top, Spacing.s)

            if section.findings.isEmpty {
                Text(section.kind.emptyText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.m)
                    .softCard(radius: Radius.tile)
                    .cardGutter()
            } else {
                VStack(spacing: Spacing.m) {
                    ForEach(section.findings) { finding in
                        FindingCard(finding: finding, profile: report.profile)
                    }
                }
                .cardGutter()
            }
        }
    }

    // MARK: Disclosures

    private var details: some View {
        VStack(spacing: 0) {
            SoftDisclosure(title: "Products analysed", meta: "\(presentation.parsedProducts.count)") {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(presentation.parsedProducts) { parsed in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(parsed.product.label)
                                .headlineStyle(Typography.pairName)
                            Text("\(parsed.knownIngredients.count) recognised · \(parsed.unknownTokens.count) unrecognised")
                                .font(Typography.meta)
                                .foregroundStyle(Palette.secondary)
                            Text(parsed.knownIngredients.map(\.inciName).joined(separator: ", "))
                                .font(Typography.meta)
                                .foregroundStyle(Palette.faint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if presentation.unknownPairCount > 0 {
                        Text("\(presentation.unknownPairCount) ingredient pairs have no rule yet. They were logged for research and are not treated as safe or unsafe.")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Rule().padding(.horizontal, Spacing.m)
            SoftDisclosure(title: "Unresolved ingredients", meta: "\(presentation.unresolvedTokens.count)") {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if presentation.unresolvedTokens.isEmpty {
                        Text("Every ingredient was recognised.")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.secondary)
                    } else {
                        ForEach(presentation.unresolvedTokens) { token in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(token.rawToken).font(Typography.bodyMedium).foregroundStyle(Palette.ink)
                                Text(token.product).font(Typography.meta).foregroundStyle(Palette.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("Unrecognised names are skipped, so a rule involving them cannot fire.")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.faint)
                    }
                }
            }
        }
        .softCard()
        .cardGutter()
        .padding(.top, Spacing.s)
    }
}

/// A disclosure whose marker is a plus that turns into a cross.
struct SoftDisclosure<Content: View>: View {
    let title: String
    var meta: String? = nil
    @ViewBuilder let content: () -> Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: Spacing.m) {
                    Text(title).eyebrowStyle(color: Palette.ink)
                    Spacer()
                    if let meta {
                        Text(meta).font(Typography.metaBold).foregroundStyle(Palette.secondary)
                    }
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .rotationEffect(.degrees(open ? 45 : 0))
                        .frame(width: 28, height: 28)
                        .background(Palette.muted, in: Circle())
                        .accessibilityHidden(true)
                }
                .padding(Spacing.m)
                .frame(minHeight: Metrics.touchTarget + 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? [.isButton, .isSelected] : .isButton)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open {
                content()
                    .padding(.horizontal, Spacing.m)
                    .padding(.bottom, Spacing.l)
            }
        }
    }
}

/// One finding. States its verdict with a word, a symbol and a surface, then
/// the pair, the explanation, scope, products, confidence and evidence.
struct FindingCard: View {
    let finding: InteractionFinding
    let profile: SkinProfile

    private var tone: TonePresentation { finding.interactionType.presentation(severity: finding.severity) }
    private var isConflict: Bool { finding.interactionType == .conflict }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            FlowLayout(spacing: Spacing.s) {
                TagPill(text: tone.label, symbol: tone.symbol, tone: tone, filled: isConflict)
                HStack(spacing: Spacing.xs) {
                    Image(systemName: finding.scope.symbol).font(.caption.weight(.bold))
                    Text(finding.scope.label)
                }
                .eyebrowStyle(color: Palette.secondary)
                .padding(.vertical, Spacing.xs + 3)
                .accessibilityLabel("Scope: \(finding.scope.label)")
            }
            (Text(finding.ingredientA.inciName) + Text(" + ").foregroundStyle(Palette.cocoa) + Text(finding.ingredientB.inciName))
                .headlineStyle(Typography.pairName)
                .accessibilityLabel("\(finding.ingredientA.inciName) with \(finding.ingredientB.inciName)")

            if let description = finding.description, !description.isEmpty {
                Text(description)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let mechanism = finding.mechanism, !mechanism.isEmpty, mechanism != finding.description {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Mechanism").eyebrowStyle()
                    Text(mechanism)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.m - 2)
                .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            if let escalation = ReportPresentation.escalationText(for: finding, profile: profile) {
                Text(escalation)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.m - 2)
                    .background(Palette.wash(Palette.accent), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .accessibilityLabel("Severity adjusted. \(escalation)")
            }
            Text(finding.scope.explanation)
                .font(Typography.meta)
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)

            Rule()
            VStack(alignment: .leading, spacing: Spacing.m) {
                MetaRow(label: "Products", value: "\(finding.productA.label) · \(finding.productB.label)")
                if let confidence = ReportPresentation.confidenceLabel(finding.confidence) {
                    MetaRow(label: "Confidence", value: confidence)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Evidence").eyebrowStyle()
                    if let url = finding.evidenceURL {
                        Link(destination: url) {
                            HStack(spacing: Spacing.xs) {
                                Text(finding.sourceCitation ?? "PubMed")
                                    .font(Typography.bodyBold)
                                    .underline()
                                Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                            }
                            .foregroundStyle(Palette.accentText)
                        }
                        .frame(minHeight: Metrics.touchTarget - 12)
                        .accessibilityLabel("Open evidence \(finding.sourceCitation ?? "") on PubMed")
                    } else {
                        Text(finding.sourceCitation ?? "Not cited")
                            .font(Typography.body)
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .shadow(color: Palette.shadow, radius: 14, x: 0, y: 6)
        .softOutline(radius: Radius.card, color: isConflict ? Palette.accent.opacity(0.55) : Palette.border)
        .accessibilityElement(children: .contain)
    }

    /// The surface carries the verdict a second time: coral wash for a conflict,
    /// hatching for a caution, a dotted mint wash for a synergy.
    @ViewBuilder
    private var surface: some View {
        switch tone.pattern {
        case .diagonal:
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
                .overlay(PatternView(pattern: .diagonal).softClip())
        case .dots:
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.wash(Palette.mint))
                .overlay(PatternView(pattern: .dots).softClip())
        case .grid:
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
                .overlay(PatternView(pattern: .grid).softClip())
        case nil:
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(isConflict ? Palette.wash(Palette.accent) : Palette.surface)
        }
    }
}

#Preview("Fixture report") {
    NavigationStack {
        ReportView(report: Fixtures.sampleReport)
    }
}
