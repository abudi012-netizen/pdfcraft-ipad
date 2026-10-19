import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: Library
    @Binding var path: [Route]
    @AppStorage("appearance") private var appearance = 0
    @State private var importing = false
    @State private var showSearch = false
    @State private var showDictionary = false
    @State private var pendingDelete: LibraryItem?
    @State private var filter = ""

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 22)]

    private var filtered: [LibraryItem] {
        filter.isEmpty ? library.items : library.items.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        content
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Label("Search all PDFs", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(library.items.isEmpty)

                    Button { showDictionary = true } label: {
                        Label("Medical Dictionary", systemImage: "cross.case")
                    }

                    Button { importing = true } label: {
                        Label("Import PDFs", systemImage: "plus")
                    }

                    Menu {
                        Picker("Appearance", selection: $appearance) {
                            Label("System", systemImage: "circle.lefthalf.filled").tag(0)
                            Label("Light", systemImage: "sun.max").tag(1)
                            Label("Dark", systemImage: "moon").tag(2)
                        }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
            .sheet(isPresented: $showDictionary) { DictionaryView() }
            .sheet(isPresented: $showSearch) {
                SearchView(title: "Search all PDFs", items: library.items) { item, target in
                    showSearch = false
                    path.append(.reader(item, target))
                }
            }
            .confirmationDialog(
                "Delete this PDF?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { item in
                Button("Delete \u{201C}\(item.title)\u{201D}", role: .destructive) { library.delete(item) }
            } message: { _ in
                Text("This removes the PDF and your Pencil notes on it from the app.")
            }
    }

    @ViewBuilder private var content: some View {
        if library.items.isEmpty {
            ContentUnavailableView {
                Label("No lectures yet", systemImage: "books.vertical")
            } description: {
                Text("Import PDFs from the Files app to start studying.")
            } actions: {
                Button("Import PDFs") { importing = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(filtered) { item in
                        Button { path.append(.reader(item, nil)) } label: {
                            LibraryCell(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { pendingDelete = item } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(24)
            }
            .searchable(text: $filter, prompt: "Filter by title")
        }
    }
}

struct LibraryCell: View {
    let item: LibraryItem
    @State private var thumb: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(0.78, contentMode: .fit)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .contentShape(Rectangle())
        .task(id: item.url) { thumb = await Thumbnailer.image(for: item.url) }
    }
}
