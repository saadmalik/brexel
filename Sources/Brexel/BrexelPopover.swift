import SwiftUI

struct BrexelPopover: View {
    @ObservedObject var model: BrexelModel
    let onQuit: () -> Void

    @State private var setupMode = false
    @State private var token = ""

    var body: some View {
        VStack(spacing: 0) {
            if model.hasToken && !setupMode {
                CardsHomeView(model: model, setupMode: $setupMode, onQuit: onQuit)
            } else {
                OnboardingView(model: model, setupMode: $setupMode, token: $token, onQuit: onQuit)
            }
        }
        .frame(width: 420, height: 600)
        .background(AppBackground())
    }
}

private struct CardsHomeView: View {
    @ObservedObject var model: BrexelModel
    @Binding var setupMode: Bool
    let onQuit: () -> Void

    @State private var searchText = ""

    private var visibleCards: [BrexCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return model.availableCards
        }

        return model.availableCards.filter { card in
            card.searchableText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model, visibleCount: visibleCards.count, setupMode: $setupMode, onQuit: onQuit)

            SearchField(text: $searchText)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            if let message = model.message {
                MessageBanner(message: message)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            if model.isRefreshing && model.cards.isEmpty {
                LoadingStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleCards.isEmpty {
                EmptyCardsView(model: model, isSearching: !searchText.isEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CardListView(cards: visibleCards, model: model)
            }

            FooterView(model: model)
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var model: BrexelModel
    let visibleCount: Int
    @Binding var setupMode: Bool
    let onQuit: () -> Void

    private var headerSubtitle: String {
        let count = "\(visibleCount) of \(model.availableCards.count)"
        guard let lastUpdatedText = model.lastUpdatedText else {
            return count
        }
        return "\(count) · Updated \(lastUpdatedText)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "creditcard")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Brexel")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await model.refreshCards() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isRefreshing ? .secondary : .primary)
            .contentShape(Circle())
            .help("Refresh cards")
            .disabled(model.isRefreshing)

            Menu {
                Toggle(isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    Label("Launch at Login", systemImage: "power")
                }

                if model.launchAtLoginRequiresApproval {
                    Text("Needs approval in Login Items")
                }

                Divider()

                Button("Open Brex Developer Settings") {
                    model.openDeveloperSettings()
                }

                Button("Replace API Token") {
                    setupMode = true
                }

                Divider()

                Button("Forget API Token", role: .destructive) {
                    model.forgetToken()
                    setupMode = true
                }

                Button("Quit Brexel") {
                    onQuit()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24, height: 24)
            .help("More")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search cards or last four", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }
}

private struct CardListView: View {
    let cards: [BrexCard]
    @ObservedObject var model: BrexelModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    CompactCardRowView(card: card, model: model)

                    if index < cards.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

private struct CompactCardRowView: View {
    let card: BrexCard
    @ObservedObject var model: BrexelModel

    @State private var isHovering = false

    private var isCopying: Bool {
        model.copyingCardID == card.id
    }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                Task { await model.copy(.number, for: card) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.cardName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text(model.detailLine(for: card))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Copy card number")
            .disabled(model.copyingCardID != nil)

            Group {
                if isCopying {
                    ProgressView()
                        .controlSize(.small)
                        .frame(height: 24)
                } else if let success = model.copySuccess, success.cardID == card.id {
                    CopiedPill(action: success.action)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 2) {
                        CopyIconButton(action: .number, card: card, model: model)
                        CopyIconButton(action: .expiration, card: card, model: model)
                        CopyIconButton(action: .cvv, card: card, model: model)
                        MoreCopyMenu(card: card, model: model)
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 24)
            .animation(.easeInOut(duration: 0.18), value: model.copySuccess)
            .animation(.easeInOut(duration: 0.12), value: isCopying)
        }
        .frame(height: 42)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(isHovering ? 0.06 : 0))
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct CopyIconButton: View {
    let action: CardCopyAction
    let card: BrexCard
    @ObservedObject var model: BrexelModel

    @State private var isHovering = false

    var body: some View {
        Button {
            Task { await model.copy(action, for: card) }
        } label: {
            Image(systemName: action.systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? Color.primary : Color.secondary)
        .background(isHovering ? Color(nsColor: .controlAccentColor).opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Copy \(action.title.lowercased())")
        .disabled(model.copyingCardID != nil)
        .onHover { isHovering = $0 }
    }
}

private struct MoreCopyMenu: View {
    let card: BrexCard
    @ObservedObject var model: BrexelModel

    @State private var isHovering = false

    var body: some View {
        Menu {
            CopyMenuButton(action: .holderName, card: card, model: model)
            CopyMenuButton(action: .allDetails, card: card, model: model)
            if card.billingAddress?.multilineDisplay != nil {
                CopyMenuButton(action: .billingAddress, card: card, model: model)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24, height: 24)
        .foregroundStyle(isHovering ? Color.primary : Color.secondary)
        .background(isHovering ? Color(nsColor: .controlAccentColor).opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("More copy actions")
        .onHover { isHovering = $0 }
    }
}

private struct CopyMenuButton: View {
    let action: CardCopyAction
    let card: BrexCard
    @ObservedObject var model: BrexelModel

    var body: some View {
        Button {
            Task { await model.copy(action, for: card) }
        } label: {
            Label("Copy \(action.title)", systemImage: action.systemImage)
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: BrexelModel
    @Binding var setupMode: Bool
    @Binding var token: String
    let onQuit: () -> Void

    @FocusState private var tokenFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect Brex")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Create a scoped API token, paste it here, and your cards stay one click away.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    onQuit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: Circle())
                .help("Quit")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: 1, title: "Open Brex Developer settings", detail: "Create a new API token from the Developer tab.")

                        Button {
                            model.openDeveloperSettings()
                        } label: {
                            Label("Open Brex Developer Settings", systemImage: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundStyle(.white)
                        .background(Color(nsColor: .controlAccentColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: 2, title: "Select only the scopes needed", detail: "Use read access for cards, card numbers, and user limits.")

                        ScopeRow(title: "Cards", value: "Read only")
                        ScopeRow(title: "Card Numbers Read and Send", value: "Read only")
                        ScopeRow(title: "Users", value: "Read only")
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 12) {
                        StepRow(number: 3, title: "Paste the token", detail: "It is stored in your macOS Keychain and cached in memory while the app is running.")

                        SecureField("bxt_...", text: $token)
                            .textFieldStyle(.plain)
                            .focused($tokenFieldFocused)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7).stroke(
                                    tokenFieldFocused
                                        ? Color(nsColor: .controlAccentColor).opacity(0.85)
                                        : Color(nsColor: .separatorColor).opacity(0.55),
                                    lineWidth: tokenFieldFocused ? 1.5 : 1
                                )
                            )
                            .animation(.easeOut(duration: 0.12), value: tokenFieldFocused)

                        Button {
                            Task {
                                await model.saveToken(token)
                                if model.hasToken {
                                    token = ""
                                    setupMode = false
                                }
                            }
                        } label: {
                            Label("Save and Load Cards", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundStyle(.white)
                        .background(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.45) : Color(nsColor: .controlAccentColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .animation(.easeOut(duration: 0.15), value: token)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isRefreshing)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1))

                    if let message = model.message {
                        MessageBanner(message: message)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                tokenFieldFocused = true
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color(nsColor: .controlAccentColor), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScopeRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)

            Spacer()

            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Color(nsColor: .controlColor).opacity(0.65), in: Capsule())
        }
    }
}

private struct MessageBanner: View {
    let message: AppMessage

    private var icon: String {
        switch message.style {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch message.style {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 11, weight: .semibold))

            Text(message.text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.18), lineWidth: 1))
    }
}

private struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading cards")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyCardsView: View {
    @ObservedObject var model: BrexelModel
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isSearching ? "magnifyingglass" : "creditcard")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(isSearching ? "No matches" : "No available cards")
                    .font(.system(size: 15, weight: .semibold))
                Text(isSearching ? "Try a card name, merchant, or last four." : "Refresh after cards are issued or permissions change.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !isSearching {
                Button {
                    Task { await model.refreshCards() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: Capsule())
            }
        }
        .padding(24)
    }
}

private struct FooterView: View {
    @ObservedObject var model: BrexelModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)

            Text("Secure fields load on copy.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct AppBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

private struct CopiedPill: View {
    let action: CardCopyAction

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)

            Text("Copied \(action.copiedLabel)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.green.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(Color.green.opacity(0.25), lineWidth: 0.5))
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private extension BrexCard {
    var searchableText: String {
        [
            cardName,
            lastFour,
            status,
            cardType,
            limitType,
            maskedLastFour,
            subtitle,
            directLimitText
        ]
        .compactMap { $0?.trimmedNonEmpty }
        .joined(separator: " ")
    }
}
