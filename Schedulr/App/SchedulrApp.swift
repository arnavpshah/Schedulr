import SwiftUI
import SwiftData

@main
struct SchedulrApp: App {
    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: TaskItem.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
