import SwiftUI

public struct HostedAISettingsSection: View {
    @Binding private var configuration: HostedAIConfiguration
    @State private var status: HostedAIHealthStatus?
    @State private var isChecking = false

    public init(configuration: Binding<HostedAIConfiguration>) {
        _configuration = configuration
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Hosted Service", selection: $configuration.service) {
                    ForEach(HostedAIService.allCases) { service in
                        Text(service.displayName).tag(service)
                    }
                }
                .onChange(of: configuration.service) { _, service in
                    configuration.applyServiceDefaults(service)
                }

                SecureField("\(configuration.service.displayName) API Key", text: selectedServiceAPIKeyBinding)

                Text("\(configuration.service.displayName) presets")
                    .font(.footnote.weight(.semibold))

                ForEach(configuration.service.presets) { preset in
                    presetRow(preset)
                }

                Text(serviceHelpText(for: configuration.service))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Saved API keys by provider")
                    .font(.footnote.weight(.semibold))

                ForEach(HostedAIService.allCases) { service in
                    SecureField(service.displayName, text: apiKeyBinding(for: service))
                }

                Toggle("Enable staged workflow routing", isOn: $configuration.enableWorkflowRouting)

                if configuration.enableWorkflowRouting {
                    TextField("Chunk Model", text: $configuration.chunkModel)
                    TextField("Polish Model", text: $configuration.polishModel)
                    TextField("Repair Model", text: $configuration.repairModel)
                    Text("Use different models for chunking, polish, and repair passes. Your app decides what each route means.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                TextField("Custom Base URL", text: $configuration.baseURL)

                if let status {
                    Text(status.summary)
                        .foregroundStyle(status.isHealthy ? Color.green : Color.secondary)
                    if let detail = status.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(isChecking ? "Checking..." : "Check Connection") {
                    Task { @MainActor in
                        isChecking = true
                        defer { isChecking = false }
                        status = await HostedAIClientFactory.healthStatus(for: configuration)
                    }
                }
                .disabled(isChecking)
            }
        } label: {
            Text("Hosted AI")
        }
    }

    private var selectedServiceAPIKeyBinding: Binding<String> {
        Binding(
            get: { configuration.selectedServiceAPIKey },
            set: { configuration.selectedServiceAPIKey = $0 }
        )
    }

    private func apiKeyBinding(for service: HostedAIService) -> Binding<String> {
        Binding(
            get: { configuration.apiKeysByService[service.rawValue] ?? "" },
            set: { configuration.setAPIKey($0, for: service) }
        )
    }

    @ViewBuilder
    private func presetRow(_ preset: HostedAIModelPreset) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .font(.subheadline.weight(.semibold))
                Text(preset.modelName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(preset.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if isSelectedPreset(preset) {
                Button("Selected") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(true)
            } else {
                Button("Use") {
                    configuration.applyPreset(preset)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func isSelectedPreset(_ preset: HostedAIModelPreset) -> Bool {
        configuration.service == preset.service &&
        configuration.baseURL == preset.baseURL &&
        configuration.primaryModel == preset.modelName
    }

    private func serviceHelpText(for service: HostedAIService) -> String {
        switch service {
        case .nvidia, .openAI, .zhipu, .mistral:
            return "Pick a preset, add an API key, then save your settings. These services use an OpenAI-compatible API surface."
        case .anthropic:
            return "Anthropic uses its native Messages API, but the setup flow stays the same."
        case .gemini:
            return "Gemini uses Google's native Generative Language API, but the setup flow stays the same."
        }
    }
}
