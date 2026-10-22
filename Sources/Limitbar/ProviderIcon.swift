import AppKit
import SwiftUI
import LimitbarCore

struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 22

    private static let claude = load("claude")
    private static let gpt = load("gpt")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Assets") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if provider == .claude, let icon = Self.claude {
                Image(nsImage: icon).resizable().scaledToFit()
            } else if provider == .chatgpt, let icon = Self.gpt {
                Image(nsImage: icon).resizable().renderingMode(.template)
                    .scaledToFit().foregroundStyle(.primary)
            } else {
                Image(systemName: provider.symbol).resizable().scaledToFit()
                    .foregroundStyle(provider.tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
