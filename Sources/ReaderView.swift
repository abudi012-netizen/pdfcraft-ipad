import SwiftUI
import PDFKit

struct ReaderView: View {
    let item: LibraryItem
    let target: ReaderTarget?

    @StateObject private var controller: ReaderController
    @State private var showFind = false

    init(item: LibraryItem, target: ReaderTarget?) {
        self.item = item
        self.target = target
        _controller = StateObject(wrappedValue: ReaderController(url: item.url))
    }

    var body: some View {
        PDFKitView(controller: controller)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Text(controller.pageLabel)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button { showFind = true } label: {
                        Label("Find in PDF", systemImage: "magnifyingglass")
                    }

                    Button { controller.darkPages.toggle() } label: {
                        Label("Night reading", systemImage: controller.darkPages ? "moon.fill" : "moon")
                    }

                    Button { controller.drawingEnabled.toggle() } label: {
                        Label("Apple Pencil",
                              systemImage: controller.drawingEnabled ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                    }
                    .tint(controller.drawingEnabled ? Color.accentColor : nil)
                }
            }
            .onAppear { controller.didAppear(target: target) }
            .onDisappear { controller.saveNow() }
            .sheet(isPresented: $showFind) {
                SearchView(title: "Find in \(item.title)", items: [item]) { _, target in
                    showFind = false
                    controller.go(to: target)
                }
            }
    }
}

struct PDFKitView: UIViewRepresentable {
    let controller: ReaderController

    func makeUIView(context: Context) -> PDFView { controller.pdfView }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
