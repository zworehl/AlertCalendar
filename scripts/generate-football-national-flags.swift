#!/usr/bin/env swift

import Foundation

struct FlagSource: Hashable {
    let associationCode: String
    let circleFlagCode: String
}

let circleFlagsVersion = "2.8.3"
let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/AlertCalendar/Resources/Images/FootballNationalFlags")

let flagSources: [FlagSource] = [
    FlagSource(associationCode: "AFG", circleFlagCode: "af"),
    FlagSource(associationCode: "AIA", circleFlagCode: "ai"),
    FlagSource(associationCode: "ALB", circleFlagCode: "al"),
    FlagSource(associationCode: "ALG", circleFlagCode: "dz"),
    FlagSource(associationCode: "AND", circleFlagCode: "ad"),
    FlagSource(associationCode: "ANG", circleFlagCode: "ao"),
    FlagSource(associationCode: "ARG", circleFlagCode: "ar"),
    FlagSource(associationCode: "ARM", circleFlagCode: "am"),
    FlagSource(associationCode: "ARU", circleFlagCode: "aw"),
    FlagSource(associationCode: "ASA", circleFlagCode: "us-as"),
    FlagSource(associationCode: "ATG", circleFlagCode: "ag"),
    FlagSource(associationCode: "AUS", circleFlagCode: "au"),
    FlagSource(associationCode: "AUT", circleFlagCode: "at"),
    FlagSource(associationCode: "AZE", circleFlagCode: "az"),
    FlagSource(associationCode: "BAH", circleFlagCode: "bs"),
    FlagSource(associationCode: "BAN", circleFlagCode: "bd"),
    FlagSource(associationCode: "BEL", circleFlagCode: "be"),
    FlagSource(associationCode: "BEN", circleFlagCode: "bj"),
    FlagSource(associationCode: "BER", circleFlagCode: "bm"),
    FlagSource(associationCode: "BFA", circleFlagCode: "bf"),
    FlagSource(associationCode: "BHR", circleFlagCode: "bh"),
    FlagSource(associationCode: "BHU", circleFlagCode: "bt"),
    FlagSource(associationCode: "BIH", circleFlagCode: "ba"),
    FlagSource(associationCode: "BLR", circleFlagCode: "by"),
    FlagSource(associationCode: "BLZ", circleFlagCode: "bz"),
    FlagSource(associationCode: "BOL", circleFlagCode: "bo"),
    FlagSource(associationCode: "BOT", circleFlagCode: "bw"),
    FlagSource(associationCode: "BRA", circleFlagCode: "br"),
    FlagSource(associationCode: "BRB", circleFlagCode: "bb"),
    FlagSource(associationCode: "BRU", circleFlagCode: "bn"),
    FlagSource(associationCode: "BUL", circleFlagCode: "bg"),
    FlagSource(associationCode: "BDI", circleFlagCode: "bi"),
    FlagSource(associationCode: "BVI", circleFlagCode: "vg"),
    FlagSource(associationCode: "CAM", circleFlagCode: "kh"),
    FlagSource(associationCode: "CAN", circleFlagCode: "ca"),
    FlagSource(associationCode: "CAY", circleFlagCode: "ky"),
    FlagSource(associationCode: "CGO", circleFlagCode: "cg"),
    FlagSource(associationCode: "CHA", circleFlagCode: "td"),
    FlagSource(associationCode: "CHE", circleFlagCode: "ch"),
    FlagSource(associationCode: "CHI", circleFlagCode: "cl"),
    FlagSource(associationCode: "CHN", circleFlagCode: "cn"),
    FlagSource(associationCode: "CIV", circleFlagCode: "ci"),
    FlagSource(associationCode: "CMR", circleFlagCode: "cm"),
    FlagSource(associationCode: "COD", circleFlagCode: "cd"),
    FlagSource(associationCode: "COK", circleFlagCode: "ck"),
    FlagSource(associationCode: "COL", circleFlagCode: "co"),
    FlagSource(associationCode: "COM", circleFlagCode: "km"),
    FlagSource(associationCode: "CPV", circleFlagCode: "cv"),
    FlagSource(associationCode: "CRC", circleFlagCode: "cr"),
    FlagSource(associationCode: "CRO", circleFlagCode: "hr"),
    FlagSource(associationCode: "CTA", circleFlagCode: "cf"),
    FlagSource(associationCode: "CUB", circleFlagCode: "cu"),
    FlagSource(associationCode: "CUW", circleFlagCode: "cw"),
    FlagSource(associationCode: "CYP", circleFlagCode: "cy"),
    FlagSource(associationCode: "CZE", circleFlagCode: "cz"),
    FlagSource(associationCode: "DEN", circleFlagCode: "dk"),
    FlagSource(associationCode: "DJI", circleFlagCode: "dj"),
    FlagSource(associationCode: "DMA", circleFlagCode: "dm"),
    FlagSource(associationCode: "DOM", circleFlagCode: "do"),
    FlagSource(associationCode: "ECU", circleFlagCode: "ec"),
    FlagSource(associationCode: "EGY", circleFlagCode: "eg"),
    FlagSource(associationCode: "ENG", circleFlagCode: "gb-eng"),
    FlagSource(associationCode: "EQG", circleFlagCode: "gq"),
    FlagSource(associationCode: "ERI", circleFlagCode: "er"),
    FlagSource(associationCode: "ESA", circleFlagCode: "sv"),
    FlagSource(associationCode: "ESP", circleFlagCode: "es"),
    FlagSource(associationCode: "EST", circleFlagCode: "ee"),
    FlagSource(associationCode: "ETH", circleFlagCode: "et"),
    FlagSource(associationCode: "FIJ", circleFlagCode: "fj"),
    FlagSource(associationCode: "FIN", circleFlagCode: "fi"),
    FlagSource(associationCode: "FRA", circleFlagCode: "fr"),
    FlagSource(associationCode: "FRO", circleFlagCode: "fo"),
    FlagSource(associationCode: "GAB", circleFlagCode: "ga"),
    FlagSource(associationCode: "GAM", circleFlagCode: "gm"),
    FlagSource(associationCode: "GBR", circleFlagCode: "gb"),
    FlagSource(associationCode: "GDL", circleFlagCode: "gp"),
    FlagSource(associationCode: "GEO", circleFlagCode: "ge"),
    FlagSource(associationCode: "GER", circleFlagCode: "de"),
    FlagSource(associationCode: "GHA", circleFlagCode: "gh"),
    FlagSource(associationCode: "GIB", circleFlagCode: "gi"),
    FlagSource(associationCode: "GRE", circleFlagCode: "gr"),
    FlagSource(associationCode: "GRN", circleFlagCode: "gd"),
    FlagSource(associationCode: "GUA", circleFlagCode: "gt"),
    FlagSource(associationCode: "GUF", circleFlagCode: "gf"),
    FlagSource(associationCode: "GUI", circleFlagCode: "gn"),
    FlagSource(associationCode: "GUM", circleFlagCode: "gu"),
    FlagSource(associationCode: "GUY", circleFlagCode: "gy"),
    FlagSource(associationCode: "GNB", circleFlagCode: "gw"),
    FlagSource(associationCode: "HAI", circleFlagCode: "ht"),
    FlagSource(associationCode: "HKG", circleFlagCode: "hk"),
    FlagSource(associationCode: "HON", circleFlagCode: "hn"),
    FlagSource(associationCode: "HUN", circleFlagCode: "hu"),
    FlagSource(associationCode: "IDN", circleFlagCode: "id"),
    FlagSource(associationCode: "IND", circleFlagCode: "in"),
    FlagSource(associationCode: "IRL", circleFlagCode: "ie"),
    FlagSource(associationCode: "IRN", circleFlagCode: "ir"),
    FlagSource(associationCode: "IRQ", circleFlagCode: "iq"),
    FlagSource(associationCode: "ISL", circleFlagCode: "is"),
    FlagSource(associationCode: "ISR", circleFlagCode: "il"),
    FlagSource(associationCode: "ITA", circleFlagCode: "it"),
    FlagSource(associationCode: "JAM", circleFlagCode: "jm"),
    FlagSource(associationCode: "JOR", circleFlagCode: "jo"),
    FlagSource(associationCode: "JPN", circleFlagCode: "jp"),
    FlagSource(associationCode: "KAZ", circleFlagCode: "kz"),
    FlagSource(associationCode: "KEN", circleFlagCode: "ke"),
    FlagSource(associationCode: "KGZ", circleFlagCode: "kg"),
    FlagSource(associationCode: "KOR", circleFlagCode: "kr"),
    FlagSource(associationCode: "KOS", circleFlagCode: "xk"),
    FlagSource(associationCode: "KSA", circleFlagCode: "sa"),
    FlagSource(associationCode: "KUW", circleFlagCode: "kw"),
    FlagSource(associationCode: "LAO", circleFlagCode: "la"),
    FlagSource(associationCode: "LBN", circleFlagCode: "lb"),
    FlagSource(associationCode: "LBR", circleFlagCode: "lr"),
    FlagSource(associationCode: "LBY", circleFlagCode: "ly"),
    FlagSource(associationCode: "LCA", circleFlagCode: "lc"),
    FlagSource(associationCode: "LES", circleFlagCode: "ls"),
    FlagSource(associationCode: "LIE", circleFlagCode: "li"),
    FlagSource(associationCode: "LTU", circleFlagCode: "lt"),
    FlagSource(associationCode: "LUX", circleFlagCode: "lu"),
    FlagSource(associationCode: "LVA", circleFlagCode: "lv"),
    FlagSource(associationCode: "MAC", circleFlagCode: "mo"),
    FlagSource(associationCode: "MAD", circleFlagCode: "mg"),
    FlagSource(associationCode: "MAR", circleFlagCode: "ma"),
    FlagSource(associationCode: "MAS", circleFlagCode: "my"),
    FlagSource(associationCode: "MDA", circleFlagCode: "md"),
    FlagSource(associationCode: "MDV", circleFlagCode: "mv"),
    FlagSource(associationCode: "MEX", circleFlagCode: "mx"),
    FlagSource(associationCode: "MKD", circleFlagCode: "mk"),
    FlagSource(associationCode: "MLI", circleFlagCode: "ml"),
    FlagSource(associationCode: "MLT", circleFlagCode: "mt"),
    FlagSource(associationCode: "MNE", circleFlagCode: "me"),
    FlagSource(associationCode: "MNG", circleFlagCode: "mn"),
    FlagSource(associationCode: "MOZ", circleFlagCode: "mz"),
    FlagSource(associationCode: "MRI", circleFlagCode: "mu"),
    FlagSource(associationCode: "MSR", circleFlagCode: "ms"),
    FlagSource(associationCode: "MTN", circleFlagCode: "mr"),
    FlagSource(associationCode: "MTQ", circleFlagCode: "mq"),
    FlagSource(associationCode: "MWI", circleFlagCode: "mw"),
    FlagSource(associationCode: "MYA", circleFlagCode: "mm"),
    FlagSource(associationCode: "NAM", circleFlagCode: "na"),
    FlagSource(associationCode: "NCA", circleFlagCode: "ni"),
    FlagSource(associationCode: "NCL", circleFlagCode: "nc"),
    FlagSource(associationCode: "NED", circleFlagCode: "nl"),
    FlagSource(associationCode: "NEP", circleFlagCode: "np"),
    FlagSource(associationCode: "NGA", circleFlagCode: "ng"),
    FlagSource(associationCode: "NIG", circleFlagCode: "ne"),
    FlagSource(associationCode: "NIR", circleFlagCode: "gb-nir"),
    FlagSource(associationCode: "NOR", circleFlagCode: "no"),
    FlagSource(associationCode: "NZL", circleFlagCode: "nz"),
    FlagSource(associationCode: "OMA", circleFlagCode: "om"),
    FlagSource(associationCode: "PAK", circleFlagCode: "pk"),
    FlagSource(associationCode: "PAN", circleFlagCode: "pa"),
    FlagSource(associationCode: "PAR", circleFlagCode: "py"),
    FlagSource(associationCode: "PER", circleFlagCode: "pe"),
    FlagSource(associationCode: "PHI", circleFlagCode: "ph"),
    FlagSource(associationCode: "PLE", circleFlagCode: "ps"),
    FlagSource(associationCode: "PNG", circleFlagCode: "pg"),
    FlagSource(associationCode: "POL", circleFlagCode: "pl"),
    FlagSource(associationCode: "POR", circleFlagCode: "pt"),
    FlagSource(associationCode: "PRK", circleFlagCode: "kp"),
    FlagSource(associationCode: "PUR", circleFlagCode: "pr"),
    FlagSource(associationCode: "QAT", circleFlagCode: "qa"),
    FlagSource(associationCode: "ROU", circleFlagCode: "ro"),
    FlagSource(associationCode: "RSA", circleFlagCode: "za"),
    FlagSource(associationCode: "RUS", circleFlagCode: "ru"),
    FlagSource(associationCode: "RWA", circleFlagCode: "rw"),
    FlagSource(associationCode: "SAM", circleFlagCode: "ws"),
    FlagSource(associationCode: "SCO", circleFlagCode: "gb-sct"),
    FlagSource(associationCode: "SDN", circleFlagCode: "sd"),
    FlagSource(associationCode: "SEN", circleFlagCode: "sn"),
    FlagSource(associationCode: "SEY", circleFlagCode: "sc"),
    FlagSource(associationCode: "SIN", circleFlagCode: "sg"),
    FlagSource(associationCode: "SKN", circleFlagCode: "kn"),
    FlagSource(associationCode: "SLE", circleFlagCode: "sl"),
    FlagSource(associationCode: "SLV", circleFlagCode: "sv"),
    FlagSource(associationCode: "SMR", circleFlagCode: "sm"),
    FlagSource(associationCode: "SOL", circleFlagCode: "sb"),
    FlagSource(associationCode: "SOM", circleFlagCode: "so"),
    FlagSource(associationCode: "SRB", circleFlagCode: "rs"),
    FlagSource(associationCode: "SRI", circleFlagCode: "lk"),
    FlagSource(associationCode: "SSD", circleFlagCode: "ss"),
    FlagSource(associationCode: "STP", circleFlagCode: "st"),
    FlagSource(associationCode: "SUI", circleFlagCode: "ch"),
    FlagSource(associationCode: "SUR", circleFlagCode: "sr"),
    FlagSource(associationCode: "SVK", circleFlagCode: "sk"),
    FlagSource(associationCode: "SVN", circleFlagCode: "si"),
    FlagSource(associationCode: "SWE", circleFlagCode: "se"),
    FlagSource(associationCode: "SWZ", circleFlagCode: "sz"),
    FlagSource(associationCode: "SYR", circleFlagCode: "sy"),
    FlagSource(associationCode: "TAH", circleFlagCode: "pf"),
    FlagSource(associationCode: "TAN", circleFlagCode: "tz"),
    FlagSource(associationCode: "TCA", circleFlagCode: "tc"),
    FlagSource(associationCode: "TGA", circleFlagCode: "to"),
    FlagSource(associationCode: "THA", circleFlagCode: "th"),
    FlagSource(associationCode: "TJK", circleFlagCode: "tj"),
    FlagSource(associationCode: "TKM", circleFlagCode: "tm"),
    FlagSource(associationCode: "TLS", circleFlagCode: "tl"),
    FlagSource(associationCode: "TOG", circleFlagCode: "tg"),
    FlagSource(associationCode: "TPE", circleFlagCode: "tw"),
    FlagSource(associationCode: "TRI", circleFlagCode: "tt"),
    FlagSource(associationCode: "TUN", circleFlagCode: "tn"),
    FlagSource(associationCode: "TUR", circleFlagCode: "tr"),
    FlagSource(associationCode: "UAE", circleFlagCode: "ae"),
    FlagSource(associationCode: "UGA", circleFlagCode: "ug"),
    FlagSource(associationCode: "UKR", circleFlagCode: "ua"),
    FlagSource(associationCode: "URU", circleFlagCode: "uy"),
    FlagSource(associationCode: "USA", circleFlagCode: "us"),
    FlagSource(associationCode: "USVI", circleFlagCode: "vi"),
    FlagSource(associationCode: "UZB", circleFlagCode: "uz"),
    FlagSource(associationCode: "VAN", circleFlagCode: "vu"),
    FlagSource(associationCode: "VEN", circleFlagCode: "ve"),
    FlagSource(associationCode: "VGB", circleFlagCode: "vg"),
    FlagSource(associationCode: "VIE", circleFlagCode: "vn"),
    FlagSource(associationCode: "VIN", circleFlagCode: "vc"),
    FlagSource(associationCode: "VIR", circleFlagCode: "vi"),
    FlagSource(associationCode: "WAL", circleFlagCode: "gb-wls"),
    FlagSource(associationCode: "YEM", circleFlagCode: "ye"),
    FlagSource(associationCode: "ZAM", circleFlagCode: "zm"),
    FlagSource(associationCode: "ZIM", circleFlagCode: "zw"),
]

enum ScriptError: Error, CustomStringConvertible {
    case commandFailed(String, [String], Int32, String)
    case missingSource(String)
    case missingThumbnail(String)

    var description: String {
        switch self {
        case let .commandFailed(command, arguments, status, output):
            return "Command failed (\(status)): \(([command] + arguments).joined(separator: " "))\n\(output)"
        case let .missingSource(path):
            return "Missing source SVG: \(path)"
        case let .missingThumbnail(path):
            return "Quick Look did not create a PNG thumbnail for: \(path)"
        }
    }
}

@discardableResult
func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw ScriptError.commandFailed(executable, arguments, process.terminationStatus, output)
    }

    return output
}

func copyLicense(from packageDirectory: URL, to outputDirectory: URL) throws {
    let licenseURL = packageDirectory.appendingPathComponent("LICENSE.md")
    let licenseText = try String(contentsOf: licenseURL, encoding: .utf8)
    let attribution = """
    AlertCalendar football national flag PNGs in this directory are generated from HatScripts/circle-flags \(circleFlagsVersion).

    Source: https://github.com/HatScripts/circle-flags
    Gallery: https://hatscripts.github.io/circle-flags/gallery.html
    Package: https://www.npmjs.com/package/circle-flags/v/\(circleFlagsVersion)

    \(licenseText)
    """

    try attribution.write(
        to: outputDirectory.appendingPathComponent("LICENSE-circle-flags.md"),
        atomically: true,
        encoding: .utf8
    )
}

func removeGeneratedFlags(from directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }

    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    for file in files where file.lastPathComponent.hasPrefix("football-flag-") && file.pathExtension == "png" {
        try FileManager.default.removeItem(at: file)
    }
}

func renderFlag(_ flagSource: FlagSource, packageDirectory: URL, workDirectory: URL) throws {
    let sourceSVG = packageDirectory
        .appendingPathComponent("flags")
        .appendingPathComponent("\(flagSource.circleFlagCode).svg")
    guard FileManager.default.fileExists(atPath: sourceSVG.path) else {
        throw ScriptError.missingSource(sourceSVG.path)
    }

    let thumbnailDirectory = workDirectory
        .appendingPathComponent("thumbnails")
        .appendingPathComponent(flagSource.associationCode.lowercased())
    try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)

    _ = try run("/usr/bin/qlmanage", [
        "-t",
        "-s",
        "512",
        "-o",
        thumbnailDirectory.path,
        sourceSVG.path,
    ])

    let thumbnailURL = thumbnailDirectory.appendingPathComponent("\(sourceSVG.lastPathComponent).png")
    guard FileManager.default.fileExists(atPath: thumbnailURL.path) else {
        throw ScriptError.missingThumbnail(sourceSVG.path)
    }

    let outputURL = outputDirectory.appendingPathComponent(
        "football-flag-\(flagSource.associationCode.lowercased()).png"
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
    }
    try FileManager.default.copyItem(at: thumbnailURL, to: outputURL)
}

do {
    let uniqueFlagSources = Array(Set(flagSources)).sorted {
        $0.associationCode < $1.associationCode
    }
    let workDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("alertcalendar-circle-flags-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workDirectory) }

    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

    let packageOutput = try run("/usr/bin/env", [
        "npm",
        "pack",
        "circle-flags@\(circleFlagsVersion)",
        "--silent",
        "--pack-destination",
        workDirectory.path,
    ])
    let packageFilename = packageOutput
        .split(whereSeparator: \.isNewline)
        .last
        .map(String.init) ?? "circle-flags-\(circleFlagsVersion).tgz"
    let packageArchive = workDirectory.appendingPathComponent(packageFilename)

    _ = try run("/usr/bin/tar", [
        "-xzf",
        packageArchive.path,
        "-C",
        workDirectory.path,
    ])

    let packageDirectory = workDirectory.appendingPathComponent("package")
    try removeGeneratedFlags(from: outputDirectory)

    for flagSource in uniqueFlagSources {
        try renderFlag(flagSource, packageDirectory: packageDirectory, workDirectory: workDirectory)
    }
    try copyLicense(from: packageDirectory, to: outputDirectory)

    print("Generated \(uniqueFlagSources.count) football national flags in \(outputDirectory.path)")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
