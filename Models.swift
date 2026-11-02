import Foundation

struct Artwork: Decodable, Hashable { let src: String? }
struct Artist: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let image: Artwork?
}
struct Release: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let date: String?
    let image: Artwork?
    let artists: [Artist]?
}
struct Track: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let duration: Int?
    let artists: [Artist]?
    let release: Release?

    var artistText: String { artists?.map(\.title).joined(separator: ", ") ?? "Неизвестный исполнитель" }
    var artworkURL: URL? { release?.image?.src.flatMap(URL.init(string:)) }
    var durationText: String {
        let value = duration ?? 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
struct Playlist: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let description: String?
    let image: Artwork?
    let duration: Int?
}

enum SearchItem: Identifiable, Hashable {
    case track(Track), artist(Artist), release(Release), playlist(Playlist)
    var id: String { switch self { case .track(let x): "t-\(x.id)"; case .artist(let x): "a-\(x.id)"; case .release(let x): "r-\(x.id)"; case .playlist(let x): "p-\(x.id)" } }
    var title: String { switch self { case .track(let x): x.title; case .artist(let x): x.title; case .release(let x): x.title; case .playlist(let x): x.title } }
    var subtitle: String { switch self { case .track(let x): x.artistText; case .artist: "Исполнитель"; case .release(let x): x.artists?.map(\.title).joined(separator: ", ") ?? "Релиз"; case .playlist: "Плейлист" } }
}
