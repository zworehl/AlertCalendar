import Foundation

extension CalendarMonitor {
    nonisolated private static let agendaSummaryRetryIntervals: [TimeInterval] = [
        60,
        5 * 60,
        15 * 60,
    ]

    nonisolated static func agendaSummaryRetryDelay(forAttempt attempt: Int) -> TimeInterval? {
        guard agendaSummaryRetryIntervals.indices.contains(attempt) else { return nil }
        return agendaSummaryRetryIntervals[attempt]
    }

    func requestAgendaSummary(_ request: AgendaSummaryRequest) {
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
        let requestFingerprint = request.generationFingerprint(
            usesLinkedPagePreviews: usesLinkedPagePreviews
        )

        if request.items.isEmpty {
            agendaSummaryTask?.cancel()
            agendaSummaryTask = nil
            resetAgendaSummaryRetryState()
            agendaSummaryRequestFingerprint = requestFingerprint
            agendaSummaryState = .ready("Nothing is scheduled in this window.")
            return
        }

        guard agendaSummaryRequestFingerprint != requestFingerprint else {
            return
        }

        agendaSummaryTask?.cancel()
        resetAgendaSummaryRetryState()
        agendaSummaryRequestFingerprint = requestFingerprint
        generateAgendaSummary(
            request,
            requestFingerprint: requestFingerprint,
            usesLinkedPagePreviews: usesLinkedPagePreviews
        )
    }

    private func generateAgendaSummary(
        _ request: AgendaSummaryRequest,
        requestFingerprint: Int,
        usesLinkedPagePreviews: Bool
    ) {
        let immediateSummary = AgendaSummaryFallback.summary(for: request)
        agendaSummaryState = .ready(immediateSummary)
        agendaSummaryGenerationErrorDescription = nil
        let client = agendaSummaryClient
        let attachmentPreviewProvider = agendaSummaryAttachmentPreviewProvider
        let linkPreviewProvider = agendaSummaryLinkPreviewProvider

        agendaSummaryTask = Task { [weak self] in
            var fallbackSummary = immediateSummary
            do {
                var generationRequest = await attachmentPreviewProvider
                    .requestByAddingAttachmentPreviews(request)
                try Task.checkCancellation()
                if usesLinkedPagePreviews {
                    generationRequest = await linkPreviewProvider
                        .requestByAddingLinkedPagePreviews(generationRequest)
                    try Task.checkCancellation()
                }
                fallbackSummary = AgendaSummaryFallback.summary(for: generationRequest)
                let summary = try await client.generateSummary(for: generationRequest)
                try Task.checkCancellation()
                guard let self,
                      self.agendaSummaryRequestFingerprint == requestFingerprint else {
                    return
                }
                self.agendaSummaryState = .ready(summary)
                self.agendaSummaryGenerationErrorDescription = nil
                self.resetAgendaSummaryRetryState()
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
                guard self.agendaSummaryAvailability.isAvailable else {
                    self.agendaSummaryTask = nil
                    return
                }

                self.agendaSummaryState = .ready(fallbackSummary)
                let retryAttempt = self.agendaSummaryRetryAttempt
                if let retryDelay = Self.agendaSummaryRetryDelay(forAttempt: retryAttempt) {
                    self.agendaSummaryGenerationErrorDescription = Self.agendaSummaryRetryDescription(
                        delay: retryDelay
                    )
                    self.scheduleAgendaSummaryRetry(
                        request,
                        requestFingerprint: requestFingerprint,
                        usesLinkedPagePreviews: usesLinkedPagePreviews,
                        retryAttempt: retryAttempt,
                        delay: retryDelay
                    )
                } else {
                    self.agendaSummaryGenerationErrorDescription = "Apple Intelligence couldn't generate the latest agenda summary. It will try again after the visible agenda changes."
                }
                self.agendaSummaryTask = nil
            }
        }
    }

    private func scheduleAgendaSummaryRetry(
        _ request: AgendaSummaryRequest,
        requestFingerprint: Int,
        usesLinkedPagePreviews: Bool,
        retryAttempt: Int,
        delay: TimeInterval
    ) {
        agendaSummaryRetryTask?.cancel()
        agendaSummaryRetryAttempt = retryAttempt + 1
        agendaSummaryRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: CalendarMonitorTime.nanoseconds(forDelay: delay)
                )
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.agendaSummaryRetryTask = nil
            guard self.currentSettings.useLinkedPagePreviewsInAgendaSummary == usesLinkedPagePreviews,
                  self.currentSettings.agendaSummaryMaximumWords == request.maximumWords,
                  self.currentSettings.showAgendaSummary,
                  self.agendaSummaryAvailability.isAvailable,
                  self.agendaSummaryRequestFingerprint == requestFingerprint else {
                return
            }

            self.generateAgendaSummary(
                request,
                requestFingerprint: requestFingerprint,
                usesLinkedPagePreviews: usesLinkedPagePreviews
            )
        }
    }

    nonisolated private static func agendaSummaryRetryDescription(delay: TimeInterval) -> String {
        let minutes = max(1, Int(delay / 60))
        return "Apple Intelligence couldn't generate the latest agenda summary. It will retry automatically in about \(minutes) minute\(minutes == 1 ? "" : "s")."
    }

    private func resetAgendaSummaryRetryState() {
        agendaSummaryRetryTask?.cancel()
        agendaSummaryRetryTask = nil
        agendaSummaryRetryAttempt = 0
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
        resetAgendaSummaryRetryState()
        agendaSummaryRequestFingerprint = nil
        if agendaSummaryState != .idle {
            agendaSummaryState = .idle
        }
        agendaSummaryGenerationErrorDescription = nil
    }
}
