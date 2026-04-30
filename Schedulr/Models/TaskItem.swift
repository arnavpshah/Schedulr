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

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

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
        createdAt: Date = .now
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
    }
}
