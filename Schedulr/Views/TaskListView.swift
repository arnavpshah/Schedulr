import SwiftUI
import SwiftData

struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\TaskItem.createdAt, order: .reverse)])
    private var tasks: [TaskItem]

    @State private var editing: TaskItem?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    ContentUnavailableView(
                        "No tasks",
                        systemImage: "checklist",
                        description: Text("Tap + to add a task with a rough duration.")
                    )
                } else {
                    List {
                        ForEach(tasks) { task in
                            TaskRow(task: task)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = task }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        toggleCompletion(task)
                                    } label: {
                                        if task.status == .completed {
                                            Label("Undo", systemImage: "arrow.uturn.backward")
                                        } else {
                                            Label("Complete", systemImage: "checkmark")
                                        }
                                    }
                                    .tint(Color(white: task.status == .completed ? 0.35 : 0.55))
                                }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New task")
                }
            }
            .sheet(isPresented: $showingNew) {
                TaskEditor(mode: .create)
            }
            .sheet(item: $editing) { task in
                TaskEditor(mode: .edit(task))
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tasks[index])
        }
        try? modelContext.save()
    }

    private func toggleCompletion(_ task: TaskItem) {
        if task.status == .completed {
            task.status = task.scheduledStart != nil ? .scheduled : .pending
        } else {
            task.status = .completed
        }
        try? modelContext.save()
    }
}

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: priorityIcon)
                .foregroundStyle(priorityColor)
                .frame(width: 22)
                .accessibilityLabel(priorityA11yLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.status == .completed, color: .secondary)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                HStack(spacing: 8) {
                    Label(durationLabel, systemImage: "clock")
                        .accessibilityLabel("Duration \(durationLabel)")
                    if let deadline = task.deadline {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "flag")
                    }
                    if task.recurrence != .none {
                        Label(task.recurrence.label, systemImage: "repeat")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe right to \(task.status == .completed ? "restore" : "complete"). Tap to edit.")
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch task.status {
        case .scheduled:
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(.primary)
                .accessibilityLabel("Scheduled")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.primary)
                .accessibilityLabel("Completed")
        case .pending:
            EmptyView()
        }
    }

    private var priorityIcon: String {
        switch task.priority {
        case .low: "circle"
        case .normal: "circle.fill"
        case .high: "exclamationmark.circle.fill"
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: .secondary
        case .normal: .primary
        case .high: .primary
        }
    }

    private var priorityA11yLabel: String {
        switch task.priority {
        case .low: "Low priority"
        case .normal: "Normal priority"
        case .high: "High priority"
        }
    }

    private var durationLabel: String {
        let minutes = task.estimatedMinutes
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60) hr" }
        if minutes >= 60 { return "\(minutes / 60) hr \(minutes % 60) min" }
        return "\(minutes) min"
    }
}

#Preview {
    TaskListView()
        .modelContainer(for: TaskItem.self, inMemory: true)
}
