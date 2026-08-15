import Foundation

/// Asks GitHub whether there is a newer release, and nothing else.
///
/// **This is the only network code in the app**, and it exists because the app
/// is not in the App Store and has no other way to tell anyone that a fix
/// shipped. The distinction worth keeping precise: your documents never leave
/// your Mac — recognition is local and always was — and this sends no
/// identifiers, no telemetry, no document data. It is one unauthenticated GET
/// of a public JSON file, and it can be turned off in Settings.
///
/// Deliberately **not** a self-installing updater. Replacing a running app
/// bundle correctly is Sparkle's job, and Sparkle wants a signing identity this
/// app does not have; worse, an app that replaced itself would land the user
/// back in the Gatekeeper dialog with no warning. So this finds out, and tells
/// you where to click.
enum Updater {

    /// What a check can conclude.
    enum Result: Equatable {
        case upToDate
        case available(Release)
        case failed(String)          // never surfaced as an alert; see `check`
    }

    struct Release: Equatable {
        let version: String          // "1.6.0", tag prefix stripped
        let url: URL                 // the human page, not the asset
        let notes: String            // may be empty
    }

    /// How often an automatic check may run. Once a day is plenty for an app
    /// that ships every few weeks, and it means opening the app forty times in
    /// an afternoon makes one request.
    static let interval: TimeInterval = 24 * 60 * 60

    static let releasesAPI =
        URL(string: "https://api.github.com/repos/charlesapetersen/vision-ocr/releases/latest")!

    // MARK: - The parts worth testing

    /// The version this build reports, from its own Info.plist.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Compares two dotted versions numerically, component by component.
    ///
    /// Not string comparison: "1.10.0" is newer than "1.9.0" and sorts before it
    /// alphabetically, which is the classic way an updater goes quiet exactly
    /// when it matters. Missing components count as zero, so 1.6 == 1.6.0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// What a response turned out to be.
    ///
    /// Three outcomes, not two. "Could not read this" and "read it fine, there
    /// is nothing to offer" look identical if both are nil, and `check` has to
    /// treat them differently: an unreadable response is a failure worth
    /// retrying in fifteen minutes, while a prerelease at the top of the list
    /// is a complete and correct answer. Collapsing them meant a repo whose
    /// latest release was a prerelease got checked ninety-six times a day, by
    /// an app whose README promises one.
    enum Parsed: Equatable {
        case offer(Release)
        case notAnOffer      // understood completely; a draft, a prerelease
        case unreadable      // truncated, not JSON, missing what it needs
    }

    /// Pulls a release out of GitHub's JSON. Refuses anything it does not fully
    /// understand, because a half-read response must not become a notification
    /// claiming an update exists.
    static func parse(_ data: Data) -> Parsed {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String,
              let page = root["html_url"] as? String,
              let url = URL(string: page),
              isOfferableURL(url) else { return .unreadable }
        // Drafts and prereleases are not offers — but they are answers.
        if root["draft"] as? Bool == true || root["prerelease"] as? Bool == true {
            return .notAnOffer
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty, version.first?.isNumber == true else { return .unreadable }
        return .offer(Release(version: version, url: url,
                              notes: root["body"] as? String ?? ""))
    }

    /// Whether a URL out of the response is one we will hand to
    /// `NSWorkspace.open`.
    ///
    /// A4.2. `parse` accepted any `URL(string:)` and `ContentView` handed it
    /// straight to `NSWorkspace.shared.open`, so whoever controls the response body
    /// controls what the Download button opens. Verified against the real parser
    /// before this guard: `file:///Applications/Calculator.app` accepted,
    /// `x-fake-handler://run?cmd=…` accepted, `https://not-github.example/evil`
    /// accepted.
    ///
    /// It needs control of the HTTPS response to matter — ATS is in force with no
    /// exceptions, so there is no plain MITM — and the marginal gain over simply
    /// publishing a malicious release page is the `file://` and custom-scheme
    /// cases. Which is exactly why the guard is cheap and worth having.
    ///
    /// **Scheme only, and the host deliberately not pinned.** `https` alone closes
    /// both cases that are actually worth closing — a local file and a registered
    /// custom scheme — because those are the two where opening the URL does
    /// something other than show a web page. What a host pin would add is refusing
    /// `https://not-github.example/evil`, whose marginal harm over simply
    /// publishing a malicious GitHub release page is nothing, since an attacker who
    /// can rewrite this response can equally rewrite the page it points at.
    ///
    /// Against that, a host pin has a real cost in the other direction: it is a
    /// second place that has to be edited if the release page ever moves, and the
    /// failure mode is that updates stop being offered with no error anywhere. This
    /// project's own register is mostly entries where the app quietly stopped doing
    /// something. So: `https`, and a comment rather than a constant.
    static func isOfferableURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    /// The offer alone, for callers that do not care why there is not one.
    static func release(from data: Data) -> Release? {
        if case .offer(let r) = parse(data) { return r }
        return nil
    }

    /// Whether an automatic check is due. Forced checks ignore all of this.
    static func isDue(now: Date = Date(),
                      last: TimeInterval = UserDefaults.standard.double(forKey: Prefs.lastUpdateCheck),
                      enabled: Bool = UserDefaults.standard.bool(forKey: Prefs.checkForUpdates)) -> Bool {
        guard enabled else { return false }
        guard last > 0 else { return true }
        // A clock that has gone backwards must not disable checking for ever.
        let elapsed = now.timeIntervalSince1970 - last
        return elapsed >= interval || elapsed < 0
    }

    /// Whether to actually tell the user about this one.
    static func shouldAnnounce(_ release: Release,
                               current: String = currentVersion,
                               skipped: String? = UserDefaults.standard
                                   .string(forKey: Prefs.skippedVersion)) -> Bool {
        guard isNewer(release.version, than: current) else { return false }
        // "Skip this version" means this one, not updates for ever.
        return release.version != skipped
    }

    // MARK: - The thin part

    /// Runs a check. Never throws, never blocks, and **never interrupts**: a
    /// failure is silent, because an app that cannot reach GitHub is not a
    /// problem the person scanning a book needs a dialog about.
    static func check(force: Bool = false,
                      session: URLSession = .shared,
                      completion: @escaping (Result) -> Void) {
        guard force || isDue() else { completion(.upToDate); return }

        var request = URLRequest(url: releasesAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false

        // Pinned, not inherited. CFNetwork fills in two headers of its own
        // unless told otherwise, and both describe the person rather than the
        // request: `Accept-Language` is built from their AppleLanguages list —
        // measured changing to `he-IL,he;q=0.9` when that list changes — and
        // `User-Agent` carries the app build and the exact Darwin kernel
        // version, i.e. the machine's precise macOS point release. Together
        // with the source IP that is a stable per-machine fingerprint, sent
        // daily, by an app whose README promises the request "sends nothing
        // about you". GitHub requires *a* User-Agent, so send a constant one
        // (U26).
        request.setValue("VisionOCR", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")

        session.dataTask(with: request) { data, response, error in
            /// A failure costs fifteen minutes, not a day. Stamping the clock
            /// before looking at the result meant one launch on a train spent
            /// the day's only automatic check, and a user whose first launch is
            /// reliably the offline one would never be told about a fix at all
            /// (U26). A real answer still spends the full interval.
            func spend(_ seconds: TimeInterval) {
                UserDefaults.standard.set(Date().timeIntervalSince1970 - interval + seconds,
                                          forKey: Prefs.lastUpdateCheck)
            }
            let retryAfterFailure: TimeInterval = 15 * 60

            if let error {
                spend(retryAfterFailure)
                completion(.failed(error.localizedDescription)); return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                spend(retryAfterFailure)
                completion(.failed("GitHub replied \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
                return
            }
            let found: Release
            switch parse(data ?? Data()) {
            case .offer(let r):
                found = r
            case .notAnOffer:
                // A complete answer. Spend the full interval and say so.
                UserDefaults.standard.set(Date().timeIntervalSince1970,
                                          forKey: Prefs.lastUpdateCheck)
                completion(.upToDate); return
            case .unreadable:
                spend(retryAfterFailure)
                completion(.failed("could not read the release list")); return
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Prefs.lastUpdateCheck)

            // A forced check answers about reality, not about what was skipped.
            // Otherwise "Check Now" says "Up to date" on a version the user can
            // see on the releases page, and the skip is unreachable once made
            // (U26).
            if force {
                completion(isNewer(found.version, than: currentVersion)
                           ? .available(found) : .upToDate)
            } else {
                completion(shouldAnnounce(found) ? .available(found) : .upToDate)
            }
        }.resume()
    }
}
