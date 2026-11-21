import PencilKit
import SwiftUI
import UIKit

/// Temporary whiteboard: full screen, Apple Pencil draws, fingers pan and zoom,
/// nothing is saved. Intentionally minimal (the user wants no more features).
/// The tab bar stays hidden until the menu button asks for it (HIG: hidden
/// navigation must be easy to bring back). The floating buttons are controls
/// above content, so they use Liquid Glass; they sit in the top corners,
/// away from a writing hand of either side.
struct BoardView: View {
    @State private var board = BoardHandle()
    @State private var showTabBar = false

    var body: some View {
        BoardCanvas(handle: board)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button(showTabBar ? "タブバーを隠す" : "タブバーを表示",
                       systemImage: showTabBar ? "xmark" : "square.grid.2x2") {
                    withAnimation { showTabBar.toggle() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    Button("ツール", systemImage: "pencil.tip.crop.circle") { board.toggleTools() }
                        .help("ツールパレットを表示")
                    Button("取り消す", systemImage: "arrow.uturn.backward") { board.undo() }
                        .help("取り消す（⌘Z）")
                    Button("全消去", systemImage: "trash") { board.clear() }
                        .help("全消去（取り消せます）")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(12)
            }
            // Black ink on white in either appearance.
            .environment(\.colorScheme, .light)
            .toolbarVisibility(showTabBar ? .visible : .hidden, for: .tabBar)
            .onAppear { showTabBar = false }
    }
}

/// Lets SwiftUI buttons reach the canvas controller.
@MainActor
final class BoardHandle {
    weak var controller: BoardViewController?
    func toggleTools() { controller?.toggleToolPicker() }
    func undo() { controller?.undo() }
    func clear() { controller?.clear() }
}

private struct BoardCanvas: UIViewControllerRepresentable {
    let handle: BoardHandle

    func makeUIViewController(context: Context) -> BoardViewController {
        let vc = BoardViewController()
        handle.controller = vc
        return vc
    }

    func updateUIViewController(_ vc: BoardViewController, context: Context) {
        handle.controller = vc
    }
}

/// Hosts the PKCanvasView.
///
/// Squeeze (Apple Pencil Pro): PKToolPicker presents itself at the hovering
/// pencil tip once it has been shown (the board shows it briefly on open).
/// If it still does not appear, the squeeze handler shows it where it last
/// was (`pencilInteraction(_:didReceiveSqueeze:)`).
final class BoardViewController: UIViewController, UIPencilInteractionDelegate,
                                  @preconcurrency PKToolPickerObserver {
    /// Board size relative to the visible area.
    private static let boardScale: CGFloat = 3

    private let canvas = PKCanvasView()
    private let toolPicker = BoardViewController.makeToolPicker()
    private let initialTool = PKInkingTool(.pen, color: .black, width: 3)
    /// Tool picker items, for "switch to previous tool" and eraser toggling.
    private var currentItemID: String?
    private var previousItemID: String?
    private var boardReady = false

    /// The standard tool set, with the eraser starting as the pixel eraser
    /// (erases what the tip touches) rather than the object eraser.
    private static func makeToolPicker() -> PKToolPicker {
        let items = PKToolPicker().toolItems.map { item -> PKToolPickerItem in
            item is PKToolPickerEraserItem ? PKToolPickerEraserItem(type: .bitmap) : item
        }
        return PKToolPicker(toolItems: items)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = initialTool
        canvas.backgroundColor = .white
        canvas.overrideUserInterfaceStyle = .light
        canvas.isOpaque = true
        canvas.minimumZoomScale = 1 / Self.boardScale
        canvas.maximumZoomScale = 5
        canvas.bouncesZoom = true
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(canvas)

        toolPicker.colorUserInterfaceStyle = .light
        toolPicker.selectedTool = initialTool
        toolPicker.addObserver(canvas)
        toolPicker.addObserver(self)
        currentItemID = toolPicker.selectedToolItemIdentifier
        // Associated with the canvas, hidden until squeezed or the tools button.
        toolPicker.setVisible(false, forFirstResponder: canvas)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        view.addInteraction(pencil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard !boardReady, size.width > 0, size.height > 0 else { return }
        boardReady = true
        canvas.contentSize = CGSize(width: size.width * Self.boardScale, height: size.height * Self.boardScale)
        // Start in the middle of the board.
        canvas.contentOffset = CGPoint(x: (canvas.contentSize.width - size.width) / 2,
                                       y: (canvas.contentSize.height - size.height) / 2)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        activateCanvas()
        // SwiftUI may still be settling the tab's view (and its focus) when
        // this runs, so the first attempt can be refused; try again on the
        // next turns of the run loop.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.activateCanvas()
            try? await Task.sleep(for: .milliseconds(300))
            self?.activateCanvas()
        }
    }

    /// The tool picker only works while the canvas is first responder, so
    /// take that as soon as the board shows, before any stroke.
    ///
    /// PKToolPicker presents itself at the pencil tip on a squeeze only after
    /// it has been shown once (before that the system's undo/redo palette
    /// appears), so show it briefly the first time, then hide it.
    private func activateCanvas() {
        guard view.window != nil else { return }
        if !canvas.isFirstResponder {
            canvas.becomeFirstResponder()
        }
        guard canvas.isFirstResponder, !pickerPrimed else { return }
        pickerPrimed = true
        toolPicker.setVisible(true, forFirstResponder: canvas)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self else { return }
            self.toolPicker.setVisible(false, forFirstResponder: self.canvas)
        }
    }
    private var pickerPrimed = false

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        toolPicker.setVisible(false, forFirstResponder: canvas)
    }

    /// Erases everything, undoably (⌘Z or the undo button brings it back).
    func clear() {
        guard !canvas.drawing.strokes.isEmpty else { return }
        swapDrawing(to: PKDrawing(), actionName: "全消去")
    }

    /// Drawings replaced by clear(), keyed by undo step. The undo handler
    /// captures only the key, so it stays Sendable.
    private var replaced: [UUID: PKDrawing] = [:]

    private func swapDrawing(to new: PKDrawing, actionName: String) {
        let token = UUID()
        replaced[token] = canvas.drawing
        canvas.drawing = new
        guard let um = canvas.undoManager else { return }
        um.registerUndo(withTarget: self) { vc in
            MainActor.assumeIsolated {
                guard let old = vc.replaced.removeValue(forKey: token) else { return }
                vc.swapDrawing(to: old, actionName: actionName) // registers redo
            }
        }
        um.setActionName(actionName)
    }

    func undo() {
        canvas.undoManager?.undo()
    }

    func toggleToolPicker() {
        canvas.becomeFirstResponder()
        toolPicker.setVisible(!toolPicker.isVisible, forFirstResponder: canvas)
    }

    // MARK: - Apple Pencil squeeze

    func pencilInteraction(_ interaction: UIPencilInteraction,
                           didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // PKToolPicker normally presents itself at the pencil tip. Only if it
        // did not (the picker is still hidden a moment later), show it where
        // it last was, rather than leave the system's undo/redo palette.
        guard squeeze.phase == .ended,
              UIPencilInteraction.preferredSqueezeAction != .ignore,
              !toolPicker.isVisible else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !self.toolPicker.isVisible else { return }
            self.activateCanvas()
            self.toolPicker.setVisible(true, forFirstResponder: self.canvas)
        }
    }

    // MARK: - Apple Pencil double-tap

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        // PKToolPicker may handle the same double-tap itself (it does while
        // it is attached to the first responder). Let it go first, and act
        // only if the selection did not change, so the two never cancel out.
        let before = toolPicker.selectedToolItemIdentifier
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.toolPicker.selectedToolItemIdentifier == before else { return }
            self.handleDoubleTap()
        }
    }

    /// Follows Settings > Apple Pencil > double-tap, switching between the
    /// tool picker's own items, so the eraser is the palette's eraser with
    /// its settings (pixel or object, width).
    private func handleDoubleTap() {
        switch UIPencilInteraction.preferredTapAction {
        case .ignore:
            return
        case .switchEraser:
            if toolPicker.selectedToolItem is PKToolPickerEraserItem {
                selectItem(previousItemID ?? firstInkingItemID)
            } else {
                selectItem(toolPicker.toolItems.first { $0 is PKToolPickerEraserItem }?.identifier)
            }
        case .switchPrevious:
            selectItem(previousItemID ?? firstInkingItemID)
        default: // color palette, ink attributes, contextual palette, …
            toggleToolPicker()
        }
    }

    private var firstInkingItemID: String? {
        toolPicker.toolItems.first { $0 is PKToolPickerInkingItem }?.identifier
    }

    /// Selects a tool picker item; the picker tells the canvas (an observer).
    private func selectItem(_ id: String?) {
        guard let id, id != toolPicker.selectedToolItemIdentifier else { return }
        toolPicker.selectedToolItemIdentifier = id
        noteSelection()
    }

    /// Remembers the item before the current one, for switching back.
    private func noteSelection() {
        let id = toolPicker.selectedToolItemIdentifier
        guard id != currentItemID else { return }
        previousItemID = currentItemID
        currentItemID = id
    }

    // MARK: - PKToolPickerObserver (choices made in the palette)

    func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
        noteSelection()
    }
}
