import SwiftUI

@main
struct FormaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .font(FormaFont.bodyFont(15))
        }
    }
}
