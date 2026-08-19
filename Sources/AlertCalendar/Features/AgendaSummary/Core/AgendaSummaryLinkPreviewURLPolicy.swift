import Darwin
import Foundation

enum AgendaSummaryLinkPreviewURLPolicy {
    private static let blockedHostSuffixes = [
        ".internal", ".lan", ".local", ".localhost", ".home", ".home.arpa",
    ]
    private static let blockedPathExtensions: Set<String> = [
        "7z", "avi", "bin", "bmp", "bz2", "dmg", "doc", "docx", "exe", "gif", "gz",
        "heic", "ico", "iso", "jpeg", "jpg", "m4a", "m4v", "mov", "mp3", "mp4", "mpeg",
        "msi", "pdf", "pkg", "png", "ppt", "pptx", "rar", "svg", "tar", "tif", "tiff",
        "wav", "webm", "webp", "xls", "xlsx", "zip",
    ]
    private static let sensitiveQueryFragments = [
        "access_token", "apikey", "api_key", "auth", "code", "credential", "jwt", "key",
        "passwd", "password", "pwd", "secret", "session", "sig", "signature", "ticket", "token",
    ]

    static func eligibleURL(_ url: URL) -> URL? {
        guard url.absoluteString.count <= 2_048,
              !MeetingURLResolver.isKnownMeetingURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let rawHost = components.host else {
            return nil
        }

        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard isLexicallyPublicHost(host),
              !blockedPathExtensions.contains(url.pathExtension.lowercased()),
              !containsSensitiveQuery(components.queryItems) else {
            return nil
        }

        components.scheme = "https"
        components.host = host
        components.fragment = nil
        components.queryItems = components.queryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_")
                && name != "fbclid"
                && name != "gclid"
                && name != "mc_cid"
                && name != "mc_eid"
        }
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }
        return components.url
    }

    static func isLexicallyPublicHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              host != "localhost",
              host != "local",
              host.contains(".") || parsedIPAddress(host) != nil,
              !blockedHostSuffixes.contains(where: { host.hasSuffix($0) }) else {
            return false
        }

        return parsedIPAddress(host) ?? true
    }

    static func isPublicIPv4Bytes(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let first = bytes[0]
        let second = bytes[1]

        if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
        if first == 100, (64...127).contains(second) { return false }
        if first == 169, second == 254 { return false }
        if first == 172, (16...31).contains(second) { return false }
        if first == 192, second == 168 { return false }
        if first == 192, second == 0 { return false }
        if first == 192, second == 0, bytes[2] == 2 { return false }
        if first == 198, second == 18 || second == 19 { return false }
        if first == 198, second == 51, bytes[2] == 100 { return false }
        if first == 203, second == 0, bytes[2] == 113 { return false }
        return true
    }

    static func isPublicIPv6Bytes(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) { return false }
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 { return false }
        if bytes[0] & 0xFE == 0xFC { return false }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return false }
        if bytes[0] == 0xFF { return false }
        if Array(bytes.prefix(4)) == [0x20, 0x01, 0x0D, 0xB8] { return false }

        let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 }
            && bytes[10] == 0xFF
            && bytes[11] == 0xFF
        if isIPv4Mapped {
            return isPublicIPv4Bytes(Array(bytes.suffix(4)))
        }
        return true
    }

    private static func containsSensitiveQuery(_ items: [URLQueryItem]?) -> Bool {
        items?.contains { item in
            let name = item.name.lowercased().replacingOccurrences(of: "-", with: "_")
            return sensitiveQueryFragments.contains { fragment in
                name == fragment || name.contains(fragment)
            }
        } == true
    }

    private static func parsedIPAddress(_ host: String) -> Bool? {
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            let bytes = withUnsafeBytes(of: &ipv4.s_addr) { Array($0) }
            return isPublicIPv4Bytes(bytes)
        }

        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            return isPublicIPv6Bytes(bytes)
        }
        return nil
    }
}

enum AgendaSummaryPublicHostResolver {
    static func resolvesOnlyToPublicAddresses(_ host: String) async -> Bool {
        await Task.detached(priority: .utility) {
            resolveOnlyPublicAddresses(host)
        }.value
    }

    private static func resolveOnlyPublicAddresses(_ host: String) -> Bool {
        guard AgendaSummaryLinkPreviewURLPolicy.isLexicallyPublicHost(host) else { return false }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &result) == 0, let result else { return false }
        defer { freeaddrinfo(result) }

        var foundAddress = false
        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let current = cursor {
            let addressInfo = current.pointee
            guard let socketAddress = addressInfo.ai_addr else { return false }
            foundAddress = true

            switch addressInfo.ai_family {
            case AF_INET:
                let address = socketAddress.withMemoryRebound(
                    to: sockaddr_in.self,
                    capacity: 1
                ) { $0.pointee.sin_addr }
                var mutableAddress = address
                let bytes = withUnsafeBytes(of: &mutableAddress.s_addr) { Array($0) }
                if !AgendaSummaryLinkPreviewURLPolicy.isPublicIPv4Bytes(bytes) { return false }
            case AF_INET6:
                let address = socketAddress.withMemoryRebound(
                    to: sockaddr_in6.self,
                    capacity: 1
                ) { $0.pointee.sin6_addr }
                var mutableAddress = address
                let bytes = withUnsafeBytes(of: &mutableAddress) { Array($0) }
                if !AgendaSummaryLinkPreviewURLPolicy.isPublicIPv6Bytes(bytes) { return false }
            default:
                return false
            }
            cursor = addressInfo.ai_next
        }
        return foundAddress
    }
}
