import Foundation

struct AgendaSummaryAttachmentReference: Equatable, Hashable, Sendable {
    let fileName: String
    let localURL: URL?
    let contentType: String?
}

struct AttachmentContextRequest: Equatable, Sendable {
    let references: [AgendaSummaryAttachmentReference]
    let referenceText: [String]
    let maximumCharactersPerAttachment: Int
    let maximumTotalCharacters: Int
    let maximumContexts: Int

    init(
        references: [AgendaSummaryAttachmentReference],
        referenceText: [String],
        maximumCharactersPerAttachment: Int,
        maximumTotalCharacters: Int,
        maximumContexts: Int
    ) {
        self.references = references
        self.referenceText = referenceText
        self.maximumCharactersPerAttachment = max(240, maximumCharactersPerAttachment)
        self.maximumTotalCharacters = max(240, maximumTotalCharacters)
        self.maximumContexts = max(1, maximumContexts)
    }
}

protocol AgendaSummaryAttachmentPreviewProviding: Sendable {
    func contexts(for request: AttachmentContextRequest) async -> [String]

    func requestByAddingAttachmentPreviews(
        _ request: AgendaSummaryRequest
    ) async -> AgendaSummaryRequest
}
