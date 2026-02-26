import Foundation
import Combine
import SwiftUI

@MainActor
class ClaudeUsageViewModel: ObservableObject {
    @Published var usage: ClaudeUsageData?
    @Published var isLoading = false
    @Published var error: String?
    @Published var isAuthenticated = false

    private var client: ClaudeAPIClient?
    private var refreshTimer: Timer?
    private var refreshInterval: TimeInterval = 60  // 1 minute default

    init() {
        loadSessionKey()
        startAutoRefresh()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Authentication

    func setSessionKey(_ key: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(cleanKey, forKey: "sessionKey")
        client = ClaudeAPIClient(sessionKey: cleanKey)
        isAuthenticated = true
        Task { await refresh() }
    }

    func loadSessionKey() {
        if let stored = UserDefaults.standard.string(forKey: "sessionKey"), !stored.isEmpty {
            client = ClaudeAPIClient(sessionKey: stored)
            isAuthenticated = true
            Task { await refresh() }
        }
    }

    func autoDetectSessionKey() async {
        if let key = await CookieExtractor.extractSessionKey() {
            setSessionKey(key)
        } else {
            error = "Could not find session cookie. Paste it manually in Settings."
        }
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: "sessionKey")
        client = nil
        usage = nil
        isAuthenticated = false
        error = nil
    }

    // MARK: - Data Fetching

    func refresh() async {
        guard let client = client else {
            error = "Not authenticated"
            return
        }

        isLoading = true
        error = nil

        do {
            usage = try await client.fetchAll()
            cacheUsage()
        } catch let apiError as ClaudeAPIError {
            error = apiError.errorDescription
            if case .unauthorized = apiError {
                isAuthenticated = false
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        startAutoRefresh()
    }

    // MARK: - Caching

    private func cacheUsage() {
        guard let usage = usage else { return }
        let cache: [String: Any] = [
            "sessionPercent": usage.sessionPercentUsed,
            "weeklyPercent": usage.weeklyPercentUsed,
            "plan": usage.plan,
            "lastUpdated": Date().timeIntervalSince1970
        ]
        UserDefaults.standard.set(cache, forKey: "cachedUsage")
    }

    func loadCachedUsage() {
        guard let cache = UserDefaults.standard.dictionary(forKey: "cachedUsage") else { return }
        // Only use cache if less than 5 minutes old
        if let timestamp = cache["lastUpdated"] as? TimeInterval,
           Date().timeIntervalSince1970 - timestamp < 300 {
            // Use cached data as placeholder
            usage = ClaudeUsageData(
                sessionPercentUsed: cache["sessionPercent"] as? Int ?? 0,
                sessionResetsIn: "loading...",
                weeklyPercentUsed: cache["weeklyPercent"] as? Int ?? 0,
                weeklyResetsIn: "loading...",
                weeklyPace: nil,
                sonnetPercentUsed: nil,
                opusPercentUsed: nil,
                extraUsageEnabled: false,
                extraMonthlyLimit: 0,
                extraCurrentSpend: 0,
                plan: cache["plan"] as? String ?? "--",
                email: nil,
                lastUpdated: Date(timeIntervalSince1970: timestamp)
            )
        }
    }
}
