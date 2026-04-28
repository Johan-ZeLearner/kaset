#!/usr/bin/env swift
//
//  main.swift
//  Standalone API Explorer for YouTube Music
//
//  A unified tool for exploring both public and authenticated YouTube Music API endpoints.
//  Reads cookies from the Kaset app's debug cookie export for authenticated requests.
//
//  Usage:
//    chmod +x Tools/api-explorer.swift
//    ./Tools/api-explorer.swift [command] [options]
//
//  Commands:
//    browse <browseId> [params]    - Explore a browse endpoint
//    action <endpoint> <body>      - Explore an action endpoint (body as JSON)
//    continuation <token> [ep]     - Explore a continuation (ep: browse or next)
//    list                          - List all known endpoints
//    auth                          - Check authentication status
//    help                          - Show this help message
//
//  Options:
//    -v, --verbose                 - Show full raw JSON response (not truncated)
//    -o, --output <file>           - Save raw JSON response to a file
//
//  Examples:
//    ./Tools/api-explorer.swift browse FEmusic_home
//    ./Tools/api-explorer.swift browse FEmusic_charts
//    ./Tools/api-explorer.swift browse FEmusic_liked_playlists   # Requires auth
//    ./Tools/api-explorer.swift action search '{"query":"never gonna give you up"}'
//    ./Tools/api-explorer.swift continuation <token> next        # Mix queue continuation
//    ./Tools/api-explorer.swift auth
//    ./Tools/api-explorer.swift list
//

import CommonCrypto
import Darwin
import Dispatch
import Foundation
import Network

// MARK: - Configuration

let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
let clientVersion = "1.20231204.01.00"
let baseURL = "https://music.youtube.com/youtubei/v1"
let origin = "https://music.youtube.com"

/// Global auth user index (0 = primary account, 1+ = brand accounts)
nonisolated(unsafe) var globalAuthUserIndex = 0

/// Global brand account ID (21-digit number from myaccount.google.com/brandaccounts)
nonisolated(unsafe) var globalBrandAccountId: String?

// MARK: - Cookie Management

/// Reads cookies from Kaset app's backup file in Application Support.
/// This allows the standalone tool to make authenticated API requests.
func loadCookiesFromAppBackup() -> [HTTPCookie]? {
    guard let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first
    else {
        return nil
    }

    let cookieFile =
        appSupport
            .appendingPathComponent("Kaset", isDirectory: true)
            .appendingPathComponent("cookies.dat")

    guard FileManager.default.fileExists(atPath: cookieFile.path) else {
        return nil
    }

    guard let data = try? Data(contentsOf: cookieFile) else {
        print("⚠️ Cookie file exists but failed to read: \(cookieFile.path)")
        return nil
    }

    guard let cookieDataArray = try? NSKeyedUnarchiver.unarchivedObject(
        ofClasses: [NSArray.self, NSData.self],
        from: data
    ) as? [Data]
    else {
        print(
            "⚠️ Cookie file exists but failed to unarchive. File may be corrupted or use a different format."
        )
        print("   Path: \(cookieFile.path)")
        print("   Size: \(data.count) bytes")
        return nil
    }

    let cookies = cookieDataArray.compactMap { cookieData -> HTTPCookie? in
        guard let stringProperties = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSString.self, NSDate.self, NSNumber.self],
            from: cookieData
        ) as? [String: Any]
        else {
            return nil
        }

        var convertedProperties: [HTTPCookiePropertyKey: Any] = [:]
        for (key, value) in stringProperties {
            convertedProperties[HTTPCookiePropertyKey(key)] = value
        }
        return HTTPCookie(properties: convertedProperties)
    }

    return cookies.isEmpty ? nil : cookies
}

/// Filters cookies to those that match the music.youtube.com domain.
/// Cookies with domain `.youtube.com` match `music.youtube.com` (subdomain matching).
func filterCookiesForMusicYouTube(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
    cookies.filter { cookie in
        let domain = cookie.domain.lowercased()
        // Cookies with leading dot match subdomains (e.g., ".youtube.com" matches "music.youtube.com")
        if domain.hasPrefix(".") {
            let withoutDot = String(domain.dropFirst())
            return "music.youtube.com".hasSuffix(withoutDot) || withoutDot == "music.youtube.com"
        }
        // Exact match or subdomain
        return domain == "music.youtube.com" || "music.youtube.com".hasSuffix("." + domain)
    }
}

/// Gets the SAPISID value from cookies for authentication.
/// Prefers .youtube.com domain cookies over .google.com for music.youtube.com requests.
func getSAPISID(from cookies: [HTTPCookie]) -> String? {
    // Filter to youtube.com domain cookies first (better match for music.youtube.com)
    let ytCookies = filterCookiesForMusicYouTube(cookies)
    let secureCookie = ytCookies.first { $0.name == "__Secure-3PAPISID" }
    let fallbackCookie = ytCookies.first { $0.name == "SAPISID" }
    return (secureCookie ?? fallbackCookie)?.value
}

/// Builds a cookie header string using HTTPCookie's built-in method.
/// This ensures proper cookie formatting that matches what browsers send.
func buildCookieHeader(from cookies: [HTTPCookie]) -> String? {
    // Filter to only cookies that match music.youtube.com
    let matchingCookies = filterCookiesForMusicYouTube(cookies)
    guard !matchingCookies.isEmpty else { return nil }

    // Use HTTPCookie's built-in method for proper formatting
    let headerFields = HTTPCookie.requestHeaderFields(with: matchingCookies)
    return headerFields["Cookie"]
}

/// Computes SAPISIDHASH for YouTube API authentication.
func computeSAPISIDHASH(sapisid: String) -> String {
    let timestamp = Int(Date().timeIntervalSince1970)
    let input = "\(timestamp) \(sapisid) \(origin)"

    let data = Data(input.utf8)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
        _ = CC_SHA1(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    }
    let hashHex = hash.map { String(format: "%02x", $0) }.joined()

    return "\(timestamp)_\(hashHex)"
}

// MARK: - Request Builder

func buildContext(brandAccountId: String? = nil) -> [String: Any] {
    var userDict: [String: Any] = [
        "lockedSafetyMode": false,
    ]

    // Add brand account ID if specified
    if let brandId = brandAccountId ?? globalBrandAccountId {
        userDict["onBehalfOfUser"] = brandId
    }

    return [
        "client": [
            "clientName": "WEB_REMIX",
            "clientVersion": clientVersion,
            "hl": "en",
            "gl": "US",
            "browserName": "Safari",
            "browserVersion": "17.0",
            "osName": "Macintosh",
            "osVersion": "10_15_7",
            "platform": "DESKTOP",
        ],
        "user": userDict,
    ]
}

func buildHeaders(authenticated: Bool = false, authUserIndex: Int? = nil) -> [String: String] {
    var headers: [String: String] = [
        "Content-Type": "application/json",
        "User-Agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        "Origin": origin,
        "Referer": "\(origin)/",
    ]

    if authenticated, let cookies = loadCookiesFromAppBackup() {
        if let sapisid = getSAPISID(from: cookies),
           let cookieHeader = buildCookieHeader(from: cookies)
        {
            let sapisidhash = computeSAPISIDHASH(sapisid: sapisid)
            headers["Cookie"] = cookieHeader
            headers["Authorization"] = "SAPISIDHASH \(sapisidhash)"
            headers["X-Goog-AuthUser"] = "\(authUserIndex ?? globalAuthUserIndex)"
            headers["X-Origin"] = origin
        }
    }

    return headers
}

// MARK: - API Request

func makeRequest(endpoint: String, body: [String: Any], authenticated: Bool = false) async throws
    -> (data: [String: Any], statusCode: Int)
{
    let urlString = "\(baseURL)/\(endpoint)?key=\(apiKey)&prettyPrint=false"
    guard let url = URL(string: urlString) else {
        throw NSError(
            domain: "APIExplorer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]
        )
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    for (key, value) in buildHeaders(authenticated: authenticated) {
        request.setValue(value, forHTTPHeaderField: key)
    }

    var fullBody = body
    fullBody["context"] = buildContext()
    request.httpBody = try JSONSerialization.data(withJSONObject: fullBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(
            domain: "APIExplorer", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
        )
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(
            domain: "APIExplorer", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"]
        )
    }

    return (json, httpResponse.statusCode)
}

// MARK: - Response Analysis

private func joinedRunsText(_ data: [String: Any]?) -> String? {
    guard let data,
          let runs = data["runs"] as? [[String: Any]]
    else {
        return nil
    }

    let text = runs.compactMap { $0["text"] as? String }.joined()
    return text.isEmpty ? nil : text
}

private func findFirstRenderer(named key: String, in value: Any) -> [String: Any]? {
    if let dictionary = value as? [String: Any] {
        if let renderer = dictionary[key] as? [String: Any] {
            return renderer
        }

        for nestedValue in dictionary.values {
            if let renderer = findFirstRenderer(named: key, in: nestedValue) {
                return renderer
            }
        }
    } else if let array = value as? [Any] {
        for item in array {
            if let renderer = findFirstRenderer(named: key, in: item) {
                return renderer
            }
        }
    }

    return nil
}

private func extractPlaylistTrackCount(from text: String) -> Int? {
    guard let regex = try? NSRegularExpression(
        pattern: #"([\d,]+)\s+(?:songs?|tracks?)"#,
        options: .caseInsensitive
    ),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let countRange = Range(match.range(at: 1), in: text)
    else {
        return nil
    }

    return Int(text[countRange].replacingOccurrences(of: ",", with: ""))
}

private func playlistBrowseSummary(_ data: [String: Any]) -> String? {
    guard let shelfRenderer = findFirstRenderer(named: "musicPlaylistShelfRenderer", in: data)
    else {
        return nil
    }

    let shelfContents = shelfRenderer["contents"] as? [[String: Any]] ?? []
    let initialTrackCount = shelfContents.reduce(into: 0) { partialResult, item in
        if item["musicResponsiveListItemRenderer"] != nil {
            partialResult += 1
        }
    }
    let hasContinuation =
        ((shelfRenderer["continuations"] as? [[String: Any]])?.isEmpty == false)
            || (shelfContents.last?["continuationItemRenderer"] != nil)

    let responsiveHeader = findFirstRenderer(named: "musicResponsiveHeaderRenderer", in: data)
    let detailHeader = findFirstRenderer(named: "musicDetailHeaderRenderer", in: data)
    let title =
        joinedRunsText(responsiveHeader?["title"] as? [String: Any])
            ?? joinedRunsText(detailHeader?["title"] as? [String: Any])
    let author: String? = {
        guard let facepile = responsiveHeader?["facepile"] as? [String: Any],
              let avatarStackViewModel = facepile["avatarStackViewModel"] as? [String: Any],
              let text = avatarStackViewModel["text"] as? [String: Any],
              let content = text["content"] as? String,
              !content.isEmpty
        else {
            return nil
        }

        return content
    }()
    let totalTrackCount =
        joinedRunsText(responsiveHeader?["secondSubtitle"] as? [String: Any]).flatMap(
            extractPlaylistTrackCount(from:)
        )
        ?? joinedRunsText(detailHeader?["secondSubtitle"] as? [String: Any]).flatMap(
            extractPlaylistTrackCount(from:)
        )

    var output = "\n🎵 Playlist summary:\n"
    if let title {
        output += "  • Title: \(title)\n"
    }
    if let author {
        output += "  • Author: \(author)\n"
    }
    if let totalTrackCount {
        output += "  • Reported total tracks: \(totalTrackCount.formatted())\n"
    }
    output += "  • Initial track rows: \(initialTrackCount)\n"
    output += "  • Has continuation: \(hasContinuation ? "yes" : "no")\n"

    return output
}

func analyzeResponse(_ data: [String: Any], verbose: Bool = false) -> String {
    var output = ""

    // Top-level keys
    let keys = Array(data.keys).sorted()
    output += "📋 Top-level keys (\(keys.count)): \(keys.joined(separator: ", "))\n"

    // Check for error
    if let error = data["error"] as? [String: Any] {
        let code = error["code"] ?? "unknown"
        let message = error["message"] ?? "Unknown error"
        output += "❌ Error: \(code) - \(message)\n"
        return output
    }

    // Navigate to contents if present
    if let contents = data["contents"] as? [String: Any] {
        output += "\n📦 Contents structure:\n"
        for (key, value) in contents.sorted(by: { $0.key < $1.key }) {
            if let dict = value as? [String: Any] {
                output += "  • \(key): {\(dict.keys.sorted().joined(separator: ", "))}\n"
            } else if let array = value as? [Any] {
                output += "  • \(key): [\(array.count) items]\n"
            } else {
                output += "  • \(key): \(type(of: value))\n"
            }
        }

        // Try to find sections
        if let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]]
        {
            output += "\n📑 Found \(tabs.count) tab(s)\n"

            for (index, tab) in tabs.enumerated() {
                if let tabRenderer = tab["tabRenderer"] as? [String: Any],
                   let title = tabRenderer["title"] as? String
                {
                    output += "  Tab \(index): \"\(title)\"\n"

                    if let content = tabRenderer["content"] as? [String: Any],
                       let sectionList = content["sectionListRenderer"] as? [String: Any],
                       let sections = sectionList["contents"] as? [[String: Any]]
                    {
                        output += "    Sections: \(sections.count)\n"

                        for (sIndex, section) in sections.prefix(10).enumerated() {
                            let sectionType = section.keys.first ?? "unknown"
                            output += "    [\(sIndex)] \(sectionType)\n"

                            if verbose, let renderer = section[sectionType] as? [String: Any] {
                                // Try to get title
                                if let header = renderer["header"] as? [String: Any] {
                                    for (_, hValue) in header {
                                        if let hDict = hValue as? [String: Any],
                                           let title = hDict["title"] as? [String: Any],
                                           let runs = title["runs"] as? [[String: Any]],
                                           let text = runs.first?["text"] as? String
                                        {
                                            output += "        Title: \"\(text)\"\n"
                                        }
                                    }
                                }
                            }
                        }

                        if sections.count > 10 {
                            output += "    ... and \(sections.count - 10) more sections\n"
                        }
                    }
                }
            }
        }
    }

    // Check for header
    if let header = data["header"] as? [String: Any] {
        output += "\n🏷️ Header keys: \(header.keys.sorted().joined(separator: ", "))\n"
    }

    if let playlistSummary = playlistBrowseSummary(data) {
        output += playlistSummary
    }

    return output
}

// MARK: - Commands

/// Known endpoints that require authentication
let authRequiredEndpoints = Set([
    "FEmusic_liked_playlists",
    "FEmusic_liked_videos",
    "FEmusic_history",
    "FEmusic_library_landing",
    "FEmusic_library_albums",
    "FEmusic_library_artists",
    "FEmusic_library_corpus_artists",
    "FEmusic_library_corpus_track_artists",
    "FEmusic_library_songs",
    "FEmusic_library_non_music_audio_list",
    "FEmusic_recently_played",
    "FEmusic_offline",
    "FEmusic_library_privately_owned_landing",
    "FEmusic_library_privately_owned_tracks",
    "FEmusic_library_privately_owned_albums",
    "FEmusic_library_privately_owned_artists",
])

/// Checks if a browseId requires authentication.
/// This includes known endpoints plus dynamic browseId prefixes that are sign-in backed.
func needsAuthentication(_ browseId: String) -> Bool {
    if authRequiredEndpoints.contains(browseId) {
        return true
    }
    // Library artists (MPLAUC...) come from signed-in library responses
    // and return 401 when browsed directly without auth.
    if browseId.hasPrefix("MPLAUC") {
        return true
    }
    // Playlists (VL...) benefit from authentication for personalized content
    if browseId.hasPrefix("VL") || browseId.hasPrefix("PL") {
        return loadCookiesFromAppBackup() != nil // Use auth if available
    }
    // Podcast shows (MPSPP...) require authentication for episode data
    if browseId.hasPrefix("MPSPP") {
        return true
    }
    return false
}

func exploreBrowse(
    _ browseId: String, params: String? = nil, verbose: Bool = false, outputFile: String? = nil
) async {
    let needsAuth = needsAuthentication(browseId)
    let authIcon = needsAuth ? "🔐" : "🌐"

    print("\(authIcon) Exploring browse endpoint: \(browseId)")
    if let params {
        print("   Params: \(params)")
    }
    if needsAuth {
        let hasAuth = loadCookiesFromAppBackup() != nil
        print("   Auth required: \(hasAuth ? "✅ cookies available" : "❌ no cookies found")")
    }
    print()

    var body: [String: Any] = ["browseId": browseId]
    if let params {
        body["params"] = params
    }

    do {
        let (data, statusCode) = try await makeRequest(
            endpoint: "browse", body: body, authenticated: needsAuth
        )

        if statusCode == 401 || statusCode == 403 {
            print("❌ HTTP \(statusCode) - Authentication required")
            print("   Run the Kaset app and sign in, then try again.")
            return
        }

        print("✅ HTTP \(statusCode)")
        print()
        print(analyzeResponse(data, verbose: verbose))

        if verbose {
            print("\n📄 Raw response (pretty-printed):")
            if let prettyData = try? JSONSerialization.data(
                withJSONObject: data, options: .prettyPrinted
            ),
                let prettyString = String(data: prettyData, encoding: .utf8)
            {
                print(prettyString)
            }
        }

        if let outputFile {
            if let prettyData = try? JSONSerialization.data(
                withJSONObject: data, options: .prettyPrinted
            ) {
                let url = URL(fileURLWithPath: outputFile)
                try prettyData.write(to: url)
                print("\n💾 Saved to: \(outputFile)")
            }
        }
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}

/// Known action endpoints that require authentication
/// Known action endpoints that require authentication.
/// Note: music/get_queue works without auth but returns richer data with auth.
let authRequiredActions = Set([
    "like/like",
    "like/dislike",
    "like/removelike",
    "feedback",
    "subscription/subscribe",
    "subscription/unsubscribe",
    "playlist/get_add_to_playlist",
    "browse/edit_playlist",
    "playlist/create",
    "playlist/delete",
    "account/account_menu",
    "account/accounts_list",
    "notification/get_notification_menu",
    "stats/watchtime",
    "next",
])

func exploreAction(
    _ endpoint: String, bodyJson: String, verbose: Bool = false, outputFile: String? = nil
) async {
    let needsAuth = authRequiredActions.contains(endpoint)
    let authIcon = needsAuth ? "🔐" : "🌐"

    print("\(authIcon) Exploring action endpoint: \(endpoint)")
    if needsAuth {
        let hasAuth = loadCookiesFromAppBackup() != nil
        print("   Auth required: \(hasAuth ? "✅ cookies available" : "❌ no cookies found")")
    }
    print()

    guard let bodyData = bodyJson.data(using: .utf8),
          let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
    else {
        print("❌ Invalid JSON body: \(bodyJson)")
        return
    }

    do {
        let (data, statusCode) = try await makeRequest(
            endpoint: endpoint, body: body, authenticated: needsAuth
        )

        if statusCode == 401 || statusCode == 403 {
            print("❌ HTTP \(statusCode) - Authentication required")
            print("   Run the Kaset app and sign in, then try again.")
            return
        }

        print("✅ HTTP \(statusCode)")
        print()
        print(analyzeResponse(data, verbose: verbose))

        if verbose {
            print("\n📄 Raw response (pretty-printed):")
            if let prettyData = try? JSONSerialization.data(
                withJSONObject: data, options: .prettyPrinted
            ),
                let prettyString = String(data: prettyData, encoding: .utf8)
            {
                print(prettyString)
            }
        }

        if let outputFile {
            if let prettyData = try? JSONSerialization.data(
                withJSONObject: data, options: .prettyPrinted
            ) {
                let url = URL(fileURLWithPath: outputFile)
                try prettyData.write(to: url)
                print("\n💾 Saved to: \(outputFile)")
            }
        }
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}

/// Explores a continuation request to fetch more items.
/// - Parameters:
///   - token: The continuation token
///   - endpoint: The endpoint to use ("browse" for home/library, "next" for mix queues)
func exploreContinuation(
    _ token: String, endpoint: String = "browse", verbose: Bool = false, outputFile: String? = nil
) async {
    print("🔄 Exploring continuation request")
    print("   Token: \(token.prefix(50))...")
    print("   Endpoint: \(endpoint)")
    print()

    var body: [String: Any] = ["continuation": token]

    // For "next" endpoint continuations (mix queues), add required parameters
    if endpoint == "next" {
        body["enablePersistentPlaylistPanel"] = true
        body["isAudioOnly"] = true
    }

    do {
        // Always authenticate for continuations
        let (data, statusCode) = try await makeRequest(
            endpoint: endpoint, body: body, authenticated: true
        )

        if statusCode == 401 || statusCode == 403 {
            print("❌ HTTP \(statusCode) - Authentication required")
            return
        }

        print("✅ HTTP \(statusCode)")
        print()
        print(analyzeResponse(data, verbose: verbose))

        // Analyze continuation-specific structure
        print("\n📊 Continuation Analysis:")
        if let continuationContents = data["continuationContents"] as? [String: Any] {
            print("   Found continuationContents with keys: \(Array(continuationContents.keys))")
            for (key, value) in continuationContents {
                if let renderer = value as? [String: Any] {
                    if let contents = renderer["contents"] as? [[String: Any]] {
                        print("   └─ \(key): \(contents.count) items")

                        // For playlistPanelContinuation (mix queues), show song count
                        if key == "playlistPanelContinuation" {
                            var songCount = 0
                            for item in contents {
                                if item["playlistPanelVideoRenderer"] != nil
                                    || item["playlistPanelVideoWrapperRenderer"] != nil
                                {
                                    songCount += 1
                                }
                            }
                            print("   └─ Songs in continuation: \(songCount)")
                        }
                    }
                    if let continuations = renderer["continuations"] as? [[String: Any]] {
                        print(
                            "   └─ \(key) has 'continuations' array (\(continuations.count) tokens)"
                        )
                        // Check for nextRadioContinuationData (mix queue specific)
                        if let firstCont = continuations.first,
                           firstCont["nextRadioContinuationData"] != nil
                        {
                            print("   └─ Has nextRadioContinuationData (more mix songs available)")
                        }
                    }
                }
            }
        } else if let actions = data["onResponseReceivedActions"] as? [[String: Any]] {
            print("   Found onResponseReceivedActions (2025 format)")
            for (idx, action) in actions.enumerated() {
                print("   └─ Action \(idx) keys: \(Array(action.keys))")
                if let appendAction = action["appendContinuationItemsAction"] as? [String: Any],
                   let items = appendAction["continuationItems"] as? [[String: Any]]
                {
                    print("      └─ continuationItems: \(items.count) items")
                }
            }
        } else {
            print("   ⚠️ No recognized continuation format found")
            print("   Top-level keys: \(Array(data.keys))")
        }

        if verbose {
            print("\n📄 Raw response (pretty-printed):")
            if let prettyData = try? JSONSerialization.data(
                withJSONObject: data, options: .prettyPrinted
            ),
                let prettyString = String(data: prettyData, encoding: .utf8)
            {
                print(prettyString)
            }
        }

        if let outputFile {
            if let prettyData = try? JSONSerialization.data(
                withJSONObject: data, options: .prettyPrinted
            ) {
                let url = URL(fileURLWithPath: outputFile)
                try prettyData.write(to: url)
                print("\n💾 Saved to: \(outputFile)")
            }
        }
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}

func checkAuthStatus() {
    print("🔐 Authentication Status")
    print("========================\n")

    guard let cookies = loadCookiesFromAppBackup() else {
        print("❌ No cookies found")
        print()
        print("To enable authenticated API access:")
        print("  1. Run the Kaset app")
        print("  2. Sign in to YouTube Music")
        print("  3. The app will save cookies to ~/Library/Application Support/Kaset/")
        print("  4. Run this tool again")
        return
    }

    let matchingCookies = filterCookiesForMusicYouTube(cookies)
    print("✅ Found \(cookies.count) cookies in app backup")
    print("✅ \(matchingCookies.count) cookies match music.youtube.com domain\n")

    // Check for key auth cookies (in youtube.com domain)
    let authCookieNames = [
        "SAPISID", "__Secure-3PAPISID", "SID", "HSID", "SSID", "APISID", "__Secure-1PAPISID",
    ]

    print("Auth cookies (youtube.com domain):")
    for name in authCookieNames {
        if let cookie = matchingCookies.first(where: { $0.name == name }) {
            var status = "✅"
            var expiry = ""

            if let date = cookie.expiresDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                expiry = formatter.string(from: date)

                if date < Date() {
                    status = "⚠️ EXPIRED"
                }
            } else if cookie.isSessionOnly {
                expiry = "session-only"
            }

            print("  \(status) \(name): expires \(expiry)")
        } else {
            print("  ❌ \(name): not found")
        }
    }

    print()

    // Check if we can compute SAPISIDHASH
    if let sapisid = getSAPISID(from: cookies) {
        print("✅ Can compute SAPISIDHASH for authenticated requests")
        print("   SAPISID value: \(sapisid.prefix(8))... (truncated)")
    } else {
        print("❌ Cannot compute SAPISIDHASH - missing SAPISID cookie")
    }
}

// MARK: - Account Discovery

/// Discovers all available accounts (primary + brand accounts) by probing authuser indices
func discoverAccounts(verbose: Bool) async {
    print("🔍 Discovering Accounts")
    print("=======================\n")

    guard loadCookiesFromAppBackup() != nil else {
        print("❌ No cookies found. Please sign in to Kaset first.")
        return
    }

    var accounts: [(index: Int, name: String, handle: String?)] = []
    let maxAttempts = 10 // Probe up to 10 accounts

    for index in 0 ..< maxAttempts {
        if verbose {
            print("  Probing authuser=\(index)...")
        }

        if let accountInfo = await fetchAccountInfo(authUserIndex: index, verbose: verbose) {
            accounts.append((index: index, name: accountInfo.name, handle: accountInfo.handle))
            if verbose {
                print("    ✅ Found: \(accountInfo.name)")
            }
        } else {
            // No more accounts at this index
            if verbose {
                print("    ❌ No account at index \(index)")
            }
            // If we found at least one account, stop after first failure
            // Brand accounts are typically consecutive starting from 0
            if !accounts.isEmpty {
                break
            }
        }
    }

    print()
    if accounts.isEmpty {
        print("❌ No accounts found. Make sure you're signed in.")
    } else {
        print("📋 Found \(accounts.count) account(s):\n")
        for account in accounts {
            let handleStr = account.handle.map { " (\($0))" } ?? ""
            let typeStr = account.index == 0 ? " [Primary]" : " [Brand Account]"
            print("  \(account.index): \(account.name)\(handleStr)\(typeStr)")
        }
        print()
        print("💡 Use --authuser N to make requests as a specific account")
        print("   Example: ./api-explorer.swift browse FEmusic_liked_playlists --authuser 1")
    }
}

/// Fetches account info for a specific authuser index
private func fetchAccountInfo(authUserIndex: Int, verbose: Bool) async -> (
    name: String, handle: String?
)? {
    let url = URL(string: "\(baseURL)/account/account_menu?key=\(apiKey)")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let headers = buildHeaders(authenticated: true, authUserIndex: authUserIndex)
    for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
    }

    let body: [String: Any] = [
        "context": [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20241127.01.00",
            ],
        ],
    ]

    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }

        // 401/403 means no account at this index
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            if verbose {
                print("    HTTP \(httpResponse.statusCode)")
            }
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Check if we got an error response
        if json["error"] != nil {
            return nil
        }

        // Extract account name from response
        // Path: actions[0].openPopupAction.popup.multiPageMenuRenderer.header.activeAccountHeaderRenderer.accountName.runs[0].text
        guard let actions = json["actions"] as? [[String: Any]],
              let firstAction = actions.first,
              let openPopupAction = firstAction["openPopupAction"] as? [String: Any],
              let popup = openPopupAction["popup"] as? [String: Any],
              let multiPageMenuRenderer = popup["multiPageMenuRenderer"] as? [String: Any],
              let header = multiPageMenuRenderer["header"] as? [String: Any],
              let activeAccountHeaderRenderer = header["activeAccountHeaderRenderer"]
              as? [String: Any]
        else {
            return nil
        }

        // Extract account name
        var accountName: String?
        if let accountNameObj = activeAccountHeaderRenderer["accountName"] as? [String: Any],
           let runs = accountNameObj["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String
        {
            accountName = text
        }

        guard let name = accountName, !name.isEmpty else {
            return nil
        }

        // Extract channel handle (optional)
        var channelHandle: String?
        if let channelHandleObj = activeAccountHeaderRenderer["channelHandle"] as? [String: Any],
           let runs = channelHandleObj["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String
        {
            channelHandle = text
        }

        return (name: name, handle: channelHandle)

    } catch {
        if verbose {
            print("    Error: \(error.localizedDescription)")
        }
        return nil
    }
}

// MARK: - Brand Account Discovery

/// Discovers all brand accounts using the account/accounts_list endpoint
func discoverBrandAccounts(verbose: Bool) async {
    print("🔍 Discovering Brand Accounts")
    print("=============================\n")

    guard loadCookiesFromAppBackup() != nil else {
        print("❌ No cookies found. Please sign in to Kaset first.")
        return
    }

    do {
        let (data, statusCode) = try await makeRequest(
            endpoint: "account/accounts_list",
            body: [:],
            authenticated: true
        )

        guard statusCode == 200 else {
            print("❌ HTTP \(statusCode) - Failed to fetch accounts list")
            return
        }

        // Parse accounts from response
        // Path: actions[0].getMultiPageMenuAction.menu.multiPageMenuRenderer.sections[0]
        //       .accountSectionListRenderer.contents[0].accountItemSectionRenderer.contents[]
        guard let actions = data["actions"] as? [[String: Any]],
              let firstAction = actions.first,
              let getMultiPageMenuAction = firstAction["getMultiPageMenuAction"] as? [String: Any],
              let menu = getMultiPageMenuAction["menu"] as? [String: Any],
              let multiPageMenuRenderer = menu["multiPageMenuRenderer"] as? [String: Any],
              let sections = multiPageMenuRenderer["sections"] as? [[String: Any]],
              let firstSection = sections.first,
              let accountSectionListRenderer = firstSection["accountSectionListRenderer"]
              as? [String: Any],
              let contents = accountSectionListRenderer["contents"] as? [[String: Any]],
              let firstContent = contents.first,
              let accountItemSectionRenderer = firstContent["accountItemSectionRenderer"]
              as? [String: Any],
              let accountItems = accountItemSectionRenderer["contents"] as? [[String: Any]]
        else {
            print("❌ Failed to parse accounts list response")
            if verbose {
                print("\nResponse structure:")
                if let prettyData = try? JSONSerialization.data(
                    withJSONObject: data, options: .prettyPrinted
                ),
                    let prettyString = String(data: prettyData, encoding: .utf8)
                {
                    print(prettyString)
                }
            }
            return
        }

        // Also get the Google account header for the email
        var googleEmail: String?
        if let header = accountSectionListRenderer["header"] as? [String: Any],
           let googleAccountHeaderRenderer = header["googleAccountHeaderRenderer"]
           as? [String: Any],
           let email = googleAccountHeaderRenderer["email"] as? [String: Any],
           let runs = email["runs"] as? [[String: Any]],
           let firstRun = runs.first,
           let text = firstRun["text"] as? String
        {
            googleEmail = text
        }

        if let email = googleEmail {
            print("📧 Google Account: \(email)\n")
        }

        // Extract account info from each item
        var accounts: [(name: String, handle: String?, brandId: String?, isSelected: Bool)] = []

        for accountItem in accountItems {
            guard let item = accountItem["accountItem"] as? [String: Any] else {
                continue
            }

            // Extract account name
            var name: String?
            if let accountName = item["accountName"] as? [String: Any],
               let runs = accountName["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let text = firstRun["text"] as? String
            {
                name = text
            }

            // Extract channel handle
            var handle: String?
            if let channelHandle = item["channelHandle"] as? [String: Any],
               let runs = channelHandle["runs"] as? [[String: Any]],
               let firstRun = runs.first,
               let text = firstRun["text"] as? String
            {
                handle = text
            }

            // Extract brand account ID from pageIdToken
            var brandId: String?
            if let serviceEndpoint = item["serviceEndpoint"] as? [String: Any],
               let selectActiveIdentityEndpoint = serviceEndpoint["selectActiveIdentityEndpoint"]
               as? [String: Any],
               let supportedTokens = selectActiveIdentityEndpoint["supportedTokens"]
               as? [[String: Any]]
            {
                for token in supportedTokens {
                    if let pageIdToken = token["pageIdToken"] as? [String: Any],
                       let pageId = pageIdToken["pageId"] as? String
                    {
                        brandId = pageId
                        break
                    }
                }
            }

            // Check if selected
            let isSelected = item["isSelected"] as? Bool ?? false

            if let accountName = name {
                accounts.append(
                    (name: accountName, handle: handle, brandId: brandId, isSelected: isSelected)
                )
            }
        }

        if accounts.isEmpty {
            print("❌ No accounts found in response")
            return
        }

        print("📋 Found \(accounts.count) account(s):\n")

        for (index, account) in accounts.enumerated() {
            let handleStr = account.handle.map { " (\($0))" } ?? ""
            let selectedStr = account.isSelected ? " ← current" : ""
            let typeStr = account.brandId == nil ? " [Primary]" : " [Brand Account]"

            print("  \(index): \(account.name)\(handleStr)\(typeStr)\(selectedStr)")

            if let brandId = account.brandId {
                print("     Brand ID: \(brandId)")
            }
        }

        print()
        print("💡 To use a brand account, use the --brand flag with the Brand ID:")
        print("   Example: ./api-explorer.swift browse FEmusic_liked_playlists --brand <ID>")
        print()
        print("   This sets context.user.onBehalfOfUser in the request body,")
        print("   which is required for brand account access.")

    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}

func listEndpoints() {
    print(
        """
        ╔══════════════════════════════════════════════════════════════════════════════╗
        ║                      YouTube Music API Endpoint Reference                     ║
        ╚══════════════════════════════════════════════════════════════════════════════╝

        ═══════════════════════════════════════════════════════════════════════════════
        📚 BROWSE ENDPOINTS (POST /browse with browseId)
        ═══════════════════════════════════════════════════════════════════════════════

        🌐 PUBLIC (No Auth Required)
        ───────────────────────────────────────────────────────────────────────────────
        FEmusic_home                  Home feed with personalized recommendations
        FEmusic_explore               Explore page (new releases, charts shortcuts)
        FEmusic_charts                Top songs, albums, trending by country/genre
        FEmusic_moods_and_genres      Browse by mood (Chill, Focus) or genre (Pop, Rock)
        FEmusic_new_releases          Recently released albums, singles, videos
        FEmusic_podcasts              Podcast discovery

        🔐 AUTHENTICATED (Requires Sign-in)
        ───────────────────────────────────────────────────────────────────────────────
        FEmusic_liked_playlists       User's saved/created playlists
        FEmusic_liked_videos          Liked songs (returns playlist format)
        FEmusic_history               Listening history (organized by time)
        FEmusic_library_landing       Library overview page
        FEmusic_library_albums        Saved albums (requires params*)
        FEmusic_library_artists       Rejected with HTTP 400 in current sessions
        FEmusic_library_corpus_artists Followed artists (returns public UC... pages)
        FEmusic_library_corpus_track_artists  Artists chip from Library (returns MPLAUC... pages)
        FEmusic_library_songs         All songs in library (requires params*)
        FEmusic_recently_played       Recently played content
        FEmusic_offline               Downloaded content (may not work on desktop)

        🔐 UPLOADS (User-Uploaded Content)
        ───────────────────────────────────────────────────────────────────────────────
        FEmusic_library_privately_owned_landing   Uploads landing page
        FEmusic_library_privately_owned_tracks    User-uploaded songs
        FEmusic_library_privately_owned_albums    User-uploaded albums
        FEmusic_library_privately_owned_artists   Artists from user uploads

        🌐 DYNAMIC BROWSE IDs (Pattern-based)
        ───────────────────────────────────────────────────────────────────────────────
        VL{playlistId}                Playlist detail (e.g., VLPLxyz...)
        UC{channelId}                 Artist/Channel detail (e.g., UCxyz...)
        MPLAUC{libraryArtistId}       Library artist detail (from Artists chip, requires auth)
        MPREb_{albumId}               Album detail
        MPLYt_{lyricsId}              Lyrics content
        FEmusic_moods_and_genres_category   Mood/Genre category (with params)

        ═══════════════════════════════════════════════════════════════════════════════
        📡 ACTION ENDPOINTS
        ═══════════════════════════════════════════════════════════════════════════════

        🌐 PUBLIC
        ───────────────────────────────────────────────────────────────────────────────
        search                        Search for content
                                      Body: {"query": "search term"}

        music/get_search_suggestions  Autocomplete suggestions
                                      Body: {"input": "partial query"}

        player                        Video metadata, streaming formats, thumbnails
                                      Body: {"videoId": "VIDEO_ID"}

        next                          Track info, lyrics ID, radio queue, feedback tokens
                                      Body: {"videoId": "VIDEO_ID"}

        music/get_queue               Queue data for videos or full playlist tracks
                                      Body: {"videoIds": ["ID1", "ID2"]}
                                        or: {"playlistId": "RDCLAK..."}  (returns ALL tracks)
                                      Note: Response uses playlistPanelVideoWrapperRenderer
                                            wrapper structure, not direct playlistPanelVideoRenderer

        guide                         Sidebar navigation structure
                                      Body: {}

        🔐 RATINGS (Requires Auth)
        ───────────────────────────────────────────────────────────────────────────────
        like/like                     Like a song/album/playlist
                                      Body: {"target": {"videoId": "VIDEO_ID"}}

        like/dislike                  Dislike a song
                                      Body: {"target": {"videoId": "VIDEO_ID"}}

        like/removelike               Remove like/dislike rating
                                      Body: {"target": {"videoId": "VIDEO_ID"}}

        🔐 LIBRARY MANAGEMENT (Requires Auth)
        ───────────────────────────────────────────────────────────────────────────────
        feedback                      Add/remove from library via feedback tokens
                                      Body: {"feedbackTokens": ["TOKEN"]}

        subscription/subscribe        Subscribe to an artist
                                      Body: {"channelIds": ["UC..."]}

        subscription/unsubscribe      Unsubscribe from an artist
                                      Body: {"channelIds": ["UC..."]}

        🔐 PLAYLIST MANAGEMENT (Requires Auth)
        ───────────────────────────────────────────────────────────────────────────────
        playlist/get_add_to_playlist  Get playlists for "Add to Playlist" menu
                                      Body: {"videoId": "VIDEO_ID"}

        playlist/create               Create a new playlist
                                      Body: {"title": "Name", "privacyStatus": "PRIVATE"}

        playlist/delete               Delete a playlist
                                      Body: {"playlistId": "PLxyz..."}

        browse/edit_playlist          Add/remove tracks from playlist
                                      Body: {"playlistId": "...", "actions": [...]}

        🔐 ACCOUNT (Requires Auth)
        ───────────────────────────────────────────────────────────────────────────────
        account/account_menu          Account settings and options
                                      Body: {}

        notification/get_notification_menu   User notifications
                                      Body: {}

        stats/watchtime               Listening statistics
                                      Body: {}

        ═══════════════════════════════════════════════════════════════════════════════
        📌 LIBRARY PARAMS (for library_albums, library_artists, library_songs)
        ═══════════════════════════════════════════════════════════════════════════════

        ggMGKgQIARAA    Recently Added
        ggMGKgQIAhAA    Recently Played
        ggMGKgQIAxAA    Alphabetical A-Z
        ggMGKgQIBBAA    Alphabetical Z-A
        ggMCCAE         Default Sort

        Example: ./api-explorer.swift browse FEmusic_library_albums ggMGKgQIARAA

        FEmusic_library_corpus_track_artists is the Library Artists chip endpoint.
        It requires sign-in for useful content but does not need sort params.
        Signed-in responses return MPLAUC... browseIds (MUSIC_PAGE_TYPE_LIBRARY_ARTIST).
        Browsing an MPLAUC... page directly also requires sign-in.

        ═══════════════════════════════════════════════════════════════════════════════
        💡 USAGE TIPS
        ═══════════════════════════════════════════════════════════════════════════════

        Check auth status:     ./api-explorer.swift auth
        Explore with verbose:  ./api-explorer.swift browse FEmusic_charts -v
        Dynamic browse ID:     ./api-explorer.swift browse VLPLrAXtmErZgOeiKm4sgNOknGvNjby9efdf
        Action with body:      ./api-explorer.swift action player '{"videoId":"dQw4w9WgXcQ"}'

        * Param-based library endpoints above return HTTP 400 without both auth AND params

        """
    )
}

func showHelp() {
    print(
        """
        YouTube Music API Explorer
        ==========================

        A standalone tool for exploring YouTube Music API endpoints.
        Supports both public and authenticated endpoints (reads cookies from Kaset app).

        Usage:
          ./api-explorer.swift <command> [options]

        Commands:
          browse <browseId> [params]     Explore a browse endpoint
          action <endpoint> <body>       Explore an action endpoint (body as JSON)
          continuation <token> [ep]      Explore a continuation (ep: 'browse' or 'next')
          list                           List all known endpoints
          auth                           Check authentication status
          accounts                       Discover available accounts (via authuser)
          brandaccounts                  List all brand accounts with their IDs
          help                           Show this help message

        Options:
          -v, --verbose                  Show full raw JSON response (not truncated)
          -o, --output <file>            Save raw JSON response to a file
          --authuser N                   Use Google account at index N (for multi-account)
          --brand <ID>                   Use brand account ID (21-digit number)

        Examples:
          # Explore public endpoints
          ./api-explorer.swift browse FEmusic_home
          ./api-explorer.swift browse FEmusic_charts
          ./api-explorer.swift browse FEmusic_moods_and_genres -v

          # Explore authenticated endpoints (requires Kaset sign-in)
          ./api-explorer.swift browse FEmusic_liked_playlists
          ./api-explorer.swift browse FEmusic_history
          ./api-explorer.swift browse FEmusic_library_corpus_track_artists

          # Discover brand accounts and use them
          ./api-explorer.swift brandaccounts                            # List brand accounts with IDs
          ./api-explorer.swift browse FEmusic_liked_playlists --brand <ID>  # Use brand account

          # Action endpoints
          ./api-explorer.swift action search '{"query":"never gonna give you up"}'
          ./api-explorer.swift action player '{"videoId":"dQw4w9WgXcQ"}'
          ./api-explorer.swift action next '{"playlistId":"RDEM...","videoId":"abc123"}'

          # Continuation (for pagination / infinite mix)
          ./api-explorer.swift continuation <token>           # browse endpoint (default)
          ./api-explorer.swift continuation <token> next      # next endpoint (for mix queues)

          # Check auth status
          ./api-explorer.swift auth

            Authentication:
                For authenticated endpoints, sign in to the Kaset app first.
                Debug builds export auth cookies to:
                    ~/Library/Application Support/Kaset/cookies.dat

        """
    )
}

// MARK: - SonosService

/// Sonos UPnP service the SOAP request targets.
/// Throwaway spike type — production equivalent lives in Phase 3.
enum SonosService {
    case avTransport
    case renderingControl
}

// MARK: - SonosSpikeError

/// Errors surfaced by the Sonos spike helpers.
/// Throwaway: production code uses typed `SonosError` (Phase 3).
enum SonosSpikeError: Error, CustomStringConvertible {
    case invalidURL(String)
    case soapFault(String)
    case httpStatus(Int)
    case malformedResponse
    case lanIPNotFound

    var description: String {
        switch self {
        case let .invalidURL(value): "invalid URL: \(value)"
        case let .soapFault(message): "Sonos SOAP fault: \(message)"
        case let .httpStatus(code): "Sonos HTTP \(code)"
        case .malformedResponse: "malformed Sonos response"
        case .lanIPNotFound: "could not detect LAN IP via getifaddrs"
        }
    }
}

// MARK: - Sonos Spike Helpers

/// Send a SOAP POST to a Sonos zone's UPnP control endpoint.
///
/// Mirrors RESEARCH.md "Verified pattern: SOAP POST helper" with proper
/// optional unwrapping (no force unwraps per CLAUDE.md). Used by plans 03/05
/// once the placeholder bodies are filled in.
func sendSonosSOAP(
    host: String,
    service: SonosService,
    action: String,
    bodyXML: String
) async throws -> Data {
    let endpoint = service == .avTransport
        ? "MediaRenderer/AVTransport/Control"
        : "MediaRenderer/RenderingControl/Control"
    let serviceURN = service == .avTransport
        ? "urn:schemas-upnp-org:service:AVTransport:1"
        : "urn:schemas-upnp-org:service:RenderingControl:1"

    let urlString = "http://\(host):1400/\(endpoint)"
    guard let url = URL(string: urlString) else {
        throw SonosSpikeError.invalidURL(urlString)
    }

    let envelope = """
    <?xml version="1.0" encoding="utf-8"?>
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <s:Body>
    \(bodyXML)
      </s:Body>
    </s:Envelope>
    """

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    // SOAP should fail loud, not stall — short timeout per RESEARCH.md.
    request.timeoutInterval = 3.0
    request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
    // Literal double quotes around the SOAPACTION value are required by Sonos
    // S1 firmware (RESEARCH.md PITFALLS Pitfall 1).
    request.setValue("\"\(serviceURN)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
    request.setValue("close", forHTTPHeaderField: "Connection")
    request.httpBody = envelope.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
        throw SonosSpikeError.malformedResponse
    }

    // Per RESEARCH.md PITFALLS Pitfall 1: SOAP encodes errors at the body
    // level, not via HTTP status. Check the body for fault markers BEFORE
    // trusting a 200.
    if let bodyString = String(data: data, encoding: .utf8),
       bodyString.contains("<s:Fault>") || bodyString.contains("<errorCode>")
    {
        throw SonosSpikeError.soapFault(String(bodyString.prefix(500)))
    }

    guard http.statusCode == 200 else {
        throw SonosSpikeError.httpStatus(http.statusCode)
    }

    return data
}

/// Best-effort detection of the Mac's LAN IPv4 address.
///
/// Iterates `getifaddrs()` for non-loopback IPv4 addresses on `en*`
/// interfaces (Wi-Fi/Ethernet) and prefers RFC-1918 ranges. Returns `nil`
/// if no candidate is found — callers should fall back to a `--mac-ip`
/// CLI override per RESEARCH.md Section 5.
///
/// Used by plan 03 (`runSonosPlay`) to advertise the spike HTTP listener
/// to Sonos, and by plan 05 indirectly via the same playback flow.
func detectMacLANIP() -> String? {
    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
        return nil
    }
    defer { freeifaddrs(ifaddrPtr) }

    var candidates: [String] = []
    var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let current = ptr {
        defer { ptr = current.pointee.ifa_next }
        guard let addr = current.pointee.ifa_addr else { continue }
        guard addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

        let name = String(cString: current.pointee.ifa_name)
        // Skip loopback, awdl, utun, llw — keep only en0/en1/etc.
        guard name.hasPrefix("en") else { continue }

        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            addr,
            socklen_t(addr.pointee.sa_len),
            &hostBuf,
            socklen_t(hostBuf.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        if result == 0 {
            // Truncate at the first NUL, then decode the leading bytes as UTF-8.
            // (Replaces deprecated `String(cString:)` on [CChar] in macOS 26+.)
            let nulIndex = hostBuf.firstIndex(of: 0) ?? hostBuf.endIndex
            let bytes = hostBuf[..<nulIndex].map { UInt8(bitPattern: $0) }
            let ip = String(decoding: bytes, as: UTF8.self)
            // Heuristic: prefer RFC-1918 LAN ranges over link-local etc.
            if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                candidates.append(ip)
            }
        }
    }
    return candidates.first
}

// MARK: - DiscoveredSonosDevice

/// A single Sonos zone discovered via SSDP M-SEARCH.
/// Throwaway spike type — production equivalent lives in Phase 3 (DISC-01).
struct DiscoveredSonosDevice {
    /// Unique Sonos identifier (USN header). Dedup key.
    let usn: String
    /// IPv4 address parsed from the LOCATION URL.
    let ip: String
    /// Sonos UPnP control port (always 1400 for S1).
    let port: Int
    /// Full LOCATION URL (e.g. http://192.168.x.x:1400/xml/device_description.xml).
    let location: String
    /// SERVER header (e.g. "Linux UPnP/1.0 Sonos/56.0-76060 (ZP100)").
    let server: String
    /// Room name extracted from the device description XML; nil until fetched.
    var roomName: String?
}

// MARK: - DiscoveryCollector

/// Actor wrapping the dedup dictionary so the receive handler (running on a
/// global dispatch queue inside `NWConnectionGroup`) can safely insert without
/// triggering Swift 6 strict-concurrency violations.
actor DiscoveryCollector {
    private(set) var devices: [String: DiscoveredSonosDevice] = [:]

    func add(_ device: DiscoveredSonosDevice) {
        if self.devices[device.usn] == nil {
            self.devices[device.usn] = device
        }
    }

    func snapshot() -> [DiscoveredSonosDevice] {
        Array(self.devices.values)
    }
}

// MARK: - Sonos Discovery Helpers (SPIKE-04)

/// Parse an SSDP HTTP/1.1 200 OK response into a `DiscoveredSonosDevice`.
///
/// Returns nil if the payload is not a valid Sonos zone response (wrong status
/// line, missing required headers, or non-ZonePlayer ST). Strictly defensive
/// per threat model T-02-02 — no force unwraps on attacker-controlled bytes.
func parseSSDPResponse(_ data: Data) -> DiscoveredSonosDevice? {
    guard let text = String(data: data, encoding: .utf8) else { return nil }

    // Split into lines on CRLF (UPnP/HTTP standard).
    let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)
    guard let firstLine = lines.first else { return nil }

    // Status line must indicate success — case-insensitive match on the prefix.
    guard firstLine.uppercased().hasPrefix("HTTP/1.1 200 OK") else { return nil }

    // Parse headers: split each on first ":". Header names are case-insensitive
    // per RFC 7230, so we lowercase the keys.
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        guard let colonIdx = line.firstIndex(of: ":") else { continue }
        let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colonIdx)...]
            .trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { headers[key] = value }
    }

    guard let location = headers["location"],
          let usn = headers["usn"],
          let st = headers["st"]
    else { return nil }

    // Filter to Sonos ZonePlayer responses — other UPnP devices on the LAN
    // (printers, smart TVs, etc.) also reply to ssdp:all but never to a
    // ZonePlayer-targeted M-SEARCH; this is a belt-and-braces check.
    guard st.contains("ZonePlayer") else { return nil }

    guard let url = URLComponents(string: location),
          let host = url.host
    else { return nil }
    let port = url.port ?? 1400
    let server = headers["server"] ?? ""

    return DiscoveredSonosDevice(
        usn: usn,
        ip: host,
        port: port,
        location: location,
        server: server,
        roomName: nil
    )
}

// MARK: - SonosRoomNameParser

/// XMLParser delegate that captures the first `<roomName>` element value it
/// encounters in a Sonos `device_description.xml` document.
///
/// Sonos devices have one `<roomName>` at the root device level plus nested
/// service-level entries on subordinate devices; we only want the first one.
private final class SonosRoomNameParser: NSObject, XMLParserDelegate {
    private(set) var roomName: String?
    private var capturing = false
    private var buffer = ""

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes _: [String: String] = [:]
    ) {
        if self.roomName == nil, elementName == "roomName" {
            self.capturing = true
            self.buffer = ""
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if self.capturing { self.buffer.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        if self.capturing, elementName == "roomName" {
            self.roomName = self.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            self.capturing = false
            // First match wins — abort parse to avoid wasted work on the rest
            // of the (often >10 KB) device description.
            parser.abortParsing()
        }
    }
}

/// Best-effort fetch of the room name for a discovered Sonos device.
///
/// GETs `device.location` (the device_description.xml URL) and parses out the
/// first `<roomName>` element. Never throws past this boundary — any failure
/// (HTTP error, oversized body, parse failure, missing tag) returns nil and
/// the caller continues with `roomName: nil` per threat model T-02-03.
func fetchRoomName(for device: DiscoveredSonosDevice) async -> String? {
    guard let url = URL(string: device.location) else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 3.0
    request.cachePolicy = .reloadIgnoringLocalCacheData

    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch {
        return nil
    }

    // T-02-03: cap body at 256 KB. Real Sonos descriptions are ~10 KB.
    guard data.count <= 256 * 1024 else { return nil }
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        return nil
    }

    let parser = XMLParser(data: data)
    let delegate = SonosRoomNameParser()
    parser.delegate = delegate
    _ = parser.parse()
    let name = delegate.roomName
    return name?.isEmpty == true ? nil : name
}

/// Send SSDP M-SEARCH via Apple-blessed `NWConnectionGroup` + `NWMulticastGroup`.
///
/// Implements RESEARCH.md Section 3 "NWConnectionGroup setup shape" with the
/// actor-wrapped dedup dictionary required by Swift 6 strict concurrency, the
/// 65,535-byte receive cap from threat model T-02-02, and the 3-iterations-
/// 1s-apart repetition discipline from RESEARCH.md "Repetition discipline".
func sendSSDPMSearchViaNWConnectionGroup(
    timeout: TimeInterval
) async throws -> [DiscoveredSonosDevice] {
    let multicast = try NWMulticastGroup(
        for: [.hostPort(host: "239.255.255.250", port: 1900)]
    )
    let group = NWConnectionGroup(with: multicast, using: .udp)
    let collector = DiscoveryCollector()

    let mSearch = "M-SEARCH * HTTP/1.1\r\n"
        + "HOST: 239.255.255.250:1900\r\n"
        + "MAN: \"ssdp:discover\"\r\n"
        + "MX: 3\r\n"
        + "ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"
        + "\r\n"
    guard let mSearchData = mSearch.data(using: .utf8) else {
        throw SonosSpikeError.malformedResponse
    }

    group.setReceiveHandler(
        maximumMessageSize: 65535,
        rejectOversizedMessages: true
    ) { _, content, _ in
        guard let content,
              let device = parseSSDPResponse(content)
        else { return }
        Task { await collector.add(device) }
    }

    group.start(queue: .global())
    group.send(content: mSearchData) { _ in }
    try await Task.sleep(for: .seconds(1))
    group.send(content: mSearchData) { _ in }
    try await Task.sleep(for: .seconds(1))
    group.send(content: mSearchData) { _ in }
    try await Task.sleep(for: .seconds(timeout))
    group.cancel()

    return await collector.snapshot()
}

/// Send SSDP M-SEARCH via raw BSD multicast socket. Fallback for the documented
/// `NWConnectionGroup` unicast-response bug FB8461681 (RESEARCH.md Section 3 —
/// "Documented edge case + BSD socket fallback").
func sendSSDPMSearchViaBSDSocket(
    timeout: TimeInterval
) async throws -> [DiscoveredSonosDevice] {
    let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard sock >= 0 else { throw POSIXError(.EACCES) }
    defer { close(sock) }

    var ttl: Int32 = 4
    _ = setsockopt(
        sock, IPPROTO_IP, IP_MULTICAST_TTL,
        &ttl, socklen_t(MemoryLayout<Int32>.size)
    )

    var loop: UInt8 = 1
    _ = setsockopt(
        sock, IPPROTO_IP, IP_MULTICAST_LOOP,
        &loop, socklen_t(MemoryLayout<UInt8>.size)
    )

    var bindAddr = sockaddr_in()
    bindAddr.sin_family = sa_family_t(AF_INET)
    bindAddr.sin_port = 0 // ephemeral
    bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
    let bindResult = withUnsafePointer(to: &bindAddr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }

    // Non-blocking so the recvfrom loop can poll without blocking the task.
    let flags = fcntl(sock, F_GETFL, 0)
    _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

    var dest = sockaddr_in()
    dest.sin_family = sa_family_t(AF_INET)
    dest.sin_port = UInt16(1900).bigEndian
    _ = "239.255.255.250".withCString { cstr in
        inet_pton(AF_INET, cstr, &dest.sin_addr)
    }

    let mSearch = "M-SEARCH * HTTP/1.1\r\n"
        + "HOST: 239.255.255.250:1900\r\n"
        + "MAN: \"ssdp:discover\"\r\n"
        + "MX: 3\r\n"
        + "ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"
        + "\r\n"
    let bytes = Array(mSearch.utf8)

    func sendOnce() {
        bytes.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(
                        sock, buf.baseAddress, buf.count, 0, sa,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }

    // Send 3 M-SEARCH packets 1s apart.
    sendOnce()
    try await Task.sleep(for: .seconds(1))
    sendOnce()
    try await Task.sleep(for: .seconds(1))
    sendOnce()

    // Receive loop: poll non-blocking recvfrom every ~50ms until timeout.
    var devices: [String: DiscoveredSonosDevice] = [:]
    let deadline = Date().addingTimeInterval(timeout)
    var recvBuf = [UInt8](repeating: 0, count: 65535)

    while Date() < deadline {
        var fromAddr = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = recvBuf.withUnsafeMutableBufferPointer { buf -> Int in
            withUnsafeMutablePointer(to: &fromAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, buf.baseAddress, buf.count, 0, sa, &fromLen)
                }
            }
        }
        if received > 0 {
            let payload = Data(recvBuf.prefix(received))
            if let device = parseSSDPResponse(payload), devices[device.usn] == nil {
                devices[device.usn] = device
            }
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    return Array(devices.values)
}

// MARK: - Sonos Spike Subcommands (placeholders — bodies filled by plans 02–06)

/// SPIKE-04 — SSDP M-SEARCH for Sonos S1 zones on the LAN.
///
/// Implements CONTEXT.md D-05: this CLI runs unsandboxed, so multicast send /
/// receive works without the still-pending Apple multicast entitlement.
///
/// Exit codes:
/// - 0 → GO: NWConnectionGroup discovered ≥1 device
/// - 1 → NO-GO: zero devices on either transport
/// - 2 → GO-WITH-WORKAROUND: NWConnectionGroup found nothing but BSD did
func runSonosDiscover(args: [String]) async {
    var timeout = 5
    var useBSDFallback = false
    var verbose = false
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--timeout":
            if i + 1 < args.count, let parsed = Int(args[i + 1]) {
                timeout = max(3, min(30, parsed))
                i += 2
            } else {
                print("❌ --timeout requires an integer 3..30")
                exit(1)
            }
        case "--bsd":
            useBSDFallback = true
            i += 1
        case "--verbose", "-v":
            verbose = true
            i += 1
        default:
            i += 1
        }
    }

    print("🔍 SPIKE-04 — SSDP discovery on 239.255.255.250:1900")
    print("   Transport: \(useBSDFallback ? "BSD socket fallback" : "NWConnectionGroup")")
    print("   Timeout:   \(timeout)s")
    if let lanIP = detectMacLANIP() {
        print("   Mac LAN IP: \(lanIP)")
    }
    print("")

    do {
        var devices = useBSDFallback
            ? try await sendSSDPMSearchViaBSDSocket(timeout: TimeInterval(timeout))
            : try await sendSSDPMSearchViaNWConnectionGroup(timeout: TimeInterval(timeout))

        // Auto-fallback heuristic: if NWConnectionGroup returned 0 devices,
        // try BSD and exit with code 2 (go-with-workaround) if BSD finds them.
        var goWithWorkaround = false
        if devices.isEmpty, !useBSDFallback {
            print("⚠️  NWConnectionGroup returned 0 devices — auto-trying BSD socket fallback...")
            devices = try await sendSSDPMSearchViaBSDSocket(timeout: TimeInterval(timeout))
            if !devices.isEmpty {
                goWithWorkaround = true
                print("⚠️  BSD socket found \(devices.count) device(s) — FB8461681 likely still bites macOS 26")
            }
        }

        if devices.isEmpty {
            print("❌ NO-GO: zero devices responded from either transport")
            print("   Diagnostic: try `sudo tcpdump -i any port 1900` while re-running this command")
            print("   to see whether M-SEARCH packets actually leave the Mac (RESEARCH.md Pitfall 5)")
            exit(1)
        }

        // Fetch room names for each device (best-effort, parallel).
        await withTaskGroup(of: (Int, String?).self) { taskGroup in
            for (idx, device) in devices.enumerated() {
                taskGroup.addTask { await (idx, fetchRoomName(for: device)) }
            }
            for await (idx, name) in taskGroup {
                devices[idx].roomName = name
            }
        }

        let verdict = goWithWorkaround ? "GO-WITH-WORKAROUND" : "GO"
        print("✅ \(verdict): discovered \(devices.count) Sonos device(s):")
        for device in devices {
            let name = device.roomName ?? "(roomName unknown)"
            print("   • \(name) — \(device.ip):\(device.port)")
            if verbose {
                print("       USN:    \(device.usn)")
                print("       SERVER: \(device.server)")
                print("       LOCATION: \(device.location)")
            }
        }
        exit(goWithWorkaround ? 2 : 0)
    } catch {
        print("❌ NO-GO: \(error)")
        exit(1)
    }
}

/// SPIKE-03 — Serve test fixture, drive Sonos via SOAP. Body added in plan 03.
func runSonosPlay(args _: [String]) async {
    print("📻 SPIKE-03 — sonos play (placeholder; see PLAN 03)")
    exit(0)
}

/// SPIKE-02 — Dual-consumer tap coexistence test. Body added in plan 04.
func runSonosTapCoexist(args _: [String]) async {
    print("🎚 SPIKE-02 — sonos tap-coexist (placeholder; see PLAN 04)")
    exit(0)
}

/// SPIKE-05 — Pause-to-silence latency, 5 trials. Body added in plan 05.
func runSonosMeasureLatency(args _: [String]) async {
    print("⏱  SPIKE-05 — sonos measure-latency (placeholder; see PLAN 05)")
    exit(0)
}

/// SPIKE-06 — Run all four bets sequentially, write REPORT.md. Body added in plan 06.
func runSonosSpikeAll(args _: [String]) async {
    print("🧪 SPIKE-06 — sonos spike-all (placeholder; see PLAN 06)")
    exit(0)
}

// MARK: - Main Entry Point

func runMain() async {
    let args = Array(CommandLine.arguments.dropFirst())
    let verbose = args.contains("-v") || args.contains("--verbose")

    // Parse output file option
    var outputFile: String?
    for (index, arg) in args.enumerated() {
        if arg == "-o" || arg == "--output", index + 1 < args.count {
            outputFile = args[index + 1]
            break
        }
    }

    // Parse authuser option
    for (index, arg) in args.enumerated() {
        if arg == "--authuser", index + 1 < args.count {
            if let value = Int(args[index + 1]) {
                globalAuthUserIndex = value
            }
            break
        }
    }

    // Parse brand account option
    for (index, arg) in args.enumerated() {
        if arg == "--brand", index + 1 < args.count {
            globalBrandAccountId = args[index + 1]
            break
        }
    }

    // Filter out option flags and their values
    var filteredArgs: [String] = []
    var skipNext = false
    for arg in args {
        if skipNext {
            skipNext = false
            continue
        }
        if arg == "-v" || arg == "--verbose" {
            continue
        }
        if arg == "-o" || arg == "--output" || arg == "--authuser" || arg == "--brand" {
            skipNext = true
            continue
        }
        filteredArgs.append(arg)
    }

    guard let command = filteredArgs.first else {
        showHelp()
        return
    }

    switch command {
    case "browse":
        guard filteredArgs.count >= 2 else {
            print("❌ Usage: browse <browseId> [params]")
            return
        }
        let browseId = filteredArgs[1]
        let params: String? = filteredArgs.count >= 3 ? filteredArgs[2] : nil
        await exploreBrowse(browseId, params: params, verbose: verbose, outputFile: outputFile)

    case "action":
        guard filteredArgs.count >= 3 else {
            print("❌ Usage: action <endpoint> <body-json>")
            print("   Example: action search '{\"query\":\"hello\"}'")
            return
        }
        let endpoint = filteredArgs[1]
        let bodyJson = filteredArgs[2]
        await exploreAction(endpoint, bodyJson: bodyJson, verbose: verbose, outputFile: outputFile)

    case "continuation":
        guard filteredArgs.count >= 2 else {
            print("❌ Usage: continuation <token> [endpoint]")
            print("   endpoint: 'browse' (default) for home/library, 'next' for mix queues")
            print("   Get the token from a browse response's continuationItemRenderer or")
            print("   from a next response's nextRadioContinuationData.continuation")
            return
        }
        let token = filteredArgs[1]
        let endpoint = filteredArgs.count >= 3 ? filteredArgs[2] : "browse"
        await exploreContinuation(
            token, endpoint: endpoint, verbose: verbose, outputFile: outputFile
        )

    case "list":
        listEndpoints()

    case "auth":
        checkAuthStatus()

    case "accounts":
        await discoverAccounts(verbose: verbose)

    case "brandaccounts":
        await discoverBrandAccounts(verbose: verbose)

    case "sonos":
        guard filteredArgs.count >= 2 else {
            print("❌ Usage: sonos <discover|play|tap-coexist|measure-latency|spike-all> [args]")
            print("   discover             — SPIKE-04: SSDP M-SEARCH for Sonos S1 zones on the LAN")
            print("   play <ip>            — SPIKE-03: serve test fixture, SOAP-control playback")
            print("   tap-coexist <id>     — SPIKE-02: dual-consumer tap test (videoId)")
            print("   measure-latency <ip> — SPIKE-05: pause-to-silence latency, 5 trials")
            print("   spike-all <ip>       — Run all four bets sequentially, write REPORT.md")
            return
        }
        let sonosArgs = Array(filteredArgs.dropFirst(2))
        switch filteredArgs[1] {
        case "discover": await runSonosDiscover(args: sonosArgs)
        case "play": await runSonosPlay(args: sonosArgs)
        case "tap-coexist": await runSonosTapCoexist(args: sonosArgs)
        case "measure-latency": await runSonosMeasureLatency(args: sonosArgs)
        case "spike-all": await runSonosSpikeAll(args: sonosArgs)
        default:
            print("❌ Unknown sonos subcommand: \(filteredArgs[1])")
            print("   Valid: discover, play, tap-coexist, measure-latency, spike-all")
        }

    case "help", "-h", "--help":
        showHelp()

    default:
        print("❌ Unknown command: \(command)")
        print("   Run './api-explorer.swift help' for usage")
    }
}

/// Run the async main
let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    await runMain()
    semaphore.signal()
}

semaphore.wait()
