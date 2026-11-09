import Foundation

enum EventTitleRewriteError: Error {
    case unavailable
    case characterLimitTooSmall
    case invalidResponse
}
