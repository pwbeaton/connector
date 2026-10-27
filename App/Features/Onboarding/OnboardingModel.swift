import Foundation
import Observation

/// The one-minute path from install to Today:
/// Continue with Google → device check → goals → join or create a group → sharing.
@Observable
final class OnboardingModel {
    enum Step: String, CaseIterable, Sendable {
        case welcome, device, goals, group, sharing
    }

    /// Opens a URL in Apple's sign-in browser and returns the URL it was redirected to.
    typealias Authenticate = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

    var step: Step
    private(set) var isBusy = false
    var errorMessage: String?

    // Device check
    private(set) var device: DeviceStatus?
    private(set) var deviceChecked = false
    private(set) var historyLoaded = false

    // Goals (smart defaults: one tap continues)
    var sleepGoalMinutes = ScoreTuning.defaultSleepGoalMinutes
    var stepGoal = ScoreTuning.defaultStepGoal

    // Group
    var inviteCode = ""
    var newGroupName = ""
    private(set) var preview: GroupPreview?
    private(set) var group: GroupInfo?
    private(set) var createdGroup = false

    // Sharing (all on by default)
    var sharing = Set(SharingCategory.allCases)

    private let services: AppServices
    private let health: HealthModel
    private let team: TeamModel
    private let onFinish: () -> Void

    init(services: AppServices, health: HealthModel, team: TeamModel, startAt step: Step = .welcome,
         inviteCode: String? = nil, onFinish: @escaping () -> Void) {
        self.services = services
        self.health = health
        self.team = team
        self.step = step
        self.inviteCode = inviteCode ?? ""
        self.onFinish = onFinish
    }

    var stepNumber: Int { Step.allCases.firstIndex(of: step)! }

    // MARK: Welcome

    /// "Continue with Google": one consent creates the account and connects the tracker.
    func continueWithGoogle(authenticate: Authenticate) async {
        await run {
            if let google = services.google {
                let request = google.makeRequest()
                let callback = try await authenticate(request.url, google.callbackScheme)
                let tokens = try await google.complete(callback: callback, request: request)
                guard let idToken = tokens.idToken else { throw GoogleAuthError.missingIDToken }
                _ = try await services.backend.signIn(googleIDToken: idToken, accessToken: tokens.accessToken,
                                                      rawNonce: request.rawNonce)
            } else {
                _ = try await services.backend.signIn(googleIDToken: "demo", accessToken: nil, rawNonce: "demo")
            }
            step = .device
        }
    }

    // MARK: Device check

    /// Finds the tracker, then pulls 90 days of history so day one already has trends.
    func checkDevice() async {
        deviceChecked = false
        historyLoaded = false
        device = try? await services.source.device()
        deviceChecked = true
        await health.sync()
        historyLoaded = true
        if let device {
            try? await services.backend.updateProfile(ProfileUpdate(timezone: TimeZone.current.identifier,
                                                                    deviceName: device.name))
        }
    }

    // MARK: Goals

    func saveGoals() async {
        await run {
            await health.updateGoals(Goals(sleepMinutes: sleepGoalMinutes, steps: stepGoal))
            step = .group
        }
    }

    // MARK: Group

    /// Shows the group's name and members once a full code is typed.
    func lookUpInviteCode() async {
        guard InviteCode.isComplete(inviteCode) else {
            preview = nil
            return
        }
        preview = try? await services.backend.previewGroup(code: InviteCode.normalize(inviteCode))
    }

    func joinGroup() async {
        await run {
            group = try await team.joinGroup(code: inviteCode, today: health.today)
            createdGroup = false
            step = .sharing
        }
    }

    func createGroup() async {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await run {
            group = try await team.createGroup(named: name, today: health.today)
            createdGroup = true
            step = .sharing
        }
    }

    func skipGroup() {
        onFinish()
    }

    // MARK: Sharing

    func finish() async {
        await run {
            for category in SharingCategory.allCases where !sharing.contains(category) {
                await team.setSharing(category, enabled: false, today: health.today)
            }
            onFinish()
        }
    }

    // MARK: Helpers

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await work()
        } catch GoogleAuthError.cancelled {
            // The user closed the sign-in sheet: nothing to report.
        } catch {
            errorMessage = Self.message(for: error)
        }
        isBusy = false
    }

    static func message(for error: any Error) -> String {
        switch error {
        case BackendError.unknownInviteCode:
            "No group has that code. Check it with whoever invited you."
        case GoogleAuthError.accessDenied:
            "Google sign-in was declined. The app needs it to read your Fitbit Air data."
        case GoogleAuthError.missingIDToken, GoogleAuthError.stateMismatch, GoogleAuthError.missingCode:
            "Google sign-in didn't finish. Please try again."
        case is URLError:
            "You're offline. Connect to the internet and try again."
        default:
            "Something went wrong. Please try again."
        }
    }
}
