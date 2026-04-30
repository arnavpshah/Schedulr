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
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
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
    }
}

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: priorityIcon)
                .foregroundStyle(priorityColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                HStack(spacing: 8) {
                    Label(durationLabel, systemImage: "clock")
                    if let deadline = task.deadline {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "flag")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if task.status == .scheduled {
                Image(systemName: "calendar.badge.checkmark").foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
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
        case .normal: .accentColor
        case .high: .red
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
