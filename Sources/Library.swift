import Foundation
import PDFKit
import PencilKit
import UIKit

struct LibraryItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

/// The app's Documents folder is the library. It is visible in the Files app
/// under "On My iPad › PdfCraft Pad", so PDFs can be dropped in from there too.
final class Library: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    let folder: URL

    init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let newItems = urls
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { LibraryItem(url: $0) }
        if newItems != items { items = newItems }
    }

    func importFiles(_ urls: [URL]) {
        for src in urls {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            let base = src.deletingPathExtension().lastPathComponent
            var dest = folder.appendingPathComponent("\(base).pdf")
            var n = 2
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = folder.appendingPathComponent("\(base) \(n).pdf")
                n += 1
            }
            try? FileManager.default.copyItem(at: src, to: dest)
        }
        reload()
    }

    func delete(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: item.url)
        try? FileManager.default.removeItem(at: InkStore.url(for: item.url))
        UserDefaults.standard.removeObject(forKey: ReaderController.lastPageKey(for: item.url))
        reload()
    }
}

/// Pencil notes live beside the app (not inside the PDF), one file per PDF.
enum InkStore {
    static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ink", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for pdf: URL) -> URL {
        folder.appendingPathComponent(pdf.lastPathComponent + ".ink")
    }

    static func load(for pdf: URL) -> [Int: PKDrawing] {
        guard let data = try? Data(contentsOf: url(for: pdf)),
              let raw = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return [:] }
        var out: [Int: PKDrawing] = [:]
        for (key, value) in raw {
            if let index = Int(key), let drawing = try? PKDrawing(data: value) { out[index] = drawing }
        }
        return out
    }

    static func save(_ drawings: [Int: PKDrawing], for pdf: URL) {
        var raw: [String: Data] = [:]
        for (index, drawing) in drawings where !drawing.strokes.isEmpty {
            raw[String(index)] = drawing.dataRepresentation()
        }
        let file = url(for: pdf)
        if raw.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        if let data = try? PropertyListEncoder().encode(raw) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

enum Thumbnailer {
    static func image(for url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 360, height: 480), for: .cropBox)
        }.value
    }
}
