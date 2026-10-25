import SwiftUI

/// Anything that can appear in a Settings-style sidebar.
protocol SidebarItem: Hashable, Identifiable {
    var title: String { get }
    var symbol: String { get }
    var tint: Color { get }
}

struct SidebarGroup<Item: SidebarItem>: Identifiable {
    let title: String?
    let items: [Item]
    var id: String { title ?? "top" }
}

/// The sidebar used by Settings and Stats: a card with the same 12pt radius and fill as the
/// grouped Form cards beside it (the system sidebar uses a different radius).
struct CardSidebar<Item: SidebarItem>: View {
    @Binding var selection: Item
    var groups: [SidebarGroup<Item>]
    /// Pass a binding to show the search field.
    var query: Binding<String>?
    var matches: (Item, String) -> Bool = { _, _ in true }
    @Environment(\.colorScheme) private var scheme

    /// Measured from the grouped Form cards so the sidebar reads as the same material.
    static var cardRadius: CGFloat { 12 }

    var body: some View {
        VStack(spacing: 10) {
            if let query { searchField(query) }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { group in
                        let items = group.items.filter { matches($0, query?.wrappedValue ?? "") }
                        if !items.isEmpty {
                            if let title = group.title {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 8)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                            }
                            ForEach(items) { item in
                                CardSidebarRow(item: item, selected: item == selection) { selection = item }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.045) : Color.white)
        )
    }

    private func searchField(_ query: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: query)
                .textFieldStyle(.plain)
                .onChange(of: query.wrappedValue) { _, q in
                    // Jump to the first match so typing feels like System Settings.
                    let all = groups.flatMap(\.items)
                    if !matches(selection, q), let first = all.first(where: { matches($0, q) }) { selection = first }
                }
            if !query.wrappedValue.isEmpty {
                Button { query.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

private struct CardSidebarRow<Item: SidebarItem>: View {
    var item: Item
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SettingsBadge(symbol: item.symbol, tint: item.tint)
                Text(item.title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.85) : (hovering ? Color.primary.opacity(0.06) : .clear))
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The large header card at the top of each page, like System Settings.
struct HeaderCard: View {
    var symbol: String
    var tint: Color
    var title: String
    var summary: String

    var body: some View {
        Section {
            VStack(spacing: 8) {
                SettingsBadge(symbol: symbol, tint: tint, size: 52)
                Text(title).font(.title2.bold())
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

/// The two-column window layout shared by Settings and Stats.
struct SidebarWindow<Item: SidebarItem, Detail: View>: View {
    @Binding var selection: Item
    var groups: [SidebarGroup<Item>]
    var query: Binding<String>?
    var matches: (Item, String) -> Bool = { _, _ in true }
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            CardSidebar(selection: $selection, groups: groups, query: query, matches: matches)
                .frame(width: 228)
                .padding(.leading, 10)
                .padding(.top, 34)      // clears the window's traffic lights
                .padding(.bottom, 10)
            detail
                .formStyle(.grouped)
                .padding(.top, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 780, minHeight: 560)
    }
}
