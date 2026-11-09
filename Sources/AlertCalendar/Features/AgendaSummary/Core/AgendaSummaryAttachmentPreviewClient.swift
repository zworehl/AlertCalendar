import AppKit
import Foundation
import PDFKit
import Vision

actor AgendaSummaryAttachmentPreviewClient: AgendaSummaryAttachmentPreviewProviding {
    private struct SourceCacheEntry {
        let text: String?
    }

    private struct ContextCandidate {
        let index: Int
        let text: String
        let score: Int
    }

    private static let maximumFileBytes = 12 * 1_024 * 1_024
    private static let maximumCachedSourceCharacters = 512 * 1_024
    private static let maximumSourceCacheEntries = 24
    private static let maximumAgendaContextCharacters = 8_000
    private static let maximumAgendaCharactersPerAttachment = 2_400
    private static let maximumAgendaContextsPerItem = 6
    private static let maximumOCRImageDimension = 2_200

    private var sourceCache: [String: SourceCacheEntry] = [:]

    func requestByAddingAttachmentPreviews(
        _ request: AgendaSummaryRequest
    ) async -> AgendaSummaryRequest {
        let itemsWithAttachments = request.items.filter {
            $0.attachmentReferences.contains(where: { $0.localURL != nil })
        }
        guard !itemsWithAttachments.isEmpty else { return request }

        let perItemBudget = min(
            6_000,
            max(
                1_200,
                Self.maximumAgendaContextCharacters / itemsWithAttachments.count
            )
        )
        var previewsByItemKey: [String: [String]] = [:]

        for item in itemsWithAttachments {
            guard !Task.isCancelled else { return request }
            let referenceText = [
                item.title,
                item.description,
                item.calendarName,
                item.location,
                item.personalizedContext,
            ].compactMap { $0 }
                + item.attachmentNames
                + item.urlHosts
            let itemContexts = await contexts(
                for: AttachmentContextRequest(
                    references: item.attachmentReferences,
                    referenceText: referenceText,
                    maximumCharactersPerAttachment: min(
                        Self.maximumAgendaCharactersPerAttachment,
                        perItemBudget
                    ),
                    maximumTotalCharacters: perItemBudget,
                    maximumContexts: Self.maximumAgendaContextsPerItem
                )
            )
            if !itemContexts.isEmpty {
                previewsByItemKey[item.sourceKey] = itemContexts
            }
        }

        trimSourceCacheIfNeeded()
        return request.addingAttachmentPreviews(previewsByItemKey)
    }

    func contexts(for request: AttachmentContextRequest) async -> [String] {
        var candidates: [ContextCandidate] = []

        for (index, reference) in request.references.enumerated() {
            guard !Task.isCancelled,
                  let sourceText = sourceText(for: reference) else {
                continue
            }
            let fileName = Self.safeFileName(reference.fileName)
            let header = "Attachment \(fileName) relevant excerpts:"
            let excerptBudget = max(
                240,
                request.maximumCharactersPerAttachment - header.count - 1
            )
            let referenceText = request.referenceText + [fileName]
            guard let selectedText = RelevantContextSelector.selectedText(
                from: sourceText,
                referenceText: referenceText,
                maximumCharacters: excerptBudget,
                maximumSegments: 24
            ) else {
                continue
            }
            let context = "\(header)\n\(selectedText)"
            candidates.append(
                ContextCandidate(
                    index: index,
                    text: context,
                    score: RelevantContextSelector.relevanceScore(
                        for: "\(fileName)\n\(selectedText)",
                        referenceText: request.referenceText
                    )
                )
            )
        }

        let rankedCandidates = candidates.sorted { left, right in
            if left.score != right.score {
                return left.score > right.score
            }
            return left.index < right.index
        }
        var contexts: [String] = []
        var usedCharacters = 0

        for candidate in rankedCandidates.prefix(request.maximumContexts) {
            let separatorCharacters = contexts.isEmpty ? 0 : 1
            let remainingCharacters = request.maximumTotalCharacters
                - usedCharacters
                - separatorCharacters
            guard remainingCharacters >= 240 else { break }
            let boundedContext = Self.wordBoundedPrefix(
                candidate.text,
                maximumCharacters: remainingCharacters
            )
            guard boundedContext.count >= 240 || candidate.text.count < 240 else { continue }
            contexts.append(boundedContext)
            usedCharacters += separatorCharacters + boundedContext.count
        }

        trimSourceCacheIfNeeded()
        return contexts
    }

    private func sourceText(
        for reference: AgendaSummaryAttachmentReference
    ) -> String? {
        guard let url = reference.localURL,
              let cacheKey = Self.cacheKey(for: url) else {
            return nil
        }
        if let cachedEntry = sourceCache[cacheKey] {
            return cachedEntry.text
        }

        let extractedText = Self.loadText(from: url, reference: reference)
        if extractedText?.count ?? 0 <= Self.maximumCachedSourceCharacters {
            sourceCache[cacheKey] = SourceCacheEntry(text: extractedText)
        }
        return extractedText
    }

    private static func cacheKey(for url: URL) -> String? {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
              ]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= maximumFileBytes else {
            return nil
        }
        return [
            url.standardizedFileURL.path,
            String(fileSize),
            String(values.contentModificationDate?.timeIntervalSince1970 ?? 0),
        ].joined(separator: "|")
    }

    private static func loadText(
        from url: URL,
        reference: AgendaSummaryAttachmentReference
    ) -> String? {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = url.pathExtension.lowercased()
        let contentType = reference.contentType?.lowercased() ?? ""
        let extractedText: String?

        if fileExtension == "pdf" || contentType.contains("pdf") {
            extractedText = pdfText(from: url)
        } else if richDocumentExtensions.contains(fileExtension)
                    || contentType.contains("rtf")
                    || contentType.contains("word")
                    || contentType.contains("openxml")
                    || contentType.contains("html") {
            extractedText = richDocumentText(from: url)
        } else if plainTextExtensions.contains(fileExtension)
                    || contentType.hasPrefix("text/")
                    || contentType.hasPrefix("public.text") {
            extractedText = plainText(from: url)
        } else if imageExtensions.contains(fileExtension)
                    || contentType.contains("image") {
            extractedText = imageText(from: url)
        } else {
            extractedText = nil
        }

        return AlertCalendarString.trimmedNonEmpty(extractedText)
    }

    private static func plainText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.isEmpty else {
            return nil
        }
        for encoding in [
            String.Encoding.utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1,
            .windowsCP1252,
        ] {
            if let value = String(data: data, encoding: encoding) {
                return value
            }
        }
        return nil
    }

    private static func richDocumentText(from url: URL) -> String? {
        (try? NSAttributedString(
            url: url,
            options: [:],
            documentAttributes: nil
        ))?.string
    }

    private static func pdfText(from url: URL) -> String? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(document.pageCount)

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let selectableText = AlertCalendarString.trimmedNonEmpty(page.string)
            if let selectableText, selectableText.count >= 24 {
                pageTexts.append(selectableText)
            } else if let recognizedText = recognizedText(from: page) {
                pageTexts.append(recognizedText)
            } else if let selectableText {
                pageTexts.append(selectableText)
            }
        }

        return AlertCalendarString.trimmedNonEmpty(pageTexts.joined(separator: "\n"))
    }

    private static func imageText(from url: URL) -> String? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = cgImage(from: image) else {
            return nil
        }
        return recognizedText(from: cgImage)
    }

    private static func recognizedText(from page: PDFPage) -> String? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(
            2,
            CGFloat(maximumOCRImageDimension) / max(bounds.width, bounds.height)
        )
        let image = page.thumbnail(
            of: NSSize(width: bounds.width * scale, height: bounds.height * scale),
            for: .mediaBox
        )
        guard let cgImage = cgImage(from: image) else { return nil }
        return recognizedText(from: cgImage)
    }

    private static func recognizedText(from image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        return AlertCalendarString.trimmedNonEmpty(text)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        )
    }

    private static func safeFileName(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(120)
            .description
    }

    private static func wordBoundedPrefix(
        _ value: String,
        maximumCharacters: Int
    ) -> String {
        guard value.count > maximumCharacters else { return value }
        let prefix = String(value.prefix(maximumCharacters))
        if let lastWhitespace = prefix.lastIndex(where: \.isWhitespace) {
            return String(prefix[..<lastWhitespace])
        }
        return prefix
    }

    private func trimSourceCacheIfNeeded() {
        guard sourceCache.count > Self.maximumSourceCacheEntries else { return }
        for key in sourceCache.keys.prefix(sourceCache.count - Self.maximumSourceCacheEntries) {
            sourceCache.removeValue(forKey: key)
        }
    }

    private static let plainTextExtensions: Set<String> = [
        "csv", "ics", "json", "log", "md", "markdown", "text", "txt", "xml", "yaml", "yml",
    ]

    private static let richDocumentExtensions: Set<String> = [
        "doc", "docx", "htm", "html", "odt", "rtf",
    ]

    private static let imageExtensions: Set<String> = [
        "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp",
    ]
}
