import Foundation
import Testing
@testable import LetheCore

struct LethePathsTests {
    @Test func defaultPathsPointToExpectedLocations() {
        let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
        let paths = LethePaths(homeDirectory: home)

        #expect(paths.repositoryRoot.path == "/Users/example/devel/lethe")
        #expect(paths.installScript.path == "/Users/example/devel/lethe/install.sh")
        #expect(paths.updateScript.path == "/Users/example/devel/lethe/update.sh")
        #expect(paths.uninstallScript.path == "/Users/example/devel/lethe/uninstall.sh")
        #expect(paths.launchAgentPlist.path == "/Users/example/Library/LaunchAgents/com.lethe.agent.plist")
        #expect(paths.installDirectory.path == "/Users/example/.lethe")
        #expect(paths.configDirectory.path == "/Users/example/.config/lethe")
        #expect(paths.workspaceDirectory.path == "/Users/example/lethe")
    }

    @Test func authEnvNameMatchesProvider() {
        var config = LetheInstallConfiguration(
            provider: .openrouter,
            model: "m",
            auxModel: "a",
            apiBase: "",
            apiKey: "k",
            telegramBotToken: "b",
            telegramUserID: "1"
        )
        #expect(config.authEnvName == "OPENROUTER_API_KEY")

        config.provider = .openai
        #expect(config.authEnvName == "OPENAI_API_KEY")

        config.provider = .anthropic
        config.anthropicAuthMode = .apiKey
        #expect(config.authEnvName == "ANTHROPIC_API_KEY")

        config.anthropicAuthMode = .subscriptionToken
        #expect(config.authEnvName == "ANTHROPIC_AUTH_TOKEN")
    }

    @Test func providerDefaultsMatchExpectedModels() {
        #expect(LetheProvider.openrouter.defaultModel == "openrouter/moonshotai/kimi-k2.5-0127")
        #expect(LetheProvider.openrouter.defaultAuxModel == "openrouter/google/gemini-3-flash-preview")
        #expect(LetheProvider.anthropic.defaultModel == "claude-opus-4-6")
        #expect(LetheProvider.anthropic.defaultAuxModel == "claude-haiku-4-5-20251001")
    }
}
