import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable(description: "A faithful, compact replacement for an agenda item title.")
struct AppleEventTitleOutput {
    @Guide(description: "Only the requested compact English text (preserving names and identifiers), without quotes, explanation, or ellipsis.")
    var title: String
}
#endif
