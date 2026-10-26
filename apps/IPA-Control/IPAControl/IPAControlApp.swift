import SwiftUI

@main
struct IPAControlApp: App {
    @StateObject private var model = IPAControlModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
