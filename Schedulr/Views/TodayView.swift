import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [TaskItem]

    @State private var calendar = CalendarService()
    @State private var selectedDate: Date = .now
    @State private var events: [BusyBlock] = []
    @State private var isRequesting = false
    @State private var generation: GenerationState = .idle
    @State private var showingResult = false

    @AppStorage("backendBaseURL") private var backendBaseURL: String = ""
    @AppStorage("backendAPIKey") private var backendAPIKey: String = ""
    @AppStorage("preferMornings") private var preferMornings: Bool = true
    @AppStorage("bufferMinutes") private var bufferMinutes: Int = 5

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
                        Task { await generate() }
                    } label: {
                        if generation.isLoading {
                            ProgressView()
                        } else {
                            Text("Generate")
                        }
                    }
                    .disabled(!canGenerate)
                }
            }
            .onChange(of: selectedDate) { _, _ in reloadEvents() }
            .onAppear {
                calendar.refreshAuthState()
                reloadEvents()
            }
            .sheet(isPresented: $showingResult) {
                if case let .success(result) = generation {
                    ScheduleResultSheet(result: result, tasks: pendingTasks) { proposal in
                        applyProposal(proposal)
                    }
                }
            }
            .alert("Couldn't generate", isPresented: errorBinding, presenting: generation.errorMessage) { _ in
                Button("OK") { generation = .idle }
            } message: { message in
                Text(message)
            }
        }
    }

    private var pendingTasks: [TaskItem] {
        allTasks.filter { $0.status == .pending }
    }

    private var canGenerate: Bool {
        guard !generation.isLoading else { return false }
        guard !backendBaseURL.isEmpty else { return false }
        guard calendar.authState == .authorized || calendar.authState == .writeOnly else { return false }
        return !pendingTasks.isEmpty
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { generation.errorMessage != nil },
            set: { if !$0 { generation = .idle } }
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
            if events.isEmpty {
                ContentUnavailableView(
                    "Nothing on the calendar",
                    systemImage: "sparkles",
                    description: Text(timelineEmptyHint)
                )
            } else {
                List {
                    Section("Existing events") {
                        ForEach(events) { event in
                            BusyBlockRow(event: event)
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

    private func generate() async {
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: 8, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let dayEnd = cal.date(bySettingHour: 22, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let prefs = SchedulePreferences(bufferMinutes: bufferMinutes, preferMornings: preferMornings)
        let busy = events.filter { !$0.isAllDay }

        generation = .loading
        let client = APIClient(baseURL: backendBaseURL, apiKey: backendAPIKey)
        do {
            let result = try await client.schedule(
                day: selectedDate,
                dayStart: dayStart,
                dayEnd: dayEnd,
                timeZone: .current,
                busyBlocks: busy,
                tasks: pendingTasks,
                preferences: prefs
            )
            generation = .success(result)
            showingResult = true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            generation = .failure(message)
        }
    }

    private func applyProposal(_ proposal: ScheduleProposal) {
        guard let uuid = UUID(uuidString: proposal.taskId),
              let task = allTasks.first(where: { $0.id == uuid }) else { return }
        task.scheduledStart = proposal.start
        task.scheduledEnd = proposal.end
        task.status = .scheduled
        try? modelContext.save()
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
    }

    private var eventColor: Color {
        if let cg = event.calendarColor { return Color(cgColor: cg) }
        return .accentColor
    }

    private var timeLabel: String {
        if event.isAllDay { return "All day" }
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(event.start.formatted(f)) – \(event.end.formatted(f))"
    }
}

private struct ScheduleResultSheet: View {
    let result: ScheduleResult
    let tasks: [TaskItem]
    let onAccept: (ScheduleProposal) -> Void

    @Environment(\.dismiss) private var dismiss

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
                                title: titleFor(proposal.taskId),
                                onAccept: { onAccept(proposal) }
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
            }
            .navigationTitle("Generated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func titleFor(_ id: String) -> String {
        guard let uuid = UUID(uuidString: id) else { return id }
        return tasks.first(where: { $0.id == uuid })?.title ?? id
    }
}

private struct ProposalRow: View {
    let proposal: ScheduleProposal
    let title: String
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body)
            Text(timeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(proposal.reasoning)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Accept", action: onAccept)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.vertical, 2)
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
