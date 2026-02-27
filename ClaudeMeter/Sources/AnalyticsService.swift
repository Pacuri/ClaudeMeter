import Foundation

/// Anonymous analytics + license key service.
/// Talks to Supabase for heartbeats, license key generation (via edge function), and verification.
@MainActor
class AnalyticsService: ObservableObject {
    @Published var activeUsers: Int = 0
    @Published var isRequestingKey: Bool = false
    @Published var isVerifyingKey: Bool = false
    @Published var licenseError: String?

    private let supabaseURL = "https://sacwbhhusphqzsaoyhit.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNhY3diaGh1c3BocXpzYW95aGl0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEwODYzNzAsImV4cCI6MjA4NjY2MjM3MH0.smY4lEzK2Wl2C8l2VeEIM7eGNLXIS1t8tws5t9vWEak"
    private let appVersion = "1.0.2"

    /// Unique device ID, generated once and stored in UserDefaults
    var deviceID: String {
        if let stored = UserDefaults.standard.string(forKey: "deviceUUID") {
            return stored
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "deviceUUID")
        return newID
    }

    // MARK: - License Key

    /// Request a license key — calls edge function which generates key and emails it
    func requestLicenseKey(email: String, useCase: String) async -> Bool {
        guard !email.isEmpty else { return false }
        isRequestingKey = true
        licenseError = nil

        defer { isRequestingKey = false }

        guard let url = URL(string: "\(supabaseURL)/functions/v1/send-license-key") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let body: [String: String] = [
            "email": email,
            "use_case": useCase.lowercased()
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return true
            } else {
                // Try to parse error
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    licenseError = error
                } else {
                    licenseError = "Failed to send license key"
                }
                return false
            }
        } catch {
            licenseError = "Network error. Please try again."
            print("[Analytics] Request license key failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Verify a license key against Supabase
    func verifyLicenseKey(_ key: String) async -> Bool {
        guard !key.isEmpty else { return false }
        isVerifyingKey = true
        licenseError = nil

        defer { isVerifyingKey = false }

        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/verify_license") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let body: [String: String] = [
            "p_license_key": key,
            "p_device_id": deviceID
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let valid = json["valid"] as? Bool {
                if valid {
                    // Store verified email locally
                    if let email = json["email"] as? String {
                        UserDefaults.standard.set(email, forKey: "userEmail")
                    }
                    if let useCase = json["use_case"] as? String {
                        UserDefaults.standard.set(useCase, forKey: "userUseCase")
                    }
                    UserDefaults.standard.set(true, forKey: "licenseVerified")
                    return true
                } else {
                    licenseError = json["error"] as? String ?? "Invalid license key"
                    return false
                }
            } else {
                licenseError = "Invalid response"
                return false
            }
        } catch {
            licenseError = "Network error. Please try again."
            print("[Analytics] Verify license key failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Whether the user has a verified license
    var isLicensed: Bool {
        UserDefaults.standard.bool(forKey: "licenseVerified")
    }

    // MARK: - Heartbeat

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

            if let count = try? JSONDecoder().decode(Int.self, from: data) {
                self.activeUsers = count
            }
        } catch {
            print("[Analytics] Heartbeat failed: \(error.localizedDescription)")
        }
    }
}
