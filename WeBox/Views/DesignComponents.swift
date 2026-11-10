import SwiftUI

// The original app's grouped surfaces, blue accent and compact poster rhythm.
// Use semantic surfaces so iOS accessibility and light/dark appearance remain native.
enum WeBoxTheme {
    static var accent: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.32, green: 0.62, blue: 1, alpha: 1)
                : UIColor(red: 0.10, green: 0.37, blue: 0.86, alpha: 1)
        })
    }
    static var background: Color { Color(uiColor: .systemGroupedBackground) }
    static var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static let gutter: CGFloat = 20
    static let radius: CGFloat = 16
}

struct SectionHeading<Trailing: View>: View {
    let title: String
    let trailing: () -> Trailing
    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) { self.title = title; self.trailing = trailing }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer(minLength: 12)
            trailing().font(.subheadline)
        }
    }
}

struct MediaPosterCard: View {
    let item: ContentItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterView(address: item.poster)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if item.isLive {
                        Text("直播").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 4)
                            .foregroundStyle(.white).background(.red, in: Capsule()).padding(8)
                    }
                }
            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
            if !item.summary.isEmpty { Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct MediaListRow: View {
    let item: ContentItem
    var subtitle: String = ""
    var body: some View {
        HStack(spacing: 14) {
            PosterView(address: item.poster).frame(width: 56, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
    }
}

struct InlineErrorView: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("暂时无法加载", systemImage: "exclamationmark.triangle").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            if let retry { Button("重试", action: retry).buttonStyle(.bordered) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(WeBoxTheme.card, in: RoundedRectangle(cornerRadius: WeBoxTheme.radius))
    }
}

struct SourceChip: View {
    let title: String
    let selected: Bool
    var body: some View {
        Text(title).font(.subheadline.weight(selected ? .semibold : .medium)).lineLimit(1)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .foregroundStyle(selected ? WeBoxTheme.accent : Color.primary)
            .background(selected ? WeBoxTheme.accent.opacity(0.12) : WeBoxTheme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? WeBoxTheme.accent.opacity(0.4) : .clear))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
