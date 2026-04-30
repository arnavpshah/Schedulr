import Foundation
import EventKit

struct BusyBlock: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarColor: CGColor?

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum CalendarAuthState {
    case notDetermined
    case denied
    case writeOnly
    case authorized
}

@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()
    var authState: CalendarAuthState = .notDetermined

    init() {
        refreshAuthState()
    }

    func refreshAuthState() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined: authState = .notDetermined
        case .denied, .restricted: authState = .denied
        case .writeOnly: authState = .writeOnly
        case .fullAccess, .authorized: authState = .authorized
        @unknown default: authState = .notDetermined
        }
    }

    func requestFullAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshAuthState()
            return granted
        } catch {
            refreshAuthState()
            return false
        }
    }

    func events(on day: Date) -> [BusyBlock] {
        guard authState == .authorized else { return [] }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
        return events.map { event in
            BusyBlock(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "(No title)",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarColor: event.calendar?.cgColor
            )
        }
        .sorted { $0.start < $1.start }
    }
}
