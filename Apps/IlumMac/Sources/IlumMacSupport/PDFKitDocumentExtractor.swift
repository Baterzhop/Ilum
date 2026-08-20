import Foundation
import PDFKit
import IlumCore

public final class PDFKitDocumentExtractor: DocumentTextExtractor, @unchecked Sendable {
    private let catalog: SecurityScopedFileCatalog
    public init(catalog: SecurityScopedFileCatalog) { self.catalog = catalog }

    public func extract(resourceID: UserFileResourceID) async throws -> ExtractedDocument {
        try catalog.withSecurityScopedURL(resourceID: resourceID) { url, descriptor in
            guard url.pathExtension.lowercased() == "pdf" else { throw DocumentExtractionError.unsupportedResource(descriptor.displayName) }
            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { throw DocumentExtractionError.invalidDocument(descriptor.displayName) }
            var pages: [ExtractedDocumentPage] = []
            var containsText = false
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index) else { throw DocumentExtractionError.invalidDocument(descriptor.displayName) }
                let text = page.string ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { containsText = true }
                pages.append(ExtractedDocumentPage(pageNumber: index + 1, text: text))
            }
            guard containsText else { throw DocumentExtractionError.noExtractableText(descriptor.displayName) }
            return ExtractedDocument(
                sourceResourceID: resourceID,
                displayName: descriptor.displayName,
                mediaType: "application/pdf",
                pages: pages,
                metadata: ["extractor": .string("PDFKit"), "pageCount": .number(Double(pdf.pageCount))]
            )
        }
    }
}
