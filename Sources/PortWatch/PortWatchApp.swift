import SwiftUI

@main
struct PortWatchApp: App {
    @NSApplicationDelegateAdaptor(StatusController.self) private var controller

    var body: some Scene {
        Settings { EmptyView() }  // all UI lives in the status item's panel
    }

    /// One Ethernet socket from the app icon, drawn as a template so macOS tints it for light/dark menu bars.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            let socket = NSBezierPath()
            socket.move(to: NSPoint(x: 1.75, y: 3))
            for (x, y) in [(16.25, 3.0), (16.25, 12), (12.5, 12), (12.5, 15.25), (5.5, 15.25), (5.5, 12), (1.75, 12)] {
                socket.line(to: NSPoint(x: x, y: y))
            }
            socket.close()
            socket.lineWidth = 1.5
            socket.lineJoinStyle = .round
            socket.stroke()
            for x in [5.7, 7.9, 10.1, 12.3] {
                let pin = NSBezierPath()
                pin.move(to: NSPoint(x: x, y: 5.5))
                pin.line(to: NSPoint(x: x, y: 8))
                pin.lineWidth = 1.1
                pin.lineCapStyle = .round
                pin.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}

@MainActor @Observable final class PortStore {
    var ports: [Port] = []
    var updated = Date()
    @ObservationIgnored private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if !UserDefaults.standard.bool(forKey: "paused") { self?.refresh() }
            }
        }
    }

    func refresh() {
        Task.detached {
            let found = scanPorts()
            await MainActor.run { [weak self] in
                guard let self else { return }
                updated = Date()
                if ports != found { ports = found }
            }
        }
    }
}

extension String {
    /// Hidden ports are stored in UserDefaults as "5000,7000".
    var portSet: Set<Int> { Set(split(separator: ",").compactMap { Int($0) }) }
}

struct ContentView: View {
    let store: PortStore
    @AppStorage("hidden") private var hiddenRaw = ""
    @AppStorage("showHidden") private var showHidden = false
    @AppStorage("paused") private var paused = false
    @State private var armed: Port?  // first click on kill arms it, second click kills
    @State private var error: String?

    var body: some View {
        let hidden = hiddenRaw.portSet
        let visible = store.ports.filter { !hidden.contains($0.port) }
        let muted = store.ports.filter { hidden.contains($0.port) }
        let showsMuted = showHidden && !muted.isEmpty

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listening Ports").font(.system(size: 14, weight: .bold))
                    Text(verbatim: (store.ports.isEmpty ? "Nothing listening" : "\(visible.count) visible · \(muted.count) hidden")
                         + (paused ? " · paused" : ""))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.refresh() } label: {
                    HeaderCircle(title: "Refresh", symbol: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r")
                .help("Refresh now (⌘R)")
                Menu {
                    Toggle("Auto Refresh", isOn: Binding(get: { !paused }, set: { paused = !$0 }))
                    Toggle("Show Hidden Ports", isOn: $showHidden)
                } label: {
                    HeaderCircle(title: "Options", symbol: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            Divider().padding(.vertical, 12)

            SectionTitle("Ports")
            if visible.isEmpty && !showsMuted {
                HStack {
                    Text(store.ports.isEmpty ? "No ports are listening." : "All \(muted.count) ports are hidden.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    if !muted.isEmpty {
                        Button("Show") { showHidden = true }.buttonStyle(.link).font(.system(size: 13))
                    }
                }
                .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visible) { row($0, isHidden: false) }
                        if showsMuted {
                            SectionTitle("Hidden").padding(.horizontal, 6).padding(.top, visible.isEmpty ? 0 : 8)
                            ForEach(muted) { row($0, isHidden: true) }
                        }
                    }
                }
                .scrollIndicators(.never)  // still scrolls with trackpad or wheel
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)  // hug short lists, scroll past 300pt
                .padding(.horizontal, -6)  // row highlight bleeds past the column, icons stay aligned
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red).padding(.top, 6)
            }

            Divider().padding(.vertical, 8)

            MenuRow(title: "Quit PortWatch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .padding(.horizontal, -6)
        }
        .padding(16)
        .frame(width: 320)
        .background(VisualEffect().clipShape(.rect(cornerRadius: 18, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private func row(_ p: Port, isHidden: Bool) -> some View {
        PortRow(port: p, isHidden: isHidden, armed: $armed,
                onToggle: { toggle(p.port) }, onKill: { terminate(p) })
    }

    private func toggle(_ port: Int) {
        var set = hiddenRaw.portSet
        if set.remove(port) == nil { set.insert(port) }
        hiddenRaw = set.sorted().map(String.init).joined(separator: ",")
    }

    private func terminate(_ p: Port) {
        armed = nil
        guard p.pid > 0 else { error = "No pid for port \(p.port)"; return }  // kill(0) would signal our own process group
        if kill(p.pid, SIGTERM) == 0 {
            error = nil
            store.refresh()
        } else {
            error = "Can't kill \(p.command) (\(p.pid)): \(String(cString: strerror(errno)))"
        }
    }
}

/// Behind-window blur like system popovers, so the desktop shows through the panel.
private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Round icon used for the header's refresh button and options menu.
private struct HeaderCircle: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(0.1)))
            .contentShape(Circle())
    }
}

private struct SectionTitle: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
    }
}

/// Full-width plain menu item with a hover highlight.
private struct MenuRow: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct PortRow: View {
    let port: Port
    let isHidden: Bool
    @Binding var armed: Port?
    let onToggle: () -> Void
    let onKill: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: port.command.isEmpty ? "Unknown" : port.command)
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(verbatim: "PID \(port.pid)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .opacity(isHidden ? 0.55 : 1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                RoundIconButton(title: isHidden ? "Unhide" : "Hide", symbol: isHidden ? "eye" : "eye.slash", action: onToggle)
                if armed == port {
                    Button(action: onKill) {
                        Text("Kill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(Capsule().fill(Color.red))
                    }
                    .buttonStyle(.plain)
                } else {
                    RoundIconButton(title: "Kill", symbol: "xmark") { armed = port }
                }
            }
            .opacity(hovering || armed == port ? 1 : 0)  // kept in the tree so VoiceOver can still reach them
            Text(verbatim: ":\(port.port)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if !inside, armed == port { armed = nil }  // moving away cancels a pending kill
        }
    }

    @ViewBuilder private var icon: some View {
        if let img = NSRunningApplication(processIdentifier: port.pid)?.icon {
            Image(nsImage: img).resizable().frame(width: 28, height: 28)
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.1)))
        }
    }
}

private struct RoundIconButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}
