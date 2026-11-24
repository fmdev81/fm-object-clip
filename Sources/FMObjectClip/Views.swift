import AppKit
import FMClipCore
import SwiftUI

extension FMClass {
    /// The badge color of the type. System colors read well in light and dark mode.
    var color: Color {
        switch self {
        case .XMSS: return .blue
        case .XMTB: return .purple
        case .XMFD: return .green
        case .XML2: return .orange
        }
    }
}

/// The type of an entry as a colored pill.
struct TypeBadge: View {
    let cls: FMClass
    /// The small badge for a list row: a fixed width, so that the names line up.
    var compact = false

    var body: some View {
        Text(cls.label)
            .font(compact ? .system(size: 10, weight: .semibold) : .caption.weight(.semibold))
            .foregroundStyle(cls.color)
            .lineLimit(1)
            .frame(width: compact ? 46 : nil)
            .padding(.horizontal, compact ? 0 : 7)
            .padding(.vertical, compact ? 1 : 2)
            .background(Capsule().fill(cls.color.opacity(0.16)))
            .overlay(Capsule().strokeBorder(cls.color.opacity(0.35), lineWidth: 0.5))
            .help(cls.rawValue)
    }
}

/// Colors for the XML view. The colors are dynamic, so they change with light and dark mode.
enum XMLHighlighter {
    static func color(_ kind: XMLSyntax) -> NSColor {
        switch kind {
        case .tag: return .systemBlue
        case .attributeName: return .systemPurple
        case .attributeValue: return .systemRed
        case .text: return .labelColor
        case .cdata: return .systemTeal
        case .comment: return .secondaryLabelColor
        case .declaration: return .systemGray
        case .plain: return .labelColor
        }
    }

    static func attributed(_ xml: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString()
        for (kind, part) in XMLFormat.highlight(xml) {
            result.append(NSAttributedString(string: String(part), attributes: [.font: font, .foregroundColor: color(kind)]))
        }
        return result
    }

    static func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.labelColor,
        ])
    }
}

/// A read-only text view that scrolls in both directions and does not wrap lines. You can select and copy text.
struct CodeTextView: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasHorizontalScroller = true
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isHorizontallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.drawsBackground = false
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
        if !storage.isEqual(to: text) {
            storage.setAttributedString(text)
            view.scroll(.zero)
        }
    }
}

/// Hides the title text of the window. The title stays in the Window menu.
struct HiddenWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.titleVisibility = .hidden }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.titleVisibility = .hidden
    }
}

/// Removes the window title from the toolbar (macOS 15 and later). On macOS 13 and 14, HiddenWindowTitle hides it.
struct NoToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

// MARK: - Glass look

/// The background of the list: the system sidebar material, translucent to the desktop behind the window.
/// On macOS 26 the system draws it as Liquid Glass. It works on macOS 13 to 15 too.
struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The soft selection: a light tint of the accent color with a thin edge, not the full accent fill.
struct RowBackground: View {
    let selected: Bool
    let hover: Bool
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if selected {
            shape.fill(Color.accentColor.opacity(0.14))
                .overlay(shape.strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        } else if hover {
            shape.fill(Color.primary.opacity(0.05))
        } else {
            shape.fill(Color.clear)
        }
    }
}

extension View {
    /// Controls on glass: Liquid Glass on macOS 26, a translucent material on macOS 13 to 15.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
    }

    /// Content (the summary and the XML) on an opaque surface with rounded corners and soft depth, so that it is easy to read.
    func contentPanel(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(Color(nsColor: .textBackgroundColor), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}
