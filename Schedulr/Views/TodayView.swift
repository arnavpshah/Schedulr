import SwiftUI
import SwiftData
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [TaskItem]

    @State private var calendar = CalendarService()
    @State private var selectedDate: Date = .now
    @State private var events: [BusyBlock] = []
    @State private var isRequesting = false
    @State private var generation: GenerationState = .idle
    @State private var showingResult = false
    @State private var generationTask: Task<Void, Never>? = nil
    @State private var editingScheduled: TaskItem? = nil
    @State private var saveErrorMessage: String? = nil

    @AppStorage("backendBaseURL") private var backendBaseURL: String = ""
    @AppStorage("backendAPIKey") private var backendAPIKey: String = ""
    @AppStorage("preferMornings") private var preferMornings: Bool = true
    @AppStorage("bufferMinutes") private var bufferMinutes: Int = 5
    @AppStorage("dayStartHour") private var dayStartHour: Int = 8
    @AppStorage("dayEndHour") private var dayEndHour: Int = 22

    var body: some View {
        NavigationStack {
            Group {
                switch calendar.authState {
                case .notDetermined:
                    permissionPrompt
                case .denied:
                    deniedView
                case .writeOnly, .authorized:
                    timeline
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startGenerate()
                    } label: {
                        Text("Generate")
                    }
                    .disabled(!canGenerate)
                }
            }
            .onChange(of: selectedDate) { _, _ in reloadEvents() }
            .onAppear {
                calendar.refreshAuthState()
                reloadEvents()
            }
            .fullScreenCover(isPresented: loadingBinding) {
                LoadingOverlay(day: selectedDate, onCancel: cancelGenerate)
            }
            .sheet(isPresented: $showingResult) {
                if case let .success(result) = generation {
                    ScheduleResultSheet(
                        result: result,
                        tasks: tasksForResult(result),
                        onApply: { proposals in
                            applyProposals(proposals)
                            showingResult = false
                        },
                        onRefine: { feedback in
                            await refine(feedback: feedback)
                        }
                    )
                }
            }
            .sheet(item: $editingScheduled) { task in
                ScheduledTimeEditor(task: task) { newStart, newEnd in
                    task.scheduledStart = newStart
                    task.scheduledEnd = newEnd
                    saveContext()
                }
            }
            .alert("Couldn't generate", isPresented: errorBinding, presenting: generation.errorMessage) { _ in
                Button("OK") { generation = .idle }
            } message: { message in
                Text(message)
            }
            .alert("Couldn't save", isPresented: saveErrorBinding, presenting: saveErrorMessage) { _ in
                Button("OK") { saveErrorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private var pendingTasks: [TaskItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return allTasks.filter { task in
            guard task.status == .pending else { return false }
            if task.isRecurringTemplate {
                guard task.recurrence.appliesTo(selectedDate, weeklyAnchor: task.createdAt) else { return false }
                let alreadyHasSnapshot = allTasks.contains { snap in
                    guard snap.sourceTemplateID == task.id, let start = snap.scheduledStart else { return false }
                    return start >= dayStart && start < dayEnd
                }
                return !alreadyHasSnapshot
            }
            return true
        }
    }

    private var scheduledForSelectedDate: [TaskItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: selectedDate)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return allTasks
            .filter { task in
                guard task.status == .scheduled, let start = task.scheduledStart else { return false }
                return start >= dayStart && start < dayEnd
            }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
    }

    private var canGenerate: Bool {
        guard !generation.isLoading else { return false }
        guard !backendBaseURL.isEmpty else { return false }
        guard calendar.authState == .authorized || calendar.authState == .writeOnly else { return false }
        guard dayEndHour > dayStartHour else { return false }
        return !pendingTasks.isEmpty
    }

    private var loadingBinding: Binding<Bool> {
        Binding(
            get: { generation.isLoading },
            set: { if !$0 { cancelGenerate() } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { generation.errorMessage != nil },
            set: { if !$0 { generation = .idle } }
        )
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
    }

    private var permissionPrompt: some View {
        ContentUnavailableView {
            Label("Connect your calendar", systemImage: "calendar")
        } description: {
            Text("Schedulr needs access to read existing events so it can fit tasks into the gaps in your day.")
        } actions: {
            Button {
                Task {
                    isRequesting = true
                    _ = await calendar.requestFullAccess()
                    reloadEvents()
                    isRequesting = false
                }
            } label: {
                Text(isRequesting ? "Requesting…" : "Allow Calendar Access")
                    .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Calendar access denied", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Enable calendar access in Settings to use AI scheduling.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var timeline: some View {
        Group {
            if events.isEmpty && pendingTasks.isEmpty && scheduledForSelectedDate.isEmpty {
                ContentUnavailableView(
                    "Nothing on the calendar",
                    systemImage: "sparkles",
                    description: Text(timelineEmptyHint)
                )
            } else {
                List {
                    if !scheduledForSelectedDate.isEmpty {
                        Section("Scheduled today") {
                            ForEach(scheduledForSelectedDate) { task in
                                ScheduledTaskRow(task: task)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingScheduled = task }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            unschedule(task)
                                        } label: {
                                            Label("Unschedule", systemImage: "calendar.badge.minus")
                                        }
                                    }
                            }
                        }
                    }
                    if !events.isEmpty {
                        Section("Existing events") {
                            ForEach(events) { event in
                                BusyBlockRow(event: event)
                            }
                        }
                    }
                    if !pendingTasks.isEmpty {
                        Section("To schedule") {
                            ForEach(pendingTasks) { task in
                                PendingTaskRow(task: task)
                            }
                        }
                    }
                }
            }
        }
    }

    private var timelineEmptyHint: String {
        if backendBaseURL.isEmpty {
            return "This day is wide open. Add tasks, configure your backend in Settings, then tap Generate."
        }
        if pendingTasks.isEmpty {
            return "This day is wide open. Add tasks, then tap Generate."
        }
        return "This day is wide open. Tap Generate to fit your tasks in."
    }

    private func reloadEvents() {
        events = calendar.events(on: selectedDate)
    }

    private func startGenerate() {
        generationTask?.cancel()
        generationTask = Task { await generate() }
    }

    private func cancelGenerate() {
        generationTask?.cancel()
        generationTask = nil
        if generation.isLoading { generation = .idle }
    }

    private func generate() async {
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let dayEnd = cal.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let prefs = SchedulePreferences(bufferMinutes: bufferMinutes, preferMornings: preferMornings)
        let busy = events.filter { !$0.isAllDay }
        let tasksToSchedule = pendingTasks

        await MainActor.run { generation = .loading }
        let client = APIClient(baseURL: backendBaseURL, apiKey: backendAPIKey)
        do {
            let result = try await client.schedule(
                day: selectedDate,
                dayStart: dayStart,
                dayEnd: dayEnd,
                timeZone: .current,
                busyBlocks: busy,
                tasks: tasksToSchedule,
                preferences: prefs
            )
            try Task.checkCancellation()
            await MainActor.run {
                generation = .success(result)
                showingResult = true
            }
        } catch is CancellationError {
            await MainActor.run { generation = .idle }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await MainActor.run { generation = .failure(message) }
        }
    }

    private func refine(feedback: String) async {
        guard case let .success(previous) = generation else { return }
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let dayEnd = cal.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let prefs = SchedulePreferences(bufferMinutes: bufferMinutes, preferMornings: preferMornings)
        let busy = events.filter { !$0.isAllDay }
        let tasksToSchedule = pendingTasks

        let client = APIClient(baseURL: backendBaseURL, apiKey: backendAPIKey)
        do {
            let result = try await client.refine(
                previous: previous,
                feedback: feedback,
                day: selectedDate,
                dayStart: dayStart,
                dayEnd: dayEnd,
                timeZone: .current,
                busyBlocks: busy,
                tasks: tasksToSchedule,
                preferences: prefs
            )
            await MainActor.run { generation = .success(result) }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await MainActor.run { generation = .failure(message) }
        }
    }

    private func tasksForResult(_ result: ScheduleResult) -> [TaskItem] {
        // Pending tasks at the time of generation are the relevant set for title lookup.
        // We re-derive by including any task referenced by id in proposals/unscheduled.
        let referencedIds: Set<String> = Set(
            result.proposals.map(\.taskId) + result.unscheduled.map(\.taskId)
        )
        return allTasks.filter { referencedIds.contains($0.id.uuidString) }
    }

    private func applyProposals(_ proposals: [ScheduleProposal]) {
        for proposal in proposals {
            guard let uuid = UUID(uuidString: proposal.taskId),
                  let task = allTasks.first(where: { $0.id == uuid }) else { continue }
            if task.isRecurringTemplate {
                let snapshot = TaskItem(
                    title: task.title,
                    estimatedMinutes: task.estimatedMinutes,
                    priority: task.priority,
                    deadline: task.deadline,
                    notes: task.notes,
                    status: .scheduled,
                    scheduledStart: proposal.start,
                    scheduledEnd: proposal.end,
                    recurrence: .none,
                    sourceTemplateID: task.id
                )
                modelContext.insert(snapshot)
            } else {
                task.scheduledStart = proposal.start
                task.scheduledEnd = proposal.end
                task.status = .scheduled
            }
        }
        if saveContext() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func unschedule(_ task: TaskItem) {
        if task.sourceTemplateID != nil {
            modelContext.delete(task)
        } else {
            task.scheduledStart = nil
            task.scheduledEnd = nil
            task.status = .pending
        }
        _ = saveContext()
    }

    @discardableResult
    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    private enum GenerationState {
        case idle
        case loading
        case success(ScheduleResult)
        case failure(String)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var errorMessage: String? {
            if case let .failure(msg) = self { return msg }
            return nil
        }
    }
}

private struct LoadingOverlay: View {
    let day: Date
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Building your schedule…")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(day.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(.top, 8)
            }
            .padding(32)
        }
        .interactiveDismissDisabled()
        .presentationBackground(.clear)
    }
}

private struct BusyBlockRow: View {
    let event: BusyBlock

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(eventColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body)
                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Busy: \(event.title), \(timeLabel)")
    }

    private var eventColor: Color {
        Color(white: 0.55)
    }

    private var timeLabel: String {
        if event.isAllDay { return "All day" }
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(event.start.formatted(f)) – \(event.end.formatted(f))"
    }
}

private struct PendingTaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: priorityIcon)
                .foregroundStyle(priorityColor)
                .frame(width: 22)
                .accessibilityLabel(priorityA11yLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.body)
                HStack(spacing: 8) {
                    Label(durationLabel, systemImage: "clock")
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
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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

private struct ScheduledTaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .foregroundStyle(.primary)
                .frame(width: 22)
                .accessibilityLabel("Scheduled")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.body)
                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to edit time. Swipe left to unschedule.")
    }

    private var timeLabel: String {
        guard let start = task.scheduledStart, let end = task.scheduledEnd else { return "" }
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(start.formatted(f)) – \(end.formatted(f))"
    }
}

private struct ScheduledTimeEditor: View {
    @Bindable var task: TaskItem
    let onSave: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var validationError: String? = nil

    init(task: TaskItem, onSave: @escaping (Date, Date) -> Void) {
        self.task = task
        self.onSave = onSave
        _start = State(initialValue: task.scheduledStart ?? .now)
        _end = State(initialValue: task.scheduledEnd ?? .now.addingTimeInterval(60 * 30))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    Text(task.title).font(.headline)
                }
                Section("Time") {
                    DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, displayedComponents: [.date, .hourAndMinute])
                }
                if let validationError {
                    Section {
                        Text(validationError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { trySave() }
                        .disabled(end <= start)
                }
            }
        }
    }

    private func trySave() {
        guard end > start else {
            validationError = "End must be after start."
            return
        }
        onSave(start, end)
        dismiss()
    }
}

private struct ScheduleResultSheet: View {
    let result: ScheduleResult
    let tasks: [TaskItem]
    let onApply: ([ScheduleProposal]) -> Void
    let onRefine: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedback: String = ""
    @State private var refining: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if !result.summary.isEmpty {
                    Section("Summary") {
                        Text(result.summary)
                    }
                }
                if !result.proposals.isEmpty {
                    Section("Proposed schedule") {
                        ForEach(result.proposals) { proposal in
                            ProposalRow(
                                proposal: proposal,
                                title: titleFor(proposal.taskId)
                            )
                        }
                    }
                }
                if !result.unscheduled.isEmpty {
                    Section("Couldn't fit") {
                        ForEach(result.unscheduled) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(titleFor(item.taskId)).font(.body)
                                Text(item.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    TextField("e.g. shift everything 30 min later", text: $feedback, axis: .vertical)
                        .lineLimit(2...4)
                        .disabled(refining)
                    Button {
                        Task { await runRefine() }
                    } label: {
                        HStack {
                            if refining {
                                ProgressView().controlSize(.small)
                                Text("Refining…")
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text("Refine")
                            }
                        }
                    }
                    .disabled(refining || feedback.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Tweak")
                } footer: {
                    Text("Describe what to change and Schedulr will produce a revised schedule.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !result.proposals.isEmpty {
                    Button {
                        onApply(result.proposals)
                    } label: {
                        Text("Apply schedule")
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                    .disabled(refining)
                }
            }
            .navigationTitle("Generated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(refining)
                }
            }
        }
    }

    private func runRefine() async {
        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        refining = true
        await onRefine(trimmed)
        refining = false
        feedback = ""
    }

    private func titleFor(_ id: String) -> String {
        guard let uuid = UUID(uuidString: id) else { return id }
        return tasks.first(where: { $0.id == uuid })?.title ?? id
    }
}

private struct ProposalRow: View {
    let proposal: ScheduleProposal
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body)
            Text(timeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(proposal.reasoning)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var timeLabel: String {
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(proposal.start.formatted(f)) – \(proposal.end.formatted(f))"
    }
}

#Preview {
    TodayView()
        .modelContainer(for: TaskItem.self, inMemory: true)
}
