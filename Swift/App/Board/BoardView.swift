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
/// Apple Pencil gestures are left entirely to PKToolPicker: squeeze shows its
/// curved palette (tools, color, undo/redo) at the pencil tip, and double-tap
/// follows Settings > Apple Pencil. PKToolPicker handles them only while it
/// is visible (hidden, a squeeze gets just the system undo/redo palette and
/// double-tap does nothing), so the picker is shown whenever the board is;
/// the user can minimize it from the palette itself, as in Notes. The app
/// installs no UIPencilInteraction of its own, which would take the gestures
/// away from PKToolPicker.
final class BoardViewController: UIViewController {
    /// Board size relative to the visible area.
    private static let boardScale: CGFloat = 3

    private let canvas = PKCanvasView()
    private let toolPicker = BoardViewController.makeToolPicker()
    private let initialTool = PKInkingTool(.pen, color: .black, width: 3)
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
        // Fingers pan and zoom; the pencil only draws. Keeping the pencil out
        // of the scroll view's recognizers means a pencil touch never waits
        // on them to fail before the stroke begins.
        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        canvas.panGestureRecognizer.allowedTouchTypes = fingers
        canvas.pinchGestureRecognizer?.allowedTouchTypes = fingers
        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(canvas)

        toolPicker.colorUserInterfaceStyle = .light
        toolPicker.selectedTool = initialTool
        toolPicker.addObserver(canvas)
        // Shown with the canvas (see the type comment); the tools button
        // hides and shows it.
        toolPicker.setVisible(true, forFirstResponder: canvas)
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

    /// The tool picker (and its squeeze palette) works only while the canvas
    /// is first responder, so take that as soon as the board shows, before
    /// any stroke.
    private func activateCanvas() {
        guard view.window != nil, !canvas.isFirstResponder else { return }
        canvas.becomeFirstResponder()
        // Hidden when the board was left (viewWillDisappear); bring it back.
        toolPicker.setVisible(true, forFirstResponder: canvas)
    }

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
}
