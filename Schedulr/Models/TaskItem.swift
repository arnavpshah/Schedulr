import Foundation
import SwiftData

enum TaskStatus: String, Codable, CaseIterable {
    case pending
    case scheduled
    case completed
}

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 0
    case normal = 1
    case high = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

enum TaskRecurrence: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekdays
    case weekly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Doesn't repeat"
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        }
    }

    func appliesTo(_ date: Date, weeklyAnchor: Date?) -> Bool {
        let cal = Calendar.current
        switch self {
        case .none:
            return false
        case .daily:
            return true
        case .weekdays:
            let weekday = cal.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6
        case .weekly:
            guard let anchor = weeklyAnchor else { return false }
            return cal.component(.weekday, from: date) == cal.component(.weekday, from: anchor)
        }
    }
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var estimatedMinutes: Int
    var priorityRaw: Int
    var deadline: Date?
    var notes: String?
    var statusRaw: String
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var calendarEventID: String?
    var createdAt: Date
    var recurrenceRaw: String = TaskRecurrence.none.rawValue
    var sourceTemplateID: UUID? = nil

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var recurrence: TaskRecurrence {
        get { TaskRecurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    var isRecurringTemplate: Bool { recurrence != .none }

    init(
        id: UUID = UUID(),
        title: String,
        estimatedMinutes: Int,
        priority: TaskPriority = .normal,
        deadline: Date? = nil,
        notes: String? = nil,
        status: TaskStatus = .pending,
        scheduledStart: Date? = nil,
        scheduledEnd: Date? = nil,
        calendarEventID: String? = nil,
        createdAt: Date = .now,
        recurrence: TaskRecurrence = .none,
        sourceTemplateID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.priorityRaw = priority.rawValue
        self.deadline = deadline
        self.notes = notes
        self.statusRaw = status.rawValue
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.calendarEventID = calendarEventID
        self.createdAt = createdAt
        self.recurrenceRaw = recurrence.rawValue
        self.sourceTemplateID = sourceTemplateID
    }
}
