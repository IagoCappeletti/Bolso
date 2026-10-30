import SwiftUI
import BolsoCore

/// The tools and actions shared by the in-place capture and the editor window.
struct MarkupToolbar: View {
    @ObservedObject var session: ImageEditorSession
    let document: ImageEditorDocument?
    let closeTitle: String
    let saveTitle: String
    let copyTitle: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(AnnotationTool.allCases, id: \.self) { tool in
                        Button { session.tool = tool } label: { Image(systemName: tool.symbol).font(.system(size: 13, weight: .medium)) }
                            .buttonStyle(ToolButtonStyle(selected: session.tool == tool))
                            .help(tool.rawValue).accessibilityLabel(tool.rawValue)
                            .accessibilityAddTraits(session.tool == tool ? .isSelected : [])
                    }
                }.padding(2).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                Divider().frame(height: 22)
                CustomColorButton(session: session)
                    .disabled(session.tool == .blur).opacity(session.tool == .blur ? 0.35 : 1)
                Divider().frame(height: 22)
                HStack(spacing: 6) {
                    Text(sizeLabel).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
                    if session.tool == .text {
                        Slider(value: Binding(get: { session.fontSize }, set: { session.fontSize = $0.rounded() }), in: 12...96).frame(width: 78).accessibilityLabel(sizeLabel)
                        Text("\(Int(session.fontSize))").font(.system(size: 11)).monospacedDigit().frame(width: 20, alignment: .leading)
                    } else {
                        Slider(value: Binding(get: { session.width }, set: { session.width = $0.rounded() }), in: 2...16).frame(width: 78).accessibilityLabel(sizeLabel)
                        Text("\(Int(session.width))").font(.system(size: 11)).monospacedDigit().frame(width: 20, alignment: .leading)
                    }
                }.controlSize(.small)
                Spacer(minLength: 0)
                if let document { HistoryButtons(session: session, document: document) }
            }.disabled(session.busy || document == nil)
            HStack(spacing: 8) {
                context.frame(maxWidth: .infinity, alignment: .leading)
                Button(closeTitle) { session.window?.performClose(nil) }
                    .buttonStyle(ActionButtonStyle()).disabled(session.busy && !session.recognizing).help("\(closeTitle) (Esc)")
                if document != nil { ImageDragHandle(session: session).disabled(session.busy) }
                Button("Copiar texto") { session.copyText() }
                    .buttonStyle(ActionButtonStyle()).disabled(session.busy || document == nil).help("Reconhecer e copiar o texto (⌘⇧C)")
                Button(saveTitle) { session.saveImage() }
                    .buttonStyle(ActionButtonStyle()).disabled(session.busy || document == nil).help("Salvar PNG (⌘S)")
                Button(copyTitle) { session.copyImage() }
                    .buttonStyle(ActionButtonStyle(prominent: true)).disabled(session.busy || document == nil).help("Copiar (⌘C)")
            }
        }.padding(12)
    }

    @ViewBuilder private var context: some View {
        if session.confirmingDiscard {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Descartar as marcações?").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Button("Continuar") { session.confirmingDiscard = false }.buttonStyle(ActionButtonStyle())
                Button("Descartar") { session.window?.performClose(nil) }.buttonStyle(ActionButtonStyle(destructive: true)).help("Esc de novo também descarta")
            }
        } else if session.tool == .text {
            HStack(spacing: 8) {
                TextField("Digite e clique na imagem", text: $session.text).textFieldStyle(.roundedBorder).controlSize(.small)
                Toggle("Fundo", isOn: $session.textBackground).toggleStyle(.checkbox).controlSize(.small).help("Texto sobre uma caixa da cor escolhida")
            }
        } else {
            HStack(spacing: 6) {
                if session.busy { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    if let document {
                        Text("\(document.image.width) × \(document.image.height) px").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }.help(session.message)
        }
    }

    private var sizeLabel: String {
        switch session.tool {
        case .text: return "Tamanho"
        case .counter: return "Tamanho"
        case .blur: return "Intensidade"
        default: return "Traço"
        }
    }
}

/// Keeps the picker inside the capture overlay instead of opening a separate color panel.
private struct CustomColorButton: View {
    @ObservedObject var session: ImageEditorSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button { session.pickingColor.toggle() } label: {
            HStack(spacing: 5) {
                Circle().fill(Color(nsColor: session.color)).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                    .scaleEffect(session.pickingColor ? 1.12 : 1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(session.pickingColor ? 180 : 0))
            }.padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(session.pickingColor ? 0.08 : 0)))
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: session.pickingColor)
        }.buttonStyle(.plain).help("Escolher cor").accessibilityLabel("Escolher cor")
            .background(ColorPopoverAnchor(session: session))
    }
}

/// AppKit lets us disable the popover's native opening/closing animation.
/// The anchor survives color updates, so editing RGB never recreates the popover.
private struct ColorPopoverAnchor: NSViewRepresentable {
    @ObservedObject var session: ImageEditorSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        guard session.pickingColor else {
            if coordinator.popover.isShown { coordinator.popover.performClose(nil) }
            return
        }
        guard !coordinator.popover.isShown, view.window != nil else { return }
        let controller = NSHostingController(rootView:
            CustomColorPicker(selected: session.color, close: { [weak session] in
                session?.pickingColor = false
            }) { [weak session] in session?.color = $0 })
        coordinator.popover.contentViewController = controller
        // Resolve SwiftUI's size before AppKit positions the window. Otherwise the
        // popover can grow over its anchor after the initial placement.
        controller.view.layoutSubtreeIfNeeded()
        coordinator.popover.contentSize = controller.view.fittingSize
        // Exclude the entire toolbar vertically, keeping its controls accessible.
        let toolbarBounds: NSRect
        if view.window is CaptureToolbarPanel, let content = view.window?.contentView {
            toolbarBounds = view.convert(content.bounds, from: content)
        } else {
            toolbarBounds = view.bounds
        }
        let anchor = NSRect(x: view.bounds.minX, y: toolbarBounds.minY - 6,
                            width: view.bounds.width, height: toolbarBounds.height + 12)
        coordinator.popover.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
        coordinator.monitorDismissal(anchor: view)
        if let window = coordinator.popover.contentViewController?.view.window {
            window.level = view.window?.level ?? .normal
            window.makeKey()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
        coordinator.popover.delegate = nil
        coordinator.popover.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        let popover = NSPopover()
        private weak var session: ImageEditorSession?
        private var clickMonitor: Any?
        private var outsideAppMonitor: Any?

        init(session: ImageEditorSession) {
            self.session = session
            super.init()
            popover.animates = false
            // Handle dismissal ourselves: a transient popover closes on mouse-down
            // before the button's mouse-up action, which can immediately reopen it.
            popover.behavior = .applicationDefined
            popover.delegate = self
        }

        func monitorDismissal(anchor: NSView) {
            stopMonitoring()
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak anchor] event in
                guard let self, self.popover.isShown else { return event }
                if event.type == .keyDown {
                    guard event.keyCode == 53 else { return event }
                    self.popover.performClose(nil)
                    return nil
                }
                if event.window === self.popover.contentViewController?.view.window { return event }
                var clickedAnchor = false
                if let anchor, let window = anchor.window, event.window === window {
                    clickedAnchor = anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
                }
                self.popover.performClose(nil)
                // Consume this click so mouse-up cannot reopen the picker.
                return clickedAnchor ? nil : event
            }
            outsideAppMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }

        func stopMonitoring() {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            if let outsideAppMonitor { NSEvent.removeMonitor(outsideAppMonitor) }
            clickMonitor = nil
            outsideAppMonitor = nil
        }

        func popoverDidClose(_ notification: Notification) {
            stopMonitoring()
            session?.pickingColor = false
        }

        deinit { stopMonitoring() }
    }
}

// Explicit alias avoids the SDK’s State macro overload on Command Line Tools.
private typealias PickerState<Value> = SwiftUI.State<Value>

struct CustomColorPicker: View {
    let close: (() -> Void)?
    let choose: (NSColor) -> Void
    @PickerState<Double> private var hue: Double
    @PickerState<Double> private var saturation: Double
    @PickerState<Double> private var brightness: Double
    @PickerState<[String]> private var channels: [String]
    @FocusState private var focusedChannel: Int?

    init(selected: NSColor, close: (() -> Void)? = nil, choose: @escaping (NSColor) -> Void) {
        let rgb = selected.usingColorSpace(.sRGB) ?? .black
        _hue = State(initialValue: Double(rgb.hueComponent))
        _saturation = State(initialValue: Double(rgb.saturationComponent))
        _brightness = State(initialValue: Double(rgb.brightnessComponent))
        _channels = State(initialValue: [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { String(Int(($0 * 255).rounded())) })
        self.close = close
        self.choose = choose
    }

    private var color: NSColor {
        NSColor(colorSpace: .sRGB, hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Escolher cor").font(.system(size: 13, weight: .semibold))
                Spacer()
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: color)).frame(width: 32, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.2)))
                if let close {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Fechar paleta").accessibilityLabel("Fechar paleta")
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color(hue: hue, saturation: 1, brightness: 1)
                    LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    Circle().strokeBorder(.white, lineWidth: 2).background(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
                        .frame(width: 12, height: 12)
                        .position(x: saturation * geometry.size.width, y: (1 - brightness) * geometry.size.height)
                }.clipShape(RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        focusedChannel = nil
                        saturation = min(1, max(0, value.location.x / geometry.size.width))
                        brightness = 1 - min(1, max(0, value.location.y / geometry.size.height))
                        publish()
                    })
            }.frame(height: 150)
                .accessibilityLabel("Saturação e brilho").accessibilityHint("Use os campos RGB para definir a cor pelo teclado")
            Text("Matiz").font(.system(size: 11)).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
                    Capsule().strokeBorder(.white, lineWidth: 2).frame(width: 8, height: 18)
                        .shadow(radius: 1).offset(x: hue * (geometry.size.width - 8))
                }.clipShape(Capsule()).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        focusedChannel = nil
                        hue = min(1, max(0, (value.location.x - 4) / (geometry.size.width - 8)))
                        publish()
                    })
            }.frame(height: 18)
                .accessibilityLabel("Matiz")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: hue = min(1, hue + 0.01)
                    case .decrement: hue = max(0, hue - 0.01)
                    @unknown default: break
                    }
                    publish()
                }
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(["R", "G", "B"][index]).font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField("0–255", text: Binding(get: { channels[index] }, set: { updateChannel(index, text: $0) }))
                            .textFieldStyle(.plain).monospacedDigit()
                            .padding(6).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(focusedChannel == index ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1))
                            .focused($focusedChannel, equals: index)
                            .accessibilityLabel(["Vermelho", "Verde", "Azul"][index])
                            .onSubmit { syncChannels() }
                    }
                }
            }
            Text("RGB · 0 a 255").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(14).frame(width: 260)
            .onChange(of: focusedChannel) { _ in syncChannels() }
    }

    private func syncChannels() {
        channels = [color.redComponent, color.greenComponent, color.blueComponent].map { String(Int(($0 * 255).rounded())) }
    }

    private func publish() {
        syncChannels()
        choose(color)
    }

    private func updateChannel(_ index: Int, text: String) {
        // Allow an empty field while replacing a number, without changing the selected color.
        guard text.isEmpty || (text.allSatisfy { $0.isASCII && $0.isNumber } && Int(text) != nil) else { return }
        channels[index] = text
        guard let value = Int(text) else { return }
        let bounded = min(255, max(0, value))
        if value != bounded { channels[index] = String(bounded) }
        var components = [color.redComponent, color.greenComponent, color.blueComponent]
        components[index] = CGFloat(bounded) / 255
        let rgb = NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
        // Keep the hue when passing through gray or black so dragging remains predictable.
        if rgb.saturationComponent > 0 { hue = Double(rgb.hueComponent) }
        saturation = Double(rgb.saturationComponent)
        brightness = Double(rgb.brightnessComponent)
        choose(rgb)
    }
}

private struct HistoryButtons: View {
    @ObservedObject var session: ImageEditorSession
    @ObservedObject var document: ImageEditorDocument
    var body: some View {
        HStack(spacing: 2) {
            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(ToolButtonStyle(selected: false)).disabled(session.busy || document.annotations.isEmpty)
                .help("Desfazer (⌘Z)").accessibilityLabel("Desfazer")
            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(ToolButtonStyle(selected: false)).disabled(session.busy || document.redoStack.isEmpty)
                .help("Refazer (⌘⇧Z)").accessibilityLabel("Refazer")
        }
    }
}

/// Square icon buttons; the selected tool keeps its fill even while the panel is not key.
struct ToolButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, selected: selected) }
    private struct Styled: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.001)))
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.35)
        }
    }
}

/// Text buttons that keep their look in a panel that never becomes key, so the main action stays recognizable.
struct ActionButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration, prominent: prominent, destructive: destructive) }
    private struct Styled: View {
        let configuration: Configuration
        let prominent: Bool
        let destructive: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent || destructive ? Color.white : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 10).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(fill.opacity(configuration.isPressed ? 0.75 : 1)))
                .opacity(enabled ? 1 : 0.4)
        }
        private var fill: Color {
            if destructive { return .red }
            return prominent ? .accentColor : Color.primary.opacity(0.09)
        }
    }
}
