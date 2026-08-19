import Foundation

extension CalendarMonitor {
    func requestAgendaSummary(_ request: AgendaSummaryRequest, force: Bool = false) {
        guard currentSettings.showAgendaSummary else {
            cancelAgendaSummary()
            return
        }

        refreshAgendaSummaryAvailability()
        guard agendaSummaryAvailability.isAvailable else {
            cancelAgendaSummary()
            return
        }

        let usesLinkedPagePreviews = currentSettings.useLinkedPagePreviewsInAgendaSummary
        var fingerprintHasher = Hasher()
        fingerprintHasher.combine(request.fingerprint)
        fingerprintHasher.combine(usesLinkedPagePreviews)
        let requestFingerprint = fingerprintHasher.finalize()

        if request.items.isEmpty {
            agendaSummaryTask?.cancel()
            agendaSummaryTask = nil
            agendaSummaryRequestFingerprint = requestFingerprint
            agendaSummaryState = .ready("Nothing is scheduled in this window.")
            return
        }

        guard force || agendaSummaryRequestFingerprint != requestFingerprint else {
            return
        }

        agendaSummaryTask?.cancel()
        agendaSummaryRequestFingerprint = requestFingerprint
        agendaSummaryState = .loading
        agendaSummaryGenerationErrorDescription = nil
        let client = agendaSummaryClient
        let linkPreviewProvider = agendaSummaryLinkPreviewProvider

        agendaSummaryTask = Task { [weak self] in
            do {
                let generationRequest: AgendaSummaryRequest
                if usesLinkedPagePreviews {
                    generationRequest = await linkPreviewProvider.requestByAddingLinkedPagePreviews(request)
                    try Task.checkCancellation()
                } else {
                    generationRequest = request
                }
                let summary = try await client.generateSummary(for: generationRequest)
                try Task.checkCancellation()
                guard let self,
                      self.agendaSummaryRequestFingerprint == requestFingerprint else {
                    return
                }
                self.agendaSummaryState = .ready(summary)
                self.agendaSummaryGenerationErrorDescription = nil
                self.agendaSummaryTask = nil
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.agendaSummaryRequestFingerprint == requestFingerprint else {
                    return
                }
                CalendarMonitorLog.agendaSummary.error(
                    "Could not generate the local agenda summary: \(String(describing: error), privacy: .public)"
                )
                self.refreshAgendaSummaryAvailability()
                self.agendaSummaryState = .unavailable
                if self.agendaSummaryAvailability.isAvailable {
                    self.agendaSummaryGenerationErrorDescription = "Apple Intelligence couldn't generate the latest agenda summary. It will try again when the visible agenda changes."
                }
                self.agendaSummaryTask = nil
            }
        }
    }

    func refreshAgendaSummaryAvailability() {
        let availability = agendaSummaryClient.availability
        guard availability != agendaSummaryAvailability else { return }
        agendaSummaryAvailability = availability
        agendaSummaryGenerationErrorDescription = nil
        if !availability.isAvailable {
            cancelAgendaSummary()
        }
    }

    func cancelAgendaSummary() {
        agendaSummaryTask?.cancel()
        agendaSummaryTask = nil
        agendaSummaryRequestFingerprint = nil
        agendaSummaryState = .idle
    }
}
