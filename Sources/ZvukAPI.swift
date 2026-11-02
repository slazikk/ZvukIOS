import Foundation

enum APIError: LocalizedError {
    case invalidResponse, graphql(String)
    var errorDescription: String? { switch self { case .invalidResponse: "Сервис вернул некорректный ответ"; case .graphql(let text): text } }
}

actor ZvukAPI {
    static let shared = ZvukAPI()
    private let endpoint = URL(string: "https://zvuk.com/api/v1/graphql")!
    private let profileEndpoint = URL(string: "https://zvuk.com/api/tiny/profile")!
    private var token: String?
    func configure(token: String?) { self.token = token }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://zvuk.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://zvuk.com", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Auth-Token") }
    }

    private func request(_ query: String, operation: String, variables: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["operationName": operation, "query": query, "variables": variables])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.invalidResponse }
        if let errors = root["errors"] as? [[String: Any]], let message = errors.first?["message"] as? String { throw APIError.graphql(message) }
        guard let result = root["data"] as? [String: Any] else { throw APIError.invalidResponse }
        return result
    }

    func verifyToken(_ value: String) async throws {
        configure(token: value)
        var request = URLRequest(url: profileEndpoint)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["result"] != nil else {
            configure(token: nil)
            throw APIError.graphql("Не удалось проверить токен. Откройте zvuk.com/api/tiny/profile в браузере и скопируйте значение поля token.")
        }
    }

    func quickSearch(_ text: String) async throws -> [SearchItem] {
        let query = "query quickSearch($query: String!, $limit: Int!) { quickSearch(query: $query, limit: $limit) { content { __typename ... on Track { id title duration artists { id title image { src } } release { id title date image { src } artists { id title image { src } } } } ... on Artist { id title image { src } } ... on Release { id title date image { src } artists { id title image { src } } } ... on Playlist { id title description duration image { src } } } } }"
        let data = try await request(query, operation: "quickSearch", variables: ["query": text, "limit": 30])
        let content = ((data["quickSearch"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
        return try content.compactMap { raw in
            guard let kind = raw["__typename"] as? String else { return nil }
            let json = try JSONSerialization.data(withJSONObject: raw)
            switch kind {
            case "Track": return .track(try JSONDecoder().decode(Track.self, from: json))
            case "Artist": return .artist(try JSONDecoder().decode(Artist.self, from: json))
            case "Release": return .release(try JSONDecoder().decode(Release.self, from: json))
            case "Playlist": return .playlist(try JSONDecoder().decode(Playlist.self, from: json))
            default: return nil
            }
        }
    }

    /// «Поток» — серверная персональная волна Звука, а не локальная очередь.
    func personalWave() async throws -> [Track] {
        let query = "query getPersonalWave($first: PositiveInt!, $options: PersonalWaveOptions, $waveSrc: MagicSource) { personalWaveContent(first: $first, options: $options, waveSrc: $waveSrc) { id title duration artists { id title image { src } } release { id title date image { src } artists { id title image { src } } } } }"
        let data = try await request(query, operation: "getPersonalWave", variables: ["first": 25, "waveSrc": "AMAZME", "options": ["mood": "energy:0.5,fun:0.5"]])
        let rows = data["personalWaveContent"] as? [[String: Any]] ?? []
        return try rows.map { try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: $0)) }
    }

    func streamURL(for trackID: String) async throws -> URL {
        let query = "query getStream($ids: [ID!]!) { mediaContents(ids: $ids) { ... on Track { stream { flac high mid } } } }"
        let data = try await request(query, operation: "getStream", variables: ["ids": [trackID]])
        let rows = data["mediaContents"] as? [[String: Any]] ?? []
        let stream = rows.first?["stream"] as? [String: Any]
        // По умолчанию iOS надёжнее играет MP3 High/Mid; FLAC может быть DRM-вариантом.
        for key in ["high", "mid", "flac"] { if let value = stream?[key] as? String, let url = URL(string: value) { return url } }
        throw APIError.graphql("Для трека нет доступного потока")
    }

    func toggleFavorite(trackID: String, add: Bool) async throws {
        let name = add ? "addItemToCollection" : "removeItemFromCollection"
        let mutation = add ? "mutation addItemToCollection($id: ID!, $type: CollectionItemType!) { collection { addItem(id: $id, type: $type) } }" : "mutation removeItemFromCollection($id: ID!, $type: CollectionItemType!) { collection { removeItem(id: $id, type: $type) } }"
        _ = try await request(mutation, operation: name, variables: ["id": trackID, "type": "TRACK"])
    }

    func libraryTracks() async throws -> [Track] {
        let idsQuery = "query userTracks($orderBy: TrackOrderByType, $orderDirection: OrderDirectionType) { collection { tracks(orderBy: $orderBy, orderDirection: $orderDirection) { id } } }"
        let idsData = try await request(idsQuery, operation: "userTracks", variables: ["orderBy": "dateAdded", "orderDirection": "desc"])
        let ids = (((idsData["collection"] as? [String: Any])?["tracks"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        guard !ids.isEmpty else { return [] }
        let query = "query getTracks($ids: [ID!]!) { getTracks(ids: $ids) { id title duration artists { id title image { src } } release { id title date image { src } artists { id title image { src } } } } }"
        let data = try await request(query, operation: "getTracks", variables: ["ids": Array(ids.prefix(100))])
        let rows = data["getTracks"] as? [[String: Any]] ?? []
        return try rows.map { try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: $0)) }
    }

    func playlists() async throws -> [Playlist] {
        let idsQuery = "query userPlaylists { collection { playlists { id } } }"
        let idsData = try await request(idsQuery, operation: "userPlaylists")
        let ids = (((idsData["collection"] as? [String: Any])?["playlists"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        guard !ids.isEmpty else { return [] }
        let query = "query getPlaylists($ids: [ID!]!) { getPlaylists(ids: $ids) { id title description duration image { src } } }"
        let data = try await request(query, operation: "getPlaylists", variables: ["ids": ids])
        let rows = data["getPlaylists"] as? [[String: Any]] ?? []
        return try rows.map { try JSONDecoder().decode(Playlist.self, from: JSONSerialization.data(withJSONObject: $0)) }
    }

    func createPlaylist(name: String) async throws {
        let mutation = "mutation createPlayList($name: String!, $items: [PlaylistItem!]!) { playlist { create(items: $items, name: $name) } }"
        _ = try await request(mutation, operation: "createPlayList", variables: ["name": name, "items": []])
    }
}
