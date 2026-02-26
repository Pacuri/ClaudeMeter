import Foundation

/// Client for claude.ai web API endpoints.
/// Supports two auth modes: session cookie (browser) or OAuth token (Claude CLI).
actor ClaudeAPIClient {
    private let baseURL = "https://claude.ai/api"
    private var sessionKey: String?
    private var oauthToken: String?
    private var organizationId: String?

    enum AuthMode {
        case sessionKey(String)
        case oauth(String)
    }

    init(sessionKey: String) {
        self.sessionKey = sessionKey
    }

    init(oauthToken: String) {
        self.oauthToken = oauthToken
    }

    func updateSessionKey(_ key: String) {
        self.sessionKey = key
        self.oauthToken = nil
    }

    // MARK: - API Calls

    /// Fetch the user's organizations to get the org UUID
    func fetchOrganizations() async throws -> [ClaudeOrganization] {
        let data = try await request(path: "/organizations")
        return try JSONDecoder().decode([ClaudeOrganization].self, from: data)
    }

    /// Fetch usage data (session + weekly windows)
    func fetchUsage(orgId: String) async throws -> ClaudeUsageResponse {
        let data = try await request(path: "/organizations/\(orgId)/usage")
        return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
    }

    /// Fetch account details (email, plan)
    func fetchAccount() async throws -> ClaudeAccountResponse {
        let data = try await request(path: "/account")
        return try JSONDecoder().decode(ClaudeAccountResponse.self, from: data)
    }

    /// Full fetch: all data in parallel
    func fetchAll() async throws -> ClaudeUsageData {
        // Get org ID first -- pick the claude_max/chat org, not the API org
        let orgs = try await fetchOrganizations()
        let org = orgs.first(where: {
            $0.capabilities?.contains("claude_max") == true ||
            $0.capabilities?.contains("chat") == true
        }) ?? orgs.first

        guard let org = org else {
            throw ClaudeAPIError.noOrganization
        }

        let orgId = org.id

        // Parallel fetch
        async let usageTask = fetchUsage(orgId: orgId)
        async let accountTask = fetchAccount()

        let usage = try await usageTask
        let account = try? await accountTask

        // utilization is already 0-100
        let sessionPercent = usage.sessionUsage?.utilization ?? 0
        let sessionResets = usage.sessionUsage?.resetsAt.map { formatTimeUntil($0) } ?? "--"

        let weeklyPercent = usage.weeklyUsage?.utilization ?? 0
        let weeklyResets = usage.weeklyUsage?.resetsAt.map { formatTimeUntil($0) } ?? "--"

        let weeklyPace = calculatePace(
            percentUsed: Double(weeklyPercent) / 100.0,
            resetsAt: usage.weeklyUsage?.resetsAt
        )

        let sonnetPercent = usage.sonnetUsage?.utilization
        let opusPercent = usage.opusUsage?.utilization

        // Extra usage from inline response
        let extra = usage.extraUsage

        return ClaudeUsageData(
            sessionPercentUsed: sessionPercent,
            sessionResetsIn: sessionResets,
            weeklyPercentUsed: weeklyPercent,
            weeklyResetsIn: weeklyResets,
            weeklyPace: weeklyPace,
            sonnetPercentUsed: sonnetPercent,
            opusPercentUsed: opusPercent,
            extraUsageEnabled: extra?.isEnabled ?? false,
            extraMonthlyLimit: extra?.monthlyLimit ?? 0,
            extraCurrentSpend: extra?.usedCredits ?? 0,
            plan: org.planDisplayName,
            email: account?.email,
            lastUpdated: Date()
        )
    }

    // MARK: - Private

    private func request(path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw ClaudeAPIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("claude.ai", forHTTPHeaderField: "Host")
        req.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        // Auth: OAuth token or session cookie
        if let token = oauthToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let key = sessionKey {
            req.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw ClaudeAPIError.unauthorized
        case 429:
            throw ClaudeAPIError.rateLimited
        default:
            throw ClaudeAPIError.httpError(http.statusCode)
        }
    }

    private func calculatePace(percentUsed: Double, resetsAt: String?) -> String? {
        guard let resetsAt = resetsAt else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var resetDate = formatter.date(from: resetsAt)
        if resetDate == nil {
            formatter.formatOptions = [.withInternetDateTime]
            resetDate = formatter.date(from: resetsAt)
        }
        guard let reset = resetDate else { return nil }

        let totalWindow: TimeInterval = 7 * 24 * 3600  // 7 days
        let remaining = reset.timeIntervalSinceNow
        let elapsed = totalWindow - remaining
        guard elapsed > 0, totalWindow > 0 else { return nil }

        let expectedPercent = elapsed / totalWindow
        let actualPercent = percentUsed
        let paceRatio = actualPercent - expectedPercent

        let pacePercent = Int(abs(paceRatio * 100))

        if paceRatio > 0.05 {
            return "Ahead (+\(pacePercent)%)"
        } else if paceRatio < -0.05 {
            return "Behind (-\(pacePercent)%) · Lasts to reset"
        } else {
            return "On pace"
        }
    }
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case noOrganization
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .unauthorized: return "Session expired. Re-authenticate in Settings."
        case .rateLimited: return "Rate limited. Retrying soon."
        case .noOrganization: return "No organization found"
        case .httpError(let code): return "HTTP error \(code)"
        }
    }
}
