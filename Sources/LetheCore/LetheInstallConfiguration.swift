import Foundation

public enum LetheProvider: String, CaseIterable, Sendable {
    case openrouter
    case anthropic
    case openai

    public var displayName: String {
        switch self {
        case .openrouter:
            return "OpenRouter"
        case .anthropic:
            return "Anthropic"
        case .openai:
            return "OpenAI"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openrouter:
            return "openrouter/moonshotai/kimi-k2.5-0127"
        case .anthropic:
            return "claude-opus-4-6"
        case .openai:
            return "gpt-5.2"
        }
    }

    public var defaultAuxModel: String {
        switch self {
        case .openrouter:
            return "openrouter/google/gemini-3-flash-preview"
        case .anthropic:
            return "claude-haiku-4-5-20251001"
        case .openai:
            return "gpt-5.2-mini"
        }
    }
}

public enum AnthropicAuthMode: String, Sendable {
    case apiKey
    case subscriptionToken
}

public struct LetheInstallConfiguration: Sendable {
    public var provider: LetheProvider
    public var anthropicAuthMode: AnthropicAuthMode
    public var model: String
    public var auxModel: String
    public var apiBase: String
    public var apiKey: String
    public var telegramBotToken: String
    public var telegramUserID: String

    public init(
        provider: LetheProvider,
        anthropicAuthMode: AnthropicAuthMode = .subscriptionToken,
        model: String,
        auxModel: String,
        apiBase: String,
        apiKey: String,
        telegramBotToken: String,
        telegramUserID: String
    ) {
        self.provider = provider
        self.anthropicAuthMode = anthropicAuthMode
        self.model = model
        self.auxModel = auxModel
        self.apiBase = apiBase
        self.apiKey = apiKey
        self.telegramBotToken = telegramBotToken
        self.telegramUserID = telegramUserID
    }

    public var authEnvName: String {
        switch provider {
        case .openrouter:
            return "OPENROUTER_API_KEY"
        case .openai:
            return "OPENAI_API_KEY"
        case .anthropic:
            return anthropicAuthMode == .apiKey ? "ANTHROPIC_API_KEY" : "ANTHROPIC_AUTH_TOKEN"
        }
    }
}
