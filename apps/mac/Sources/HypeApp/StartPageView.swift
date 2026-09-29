import SwiftUI
import HypeCore

/// Shown on a plain launch (no file, nothing typed yet): four ways to begin,
/// plus the presentations you were last working on. Matches the Qt app's
/// `StartPage.qml`.
struct StartPageView: View {
    @EnvironmentObject var deck: DeckModel
    var onOpen: () -> Void
    var onWingIt: () -> Void
    var onPlanIt: () -> Void
    var onMindMap: () -> Void
    var onChooseRecent: (String) -> Void
    var onDismiss: () -> Void

    private struct Choice: Identifiable {
        let id: String; let key: String; let title: String; let blurb: String; let icon: String
        let action: () -> Void
    }
    private var choices: [Choice] {
        [
            Choice(id: "open", key: "O", title: "Open", blurb: "Continue with a presentation you already have",
                  icon: "folder", action: onOpen),
            Choice(id: "wing", key: "W", title: "Wing it", blurb: "Start with a blank slide and just write",
                  icon: "square.and.pencil", action: onWingIt),
            Choice(id: "plan", key: "P", title: "Plan it", blurb: "Describe your talk and let AI draft it",
                  icon: "square.grid.2x2", action: onPlanIt),
            Choice(id: "mindmap", key: "M", title: "Mind map", blurb: "Paste an outline and turn it into slides",
                  icon: "point.topleft.down.curvedto.point.bottomright.up", action: onMindMap),
        ]
    }

    @State private var recent: [RecentPresentation] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hype").font(.system(size: 48, weight: .bold)).foregroundStyle(.tint)
                    Text("How do you want to start?").font(.title3).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)], spacing: 16) {
                    ForEach(choices) { choice in
                        Button(action: choice.action) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: choice.icon).font(.title2).foregroundStyle(.tint)
                                    Spacer()
                                    Text(choice.key).font(.caption).foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                                }
                                Spacer(minLength: 24)
                                Text(choice.title).font(.title3).bold().foregroundStyle(.primary)
                                Text(choice.blurb).font(.callout).foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .frame(height: 160, alignment: .topLeading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.3)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(KeyEquivalent(Character(choice.key.lowercased())), modifiers: [])
                    }
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent").font(.headline).foregroundStyle(.secondary)
                        ForEach(recent.prefix(5)) { item in
                            Button { onChooseRecent(item.path) } label: {
                                HStack(spacing: 12) {
                                    Text(item.name).font(.body)
                                    Text(item.folder).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Back to editing (Esc)", action: onDismiss)
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(48)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
        .onAppear { recent = RecentPresentations.list() }
    }
}
