import SwiftUI

/// Checkboxes stay open across clicks; an empty set always means all values.
struct MultiSelectFilter: View {
    let title: String
    let options: [(key: String, label: String)]
    @Binding var selection: Set<String>
    @State private var presented = false
    @State private var query = ""
    @ObservedObject private var settings = DisplaySettings.shared

    private var visibleOptions: [(key: String, label: String)] {
        let known = Set(options.map(\.key))
        return (options + selection.subtracting(known).sorted().map { ($0, "\($0) · 当前范围无数据") })
            .filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) || $0.key.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Button { presented.toggle() } label: {
            ThemedMenuLabel(title: title, count: selection.count)
        }
        .buttonStyle(.plain)
        .modifier(ThemedMenuChrome(active: !selection.isEmpty))
        .fixedSize()
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text("\(options.count) 项").font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(themeAccent().opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(themeAccent())
                    Spacer()
                    Button("完成") { presented = false }
                        .buttonStyle(ThemedToolbarButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                ThemedSearchField(title: "搜索\(title)", text: $query)
                ThemedChoiceRow(title: "全部\(title)", selected: selection.isEmpty) { selection = [] }
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(visibleOptions, id: \.key) { option in
                            Toggle(isOn: Binding(get: { selection.contains(option.key) }, set: { on in
                                if on { selection.insert(option.key) } else { selection.remove(option.key) }
                            })) {
                                Text(option.label).font(.system(size: 12)).lineLimit(2).help(option.key)
                            }
                            .toggleStyle(ThemedCheckToggleStyle())
                            .padding(9)
                            .background(selection.contains(option.key) ? themeAccent().opacity(0.10) : .clear,
                                        in: RoundedRectangle(cornerRadius: 4))
                        }
                        if visibleOptions.isEmpty { Text("没有匹配项").foregroundStyle(.secondary).padding(9) }
                    }
                }.frame(maxHeight: 270)
                Text(selection.isEmpty ? "全部 \(options.count) 项 · 可多选" : "已选 \(selection.count) 项 · 点击外部即可收起")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(16).frame(width: 320)
                .foregroundStyle(settings.isPrism ? Prism.silver : .primary)
                .background(settings.isPrism ? Prism.panel : Color(nsColor: .windowBackgroundColor))
                .tint(themeAccent())
                .preferredColorScheme(settings.isDarkSkin ? .dark : nil)
        }
        .onChange(of: presented) { _, showing in if showing { query = "" } }
    }
}

struct FilterChipsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 700).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (view, point) in zip(subviews, result.points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: min(view.sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func arrange(_ views: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        var points: [CGPoint] = []
        for view in views {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += row + 6; row = 0 }
            points.append(CGPoint(x: x, y: y)); x += min(size.width, width) + 6; row = max(row, size.height)
        }
        return (CGSize(width: width, height: y + row), points)
    }
}
