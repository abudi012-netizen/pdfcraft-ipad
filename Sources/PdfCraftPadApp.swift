import SwiftUI

@main
struct PdfCraftPadApp: App {
    @StateObject private var library = Library()
    @AppStorage("appearance") private var appearance = 0

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
        }
    }
}

/// Where a search result should land inside a PDF.
struct ReaderTarget: Hashable {
    let pageIndex: Int
    let query: String
    let ordinalOnPage: Int
}

enum Route: Hashable {
    case reader(LibraryItem, ReaderTarget?)
}

struct RootView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            LibraryView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .reader(let item, let target):
                        ReaderView(item: item, target: target)
                    }
                }
        }
        // PDFs dropped into the app's folder from the Files app show up on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.reload() }
        }
    }
}
