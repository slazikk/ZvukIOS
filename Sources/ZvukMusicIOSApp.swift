import SwiftUI

@main
struct ZvukMusicIOSApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var player = PlayerStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isAuthenticated { MainTabs() } else { TokenSignInView() }
            }
            .environmentObject(session)
            .environmentObject(player)
            .tint(.orange)
        }
    }
}
