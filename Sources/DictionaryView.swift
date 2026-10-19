import SwiftUI

/// Something to look up, used to present the dictionary as a sheet.
struct DictionaryRequest: Identifiable {
    let id = UUID()
    let query: String
}

struct DictionaryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var exact: [MedEntry] = []
    @State private var suggestions: [MedEntry] = []

    init(query: String = "") {
        _query = State(initialValue: query)
    }

    var body: some View {
        NavigationStack {
            List {
                if !MedDictionary.shared.isAvailable {
                    Text("The medical dictionary isn't included in this build.")
                        .foregroundStyle(.secondary)
                } else if query.isEmpty {
                    Text("Type a drug, disease or term. Works offline.")
                        .foregroundStyle(.secondary)
                } else if exact.isEmpty && suggestions.isEmpty {
                    ContentUnavailableView.search(text: query)
                }

                if !exact.isEmpty {
                    Section {
                        ForEach(exact) { EntryCard(entry: $0) }
                    }
                }
                if !suggestions.isEmpty {
                    Section(exact.isEmpty ? "Did you mean" : "Related terms") {
                        ForEach(suggestions) { entry in
                            NavigationLink(value: entry) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                    if !entry.category.isEmpty {
                                        Text(entry.category).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    Text("Definitions from MeSH, courtesy of the U.S. National Library of Medicine.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationDestination(for: MedEntry.self) { entry in
                List { EntryCard(entry: entry) }
                    .navigationTitle(entry.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Drug, disease, term…")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let q = query
                let result = await Task.detached { MedDictionary.shared.lookup(q) }.value
                exact = result.exact
                suggestions = result.suggestions
            }
            .navigationTitle("Medical Dictionary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct EntryCard: View {
    let entry: MedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.title3.weight(.semibold))
                if !entry.category.isEmpty {
                    Text(entry.category).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(entry.definition)
                .font(.body)
                .textSelection(.enabled)
            if !entry.actions.isEmpty {
                LabeledBlock(title: "Drug class / action", text: entry.actions.replacingOccurrences(of: "; ", with: " · "))
            }
            if !entry.synonyms.isEmpty {
                LabeledBlock(title: "Also called", text: entry.synonyms.replacingOccurrences(of: "; ", with: " · "))
            }
        }
        .padding(.vertical, 6)
    }
}

private struct LabeledBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
    }
}
