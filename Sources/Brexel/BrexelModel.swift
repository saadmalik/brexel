import AppKit
import Combine
import Foundation

enum CardCopyAction: String, CaseIterable {
    case number
    case expiration
    case cvv
    case holderName
    case allDetails
    case billingAddress

    var title: String {
        switch self {
        case .number:
            return "Number"
        case .expiration:
            return "Expiration"
        case .cvv:
            return "CVV"
        case .holderName:
            return "Cardholder"
        case .allDetails:
            return "All Details"
        case .billingAddress:
            return "Billing Address"
        }
    }

    var copiedLabel: String {
        switch self {
        case .number:
            return "number"
        case .expiration:
            return "expiration"
        case .cvv:
            return "CVV"
        case .holderName:
            return "cardholder"
        case .allDetails:
            return "card details"
        case .billingAddress:
            return "billing address"
        }
    }

    var systemImage: String {
        switch self {
        case .number:
            return "creditcard"
        case .expiration:
            return "calendar"
        case .cvv:
            return "lock.shield"
        case .holderName:
            return "person.text.rectangle"
        case .allDetails:
            return "doc.on.doc"
        case .billingAddress:
            return "house"
        }
    }
}

struct AppMessage: Identifiable {
    enum Style {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    let text: String
    let style: Style
}

struct CopySuccess: Equatable {
    let cardID: String
    let action: CardCopyAction
}

@MainActor
final class BrexelModel: ObservableObject {
    static let developerSettingsURL = URL(string: "https://dashboard.brex.com/settings/developer")!

    @Published private(set) var cards: [BrexCard] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var copyingCardID: String?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published var message: AppMessage? {
        didSet { scheduleMessageAutoDismiss() }
    }
    @Published private(set) var copySuccess: CopySuccess?
    @Published private var userLimitTextByUserID: [String: String] = [:]

    private let client = BrexClient()
    private let keychain = KeychainStore()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private var cachedToken: String?
    private var lastUpdated: Date?
    private var messageDismissTask: Task<Void, Never>?
    private var copySuccessTask: Task<Void, Never>?

    init() {
        loadToken()
        refreshLaunchAtLoginStatus()
    }

    var hasToken: Bool {
        cachedToken != nil
    }

    var availableCards: [BrexCard] {
        cards
            .filter(\.isActive)
            .sorted { lhs, rhs in
                lhs.cardName.localizedCaseInsensitiveCompare(rhs.cardName) == .orderedAscending
            }
    }

    var lastUpdatedText: String? {
        lastUpdated?.formatted(date: .omitted, time: .shortened)
    }

    func refreshCards() async {
        guard let token = cachedToken else {
            message = AppMessage(text: "Add a Brex API token to load cards.", style: .info)
            return
        }

        isRefreshing = true
        message = nil

        do {
            let loadedCards = try await client.listCards(token: token)
            cards = loadedCards
            lastUpdated = Date()
            message = AppMessage(text: "Cards updated.", style: .success)
            await refreshUserLimits(for: loadedCards, token: token)
        } catch {
            message = AppMessage(text: error.localizedDescription, style: .error)
        }

        isRefreshing = false
    }

    func saveToken(_ token: String) async {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            message = AppMessage(text: "Paste a Brex API token first.", style: .warning)
            return
        }

        do {
            try keychain.saveToken(trimmedToken)
            cachedToken = trimmedToken
            message = AppMessage(text: "Token saved securely.", style: .success)
            await refreshCards()
        } catch {
            message = AppMessage(text: error.localizedDescription, style: .error)
        }
    }

    func forgetToken() {
        do {
            try keychain.deleteToken()
            cachedToken = nil
            cards = []
            lastUpdated = nil
            message = AppMessage(text: "Token removed from Keychain.", style: .success)
        } catch {
            message = AppMessage(text: error.localizedDescription, style: .error)
        }
    }

    func openDeveloperSettings() {
        NSWorkspace.shared.open(Self.developerSettingsURL)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            refreshLaunchAtLoginStatus()

            if launchAtLoginRequiresApproval {
                message = AppMessage(text: "Approve Brexel in System Settings > Login Items.", style: .warning)
            } else {
                let text = launchAtLoginEnabled ? "Brexel will launch at login." : "Launch at login turned off."
                message = AppMessage(text: text, style: .success)
            }
        } catch {
            refreshLaunchAtLoginStatus()
            message = AppMessage(text: "Launch at login could not be updated: \(error.localizedDescription)", style: .error)
        }
    }

    func detailLine(for card: BrexCard) -> String {
        let limit = card.directLimitText ?? userLimitText(for: card)
        return [card.maskedLastFour, limit]
            .compactMap { $0?.trimmedNonEmpty }
            .joined(separator: " · ")
    }

    func copy(_ action: CardCopyAction, for card: BrexCard) async {
        guard let token = cachedToken else {
            message = AppMessage(text: "Add a Brex API token first.", style: .warning)
            return
        }

        if action == .billingAddress {
            guard let address = card.billingAddress?.multilineDisplay else {
                message = AppMessage(text: "No billing address is available for \(card.cardName).", style: .warning)
                return
            }

            Clipboard.copy(address)
            flashCopySuccess(cardID: card.id, action: action)
            return
        }

        copyingCardID = card.id

        do {
            let pan = try await client.cardPAN(cardID: card.id, token: token)
            Clipboard.copy(copyText(for: action, card: card, pan: pan))
            flashCopySuccess(cardID: card.id, action: action)
        } catch {
            message = AppMessage(text: error.localizedDescription, style: .error)
        }

        copyingCardID = nil
    }

    private func flashCopySuccess(cardID: String, action: CardCopyAction) {
        copySuccessTask?.cancel()
        let success = CopySuccess(cardID: cardID, action: action)
        copySuccess = success

        copySuccessTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            if self.copySuccess == success {
                self.copySuccess = nil
            }
        }
    }

    private func scheduleMessageAutoDismiss() {
        messageDismissTask?.cancel()

        // Only auto-dismiss success toasts. Info is used for in-flight loaders
        // ("Fetching secure card details…"); warning/error need explicit user attention.
        guard let current = message, current.style == .success else {
            return
        }

        let id = current.id
        messageDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            if self.message?.id == id {
                self.message = nil
            }
        }
    }

    private func refreshLaunchAtLoginStatus() {
        let snapshot = launchAtLoginManager.snapshot
        launchAtLoginEnabled = snapshot.isEnabled
        launchAtLoginRequiresApproval = snapshot.requiresApproval
    }

    private func loadToken() {
        do {
            cachedToken = try keychain.token()?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
        } catch {
            message = AppMessage(text: error.localizedDescription, style: .error)
            return
        }

        guard cachedToken == nil else {
            return
        }

        guard let token = ProcessInfo.processInfo.environment["BREX_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              token.hasPrefix("bxt_") else {
            return
        }

        do {
            try keychain.saveToken(token)
            cachedToken = token
            message = AppMessage(text: "Token saved to Keychain.", style: .success)
        } catch {
            message = AppMessage(text: error.localizedDescription, style: .error)
        }
    }

    private func refreshUserLimits(for cards: [BrexCard], token: String) async {
        let userIDs = Set(cards.compactMap { card -> String? in
            guard card.usesUserLimit else {
                return nil
            }

            return card.owner?.userID
        })

        guard !userIDs.isEmpty else {
            userLimitTextByUserID = [:]
            return
        }

        var nextUserLimits = userLimitTextByUserID

        for userID in userIDs where nextUserLimits[userID] == nil {
            do {
                if let limit = try await client.userLimit(userID: userID, token: token).limitDisplay {
                    nextUserLimits[userID] = limit
                }
            } catch BrexAPIError.httpStatus(403, _) {
                break
            } catch {
                continue
            }
        }

        userLimitTextByUserID = nextUserLimits
    }

    private func userLimitText(for card: BrexCard) -> String? {
        guard card.usesUserLimit else {
            return nil
        }

        if let userID = card.owner?.userID,
           let limit = userLimitTextByUserID[userID] {
            return limit
        }

        return "User limit"
    }

    private func copyText(for action: CardCopyAction, card: BrexCard, pan: CardPAN) -> String {
        switch action {
        case .number:
            return pan.number
        case .expiration:
            return pan.expirationShort
        case .cvv:
            return pan.cvv
        case .holderName:
            return pan.holderName
        case .allDetails:
            return pan.formattedDetails(card: card, billingAddress: card.billingAddress)
        case .billingAddress:
            return card.billingAddress?.multilineDisplay ?? ""
        }
    }
}
