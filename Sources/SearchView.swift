import SwiftUI
import PDFKit

struct SearchHit: Identifiable {
    let id = UUID()
    let item: LibraryItem
    let pageIndex: Int
    let ordinalOnPage: Int
    let snippet: String
}

enum SearchEngine {
    static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Finds every mention of `query` in each PDF, with a little surrounding text.
    static func search(_ query: String, in items: [LibraryItem], limitPerDocument: Int = 300) -> [SearchHit] {
        var hits: [SearchHit] = []
        for item in items {
            guard let doc = PDFDocument(url: item.url) else { continue }
            var countPerPage: [Int: Int] = [:]
            for selection in doc.findString(query, withOptions: options).prefix(limitPerDocument) {
                guard let page = selection.pages.first else { continue }
                let pageIndex = doc.index(for: page)
                let ordinal = countPerPage[pageIndex, default: 0]
                countPerPage[pageIndex] = ordinal + 1

                var snippet = query
                if let context = selection.copy() as? PDFSelection {
                    context.extend(atStart: 60, atEnd: 80)
                    snippet = (context.string ?? query)
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }
                hits.append(SearchHit(item: item, pageIndex: pageIndex, ordinalOnPage: ordinal, snippet: snippet))
            }
        }
        return hits
    }
}

struct SearchView: View {
    let title: String
    let items: [LibraryItem]
    let onOpen: (LibraryItem, ReaderTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchedFor = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false

    private struct HitGroup: Identifiable {
        let item: LibraryItem
        let hits: [SearchHit]
        var id: URL { item.url }
    }

    private var groups: [HitGroup] {
        var order: [LibraryItem] = []
        var byItem: [LibraryItem: [SearchHit]] = [:]
        for hit in hits {
            if byItem[hit.item] == nil { order.append(hit.item) }
            byItem[hit.item, default: []].append(hit)
        }
        return order.map { HitGroup(item: $0, hits: byItem[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if searching {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching \(items.count == 1 ? "this PDF" : "\(items.count) PDFs")…")
                            .foregroundStyle(.secondary)
                    }
                } else if !searchedFor.isEmpty && hits.isEmpty {
                    ContentUnavailableView.search(text: searchedFor)
                } else if searchedFor.isEmpty {
                    Text("Type a word and press Search. Every mention shows up here, grouped by PDF.")
                        .foregroundStyle(.secondary)
                }

                ForEach(groups) { group in
                    Section {
                        ForEach(group.hits) { hit in
                            Button {
                                onOpen(hit.item, ReaderTarget(pageIndex: hit.pageIndex, query: searchedFor, ordinalOnPage: hit.ordinalOnPage))
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Page \(hit.pageIndex + 1)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(emphasized(hit.snippet))
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("\(group.item.title) · \(group.hits.count)")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Drug name, term, anything…")
            .onSubmit(of: .search) { run() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchedFor = q
        hits = []
        searching = true
        let items = self.items
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                SearchEngine.search(q, in: items)
            }.value
            hits = found
            searching = false
        }
    }

    private func emphasized(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard !searchedFor.isEmpty else { return result }
        var start = result.startIndex
        while start < result.endIndex,
              let range = result[start...].range(of: searchedFor, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[range].inlinePresentationIntent = .stronglyEmphasized
            start = range.upperBound
        }
        return result
    }
}
