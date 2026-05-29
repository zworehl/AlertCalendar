import EventKit
import Foundation

enum EventMeetingURLResolver {
    static func meetingURL(for event: EKEvent) -> URL? {
        MeetingURLResolver.bestMeetingURL(from: meetingURLCandidates(for: event))
    }

    static func meetingURLCandidates(for event: EKEvent) -> [URL] {
        var candidates: [URL] = []

        if let url = event.url {
            candidates.append(url)
        }
        if let notes = event.notes {
            candidates.append(contentsOf: MeetingURLResolver.allURLs(in: notes))
        }
        if let location = event.location {
            candidates.append(contentsOf: MeetingURLResolver.allURLs(in: location))
        }

        appendEventKitConferenceCandidates(for: event, to: &candidates)
        return candidates
    }

    private static func appendEventKitConferenceCandidates(for event: EKEvent, to candidates: inout [URL]) {
        let eventObject = event as NSObject
        let eventSelectors = [
            "conferenceURL",
            "conferenceURLForDisplay",
            "conferenceURLString",
            "conferenceURLDetectedString",
            "virtualConferenceTextRepresentation",
        ]

        for selectorName in eventSelectors {
            appendSelectorValue(selectorName, on: eventObject, to: &candidates)
        }

        guard let virtualConference = selectorValue("virtualConference", on: eventObject) as? NSObject else {
            return
        }

        appendSelectorValue("urlWithAllowedScheme", on: virtualConference, to: &candidates)
        appendSelectorValue("conferenceDetails", on: virtualConference, to: &candidates)

        guard let joinMethods = selectorValue("joinMethods", on: virtualConference) else {
            return
        }
        for joinMethod in arrayValues(from: joinMethods) {
            guard let joinMethodObject = joinMethod as? NSObject else { continue }
            appendSelectorValue("URL", on: joinMethodObject, to: &candidates)
        }
    }

    private static func appendSelectorValue(_ selectorName: String, on object: NSObject, to candidates: inout [URL]) {
        guard let value = selectorValue(selectorName, on: object) else { return }
        appendCandidates(from: value, to: &candidates)
    }

    private static func selectorValue(_ selectorName: String, on object: NSObject) -> Any? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let result = object.perform(selector) else {
            return nil
        }
        return result.takeUnretainedValue()
    }

    private static func appendCandidates(from value: Any, to candidates: inout [URL]) {
        if let url = value as? URL {
            candidates.append(url)
            return
        }

        if let string = value as? String {
            if let directURL = URL(string: string) {
                candidates.append(directURL)
            }
            candidates.append(contentsOf: MeetingURLResolver.allURLs(in: string))
            return
        }

        for item in arrayValues(from: value) {
            appendCandidates(from: item, to: &candidates)
        }
    }

    private static func arrayValues(from value: Any) -> [Any] {
        if let array = value as? [Any] {
            return array
        }
        if let array = value as? NSArray {
            return array.map { $0 }
        }
        return []
    }
}
