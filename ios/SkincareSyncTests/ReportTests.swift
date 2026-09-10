import Foundation
import Testing
@testable import SkincareSync

struct ReportTests {
    @Test func sectionsAreInSafetyOrderWithCounts() {
        let presentation = ReportPresentation(result: Fixtures.analysis)
        #expect(presentation.sections.map(\.kind) == [.conflicts, .cautions, .synergies])
        #expect(presentation.sections.map(\.count) == [1, 7, 5])
        #expect(presentation.status == .conflict)
        #expect(presentation.summaryTitle == "Conflicts detected")
        #expect(presentation.countsLine == "1 conflict · 7 cautions · 5 synergies")
    }

    @Test func cautionsAreOrderedHighToLowStably() {
        let presentation = ReportPresentation(result: Fixtures.analysis)
        let severities = presentation.sections[1].findings.map(\.severity.rank)
        #expect(severities == severities.sorted(by: >))
        // Highest first: the escalated Ascorbic Acid + Benzoyl Peroxide caution keeps its lead.
        #expect(presentation.sections[1].findings.first?.ingredientA.inciName == "Ascorbic Acid")
        #expect(presentation.sections[1].findings.last?.severity == .medium)
    }

    @Test func summaryTitlesCoverEveryStatus() {
        #expect(ReportPresentation.summaryTitle(for: OverallScore(status: .conflict, high: 1, medium: 0, count: nil)) == "Conflicts detected")
        #expect(ReportPresentation.summaryTitle(for: OverallScore(status: .caution, high: nil, medium: nil, count: 2)) == "Use with care")
        #expect(ReportPresentation.summaryTitle(for: OverallScore(status: .clean, high: nil, medium: nil, count: nil)) == "No conflicts found")
        #expect(ReportPresentation.countsLine(conflicts: 0, cautions: 1, synergies: 0) == "0 conflicts · 1 caution · 0 synergies")
    }

    @Test func emptySectionsStillAppear() {
        var result = Fixtures.analysis
        result.conflicts = []
        result.synergies = []
        result.overallScore = OverallScore(status: .caution, high: nil, medium: nil, count: result.cautions.count)
        let presentation = ReportPresentation(result: result)
        #expect(presentation.sections.count == 3)
        #expect(presentation.sections[0].findings.isEmpty)
        #expect(presentation.summaryTitle == "Use with care")
    }

    @Test func severityPresentationHasWordSymbolAndColour() {
        #expect(Severity.high.presentation.label == "High severity")
        #expect(Severity.high.presentation.symbol == "exclamationmark.octagon.fill")
        #expect(Severity.medium.presentation.label == "Medium severity")
        #expect(Severity.low.presentation.symbol == "info.circle.fill")
        #expect(InteractionType.synergy.presentation(severity: .low).label == "Synergy")
        #expect(InteractionType.redundant.presentation(severity: .medium).label == "Redundant · Medium")
        #expect(InteractionScope.cumulative.label == "Across AM and PM")
        #expect(InteractionScope.direct.label == "In one routine")
    }

    @Test func escalationCopyMentionsProfile() {
        let profile = SkinProfile(skinType: .sensitive, concerns: [.rosacea, .acne])
        let escalated = Fixtures.analysis.cautions.first { $0.wasEscalated }!
        let text = ReportPresentation.escalationText(for: escalated, profile: profile)
        #expect(text == "Raised from medium to high for sensitive skin and your concerns (rosacea, acne).")
        let plain = Fixtures.analysis.conflicts[0]
        #expect(ReportPresentation.escalationText(for: plain, profile: profile) == nil)
        #expect(ReportPresentation.confidenceLabel("provisional") == "Provisional")
        #expect(ReportPresentation.confidenceLabel(nil) == nil)
    }

    @Test func citationsOnlyLinkToPubMed() {
        #expect(Citation.url(for: "PMID:33377285")?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/33377285/")
        #expect(Citation.url(for: "pmid 12")?.absoluteString == "https://pubmed.ncbi.nlm.nih.gov/12/")
        #expect(Citation.url(for: "https://evil.example") == nil)
        #expect(Citation.url(for: nil) == nil)
    }
}
