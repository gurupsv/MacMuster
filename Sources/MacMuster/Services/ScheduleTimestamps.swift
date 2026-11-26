import Foundation

/// Pure helpers behind the "last checked / next check" lines in Settings, so the wording rules
/// can be unit-tested without a live timer or window.
enum ScheduleTimestamps {
    /// When the automatic update check will next be allowed to run.
    enum NextUpdateCheck: Equatable {
        /// Never checked, or already due: the next launch (or enabling the setting) checks.
        case nextLaunch
        /// Not due before this date. The check itself still only happens at launch or when the
        /// setting is switched on: there is no timer, which keeps the network contract at
        /// "at most once per 24 h, on launch".
        case onLaunchAfter(Date)
    }

    nonisolated static func nextUpdateCheck(lastCheck: Date?, now: Date,
                                            interval: TimeInterval = UpdateMetrics.automaticCheckInterval) -> NextUpdateCheck {
        guard let lastCheck else { return .nextLaunch }
        let due = lastCheck.addingTimeInterval(interval)
        // A last-check date in the future (clock change) must not push the next check out
        // indefinitely; this mirrors `UpdateChecker.isCheckDue`.
        guard now < due, now >= lastCheck else { return .nextLaunch }
        return .onLaunchAfter(due)
    }

    /// Time only for today ("5:02 PM"), date and time otherwise ("Nov 27, 5:02 PM"), in the
    /// user's locale and calendar.
    nonisolated static func display(_ date: Date, now: Date = Date(),
                                    calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        if !calendar.isDate(date, inSameDayAs: now) {
            style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: calendar)
        }
        return date.formatted(style)
    }
}
