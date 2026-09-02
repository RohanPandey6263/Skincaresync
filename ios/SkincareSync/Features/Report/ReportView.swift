import SwiftUI

struct ReportView: View {
    let report: AnalysisReport
    private let presentation: ReportPresentation

    init(report: AnalysisReport) {
        self.report = report
        presentation = ReportPresentation(result: report.result)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                summary
                ForEach(presentation.sections) { section in
                    sectionView(section)
                }
                details
                Text(ReportPresentation.disclaimer)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Palette.page)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        let tone = presentation.status.presentation
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: tone.symbol)
                    .foregroundStyle(tone.tint)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(presentation.summaryTitle)
                    .font(Typography.title)
                    .foregroundStyle(Palette.forest)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(presentation.countsLine)
                .font(.body.weight(.medium))
                .foregroundStyle(tone.text)
            Text("Checked for \(report.profile.summary). \(report.generatedAt.formatted(date: .abbreviated, time: .shortened)).")
                .font(Typography.meta)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.wash)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func sectionView(_ section: ReportSection) -> some View {
        let tone = section.kind.presentation
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: tone.symbol)
                    .foregroundStyle(tone.tint)
                    .accessibilityHidden(true)
                Text(section.kind.title)
                    .font(Typography.groupHeading)
                    .foregroundStyle(Palette.forest)
                Text("\(section.count)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tone.text)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 2)
                    .background(tone.wash)
                    .clipShape(Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(section.kind.title), \(section.count)")
            .accessibilityAddTraits(.isHeader)
            Text(section.kind.blurb)
                .font(Typography.meta)
                .foregroundStyle(Palette.muted)
            if section.findings.isEmpty {
                Text(section.kind.emptyText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.muted)
                    .padding(.vertical, Spacing.s)
            } else {
                ForEach(section.findings) { finding in
                    FindingCard(finding: finding, profile: report.profile)
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Hairline()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(presentation.parsedProducts) { parsed in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(parsed.product.label)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Palette.forest)
                            Text("\(parsed.knownIngredients.count) recognised · \(parsed.unknownTokens.count) unrecognised")
                                .font(Typography.meta)
                                .foregroundStyle(Palette.muted)
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
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, Spacing.s)
            } label: {
                Text("Products analysed (\(presentation.parsedProducts.count))")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.forest)
            }
            .frame(minHeight: Metrics.touchTarget)
            Hairline()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if presentation.unresolvedTokens.isEmpty {
                        Text("Every ingredient was recognised.")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.muted)
                    } else {
                        ForEach(presentation.unresolvedTokens) { token in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(token.rawToken).font(Typography.body).foregroundStyle(Palette.forest)
                                Text(token.product).font(Typography.meta).foregroundStyle(Palette.muted)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("Unrecognised names are skipped, so a rule involving them cannot fire.")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.faint)
                    }
                }
                .padding(.top, Spacing.s)
            } label: {
                Text("Unresolved ingredients (\(presentation.unresolvedTokens.count))")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.forest)
            }
            .frame(minHeight: Metrics.touchTarget)
            Hairline()
        }
        .tint(Palette.forest)
    }
}

/// One finding. States its verdict with a word, a symbol and a colour, then
/// the pair, the explanation, scope, products, confidence and evidence.
struct FindingCard: View {
    let finding: InteractionFinding
    let profile: SkinProfile

    private var tone: TonePresentation { finding.interactionType.presentation(severity: finding.severity) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            FlowLayout(spacing: Spacing.s) {
                TagPill(text: tone.label, symbol: tone.symbol, tone: tone)
                Label(finding.scope.label, systemImage: finding.scope.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.vertical, Spacing.xs + 1)
                    .accessibilityLabel("Scope: \(finding.scope.label)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.ingredientA.inciName)
                Text("+ \(finding.ingredientB.inciName)")
            }
            .font(Typography.pairName)
            .foregroundStyle(Palette.forest)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(finding.ingredientA.inciName) with \(finding.ingredientB.inciName)")

            if let description = finding.description, !description.isEmpty {
                Text(description)
                    .font(Typography.body)
                    .foregroundStyle(Palette.forest)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let mechanism = finding.mechanism, !mechanism.isEmpty, mechanism != finding.description {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Mechanism").eyebrowStyle()
                    Text(mechanism)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let escalation = ReportPresentation.escalationText(for: finding, profile: profile) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(escalation)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Typography.meta)
                .foregroundStyle(Palette.clayText)
                .accessibilityLabel("Severity raised. \(escalation)")
            }
            Text(finding.scope.explanation)
                .font(Typography.meta)
                .foregroundStyle(Palette.faint)
                .fixedSize(horizontal: false, vertical: true)

            Hairline()
            VStack(alignment: .leading, spacing: Spacing.s) {
                MetaRow(label: "Products", value: "\(finding.productA.label) · \(finding.productB.label)")
                if let confidence = ReportPresentation.confidenceLabel(finding.confidence) {
                    MetaRow(label: "Confidence", value: confidence)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Evidence").eyebrowStyle()
                    if let url = finding.evidenceURL {
                        Link(destination: url) {
                            Label(finding.sourceCitation ?? "PubMed", systemImage: "arrow.up.right.square")
                                .font(.body)
                                .foregroundStyle(Palette.terracottaText)
                        }
                        .frame(minHeight: Metrics.touchTarget - 12)
                        .accessibilityLabel("Open evidence \(finding.sourceCitation ?? "") on PubMed")
                    } else {
                        Text(finding.sourceCitation ?? "Not cited")
                            .font(.body)
                            .foregroundStyle(Palette.forest)
                    }
                }
            }
        }
        .padding(Spacing.m)
        .padding(.leading, Metrics.findingEdge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.wash)
        .overlay(alignment: .leading) {
            Rectangle().fill(tone.tint).frame(width: Metrics.findingEdge)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Fixture report") {
    NavigationStack {
        ReportView(report: Fixtures.sampleReport)
    }
}
