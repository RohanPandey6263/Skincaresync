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
            VStack(alignment: .leading, spacing: 0) {
                summary
                ForEach(presentation.sections) { section in
                    sectionView(section)
                }
                details
                Text(ReportPresentation.disclaimer)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.m)
                    .padding(.bottom, Spacing.xxl)
            }
        }
        .background(Palette.page)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Verdict

    private var summary: some View {
        let tone = presentation.status.presentation
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: tone.symbol)
                        .font(.body.weight(.bold))
                        .foregroundStyle(presentation.status == .conflict ? Palette.accent : Palette.ink)
                        .accessibilityHidden(true)
                    SectionLabel("00", "Verdict")
                }
                Text(presentation.summaryTitle)
                    .headlineStyle(Typography.display, color: presentation.status == .conflict ? Palette.accent : Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Checked for \(report.profile.summary). \(report.generatedAt.formatted(date: .abbreviated, time: .shortened)).")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.m)
            .padding(.top, Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Rule(width: Metrics.borderHeavy)

            // Three counts, three cells, black rules between. Stacked at
            // accessibility sizes so no label has to break inside a word.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    statCell("Conflicts", report.result.conflicts.count, accent: report.result.conflicts.count > 0)
                    Rule()
                    statCell("Cautions", report.result.cautions.count, accent: false)
                    Rule()
                    statCell("Synergies", report.result.synergies.count, accent: false)
                }
            } else {
                HStack(spacing: 0) {
                    statCell("Conflicts", report.result.conflicts.count, accent: report.result.conflicts.count > 0)
                    Rectangle().fill(Palette.ink).frame(width: Metrics.border)
                    statCell("Cautions", report.result.cautions.count, accent: false)
                    Rectangle().fill(Palette.ink).frame(width: Metrics.border)
                    statCell("Synergies", report.result.synergies.count, accent: false)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Rule(width: Metrics.borderHeavy)
        }
    }

    private func statCell(_ label: String, _ value: Int, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(label).eyebrowStyle()
            Text("\(value)")
                .font(Typography.numeral)
                .foregroundStyle(accent ? Palette.accent : Palette.ink)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.lowercased())")
    }

    // MARK: Sections

    private func sectionView(_ section: ReportSection) -> some View {
        let tone = section.kind.presentation
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(section.kind.number)
                    .eyebrowStyle(color: Palette.accentText)
                    .accessibilityHidden(true)
                HStack(alignment: .lastTextBaseline, spacing: Spacing.m) {
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
            .padding(Spacing.m)
            .padding(.top, Spacing.xl)
            Rule(width: Metrics.borderHeavy)
            if section.findings.isEmpty {
                Text(section.kind.emptyText)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.secondary)
                    .padding(Spacing.m)
            } else {
                VStack(spacing: Spacing.m) {
                    ForEach(section.findings) { finding in
                        FindingCard(finding: finding, profile: report.profile)
                    }
                }
                .padding(Spacing.m)
            }
        }
    }

    // MARK: Disclosures

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule(width: Metrics.borderHeavy)
            SwissDisclosure(title: "Products analysed", meta: "\(presentation.parsedProducts.count)") {
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
            Rule()
            SwissDisclosure(title: "Unresolved ingredients", meta: "\(presentation.unresolvedTokens.count)") {
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
            Rule()
        }
    }
}

/// A disclosure whose marker is a plus that turns into a cross.
struct SwissDisclosure<Content: View>: View {
    let title: String
    var meta: String? = nil
    @ViewBuilder let content: () -> Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.linear(duration: 0.12)) { open.toggle() }
            } label: {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .rotationEffect(.degrees(open ? 45 : 0))
                        .accessibilityHidden(true)
                    Text(title).eyebrowStyle(color: Palette.ink)
                    Spacer()
                    if let meta {
                        Text(meta).font(Typography.metaBold).foregroundStyle(Palette.secondary)
                    }
                }
                .foregroundStyle(Palette.ink)
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
                .padding(.vertical, Spacing.xs + 2)
                .accessibilityLabel("Scope: \(finding.scope.label)")
            }
            (Text(finding.ingredientA.inciName) + Text(" + ").foregroundStyle(Palette.accent) + Text(finding.ingredientB.inciName))
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
                .padding(.leading, Spacing.m)
                .overlay(alignment: .leading) { Rectangle().fill(Palette.ink).frame(width: Metrics.border) }
                .accessibilityElement(children: .combine)
            }
            if let escalation = ReportPresentation.escalationText(for: finding, profile: profile) {
                Text(escalation)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Spacing.m)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.accent).frame(width: Metrics.border) }
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
        .padding(Spacing.m)
        .padding(.leading, Metrics.findingEdge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(isConflict ? Palette.accent : Palette.ink).frame(width: Metrics.findingEdge)
        }
        .overlay(Rectangle().strokeBorder(isConflict ? Palette.accent : Palette.ink, lineWidth: Metrics.border))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var surface: some View {
        switch tone.pattern {
        case .diagonal: Palette.page.overlay(PatternView(pattern: .diagonal))
        case .dots: Palette.page.overlay(PatternView(pattern: .dots))
        case .grid: Palette.page.overlay(PatternView(pattern: .grid))
        case nil: Palette.page
        }
    }
}

#Preview("Fixture report") {
    NavigationStack {
        ReportView(report: Fixtures.sampleReport)
    }
}
