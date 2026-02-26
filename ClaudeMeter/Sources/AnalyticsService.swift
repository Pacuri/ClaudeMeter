import Foundation

/// Anonymous heartbeat service — pings Supabase on launch, returns active user count.
/// No personal data is collected. Just a random device UUID and app version.
@MainActor
class AnalyticsService: ObservableObject {
    @Published var activeUsers: Int = 0

    private let supabaseURL = "https://sacwbhhusphqzsaoyhit.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNhY3diaGh1c3BocXpzYW95aGl0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEwODYzNzAsImV4cCI6MjA4NjY2MjM3MH0.smY4lEzK2Wl2C8l2VeEIM7eGNLXIS1t8tws5t9vWEak"
    private let appVersion = "1.0.0"

    /// Unique device ID, generated once and stored in UserDefaults
    private var deviceID: String {
        if let stored = UserDefaults.standard.string(forKey: "deviceUUID") {
            return stored
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "deviceUUID")
        return newID
    }

    /// Send heartbeat and get active user count
    func sendHeartbeat() async {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/heartbeat") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let body: [String: String] = [
            "p_device_id": deviceID,
            "p_app_version": appVersion
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)

            // Supabase RPC returns the integer directly as JSON
            if let count = try? JSONDecoder().decode(Int.self, from: data) {
                self.activeUsers = count
            }
        } catch {
            // Silently fail — analytics should never break the app
            print("[Analytics] Heartbeat failed: \(error.localizedDescription)")
        }
    }
}
