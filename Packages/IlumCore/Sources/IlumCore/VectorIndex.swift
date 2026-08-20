import Foundation

public struct DenseVectorRecord: Sendable {
    public let document: KnowledgeDocument
    public let chunk: KnowledgeChunk
    public let modelID: String
    public let vector: [Float]

    public init(document: KnowledgeDocument, chunk: KnowledgeChunk, modelID: String, vector: [Float]) {
        self.document = document; self.chunk = chunk; self.modelID = modelID; self.vector = vector
    }
}

public protocol DenseVectorIndex: Sendable {
    func replace(documentID: UUID, records: [DenseVectorRecord]) async throws
    func removeDocument(id: UUID) async throws
    func search(vector: [Float], modelID: String, limit: Int) async throws -> [KnowledgeHit]
}

public enum VectorIndexError: Error, CustomStringConvertible, Sendable {
    case emptyVector
    case dimensionMismatch
    case invalidVector
    case openFailed(String)
    case migrationFailed(String)
    case statementFailed(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .emptyVector: return "The vector is empty."
        case .dimensionMismatch: return "Vector dimensions do not match."
        case .invalidVector: return "The vector contains invalid values."
        case .openFailed(let d): return "Could not open the vector database: \(d)"
        case .migrationFailed(let d): return "Could not migrate the vector database: \(d)"
        case .statementFailed(let d): return "Vector database statement failed: \(d)"
        case .writeFailed(let d): return "Could not write vector data: \(d)"
        }
    }
}

public enum VectorMath {
    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) throws -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { throw VectorIndexError.emptyVector }
        guard lhs.count == rhs.count else { throw VectorIndexError.dimensionMismatch }
        guard lhs.allSatisfy({ $0.isFinite }), rhs.allSatisfy({ $0.isFinite }) else { throw VectorIndexError.invalidVector }
        var dot = 0.0, lhsNorm = 0.0, rhsNorm = 0.0
        for i in lhs.indices {
            let a = Double(lhs[i]), b = Double(rhs[i])
            dot += a * b; lhsNorm += a * a; rhsNorm += b * b
        }
        guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
        return dot / (sqrt(lhsNorm) * sqrt(rhsNorm))
    }
}
