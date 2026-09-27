import Foundation

/// Curated summaries, not a consolidated legal database or a live web search.
public struct GeodesyReferenceEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let jurisdiction: String
    public let kind: String
    public let section: String
    public let summary: String
    public let caution: String
    public let publisher: String
    public let sourceEdition: String
    public let reviewedOn: String
    public let sourceURL: String
    public let relatedSourceURLs: [String]
    public let aliases: [String]
}

public enum GeodesyReferenceCatalog {
    public static let snapshotDate = "2026-09-27"
    public static let scopeNote = """
    Offline starter reference: German federal topics and Nordrhein-Westfalen (NRW), not all German states or municipal plans. Short curated summaries, not complete statutes. Source edition and editorial review date are different; no live legal-validity check. Before applying a rule, check the current official text, amendments, project date, municipality and applicable Bebauungsplan/BauNVO edition. Cite the entry's source URL and section. DIN entries contain bibliographic guidance only.
    """

    /// Bounded lexical search; the UI uses `entries` directly when its filter is empty.
    public static func search(_ query: String, limit: Int = 5) -> [GeodesyReferenceEntry] {
        let words = tokens(String(query.prefix(2048))).filter { !stopWords.contains($0) }
        let terms = Array(Set(words)).sorted().prefix(24)
        guard !terms.isEmpty, limit > 0 else { return [] }
        let ranked = entries.compactMap { entry -> (GeodesyReferenceEntry, Int)? in
            let keywords = Set(tokens(entry.title + " " + entry.aliases.joined(separator: " ")))
            let body = Set(tokens(entry.summary + " " + entry.section))
            var score = 0
            for term in terms {
                if keywords.contains(term) { score += 12 }
                else if term.count >= 4 && keywords.contains(where: { $0.hasPrefix(term) }) { score += 6 }
                else if body.contains(term) { score += 1 }
            }
            return score > 0 ? (entry, score) : nil
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 > rhs.1
        }
        return ranked.prefix(min(limit, entries.count)).map { $0.0 }
    }

    private static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private static let stopWords: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "einen",
        "und", "oder", "mit", "von", "fur", "im", "in", "ist", "sind", "wie", "was",
        "bitte", "mir", "ich", "zu", "zur", "zum", "nrw", "deutschland", "germany",
        "the", "and", "for", "what", "is", "explain", "про", "для", "та", "це", "як",
        "що", "таке", "мені", "поясни", "німеччині", "німеччина", "германії"
    ]
}

public struct GeodesySearchInput: Codable, Equatable, Sendable {
    public let query: String
    public let limit: Int?
    public init(query: String, limit: Int? = nil) { self.query = query; self.limit = limit }
}

public struct GeodesySearchOutput: Codable, Equatable, Sendable {
    public let scopeNote: String
    public let entries: [GeodesyReferenceEntry]
}

public struct GeodesySearchTool: Tool {
    public static let descriptor = ToolDescriptor(
        name: "geodesy.search", version: "1",
        summary: "Search offline German/NRW surveying references: Erhebungserlass, GRZ/GFZ, cadastral boundaries, building plans, coordinate systems and official sources. German and Ukrainian keywords supported. Returns summaries with source editions; not live legal verification.",
        risk: .readOnly, capability: .readAppData,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string"), "maxLength": .number(2048)]),
                "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(5)])
            ]),
            "required": .array([.string("query")]),
            "additionalProperties": .bool(false)
        ])
    )

    public init() {}
    public func resource(for input: GeodesySearchInput) throws -> ResourceScope { .appData("geodesy-reference") }
    public func execute(_ input: GeodesySearchInput) async throws -> GeodesySearchOutput {
        GeodesySearchOutput(
            scopeNote: GeodesyReferenceCatalog.scopeNote,
            entries: GeodesyReferenceCatalog.search(input.query, limit: min(max(input.limit ?? 3, 1), 5))
        )
    }
}
