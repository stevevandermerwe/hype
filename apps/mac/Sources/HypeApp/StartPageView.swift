import SwiftUI
import HypeCore
import AppKit

/// Shown on a plain launch (no file, nothing typed yet): four ways to begin,
/// in a fixed 2×2 grid, plus the presentations you were last working on.
/// Matches the Qt app's `StartPage.qml`.
struct StartPageView: View {
    @EnvironmentObject var deck: DeckModel
    var onOpen: () -> Void
    var onWingIt: () -> Void
    var onPlanIt: () -> Void
    var onMindMap: () -> Void
    var onChooseRecent: (String) -> Void
    var onRecover: (RecoverySnapshot) -> Void
    var onDismiss: () -> Void

    fileprivate struct Choice: Identifiable {
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
                   icon: "sparkles", action: onPlanIt),
            Choice(id: "mindmap", key: "M", title: "Mind map", blurb: "Paste an outline and turn it into slides",
                   icon: "point.topleft.down.curvedto.point.bottomright.up", action: onMindMap),
        ]
    }
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    private let contentWidth: CGFloat = 680

    @State private var recent: [RecentPresentation] = []
    @State private var recoverable: [RecoverySnapshot] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(choices) { ChoiceCard(choice: $0) }
                }
                if !recoverable.isEmpty { recoveryList }
                if !recent.isEmpty { recentList }
                Button(action: onDismiss) {
                    Label("Back to editing", systemImage: "arrow.uturn.backward")
                    Text("esc").font(.caption).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 48).padding(.vertical, 56)
            .frame(maxWidth: contentWidth + 96)
            .frame(maxWidth: .infinity)
        }
        .background(backdrop)
        .onAppear { refresh() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            // The bundle's icon (Icon/AppIcon.icns, shipped by bin/run); a bare
            // `swift run` binary gets the generic app icon here instead.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hype").font(.system(size: 40, weight: .bold, design: .rounded))
                Text("How do you want to start?").font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() {
        recent = RecentPresentations.list()
        // The deck open right now has its own snapshot; that isn't something to "recover".
        recoverable = (deck.recovery?.pending() ?? []).filter { !($0.key == deck.recoveryKey && deck.dirty) }
    }

    /// Unsaved edits from a session that ended without saving (a crash, or a quit
    /// that skipped the prompt), offered before anything else.
    private var recoveryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Unsaved work from last time", systemImage: "arrow.counterclockwise.circle.fill")
                .font(.headline).foregroundStyle(.orange)
            VStack(spacing: 0) {
                ForEach(Array(recoverable.enumerated()), id: \.element.id) { offset, snapshot in
                    if offset > 0 { Divider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(snapshot.title).font(.body.weight(.medium))
                            Text((snapshot.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Never saved")
                                 + " · " + snapshot.savedAt.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Discard") {
                            deck.recovery?.discard(key: snapshot.key)
                            refresh()
                        }
                        Button("Recover") { onRecover(snapshot) }.buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                }
            }
            .card(cornerRadius: 10)
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent").font(.headline).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(recent.prefix(5).enumerated()), id: \.element.id) { offset, item in
                    if offset > 0 { Divider().padding(.leading, 44) }
                    RecentRow(item: item) { onChooseRecent(item.path) }
                }
            }
            .card(cornerRadius: 10)
        }
    }

    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.accentColor.opacity(0.12), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

private struct ChoiceCard: View {
    let choice: StartPageView.Choice
    @State private var isHovered = false

    var body: some View {
        Button(action: choice.action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Image(systemName: choice.icon)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint.opacity(0.12)))
                    Spacer()
                    Text(choice.key)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.5)))
                }
                Spacer(minLength: 20)
                Text(choice.title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Text(choice.blurb).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .contentShape(Rectangle())
            .card(highlighted: isHovered, cornerRadius: 14)
            .scaleEffect(isHovered ? 1.015 : 1)
            .shadow(color: .black.opacity(isHovered ? 0.12 : 0.04), radius: isHovered ? 12 : 4, y: isHovered ? 6 : 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(choice.key.lowercased())), modifiers: [])
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering } }
    }
}

private struct RecentRow: View {
    let item: RecentPresentation
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext").foregroundStyle(.tint).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.body)
                    Text(item.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(isHovered ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
