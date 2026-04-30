import Foundation

enum APIError: LocalizedError {
    case missingBaseURL
    case invalidBaseURL
    case http(status: Int, message: String?)
    case transport(Error)
    case decoding(Error)
    case encoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL: "No backend URL is configured. Set one in Settings."
        case .invalidBaseURL: "The configured backend URL is not valid."
        case let .http(status, message):
            if let message, !message.isEmpty { "Server returned \(status): \(message)" }
            else { "Server returned \(status)." }
        case let .transport(err): "Network error: \(err.localizedDescription)"
        case let .decoding(err): "Could not parse server response: \(err.localizedDescription)"
        case let .encoding(err): "Could not build the request: \(err.localizedDescription)"
        }
    }
}

struct ScheduleProposal: Codable, Identifiable, Hashable {
    let taskId: String
    let start: Date
    let end: Date
    let reasoning: String

    var id: String { taskId }
}

struct ScheduleUnscheduled: Codable, Identifiable, Hashable {
    let taskId: String
    let reason: String

    var id: String { taskId }
}

struct ScheduleUsage: Codable, Hashable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

struct ScheduleResult: Codable, Hashable {
    let proposals: [ScheduleProposal]
    let unscheduled: [ScheduleUnscheduled]
    let summary: String
    let usage: ScheduleUsage?
}

struct HealthResponse: Codable, Hashable {
    let ok: Bool
    let service: String
    let version: String
    let requiresApiKey: Bool
}

@MainActor
@Observable
final class APIClient {
    var baseURL: String
    var apiKey: String

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: String = "", apiKey: String = "", session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.encoder = APIClient.makeEncoder()
        self.decoder = APIClient.makeDecoder()
    }

    func health() async throws -> HealthResponse {
        let (data, response) = try await send(path: "/api/health", method: "GET", body: Optional<EmptyBody>.none)
        try Self.checkStatus(response: response, data: data)
        do { return try decoder.decode(HealthResponse.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    func schedule(
        day: Date,
        dayStart: Date,
        dayEnd: Date,
        timeZone: TimeZone,
        busyBlocks: [BusyBlock],
        tasks: [TaskItem],
        preferences: SchedulePreferences = .default
    ) async throws -> ScheduleResult {
        let body = ScheduleRequestDTO(
            day: day,
            dayStart: dayStart,
            dayEnd: dayEnd,
            timeZone: timeZone.identifier,
            busyBlocks: busyBlocks.map(BusyBlockDTO.init),
            tasks: tasks.map(TaskInputDTO.init),
            preferences: preferences
        )
        return try await postSchedule(path: "/api/schedule", body: body)
    }

    func refine(
        previous: ScheduleResult,
        feedback: String,
        day: Date,
        dayStart: Date,
        dayEnd: Date,
        timeZone: TimeZone,
        busyBlocks: [BusyBlock],
        tasks: [TaskItem],
        preferences: SchedulePreferences = .default
    ) async throws -> ScheduleResult {
        let body = RefineRequestDTO(
            day: day,
            dayStart: dayStart,
            dayEnd: dayEnd,
            timeZone: timeZone.identifier,
            busyBlocks: busyBlocks.map(BusyBlockDTO.init),
            tasks: tasks.map(TaskInputDTO.init),
            preferences: preferences,
            previous: ScheduleResultBare(
                proposals: previous.proposals,
                unscheduled: previous.unscheduled,
                summary: previous.summary
            ),
            feedback: feedback
        )
        return try await postSchedule(path: "/api/refine", body: body)
    }

    private func postSchedule<Body: Encodable>(path: String, body: Body) async throws -> ScheduleResult {
        let (data, response) = try await send(path: path, method: "POST", body: body)
        try Self.checkStatus(response: response, data: data)
        do { return try decoder.decode(ScheduleResult.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func send<Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> (Data, URLResponse) {
        guard !baseURL.isEmpty else { throw APIError.missingBaseURL }
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed + path) else { throw APIError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { request.httpBody = try encoder.encode(body) }
            catch { throw APIError.encoding(error) }
        }
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
    }

    private static func checkStatus(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200..<300).contains(http.statusCode) { return }
        let message = String(data: data, encoding: .utf8)
        throw APIError.http(status: http.statusCode, message: message)
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = formatter.date(from: value) { return date }
            if let date = fallback.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Could not parse ISO 8601 date: \(value)"
            )
        }
        return d
    }
}

private struct EmptyBody: Encodable {}

struct SchedulePreferences: Codable, Hashable {
    var bufferMinutes: Int
    var preferMornings: Bool

    static let `default` = SchedulePreferences(bufferMinutes: 5, preferMornings: true)
}

private struct ScheduleResultBare: Codable {
    let proposals: [ScheduleProposal]
    let unscheduled: [ScheduleUnscheduled]
    let summary: String
}

private struct ScheduleRequestDTO: Encodable {
    let day: Date
    let dayStart: Date
    let dayEnd: Date
    let timeZone: String
    let busyBlocks: [BusyBlockDTO]
    let tasks: [TaskInputDTO]
    let preferences: SchedulePreferences
}

private struct RefineRequestDTO: Encodable {
    let day: Date
    let dayStart: Date
    let dayEnd: Date
    let timeZone: String
    let busyBlocks: [BusyBlockDTO]
    let tasks: [TaskInputDTO]
    let preferences: SchedulePreferences
    let previous: ScheduleResultBare
    let feedback: String
}

private struct BusyBlockDTO: Encodable {
    let title: String
    let start: Date
    let end: Date

    init(_ block: BusyBlock) {
        self.title = block.title
        self.start = block.start
        self.end = block.end
    }
}

private struct TaskInputDTO: Encodable {
    let id: String
    let title: String
    let estimatedMinutes: Int
    let priority: String
    let deadline: Date?
    let notes: String?

    init(_ task: TaskItem) {
        self.id = task.id.uuidString
        self.title = task.title
        self.estimatedMinutes = task.estimatedMinutes
        self.priority = switch task.priority {
        case .low: "low"
        case .normal: "normal"
        case .high: "high"
        }
        self.deadline = task.deadline
        let trimmedNotes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = (trimmedNotes?.isEmpty ?? true) ? nil : trimmedNotes
    }
}
