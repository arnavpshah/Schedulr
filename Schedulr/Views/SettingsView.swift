import SwiftUI

struct SettingsView: View {
    @AppStorage("backendBaseURL") private var backendBaseURL: String = ""
    @AppStorage("backendAPIKey") private var backendAPIKey: String = ""
    @AppStorage("preferMornings") private var preferMornings: Bool = true
    @AppStorage("bufferMinutes") private var bufferMinutes: Int = 5
    @AppStorage("dayStartHour") private var dayStartHour: Int = 8
    @AppStorage("dayEndHour") private var dayEndHour: Int = 22

    @State private var calendar = CalendarService()
    @State private var healthState: HealthState = .idle

    var body: some View {
        NavigationStack {
            Form {
                Section("Calendar") {
                    LabeledContent("Access", value: calendar.authState.label)
                    if calendar.authState == .notDetermined {
                        Button("Request Access") {
                            Task {
                                _ = await calendar.requestFullAccess()
                            }
                        }
                    }
                }

                Section {
                    TextField("https://your-app.vercel.app", text: $backendBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("x-api-key (optional)", text: $backendAPIKey)
                    Button {
                        Task { await runHealthCheck() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            healthIndicator
                        }
                    }
                    .disabled(backendBaseURL.isEmpty || healthState.isChecking)
                    if case let .failure(message) = healthState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    if case let .success(response) = healthState {
                        Text("\(response.service) v\(response.version)\(response.requiresApiKey ? " · auth required" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Backend")
                } footer: {
                    Text("Your Vercel-hosted scheduler endpoint. The API key is sent as the x-api-key header.")
                }

                Section {
                    DatePicker(
                        "Day starts",
                        selection: dayStartBinding,
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        "Day ends",
                        selection: dayEndBinding,
                        displayedComponents: .hourAndMinute
                    )
                    Stepper(value: $bufferMinutes, in: 0...60, step: 5) {
                        LabeledContent("Buffer between items", value: "\(bufferMinutes) min")
                    }
                    Toggle("Prefer mornings for high-priority", isOn: $preferMornings)
                } header: {
                    Text("Scheduling Preferences")
                } footer: {
                    if dayEndHour <= dayStartHour {
                        Text("⚠ End must be after start.")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    } else {
                        Text("Schedulr will only place tasks inside this window.")
                    }
                }

                Section("About") {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                    )
                }
            }
            .navigationTitle("Settings")
            .onAppear { calendar.refreshAuthState() }
        }
    }

    private var dayStartBinding: Binding<Date> {
        hourBinding($dayStartHour)
    }

    private var dayEndBinding: Binding<Date> {
        hourBinding($dayEndHour)
    }

    private func hourBinding(_ source: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: source.wrappedValue, minute: 0, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let hour = Calendar.current.component(.hour, from: newValue)
                source.wrappedValue = hour
            }
        )
    }

    @ViewBuilder
    private var healthIndicator: some View {
        switch healthState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.primary)
        case .failure:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.primary)
        }
    }

    private func runHealthCheck() async {
        healthState = .checking
        let client = APIClient(baseURL: backendBaseURL, apiKey: backendAPIKey)
        do {
            let response = try await client.health()
            healthState = .success(response)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            healthState = .failure(message)
        }
    }

    private enum HealthState {
        case idle
        case checking
        case success(HealthResponse)
        case failure(String)

        var isChecking: Bool {
            if case .checking = self { return true }
            return false
        }
    }
}

private extension CalendarAuthState {
    var label: String {
        switch self {
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .writeOnly: "Write-only"
        case .authorized: "Granted"
        }
    }
}

#Preview {
    SettingsView()
}
