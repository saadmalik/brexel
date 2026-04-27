import Foundation

struct CardListResponse: Decodable {
    let nextCursor: String?
    let items: [BrexCard]

    enum CodingKeys: String, CodingKey {
        case nextCursor = "next_cursor"
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)

        let decodedItems = try container.decodeIfPresent([FailableDecodable<BrexCard>].self, forKey: .items) ?? []
        items = decodedItems.compactMap(\.value)
    }
}

struct BrexCard: Decodable, Identifiable {
    let id: String
    let status: String?
    let lastFour: String?
    let cardName: String
    let cardType: String?
    let limitType: String?
    let expirationDate: CardExpiration?
    let billingAddress: Address?
    let owner: CardOwner?
    let spendControls: SpendControls?

    enum CodingKeys: String, CodingKey {
        case id
        case owner
        case status
        case lastFour = "last_four"
        case cardName = "card_name"
        case cardType = "card_type"
        case limitType = "limit_type"
        case expirationDate = "expiration_date"
        case billingAddress = "billing_address"
        case spendControls = "spend_controls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        owner = try container.decodeIfPresent(CardOwner.self, forKey: .owner)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        lastFour = try container.decodeIfPresent(String.self, forKey: .lastFour)
        cardName = try container.decodeIfPresent(String.self, forKey: .cardName)?.trimmedNonEmpty ?? "Brex card"
        cardType = try container.decodeIfPresent(String.self, forKey: .cardType)
        limitType = try container.decodeIfPresent(String.self, forKey: .limitType)
        expirationDate = try container.decodeIfPresent(CardExpiration.self, forKey: .expirationDate)
        billingAddress = try container.decodeIfPresent(Address.self, forKey: .billingAddress)
        spendControls = try container.decodeIfPresent(SpendControls.self, forKey: .spendControls)
    }

    var isActive: Bool {
        guard let normalizedStatus = status?.trimmedNonEmpty?.uppercased() else {
            return false
        }

        return normalizedStatus == "ACTIVE" && expirationDate?.isExpired != true
    }

    var menuTitle: String {
        var title = cardName
        if let maskedLastFour {
            title += " - \(maskedLastFour)"
        }
        if let status, !status.isEmpty {
            title += " (\(status.capitalized))"
        }
        return title
    }

    var maskedLastFour: String? {
        guard let lastFour, !lastFour.isEmpty else {
            return nil
        }
        return "ending \(lastFour)"
    }

    var subtitle: String {
        [cardType?.capitalized, limitType?.capitalized]
            .compactMap { $0 }
            .joined(separator: " / ")
    }

    var directLimitText: String? {
        spendControls?.limitDisplay
    }

    var usesUserLimit: Bool {
        limitType?.uppercased() == "USER"
    }
}

struct CardOwner: Decodable {
    let type: String?
    let userID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case userID = "user_id"
    }
}

struct SpendControls: Decodable {
    let spendLimit: Money?
    let spendAvailable: Money?
    let spendDuration: String?

    enum CodingKeys: String, CodingKey {
        case spendLimit = "spend_limit"
        case spendAvailable = "spend_available"
        case spendDuration = "spend_duration"
    }

    var limitDisplay: String? {
        guard let limit = spendLimit?.displayText else {
            return nil
        }

        guard let duration = spendDuration?.durationDisplay else {
            return limit
        }

        return "\(limit) \(duration)"
    }
}

struct Money: Decodable {
    let amount: Int?
    let currency: String?

    var displayText: String? {
        guard let amount else {
            return nil
        }

        let value = Decimal(amount) / Decimal(100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        formatter.maximumFractionDigits = amount % 100 == 0 ? 0 : 2
        formatter.minimumFractionDigits = 0

        return formatter.string(from: NSDecimalNumber(decimal: value))
    }
}

struct UserLimit: Decodable {
    let monthlyLimit: Money?
    let monthlyAvailable: Money?

    enum CodingKeys: String, CodingKey {
        case monthlyLimit = "monthly_limit"
        case monthlyAvailable = "monthly_available"
    }

    var limitDisplay: String? {
        guard let limit = monthlyLimit?.displayText else {
            return nil
        }

        return "\(limit) monthly"
    }
}

private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

struct CardPAN: Decodable {
    let id: String
    let number: String
    let cvv: String
    let expirationDate: CardExpiration
    let holderName: String

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case cvv
        case expirationDate = "expiration_date"
        case holderName = "holder_name"
    }

    var expirationShort: String {
        expirationDate.shortDisplay
    }

    func formattedDetails(card: BrexCard, billingAddress: Address?) -> String {
        var lines = [
            "Card: \(card.cardName)",
            "Cardholder: \(holderName)",
            "Number: \(number)",
            "Expiration: \(expirationShort)",
            "CVV: \(cvv)"
        ]

        if let billing = billingAddress?.multilineDisplay {
            lines.append("Billing address:")
            lines.append(billing)
        }

        return lines.joined(separator: "\n")
    }
}

struct CardExpiration: Decodable {
    let month: Int
    let year: Int

    var normalizedYear: Int? {
        if year >= 1000 {
            return year
        }

        if (0...99).contains(year) {
            return 2000 + year
        }

        return nil
    }

    var isExpired: Bool {
        guard (1...12).contains(month),
              let normalizedYear else {
            return false
        }

        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        guard let currentYear = components.year,
              let currentMonth = components.month else {
            return false
        }

        return normalizedYear < currentYear || (normalizedYear == currentYear && month < currentMonth)
    }

    var shortDisplay: String {
        let monthText = String(format: "%02d", month)
        let twoDigitYear = String(format: "%02d", (normalizedYear ?? year) % 100)
        return "\(monthText)/\(twoDigitYear)"
    }

    var longDisplay: String {
        let monthText = String(format: "%02d", month)
        return "\(monthText)/\(normalizedYear ?? year)"
    }
}

struct Address: Decodable {
    let line1: String?
    let line2: String?
    let city: String?
    let state: String?
    let country: String?
    let postalCode: String?
    let phoneNumber: String?

    enum CodingKeys: String, CodingKey {
        case line1
        case line2
        case city
        case state
        case country
        case postalCode = "postal_code"
        case phoneNumber = "phone_number"
    }

    var multilineDisplay: String? {
        let firstLines = [line1, line2]
            .compactMap { $0?.trimmedNonEmpty }

        let cityLine = [city?.trimmedNonEmpty, state?.trimmedNonEmpty, postalCode?.trimmedNonEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")

        var lines = firstLines
        if !cityLine.isEmpty {
            lines.append(cityLine)
        }
        if let country = country?.trimmedNonEmpty {
            lines.append(country)
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var durationDisplay: String? {
        switch uppercased() {
        case "WEEKLY":
            return "weekly"
        case "MONTHLY":
            return "monthly"
        case "QUARTERLY":
            return "quarterly"
        case "YEARLY":
            return "yearly"
        case "ONE_TIME":
            return "one-time"
        default:
            return trimmedNonEmpty?.lowercased()
        }
    }
}
