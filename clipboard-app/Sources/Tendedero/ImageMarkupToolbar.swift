import AppKit

/// The leading accessory of the preview's shared HUD. Only the shared preview
/// bar draws a background; styles and less frequent actions use native popovers.
@MainActor final class ImageMarkupToolbar: NSView {
    var onTool: (ImageMarkupTool) -> Void = { _ in }
    var onColor: (MarkupColor) -> Void = { _ in }
    var onWidth: (Double) -> Void = { _ in }
    var onFill: (Bool) -> Void = { _ in }
    var onFontSize: (Double) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onDelete: () -> Void = {}
    var onClear: () -> Void = {}
    var onDone: () -> Void = {}
    var onCrop: () -> Void = {}
    var onApplyCrop: () -> Void = {}
    var onCancelCrop: () -> Void = {}
    var onResetCrop: () -> Void = {}
    let cropButton = ImageMarkupToolbar.icon("crop", L("Crop image"))
    let applyCropButton = ImageMarkupToolbar.icon("checkmark", L("Apply crop"))
    let cancelCropButton = ImageMarkupToolbar.icon("xmark", L("Cancel crop"))
    let resetCropButton = ImageMarkupToolbar.icon("arrow.counterclockwise", L("Reset crop"))
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let colorWell = NSColorWell()
    let widthPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let fontPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let fillButton = NSButton(checkboxWithTitle: L("Fill shape"), target: nil, action: nil)
    let toolPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let styleButton = ImageMarkupToolbar.icon("slider.horizontal.3", L("Annotation style"))
    let moreButton = ImageMarkupToolbar.icon("ellipsis", L("More annotation actions"))
    let statusButton = ImageMarkupToolbar.icon("checkmark.circle", L("Markup status"))
    let stylePopover = NSPopover()
    let morePopover = NSPopover()
    private(set) var toolButtons: [ImageMarkupTool: NSButton] = [:]
    private(set) var isCompact = false
    private(set) var hasError = false
    private(set) var isCropping = false
    private let toolsStack = NSStackView()
    private let row = NSStackView()
    private let undoButton = ImageMarkupToolbar.icon("arrow.uturn.backward", L("Undo"))
    private let redoButton = ImageMarkupToolbar.icon("arrow.uturn.forward", L("Redo"))
    private let overflowUndoButton = ImageMarkupToolbar.icon("arrow.uturn.backward", L("Undo"))
    private let overflowRedoButton = ImageMarkupToolbar.icon("arrow.uturn.forward", L("Redo"))
    let deleteButton = ImageMarkupToolbar.icon("trash", L("Delete annotation"))
    let clearButton = NSButton(title: L("Clear annotations"), target: nil, action: nil)
    let doneButton = ImageMarkupToolbar.icon("checkmark", L("Done"))
    private var widths: [Double] = [0.002, 0.004, 0.008, 0.016]
    private let fontSizes: [Double] = [0.025, 0.05, 0.08, 0.12]
    private static var tools: [(ImageMarkupTool, String, String)] { [
        (.select, "cursorarrow", L("Select annotation")),
        (.pen, "pencil.tip", L("Pen")), (.marker, "highlighter", L("Marker")),
        (.rectangle, "rectangle", L("Rectangle")), (.ellipse, "circle", L("Ellipse")),
        (.arrow, "arrow.up.right", L("Arrow")), (.line, "line.diagonal", L("Line")),
        (.text, "textformat", L("Text annotation"))
    ] }
    static let expandedWidth: CGFloat = 494
    var preferredWidth: CGFloat { isCropping ? 124 : isCompact ? 238 : Self.expandedWidth }
    var ownsKeyboardInput: Bool {
        stylePopover.isShown || morePopover.isShown || (colorWell.isActive && NSColorPanel.shared.isKeyWindow)
    }
    override var intrinsicContentSize: NSSize { NSSize(width: preferredWidth, height: 28) }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.expandedWidth, height: 28))
        setAccessibilityLabel(L("Image markup"))
        toolsStack.orientation = .horizontal; toolsStack.spacing = 2
        for (tool, symbol, label) in Self.tools {
            let button = Self.icon(symbol, label)
            button.setButtonType(.toggle); button.tag = ImageMarkupTool.allCases.firstIndex(of: tool)!
            button.target = self; button.action = #selector(chooseTool(_:))
            toolButtons[tool] = button; toolsStack.addArrangedSubview(button)
            toolPicker.addItem(withTitle: label)
            toolPicker.lastItem?.image = button.image; toolPicker.lastItem?.tag = button.tag
        }
        toolPicker.bezelStyle = .texturedRounded; toolPicker.imagePosition = .imageOnly
        toolPicker.setAccessibilityLabel(L("Annotation tool")); toolPicker.toolTip = L("Annotation tool")
        toolPicker.widthAnchor.constraint(equalToConstant: 46).isActive = true
        toolPicker.heightAnchor.constraint(equalToConstant: 28).isActive = true
        toolPicker.target = self; toolPicker.action = #selector(chooseCompactTool(_:))
        colorWell.color = MarkupColor.red.nsColor; colorWell.colorWellStyle = .minimal
        colorWell.setAccessibilityLabel(L("Annotation color")); colorWell.toolTip = L("Annotation color")
        colorWell.widthAnchor.constraint(equalToConstant: 28).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        doneButton.toolTip = L("Done") + " · ⌘↩"
        cropButton.setButtonType(.toggle)
        for (button, action) in [(cropButton, #selector(crop)), (applyCropButton, #selector(applyCrop)),
                                  (cancelCropButton, #selector(cancelCrop)), (resetCropButton, #selector(resetCrop))] {
            button.target = self; button.action = action
        }
        applyCropButton.toolTip = L("Apply crop") + " · ↩"
        cancelCropButton.toolTip = L("Cancel crop") + " · Esc"
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor), row.heightAnchor.constraint(equalToConstant: 28)
        ])
        configureStylePopover(); configureMorePopover(); rebuildRow()
        colorWell.target = self; colorWell.action = #selector(chooseColor)
        widthPicker.target = self; widthPicker.action = #selector(chooseWidth)
        fillButton.target = self; fillButton.action = #selector(chooseFill)
        fontPicker.target = self; fontPicker.action = #selector(chooseFontSize)
        for (button, action) in [(undoButton, #selector(undo)), (redoButton, #selector(redo)),
            (overflowUndoButton, #selector(undo)), (overflowRedoButton, #selector(redo)),
            (deleteButton, #selector(deleteAnnotation)), (clearButton, #selector(clear)), (doneButton, #selector(done)),
            (styleButton, #selector(showStyle)), (moreButton, #selector(showMore)), (statusButton, #selector(showMore))] {
            button.target = self; button.action = action
        }
        for button in [undoButton, overflowUndoButton] { button.toolTip = L("Undo") + " · ⌘Z" }
        for button in [redoButton, overflowRedoButton] { button.toolTip = L("Redo") + " · ⇧⌘Z" }
        update(tool: .pen, color: .red, width: 0.004, fill: false,
               canUndo: false, canRedo: false, hasSelection: false, status: "")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { closeTransientUI() }
    }

    func setCompact(_ compact: Bool) {
        guard compact != isCompact else { return }
        isCompact = compact; rebuildRow(); invalidateIntrinsicContentSize()
    }
    func setCropMode(_ cropping: Bool) {
        guard cropping != isCropping else { return }
        closeTransientUI(); isCropping = cropping
        cropButton.state = cropping ? .on : .off
        rebuildRow(); invalidateIntrinsicContentSize()
    }
    private func rebuildRow() {
        for view in row.arrangedSubviews { row.removeArrangedSubview(view); view.removeFromSuperview() }
        var views: [NSView]
        if isCropping { views = [cropButton, resetCropButton, cancelCropButton, applyCropButton] }
        else {
            views = [cropButton, isCompact ? toolPicker : toolsStack, colorWell, styleButton]
            if !isCompact { views += [undoButton, redoButton] }
            views += [moreButton, statusButton, doneButton]
        }
        for view in views { row.addArrangedSubview(view) }
    }
    private func configureStylePopover() {
        for label in [L("Thin"), L("Medium"), L("Thick"), L("Heavy")] { widthPicker.addItem(withTitle: label) }
        widthPicker.setAccessibilityLabel(L("Stroke width")); widthPicker.toolTip = L("Stroke width")
        widthPicker.widthAnchor.constraint(equalToConstant: 112).isActive = true
        fillButton.setAccessibilityLabel(L("Fill shape"))
        fontPicker.addItems(withTitles: [L("Small"), L("Medium"), L("Large"), L("Very large")])
        fontPicker.setAccessibilityLabel(L("Annotation text size"))
        fontPicker.widthAnchor.constraint(equalToConstant: 112).isActive = true
        let width = NSStackView(views: [NSTextField(labelWithString: L("Stroke width")), widthPicker])
        let font = NSStackView(views: [NSTextField(labelWithString: L("Annotation text size")), fontPicker])
        for row in [width, font] { row.orientation = .horizontal; row.spacing = 12; row.distribution = .equalSpacing }
        let stack = NSStackView(views: [width, fillButton, font])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        configurePopover(stylePopover, content: stack, width: 294)
        width.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        font.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func configureMorePopover() {
        let actions = NSStackView(views: [overflowUndoButton, overflowRedoButton, deleteButton, clearButton])
        actions.orientation = .horizontal; actions.spacing = 8
        clearButton.bezelStyle = .rounded; clearButton.font = .systemFont(ofSize: 11)
        clearButton.setAccessibilityLabel(L("Clear annotations"))
        statusLabel.font = .systemFont(ofSize: 11); statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityLabel(L("Markup status"))
        let stack = NSStackView(views: [actions, statusLabel])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        configurePopover(morePopover, content: stack, width: 300)
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func configurePopover(_ popover: NSPopover, content: NSStackView, width: CGFloat) {
        let controller = NSViewController(); controller.view = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false; controller.view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -14),
            controller.view.widthAnchor.constraint(equalToConstant: width)
        ])
        popover.contentViewController = controller; popover.behavior = .transient; popover.animates = false
    }
    func closeTransientUI() {
        stylePopover.close(); morePopover.close(); colorWell.deactivate()
    }
    func update(tool: ImageMarkupTool, color: MarkupColor, width: Double, fill: Bool,
                canUndo: Bool, canRedo: Bool, hasSelection: Bool, status: String,
                selectionTool: ImageMarkupTool? = nil, fontSize: Double = 0.05, isError: Bool = false, isDirty: Bool = false) {
        for (value, button) in toolButtons { button.state = value == tool ? .on : .off }
        toolPicker.selectItem(withTag: ImageMarkupTool.allCases.firstIndex(of: tool) ?? 0)
        colorWell.color = color.nsColor
        let effective = selectionTool ?? tool
        widths = effective == .marker ? [0.02, 0.04, 0.06, 0.09] : [0.002, 0.004, 0.008, 0.016]
        let index = widths.indices.min { abs(widths[$0] - width) < abs(widths[$1] - width) } ?? 1
        widthPicker.selectItem(at: index); fillButton.state = fill ? .on : .off
        fillButton.isEnabled = effective == .rectangle || effective == .ellipse
        fontPicker.isEnabled = effective == .text
        fontPicker.selectItem(at: fontSizes.indices.min { abs(fontSizes[$0] - fontSize) < abs(fontSizes[$1] - fontSize) } ?? 1)
        undoButton.isEnabled = canUndo; overflowUndoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo; overflowRedoButton.isEnabled = canRedo
        deleteButton.isEnabled = hasSelection
        statusLabel.stringValue = status; hasError = isError
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        statusButton.image = NSImage(systemSymbolName: isError ? "exclamationmark.triangle.fill" : isDirty ? "pencil.circle" : "checkmark.circle", accessibilityDescription: nil)
        statusButton.contentTintColor = isError ? .systemRed : .secondaryLabelColor
        statusButton.toolTip = status
        statusButton.setAccessibilityLabel(L("Markup status") + (status.isEmpty ? "" : ": " + status))
        statusButton.setAccessibilityHelp(status)
    }

    /// Tool hints follow the user's configured bindings, including disabled keys.
    func refreshKeyHints(_ bindings: KeyboardBindings) {
        let cropHint = bindings.title(.cropImage, in: .imageMarkup)
        cropButton.toolTip = L("Crop image") + (cropHint.isEmpty ? "" : " · " + cropHint)
        let actions: [(ImageMarkupTool, KeyboardAction)] = [(.select, .markupSelect), (.pen, .markupPen),
            (.marker, .markupMarker), (.rectangle, .markupRectangle), (.ellipse, .markupEllipse),
            (.arrow, .markupArrow), (.line, .markupLine), (.text, .markupText)]
        for (tool, action) in actions {
            let hint = bindings.title(action)
            let title = action.title + (hint.isEmpty ? "" : " · " + hint)
            toolButtons[tool]?.toolTip = title
            if let tag = ImageMarkupTool.allCases.firstIndex(of: tool) { toolPicker.menu?.item(withTag: tag)?.title = title }
        }
    }
    private static func icon(_ symbol: String, _ label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: "pencil", accessibilityDescription: label)!
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .regularSquare; button.isBordered = false
        button.setAccessibilityLabel(label); button.toolTip = label
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }
    @objc private func crop() { onCrop() }
    @objc private func applyCrop() { onApplyCrop() }
    @objc private func cancelCrop() { onCancelCrop() }
    @objc private func resetCrop() { onResetCrop() }
    @objc private func chooseTool(_ sender: NSButton) {
        guard ImageMarkupTool.allCases.indices.contains(sender.tag) else { return }
        onTool(ImageMarkupTool.allCases[sender.tag])
    }
    @objc private func chooseCompactTool(_ sender: NSPopUpButton) {
        guard let tag = sender.selectedItem?.tag, ImageMarkupTool.allCases.indices.contains(tag) else { return }
        onTool(ImageMarkupTool.allCases[tag])
    }
    @objc private func chooseColor() {
        guard let color = colorWell.color.usingColorSpace(.sRGB) else { return }
        onColor(MarkupColor(red: max(0, min(1, color.redComponent)), green: max(0, min(1, color.greenComponent)),
                            blue: max(0, min(1, color.blueComponent)), alpha: max(0, min(1, color.alphaComponent))))
    }
    @objc private func chooseWidth() {
        guard widths.indices.contains(widthPicker.indexOfSelectedItem) else { return }
        onWidth(widths[widthPicker.indexOfSelectedItem])
    }
    @objc private func chooseFill() { onFill(fillButton.state == .on) }
    @objc private func chooseFontSize() { if fontSizes.indices.contains(fontPicker.indexOfSelectedItem) { onFontSize(fontSizes[fontPicker.indexOfSelectedItem]) } }
    @objc private func showStyle() {
        if stylePopover.isShown { stylePopover.close(); return }
        morePopover.close(); sizePopover(stylePopover); stylePopover.show(relativeTo: styleButton.bounds, of: styleButton, preferredEdge: .minY)
    }
    @objc private func showMore() {
        if morePopover.isShown { morePopover.close(); return }
        stylePopover.close(); sizePopover(morePopover); morePopover.show(relativeTo: moreButton.bounds, of: moreButton, preferredEdge: .minY)
    }
    private func sizePopover(_ popover: NSPopover) {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        popover.contentSize = view.fittingSize
    }
    @objc private func undo() { onUndo() }
    @objc private func redo() { onRedo() }
    @objc private func deleteAnnotation() { onDelete() }
    @objc private func clear() { onClear() }
    @objc private func done() { onDone() }
}
