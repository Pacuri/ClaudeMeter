import Foundation

// MARK: - Claude API Response Models

struct ClaudeOrganization: Codable, Identifiable {
    let id: String  // UUID used in API calls
    let name: String
    let capabilities: [String]?
    let rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case id = "uuid"
        case name
        case capabilities
        case rateLimitTier = "rate_limit_tier"
    }

    /// Derive plan display name from capabilities/rate_limit_tier
    var planDisplayName: String {
        if let tier = rateLimitTier {
            if tier.contains("claude_max_20x") { return "Max (20x)" }
            if tier.contains("claude_max_5x") { return "Max (5x)" }
            if tier.contains("claude_max") { return "Max" }
        }
        if let caps = capabilities {
            if caps.contains("claude_max") { return "Max" }
            if caps.contains("chat") && caps.count == 1 { return "Pro" }
        }
        return "Pro"
    }
}

struct ClaudeUsageResponse: Codable {
    let sessionUsage: UsageWindow?
    let weeklyUsage: UsageWindow?
    let sonnetUsage: UsageWindow?
    let opusUsage: UsageWindow?
    let coworkUsage: UsageWindow?
    let extraUsage: ExtraUsageData?

    enum CodingKeys: String, CodingKey {
        case sessionUsage = "five_hour"
        case weeklyUsage = "seven_day"
        case sonnetUsage = "seven_day_sonnet"
        case opusUsage = "seven_day_opus"
        case coworkUsage = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }
}

struct UsageWindow: Codable {
    let utilization: Int?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// Extra usage is embedded in the usage response, not a separate endpoint
struct ExtraUsageData: Codable {
    let utilization: Int?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let isEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case utilization
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case isEnabled = "is_enabled"
    }
}

struct ClaudeAccountResponse: Codable {
    let email: String?
    let plan: String?

    enum CodingKeys: String, CodingKey {
        case email
        case plan = "plan_display_name"
    }
}

// MARK: - App Models

struct ClaudeUsageData {
    let sessionPercentUsed: Int
    let sessionResetsIn: String
    let weeklyPercentUsed: Int
    let weeklyResetsIn: String
    let weeklyPace: String?
    let sonnetPercentUsed: Int?
    let opusPercentUsed: Int?
    let extraUsageEnabled: Bool
    let extraMonthlyLimit: Double
    let extraCurrentSpend: Double
    let plan: String
    let email: String?
    let lastUpdated: Date

    static let placeholder = ClaudeUsageData(
        sessionPercentUsed: 0,
        sessionResetsIn: "--",
        weeklyPercentUsed: 0,
        weeklyResetsIn: "--",
        weeklyPace: nil,
        sonnetPercentUsed: nil,
        opusPercentUsed: nil,
        extraUsageEnabled: false,
        extraMonthlyLimit: 0,
        extraCurrentSpend: 0,
        plan: "--",
        email: nil,
        lastUpdated: Date()
    )
}

// MARK: - Helpers

extension ClaudeUsageData {
    var sessionColor: UsageLevel { UsageLevel.from(percent: sessionPercentUsed) }
    var weeklyColor: UsageLevel { UsageLevel.from(percent: weeklyPercentUsed) }
    var sonnetColor: UsageLevel { UsageLevel.from(percent: sonnetPercentUsed ?? 0) }
    var opusColor: UsageLevel { UsageLevel.from(percent: opusPercentUsed ?? 0) }
}

enum UsageLevel {
    case low, moderate, high, critical

    static func from(percent: Int) -> UsageLevel {
        switch percent {
        case 0..<40: return .low
        case 40..<70: return .moderate
        case 70..<90: return .high
        default: return .critical
        }
    }

    var color: String {
        switch self {
        case .low: return "usageGreen"
        case .moderate: return "usageAmber"
        case .high: return "usageOrange"
        case .critical: return "usageRed"
        }
    }
}

func formatTimeUntil(_ isoString: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    guard let resetDate = formatter.date(from: isoString) else {
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        guard let resetDate = formatter.date(from: isoString) else { return "--" }
        return formatInterval(until: resetDate)
    }
    return formatInterval(until: resetDate)
}

private func formatInterval(until date: Date) -> String {
    let interval = date.timeIntervalSinceNow
    guard interval > 0 else { return "now" }

    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60

    if hours > 24 {
        let days = hours / 24
        let remainingHours = hours % 24
        return "\(days)d \(remainingHours)h"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}
