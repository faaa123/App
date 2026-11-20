import PencilKit
import SwiftUI
import UIKit

/// Temporary whiteboard: full screen, Apple Pencil draws, fingers pan and zoom,
/// nothing is saved. Intentionally minimal (the user wants no more features).
/// The tab bar stays hidden until the menu button asks for it.
struct BoardView: View {
    @State private var board = BoardHandle()
    @State private var showTabBar = false

    var body: some View {
        BoardCanvas(handle: board)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button(showTabBar ? "メニューを隠す" : "メニュー",
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
                    Button("元に戻す", systemImage: "arrow.uturn.backward") { board.undo() }
                    Button("全消去", systemImage: "trash") { board.clear() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(12)
            }
            // Black ink on white even though the app is dark.
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
/// Squeeze (Apple Pencil Pro) is left to PKToolPicker: with the "show
/// contextual palette" setting it shows the palette right at the hovering
/// pencil tip. The UIPencilInteraction here therefore implements only the tap
/// callback (a squeeze callback would override that built-in behavior).
/// PKToolPicker handles double-tap only while it is visible, so we handle it
/// while it is hidden.
final class BoardViewController: UIViewController, UIPencilInteractionDelegate {
    /// Board size relative to the visible area.
    private static let boardScale: CGFloat = 3

    private let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private let initialTool = PKInkingTool(.pen, color: .black, width: 3)
    /// Tool to return to for "switch to previous tool" and eraser toggling.
    private var previousTool: PKTool?
    private var boardReady = false

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
        canvas.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        toolPicker.setVisible(false, forFirstResponder: canvas)
    }

    func clear() {
        canvas.drawing = PKDrawing()
    }

    func undo() {
        canvas.undoManager?.undo()
    }

    func toggleToolPicker() {
        canvas.becomeFirstResponder()
        toolPicker.setVisible(!toolPicker.isVisible, forFirstResponder: canvas)
    }

    // MARK: - Apple Pencil double-tap

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        handleDoubleTap()
    }

    /// Follows Settings > Apple Pencil > double-tap. Only while the picker is
    /// hidden; when visible, PKToolPicker does this itself.
    private func handleDoubleTap() {
        guard !toolPicker.isVisible else { return }
        switch UIPencilInteraction.preferredTapAction {
        case .ignore:
            return
        case .switchEraser:
            if canvas.tool is PKEraserTool {
                select(previousTool ?? initialTool)
            } else {
                select(PKEraserTool(.vector))
            }
        case .switchPrevious:
            select(previousTool ?? initialTool)
        default: // color palette, ink attributes, contextual palette, …
            toggleToolPicker()
        }
    }

    private func select(_ tool: PKTool) {
        previousTool = canvas.tool
        canvas.tool = tool
        toolPicker.selectedTool = tool // keep the picker in sync
    }
}
