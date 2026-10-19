import UIKit
import PDFKit
import PencilKit

/// A PDF page that can draw itself inverted for night reading.
/// Pencil ink sits in a separate layer on top, so it keeps its real colors.
final class InvertiblePage: PDFPage {
    static var invert = false

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        guard InvertiblePage.invert else { return }
        context.saveGState()
        context.setBlendMode(.difference)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(bounds(for: box).insetBy(dx: -4, dy: -4))
        context.restoreGState()
    }
}

/// PDFView that adds "Medical Dictionary" to the menu shown for selected text.
final class StudyPDFView: PDFView {
    var onDefine: ((String) -> Void)?

    var selectedText: String? {
        let text = currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty || text.count > 80 ? nil : text
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let text = selectedText else { return }
        let action = UIAction(title: "Medical Dictionary", image: UIImage(systemName: "cross.case")) { [weak self] _ in
            self?.onDefine?(text)
        }
        let menu = UIMenu(options: .displayInline, children: [action])
        if builder.menu(for: .lookup) != nil {
            builder.insertChild(menu, atStartOfMenu: .lookup)
        } else {
            builder.insertChild(menu, atStartOfMenu: .root)
        }
    }
}

/// Transparent layer over each page holding that page's Pencil canvas.
final class PageOverlayView: UIView {
    let canvas = PKCanvasView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly   // Pencil draws, fingers still scroll and zoom
        canvas.isScrollEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
    }
}

final class ReaderController: NSObject, ObservableObject {
    static func lastPageKey(for url: URL) -> String { "lastPage.\(url.lastPathComponent)" }

    let url: URL
    let pdfView = StudyPDFView()
    let toolPicker = PKToolPicker()

    @Published var drawingEnabled = false {
        didSet { applyDrawingState() }
    }
    @Published var darkPages: Bool {
        didSet {
            UserDefaults.standard.set(darkPages, forKey: "darkPages")
            applyDarkPages(reload: true)
        }
    }
    @Published private(set) var pageLabel = ""
    @Published var dictionaryRequest: DictionaryRequest?

    private var drawings: [Int: PKDrawing]
    private var overlays: [Int: PageOverlayView] = [:]
    private var saveWork: DispatchWorkItem?
    private var didInitialNavigation = false

    init(url: URL) {
        self.url = url
        self.darkPages = UserDefaults.standard.bool(forKey: "darkPages")
        self.drawings = InkStore.load(for: url)
        super.init()

        pdfView.pageOverlayViewProvider = self
        pdfView.onDefine = { [weak self] text in
            self?.dictionaryRequest = DictionaryRequest(query: text)
        }
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.pageShadowsEnabled = true
        pdfView.pageBreakMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        InvertiblePage.invert = darkPages
        pdfView.document = makeDocument()
        applyDarkPages(reload: false)

        NotificationCenter.default.addObserver(
            self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        updatePageLabel()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func makeDocument() -> PDFDocument? {
        let doc = PDFDocument(url: url)
        doc?.delegate = self   // must be set before pages are touched so they use InvertiblePage
        return doc
    }

    // MARK: Navigation

    /// Call once the view is on screen: jumps to a search hit, or back to where you left off.
    func didAppear(target: ReaderTarget?) {
        guard !didInitialNavigation else { return }
        didInitialNavigation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if let target {
                self.go(to: target)
            } else if let doc = self.pdfView.document {
                let last = UserDefaults.standard.integer(forKey: Self.lastPageKey(for: self.url))
                if last > 0, let page = doc.page(at: min(last, doc.pageCount - 1)) {
                    self.pdfView.go(to: page)
                }
            }
        }
    }

    /// Opens the dictionary for the selected word (or empty if nothing is selected).
    func defineSelection() {
        dictionaryRequest = DictionaryRequest(query: pdfView.selectedText ?? "")
    }

    func go(to target: ReaderTarget) {
        guard let doc = pdfView.document else { return }
        let onPage = doc.findString(target.query, withOptions: SearchEngine.options).filter {
            guard let page = $0.pages.first else { return false }
            return doc.index(for: page) == target.pageIndex
        }
        let match = target.ordinalOnPage < onPage.count ? onPage[target.ordinalOnPage] : onPage.first
        if let match {
            match.color = UIColor.systemYellow.withAlphaComponent(0.6)
            pdfView.highlightedSelections = [match]
            pdfView.go(to: match)
        } else if let page = doc.page(at: target.pageIndex) {
            pdfView.go(to: page)
        }
    }

    private var currentPageIndex: Int? {
        guard let doc = pdfView.document, let page = pdfView.currentPage else { return nil }
        return doc.index(for: page)
    }

    @objc private func pageChanged() {
        updatePageLabel()
        if let index = currentPageIndex {
            UserDefaults.standard.set(index, forKey: Self.lastPageKey(for: url))
        }
        if drawingEnabled { focusCurrentCanvas() }
    }

    private func updatePageLabel() {
        guard let doc = pdfView.document, doc.pageCount > 0 else { pageLabel = ""; return }
        pageLabel = "\((currentPageIndex ?? 0) + 1) / \(doc.pageCount)"
    }

    // MARK: Pencil

    private func applyDrawingState() {
        pdfView.isInMarkupMode = drawingEnabled
        for overlay in overlays.values {
            overlay.isUserInteractionEnabled = drawingEnabled
            toolPicker.setVisible(drawingEnabled, forFirstResponder: overlay.canvas)
        }
        if drawingEnabled {
            focusCurrentCanvas()
        } else {
            overlays.values.forEach { _ = $0.canvas.resignFirstResponder() }
            saveNow()
        }
    }

    private func focusCurrentCanvas() {
        guard let index = currentPageIndex, let overlay = overlays[index] else { return }
        toolPicker.setVisible(true, forFirstResponder: overlay.canvas)
        overlay.canvas.becomeFirstResponder()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        for (index, overlay) in overlays { drawings[index] = overlay.canvas.drawing }
        InkStore.save(drawings, for: url)
    }

    // MARK: Night reading

    private func applyDarkPages(reload: Bool) {
        pdfView.backgroundColor = darkPages ? UIColor(white: 0.08, alpha: 1) : .secondarySystemBackground
        guard reload, InvertiblePage.invert != darkPages else { return }
        InvertiblePage.invert = darkPages

        // Pages are cached as images, so reload the document to redraw them.
        let wasDrawing = drawingEnabled
        let pageIndex = currentPageIndex ?? 0
        saveNow()
        overlays.values.forEach { toolPicker.removeObserver($0.canvas) }
        overlays.removeAll()
        pdfView.document = makeDocument()
        if let page = pdfView.document?.page(at: pageIndex) { pdfView.go(to: page) }
        if wasDrawing {
            DispatchQueue.main.async { [weak self] in self?.applyDrawingState() }
        }
    }
}

extension ReaderController: PDFDocumentDelegate {
    func classForPage() -> AnyClass { InvertiblePage.self }
}

extension ReaderController: PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let doc = view.document else { return nil }
        let index = doc.index(for: page)
        if let existing = overlays[index] { return existing }

        let overlay = PageOverlayView()
        overlay.canvas.drawing = drawings[index] ?? PKDrawing()
        overlay.canvas.tag = index
        overlay.canvas.delegate = self
        overlay.isUserInteractionEnabled = drawingEnabled
        toolPicker.addObserver(overlay.canvas)
        toolPicker.setVisible(drawingEnabled, forFirstResponder: overlay.canvas)
        overlays[index] = overlay
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let overlay = overlayView as? PageOverlayView else { return }
        let index = overlay.canvas.tag
        toolPicker.removeObserver(overlay.canvas)
        if overlays[index] === overlay {
            drawings[index] = overlay.canvas.drawing
            overlays[index] = nil
            scheduleSave()
        }
    }
}

extension ReaderController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        drawings[canvasView.tag] = canvasView.drawing
        scheduleSave()
    }
}
