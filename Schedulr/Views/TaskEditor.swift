import SwiftUI
import SwiftData

enum TaskEditorMode {
    case create
    case edit(TaskItem)
}

struct TaskEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: TaskEditorMode

    @State private var title: String = ""
    @State private var estimatedMinutes: Int = 30
    @State private var priority: TaskPriority = .normal
    @State private var hasDeadline: Bool = false
    @State private var deadline: Date = .now.addingTimeInterval(60 * 60 * 24)
    @State private var notes: String = ""
    @State private var recurrence: TaskRecurrence = .none

    private static let durationPresets = [15, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Duration") {
                    Picker("Estimate", selection: $estimatedMinutes) {
                        ForEach(Self.durationPresets, id: \.self) { value in
                            Text(format(minutes: value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Custom: \(format(minutes: estimatedMinutes))",
                            value: $estimatedMinutes, in: 5...600, step: 5)
                }
                Section("Deadline") {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("By", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section {
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(TaskRecurrence.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Recurrence")
                } footer: {
                    if recurrence != .none {
                        Text("Each time you generate, this task appears in the pending list for the day if it hasn't already been scheduled. Applying creates a one-off scheduled copy and leaves this template for the next occurrence.")
                    }
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadIfEditing)
        }
    }

    private var navTitle: String {
        if case .edit = mode { return "Edit Task" }
        return "New Task"
    }

    private func loadIfEditing() {
        if case let .edit(task) = mode {
            title = task.title
            estimatedMinutes = task.estimatedMinutes
            priority = task.priority
            hasDeadline = task.deadline != nil
            if let d = task.deadline { deadline = d }
            notes = task.notes ?? ""
            recurrence = task.recurrence
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let cleanedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDeadline = hasDeadline ? deadline : nil
        let resolvedNotes = cleanedNotes.isEmpty ? nil : cleanedNotes

        switch mode {
        case .create:
            let task = TaskItem(
                title: trimmed,
                estimatedMinutes: estimatedMinutes,
                priority: priority,
                deadline: resolvedDeadline,
                notes: resolvedNotes,
                recurrence: recurrence
            )
            modelContext.insert(task)
        case .edit(let task):
            task.title = trimmed
            task.estimatedMinutes = estimatedMinutes
            task.priority = priority
            task.deadline = resolvedDeadline
            task.notes = resolvedNotes
            task.recurrence = recurrence
        }
        dismiss()
    }

    private func format(minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60) hr" }
        if minutes >= 60 { return "\(minutes / 60) hr \(minutes % 60) min" }
        return "\(minutes) min"
    }
}

#Preview("Create") {
    TaskEditor(mode: .create)
        .modelContainer(for: TaskItem.self, inMemory: true)
}
