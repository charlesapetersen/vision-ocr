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

    /// Pulls a release out of GitHub's JSON. Returns nil for anything it does
    /// not fully understand, because a half-read response must not become a
    /// notification claiming an update exists.
    static func release(from data: Data) -> Release? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String,
              let page = root["html_url"] as? String,
              let url = URL(string: page) else { return nil }
        // Drafts and prereleases are not offers.
        if root["draft"] as? Bool == true || root["prerelease"] as? Bool == true { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty, version.first?.isNumber == true else { return nil }
        return Release(version: version, url: url, notes: root["body"] as? String ?? "")
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
        // No cookies, no credentials, nothing identifying beyond what any HTTP
        // client sends.
        request.httpShouldHandleCookies = false

        session.dataTask(with: request) { data, response, error in
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Prefs.lastUpdateCheck)
            if let error {
                completion(.failed(error.localizedDescription)); return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                completion(.failed("GitHub replied \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
                return
            }
            guard let data, let found = release(from: data) else {
                completion(.failed("could not read the release list")); return
            }
            completion(shouldAnnounce(found) ? .available(found) : .upToDate)
        }.resume()
    }
}
