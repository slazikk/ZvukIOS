import SwiftUI

struct TokenSignInView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var token = ""
    @State private var working = false
    var body: some View {
        NavigationStack { VStack(spacing: 22) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 72)).foregroundStyle(.orange)
            Text("Zvuk Music").font(.largeTitle.bold())
            SecureField("X-Auth-Token", text: $token).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
            if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
            Button(working ? "Проверяем…" : "Войти") { working = true; Task { await session.signIn(token: token.trimmingCharacters(in: .whitespacesAndNewlines)); working = false } }.buttonStyle(.borderedProminent).disabled(token.isEmpty || working)
            Text("Скопируйте token из zvuk.com/api/tiny/profile после входа в Звук.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28).navigationTitle("Авторизация") }
    }
}

struct MainTabs: View {
    var body: some View { TabView {
        FlowView().tabItem { Label("Поток", systemImage: "sparkles") }
        SearchView().tabItem { Label("Поиск", systemImage: "magnifyingglass") }
        LibraryView().tabItem { Label("Медиатека", systemImage: "books.vertical") }
        SettingsView().tabItem { Label("Настройки", systemImage: "gearshape") }
    }.safeAreaInset(edge: .bottom) { MiniPlayer() } }
}

struct FlowView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var tracks = [Track]()
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .purple.opacity(0.85), .orange.opacity(0.55)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView { VStack(alignment: .leading, spacing: 24) {
                HStack { Text("Поток").font(.system(size: 38, weight: .bold)); Spacer(); Image(systemName: "wave.3.right.circle.fill").font(.system(size: 38)) }
                Text("Твоя персональная музыка\nпрямо сейчас").font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                Button { Task { await start() } } label: { Label(loading ? "Собираем поток…" : "Запустить поток", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17) }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).disabled(loading)
                if let error { Text(error).font(.footnote).padding().background(.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 14)) }
                if let playerError = player.error { Text(playerError).font(.footnote).padding().background(.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 14)) }
                Text("В вашем потоке").font(.headline).opacity(tracks.isEmpty ? 0 : 1)
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in FlowTrackRow(index: index + 1, track: track, tracks: tracks) }
            }.foregroundStyle(.white).padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 115) }
        }.task { if tracks.isEmpty { await load() } }
    }
    private func load() async { loading = true; error = nil; do { tracks = try await ZvukAPI.shared.personalWave() } catch { self.error = error.localizedDescription }; loading = false }
    private func start() async { if tracks.isEmpty { await load() }; if let first = tracks.first { await player.play(first, in: tracks) } }
}

private struct FlowTrackRow: View {
    @EnvironmentObject private var player: PlayerStore
    let index: Int; let track: Track; let tracks: [Track]
    var body: some View { Button { Task { await player.play(track, in: tracks) } } label: { HStack(spacing: 12) { Text("\(index)").font(.caption.monospacedDigit()).frame(width: 20); ArtworkView(url: track.artworkURL).frame(width: 52, height: 52); VStack(alignment: .leading) { Text(track.title).lineLimit(1); Text(track.artistText).font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(1) }; Spacer(); Image(systemName: "play.fill").font(.caption) }.padding(8).background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain) }
}

struct SearchView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var text = ""; @State private var results = [SearchItem](); @State private var error: String?
    var body: some View { NavigationStack { List { if let error { Text(error).foregroundStyle(.red) }; ForEach(results) { item in SearchResultButton(item: item, results: results) } }.navigationTitle("Поиск").searchable(text: $text).onChange(of: text) { _, value in search(value) } } }
    private func search(_ value: String) { guard value.count > 1 else { results = []; return }; Task { try? await Task.sleep(for: .milliseconds(300)); guard text == value else { return }; do { results = try await ZvukAPI.shared.quickSearch(value) } catch { self.error = error.localizedDescription } } }
}
private struct SearchResultButton: View {
    @EnvironmentObject private var player: PlayerStore
    let item: SearchItem; let results: [SearchItem]
    var body: some View { Button { if case let .track(track) = item { let queue = results.compactMap { if case let .track(value) = $0 { value } else { nil } }; Task { await player.play(track, in: queue) } } } label: { SearchRow(item: item) }.buttonStyle(.plain) }
}
struct SearchRow: View { let item: SearchItem; var body: some View { HStack(spacing: 12) { ArtworkView(url: artwork).frame(width: 54, height: 54); VStack(alignment: .leading) { Text(item.title).lineLimit(1); Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }; Spacer() } }; private var artwork: URL? { switch item { case .track(let x): x.artworkURL; case .artist(let x): x.image?.src.flatMap(URL.init(string:)); case .release(let x): x.image?.src.flatMap(URL.init(string:)); case .playlist(let x): x.image?.src.flatMap(URL.init(string:)) } } }
struct ArtworkView: View { let url: URL?; var body: some View { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: "music.note").frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }.clipShape(RoundedRectangle(cornerRadius: 8)) } }
struct LibraryView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var tracks = [Track]()
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack { List {
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let error { Text(error).foregroundStyle(.red) }
            if tracks.isEmpty && !loading && error == nil { ContentUnavailableView("В медиатеке пока нет треков", systemImage: "heart") }
            ForEach(tracks) { track in LibraryTrackRow(track: track, tracks: tracks) }
        }.navigationTitle("Медиатека").refreshable { await load() }.task { await load() } }
    }
    private func load() async { loading = true; error = nil; do { tracks = try await ZvukAPI.shared.libraryTracks() } catch { self.error = error.localizedDescription }; loading = false }
}
private struct LibraryTrackRow: View {
    @EnvironmentObject private var player: PlayerStore
    let track: Track; let tracks: [Track]
    var body: some View { Button { Task { await player.play(track, in: tracks) } } label: { SearchRow(item: .track(track)) }.buttonStyle(.plain) }
}
struct SettingsView: View { @EnvironmentObject private var session: SessionStore; var body: some View { NavigationStack { Form { Button("Выйти", role: .destructive) { session.signOut() } }.navigationTitle("Настройки") } } }

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerStore; @State private var showingPlayer = false
    var body: some View { if let track = player.current { HStack { Button { showingPlayer = true } label: { HStack { ArtworkView(url: track.artworkURL).frame(width: 40, height: 40); Text(track.title).lineLimit(1) } }.buttonStyle(.plain); Spacer(); Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }; Button { Task { await player.next() } } label: { Image(systemName: "forward.fill") } }.padding().background(.bar).fullScreenCover(isPresented: $showingPlayer) { NowPlayingView() } } }
}
struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerStore; @Environment(\.dismiss) private var dismiss
    var body: some View { NavigationStack { VStack(spacing: 28) { if let track = player.current { ArtworkView(url: track.artworkURL).frame(width: 280, height: 280); Text(track.title).font(.title2.bold()); Text(track.artistText).foregroundStyle(.secondary); Slider(value: Binding(get: { player.progress }, set: { player.progress = $0 }), in: 0...max(player.duration, 1), onEditingChanged: { if !$0 { player.seek(player.progress) } }); HStack(spacing: 35) { Button { Task { await player.previous() } } label: { Image(systemName: "backward.fill") }; Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }; Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64)) }; Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15") }; Button { Task { await player.next() } } label: { Image(systemName: "forward.fill") } } } else { ContentUnavailableView("Ничего не играет", systemImage: "music.note") }; Spacer() }.padding().navigationTitle("Сейчас играет").toolbar { Button("Готово") { dismiss() } } } }
}
