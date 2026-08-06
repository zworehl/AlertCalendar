import XCTest
@testable import AlertCalendar

final class SlackStatusSyncSchedulingTests: SlackStatusSyncTestCase {
    func testSlackHeartbeatUsesOneMinuteFallback() {
        XCTAssertEqual(CalendarMonitorCadence.slackStatusHeartbeatInterval, 60)
        XCTAssertEqual(CalendarMonitorCadence.slackDynamicStatusRotationInterval, 30)
    }

    func testSlackStatusSyncTaskStartRequiresPendingWorkAndNoRunningTask() {
        XCTAssertTrue(
            CalendarMonitor.shouldStartSlackStatusSyncTask(
                hasRunningTask: false,
                needsAnotherPass: true
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldStartSlackStatusSyncTask(
                hasRunningTask: true,
                needsAnotherPass: true
            )
        )
        XCTAssertFalse(
            CalendarMonitor.shouldStartSlackStatusSyncTask(
                hasRunningTask: false,
                needsAnotherPass: false
            )
        )
    }

    func testSlackStatusSyncTaskTimeoutUsesConfiguredBoundary() {
        let now = Date(timeIntervalSince1970: 1_777_000_100)
        XCTAssertFalse(
            CalendarMonitor.slackStatusSyncTaskTimedOut(
                startedAt: nil,
                now: now,
                timeout: 45
            )
        )
        XCTAssertFalse(
            CalendarMonitor.slackStatusSyncTaskTimedOut(
                startedAt: now.addingTimeInterval(-44),
                now: now,
                timeout: 45
            )
        )
        XCTAssertTrue(
            CalendarMonitor.slackStatusSyncTaskTimedOut(
                startedAt: now.addingTimeInterval(-45),
                now: now,
                timeout: 45
            )
        )
    }

    func testSlackStatusSyncTargetEqualityIgnoresConnectionMetadataRefresh() {
        let baseConnection = makeConnection(
            id: "T1|U1",
            workspaceImageURLString: nil,
            profileImageURLString: nil,
            lastValidatedAt: Date(timeIntervalSince1970: 100)
        )
        let refreshedConnection = makeConnection(
            id: "T1|U1",
            workspaceImageURLString: "https://workspace.example/icon.png",
            profileImageURLString: "https://workspace.example/profile.png",
            lastValidatedAt: Date(timeIntervalSince1970: 200)
        )
        let snapshot = SlackProfileStatusSnapshot(
            statusText: "In a meeting",
            statusEmoji: "🗓️",
            statusExpiration: 1_777_000_600
        )

        XCTAssertEqual(
            CalendarMonitor.SlackStatusSyncTarget(
                connection: baseConnection,
                mode: .meeting(snapshot: snapshot)
            ),
            CalendarMonitor.SlackStatusSyncTarget(
                connection: refreshedConnection,
                mode: .meeting(snapshot: snapshot)
            )
        )
        XCTAssertNotEqual(
            CalendarMonitor.SlackStatusSyncTarget(
                connection: baseConnection,
                mode: .meeting(snapshot: snapshot)
            ),
            CalendarMonitor.SlackStatusSyncTarget(
                connection: makeConnection(id: "T2|U1"),
                mode: .meeting(snapshot: snapshot)
            )
        )
    }

    func testSlackMeetingStatusExpirationUsesLatestEndAcrossSelectedCalendar() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let selectedCalendarID = "work-calendar"
        let items = [
            makeEvent(
                id: "first",
                title: "Standup",
                calendarID: selectedCalendarID,
                startDate: now.addingTimeInterval(-10 * 60),
                endDate: now.addingTimeInterval(20 * 60)
            ),
            makeEvent(
                id: "second",
                title: "Planning",
                calendarID: selectedCalendarID,
                startDate: now.addingTimeInterval(-5 * 60),
                endDate: now.addingTimeInterval(55 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.slackMeetingStatusExpirationTimestamp(
                for: items,
                calendarID: selectedCalendarID,
                now: now
            ),
            Int(now.addingTimeInterval(55 * 60).timeIntervalSince1970)
        )
    }

    func testSlackMeetingStatusExpirationIgnoresAllDayAndOtherCalendars() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let selectedCalendarID = "work-calendar"
        let items = [
            makeEvent(
                id: "other",
                title: "Other Team",
                calendarID: "different-calendar",
                startDate: now.addingTimeInterval(-15 * 60),
                endDate: now.addingTimeInterval(30 * 60)
            ),
            makeEvent(
                id: "all-day",
                title: "Conference",
                calendarID: selectedCalendarID,
                startDate: now.addingTimeInterval(-2 * 60 * 60),
                endDate: now.addingTimeInterval(5 * 60 * 60),
                isAllDay: true
            ),
        ]

        XCTAssertNil(
            CalendarMonitor.slackMeetingStatusExpirationTimestamp(
                for: items,
                calendarID: selectedCalendarID,
                now: now
            )
        )
    }

    func testSlackMeetingStatusExpirationIgnoresMutedParticipationEvents() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let selectedCalendarID = "work-calendar"
        let items = [
            makeEvent(
                id: "tentative",
                title: "Tentative hold",
                calendarID: selectedCalendarID,
                startDate: now.addingTimeInterval(-10 * 60),
                endDate: now.addingTimeInterval(20 * 60),
                showsMutedBackground: true
            ),
        ]

        XCTAssertNil(
            CalendarMonitor.slackMeetingStatusExpirationTimestamp(
                for: items,
                calendarID: selectedCalendarID,
                now: now
            )
        )
    }

    func testActiveSlackRuleStateKeepsStatusAliveAcrossOverlappingMeetings() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "Heads down",
                statusEmoji: "🎯",
                isEnabled: true
            ),
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-2",
                statusText: "In a meeting",
                statusEmoji: "🗓️",
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "first",
                title: "Planning",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-15 * 60),
                endDate: now.addingTimeInterval(20 * 60)
            ),
            makeEvent(
                id: "second",
                title: "Review",
                calendarID: "calendar-2",
                startDate: now.addingTimeInterval(-5 * 60),
                endDate: now.addingTimeInterval(50 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: now
            ),
            [
                connectionID: CalendarMonitor.SlackActiveRuleState(
                    statusText: "Heads down",
                    statusEmoji: "🎯",
                    expiration: Int(now.addingTimeInterval(50 * 60).timeIntervalSince1970)
                ),
            ]
        )
    }

    func testActiveSlackRuleStateUsesRuleOrderAsPriority() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-2",
                statusText: "Pairing",
                statusEmoji: "💬",
                isEnabled: true
            ),
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "Heads down",
                statusEmoji: "🎯",
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "first",
                title: "Focus",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-10 * 60),
                endDate: now.addingTimeInterval(20 * 60)
            ),
            makeEvent(
                id: "second",
                title: "Pairing",
                calendarID: "calendar-2",
                startDate: now.addingTimeInterval(-5 * 60),
                endDate: now.addingTimeInterval(35 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: now
            ),
            [
                connectionID: CalendarMonitor.SlackActiveRuleState(
                    statusText: "Pairing",
                    statusEmoji: "💬",
                    expiration: Int(now.addingTimeInterval(35 * 60).timeIntervalSince1970)
                ),
            ]
        )
    }

    func testActiveSlackRuleStateUsesEventTitleWhenRuleRequestsDynamicText() {
        let now = Date(timeIntervalSince1970: 90)
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "In a meeting",
                statusEmoji: "💬",
                statusTextSource: .eventTitle,
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "event-title",
                title: "Design Review",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-10 * 60),
                endDate: now.addingTimeInterval(20 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: now
            ),
            [
                connectionID: CalendarMonitor.SlackActiveRuleState(
                    statusText: "Design Review",
                    statusEmoji: "💬",
                    expiration: Int(now.addingTimeInterval(20 * 60).timeIntervalSince1970)
                ),
            ]
        )
    }

    func testActiveSlackRuleStateRotatesConcurrentDynamicEventTitlesEveryThirtySeconds() {
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "In a meeting",
                statusEmoji: "🗓️",
                statusTextSource: .eventTitle,
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "alpha",
                title: "Alpha Review",
                calendarID: "calendar-1",
                startDate: Date(timeIntervalSince1970: 10),
                endDate: Date(timeIntervalSince1970: 300)
            ),
            makeEvent(
                id: "beta",
                title: "Beta Planning",
                calendarID: "calendar-1",
                startDate: Date(timeIntervalSince1970: 10),
                endDate: Date(timeIntervalSince1970: 300)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: Date(timeIntervalSince1970: 91)
            )[connectionID]?.statusText,
            "Beta Planning"
        )
        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: Date(timeIntervalSince1970: 121)
            )[connectionID]?.statusText,
            "Alpha Review"
        )
    }

    func testNextSlackStatusSyncTransitionDateUsesDynamicRotationBoundary() {
        let now = Date(timeIntervalSince1970: 91)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                statusTextSource: .eventTitle,
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "alpha",
                title: "Alpha Review",
                calendarID: "calendar-1",
                startDate: Date(timeIntervalSince1970: 10),
                endDate: Date(timeIntervalSince1970: 300)
            ),
            makeEvent(
                id: "beta",
                title: "Beta Planning",
                calendarID: "calendar-1",
                startDate: Date(timeIntervalSince1970: 10),
                endDate: Date(timeIntervalSince1970: 300)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            Date(timeIntervalSince1970: 120)
        )
    }

    func testActiveSlackRuleStateUsesRemainingMeetingAfterSkippedOverlapDropsOut() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "In a meeting",
                statusEmoji: "🗓️",
                isEnabled: true
            ),
        ]

        let remainingVisibleItems = [
            makeEvent(
                id: "still-active",
                title: "1:1",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-3 * 60),
                endDate: now.addingTimeInterval(35 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: remainingVisibleItems,
                rules: rules,
                now: now
            ),
            [
                connectionID: CalendarMonitor.SlackActiveRuleState(
                    statusText: "In a meeting",
                    statusEmoji: "🗓️",
                    expiration: Int(now.addingTimeInterval(35 * 60).timeIntervalSince1970)
                ),
            ]
        )
    }

    func testNextSlackStatusSyncTransitionDateUsesCurrentMeetingEndWhenAppOpensMidMeeting() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                isEnabled: true
            ),
        ]
        let meetingEnd = now.addingTimeInterval(18 * 60)
        let items = [
            makeEvent(
                id: "active",
                title: "Active meeting",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-12 * 60),
                endDate: meetingEnd
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            meetingEnd
        )
    }

    func testUpcomingMeetingDoesNotSetSlackStatusWhenPreEventOptionIsDisabled() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let meetingStart = now.addingTimeInterval(10 * 60)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                startsBeforeEvent: false,
                leadMinutes: 15,
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "upcoming",
                title: "Design Review",
                calendarID: "calendar-1",
                startDate: meetingStart,
                endDate: now.addingTimeInterval(40 * 60)
            ),
        ]

        XCTAssertTrue(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: now
            ).isEmpty
        )
        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            meetingStart
        )
    }

    func testPreEventSlackStatusStartsInsideConfiguredLeadWindow() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let meetingStart = now.addingTimeInterval(10 * 60)
        let meetingEnd = now.addingTimeInterval(40 * 60)
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "In progress",
                statusEmoji: "⏳",
                startsBeforeEvent: true,
                leadMinutes: 15,
                preEventStatusText: "Joining in a few minutes",
                preEventStatusEmoji: "🔜",
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "upcoming",
                title: "Design Review",
                calendarID: "calendar-1",
                startDate: meetingStart,
                endDate: meetingEnd
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: now
            ),
            [
                connectionID: CalendarMonitor.SlackActiveRuleState(
                    statusText: "Joining in a few minutes",
                    statusEmoji: "🔜",
                    expiration: Int(meetingEnd.timeIntervalSince1970)
                ),
            ]
        )
        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            meetingStart
        )
    }

    func testNextSlackStatusSyncTransitionDateUsesPreEventLeadBoundary() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let meetingStart = now.addingTimeInterval(45 * 60)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                startsBeforeEvent: true,
                leadMinutes: 15,
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "upcoming",
                title: "Planning",
                calendarID: "calendar-1",
                startDate: meetingStart,
                endDate: now.addingTimeInterval(75 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            meetingStart.addingTimeInterval(-15 * 60)
        )
    }

    func testSlackStatusSwitchesFromCustomPreEventTextToActiveTextAtStart() {
        let meetingStart = Date(timeIntervalSince1970: 1_777_000_000)
        let meetingEnd = meetingStart.addingTimeInterval(30 * 60)
        let connectionID = "T1|U1"
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusText: "In the meeting",
                startsBeforeEvent: true,
                leadMinutes: 10,
                preEventStatusText: "Joining shortly",
                preEventStatusEmoji: "⌛️",
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "meeting",
                title: "Planning",
                calendarID: "calendar-1",
                startDate: meetingStart,
                endDate: meetingEnd
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: meetingStart.addingTimeInterval(-5 * 60)
            )[connectionID]?.statusText,
            "Joining shortly"
        )
        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: meetingStart.addingTimeInterval(-5 * 60)
            )[connectionID]?.statusEmoji,
            "⌛️"
        )
        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: meetingStart
            )[connectionID]?.statusText,
            "In the meeting"
        )
    }

    func testActiveMeetingTakesPriorityOverHigherPriorityUpcomingMeeting() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let connectionID = "T1|U1"
        let activeEnd = now.addingTimeInterval(20 * 60)
        let upcomingEnd = now.addingTimeInterval(50 * 60)
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-upcoming",
                statusText: "In progress soon",
                statusEmoji: "⏳",
                startsBeforeEvent: true,
                leadMinutes: 15,
                preEventStatusText: "Starting soon",
                isEnabled: true
            ),
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-active",
                statusText: "In progress",
                statusEmoji: "🗓️",
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "upcoming",
                title: "Planning",
                calendarID: "calendar-upcoming",
                startDate: now.addingTimeInterval(10 * 60),
                endDate: upcomingEnd
            ),
            makeEvent(
                id: "active",
                title: "Standup",
                calendarID: "calendar-active",
                startDate: now.addingTimeInterval(-5 * 60),
                endDate: activeEnd
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: now
            ),
            [
                connectionID: CalendarMonitor.SlackActiveRuleState(
                    statusText: "In progress",
                    statusEmoji: "🗓️",
                    expiration: Int(upcomingEnd.timeIntervalSince1970)
                ),
            ]
        )
    }

    func testPreEventStatusUsesCustomTextWhenActiveStatusUsesEventTitle() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let connectionID = "T1|U1"
        let meetingEnd = now.addingTimeInterval(35 * 60)
        let rules = [
            SlackStatusSyncRule(
                connectionID: connectionID,
                calendarID: "calendar-1",
                statusTextSource: .eventTitle,
                startsBeforeEvent: true,
                leadMinutes: 10,
                preEventStatusText: "Getting ready",
                preEventStatusEmoji: "🔜",
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "upcoming",
                title: "Architecture Review",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(5 * 60),
                endDate: meetingEnd
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.activeSlackRuleStateByConnectionID(
                for: items,
                rules: rules,
                now: now
            )[connectionID],
            CalendarMonitor.SlackActiveRuleState(
                statusText: "Getting ready",
                statusEmoji: "🔜",
                expiration: Int(meetingEnd.timeIntervalSince1970)
            )
        )
    }

    func testNextSlackStatusSyncTransitionDateIgnoresMutedParticipationEvents() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                startsBeforeEvent: true,
                leadMinutes: 15,
                isEnabled: true
            ),
        ]
        let items = [
            makeEvent(
                id: "tentative",
                title: "Tentative hold",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(10 * 60),
                endDate: now.addingTimeInterval(40 * 60),
                showsMutedBackground: true
            ),
        ]

        XCTAssertNil(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            )
        )
    }

    func testSlackRestoredStatusClearsPreviousCalendarManagedStatus() {
        let managedStatus = SlackProfileStatusSnapshot(
            statusText: "In a meeting",
            statusEmoji: ":spiral_calendar_pad:",
            statusExpiration: 1_777_000_600
        )
        let state = CalendarMonitor.SlackManagedStatusState(
            previousStatus: SlackProfileStatusSnapshot(
                statusText: "In a meeting",
                statusEmoji: "🗓️",
                statusExpiration: 1_777_000_300
            ),
            requestedStatus: managedStatus,
            managedStatus: managedStatus
        )

        XCTAssertEqual(
            CalendarMonitor.slackRestoredStatus(from: state),
            SlackProfileStatusSnapshot(statusText: "", statusEmoji: "", statusExpiration: 0)
        )
    }

    func testSlackRestoredStatusPreservesDistinctPreviousStatus() {
        let previousStatus = SlackProfileStatusSnapshot(
            statusText: "Heads down",
            statusEmoji: "🎯",
            statusExpiration: 0
        )
        let state = CalendarMonitor.SlackManagedStatusState(
            previousStatus: previousStatus,
            requestedStatus: SlackProfileStatusSnapshot(
                statusText: "In a meeting",
                statusEmoji: "🗓️",
                statusExpiration: 1_777_000_600
            ),
            managedStatus: SlackProfileStatusSnapshot(
                statusText: "In a meeting",
                statusEmoji: ":spiral_calendar_pad:",
                statusExpiration: 1_777_000_600
            )
        )

        XCTAssertEqual(CalendarMonitor.slackRestoredStatus(from: state), previousStatus)
    }

    func testNextSlackStatusSyncTransitionDateUsesOverlapStartBeforeCurrentMeetingEnds() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                isEnabled: true
            ),
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-2",
                isEnabled: true
            ),
        ]
        let overlappingStart = now.addingTimeInterval(10 * 60)
        let items = [
            makeEvent(
                id: "current",
                title: "Current",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-20 * 60),
                endDate: now.addingTimeInterval(30 * 60)
            ),
            makeEvent(
                id: "overlap",
                title: "Overlap",
                calendarID: "calendar-2",
                startDate: overlappingStart,
                endDate: now.addingTimeInterval(55 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            overlappingStart
        )
    }

    func testNextSlackStatusSyncTransitionDateUsesSharedBoundaryForConsecutiveMeetings() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let rules = [
            SlackStatusSyncRule(
                connectionID: "T1|U1",
                calendarID: "calendar-1",
                isEnabled: true
            ),
        ]
        let sharedBoundary = now.addingTimeInterval(25 * 60)
        let items = [
            makeEvent(
                id: "first",
                title: "First",
                calendarID: "calendar-1",
                startDate: now.addingTimeInterval(-15 * 60),
                endDate: sharedBoundary
            ),
            makeEvent(
                id: "second",
                title: "Second",
                calendarID: "calendar-1",
                startDate: sharedBoundary,
                endDate: now.addingTimeInterval(50 * 60)
            ),
        ]

        XCTAssertEqual(
            CalendarMonitor.nextSlackStatusSyncTransitionDate(
                for: items,
                rules: rules,
                now: now
            ),
            sharedBoundary
        )
    }

    private func makeConnection(
        id: String,
        workspaceImageURLString: String? = nil,
        profileImageURLString: String? = nil,
        lastValidatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> SlackConnection {
        let ids = id.split(separator: "|", maxSplits: 1).map(String.init)
        let teamID = ids.first ?? "T1"
        let userID = ids.dropFirst().first ?? "U1"
        return SlackConnection(
            id: id,
            teamID: teamID,
            teamName: "Workspace",
            workspaceURLString: "https://workspace.example/",
            workspaceImageURLString: workspaceImageURLString,
            userID: userID,
            userName: "sam",
            userDisplayName: "Sam",
            emailAddress: "sam@example.com",
            profileImageURLString: profileImageURLString,
            connectedAt: Date(timeIntervalSince1970: 50),
            lastValidatedAt: lastValidatedAt
        )
    }
}
