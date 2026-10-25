import AppKit
import SwiftUI

struct KeyflowPanelView: View {
    @ObservedObject var status: DeviceStatus
    @ObservedObject var catalog: ProfileCatalogStore
    @State private var automationEnabled = true
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = writeError {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            profilesSection
            Divider().padding(.horizontal, 16)
            footer
        }
        .frame(width: 320)
        .background(PopoverMaterialView())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Keyflow").font(.system(size: 14, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(status.isConnected ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(status.isConnected ? "Connected" : "Not connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(status.isConnected ? Color.primary : Color.secondary)
            }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PROFILES")
                .font(.system(size: 9, weight: .semibold)).tracking(0.7)
                .foregroundStyle(.secondary)
                .padding(.bottom, 3)
            if let errorMessage = catalog.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9).padding(.vertical, 7)
            } else if catalog.profiles.isEmpty {
                Text("No profiles are installed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 7)
            }
            ForEach(catalog.profiles) { profile in
                Button {
                    catalog.select(profile)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.system(size: 12, weight: .medium))
                            Text(profile.matchSummary).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .background(catalog.selectedProfileID == profile.id ? Color.accentColor.opacity(0.09) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Toggle("Automatic switching", isOn: $automationEnabled)
                .toggleStyle(.switch).controlSize(.mini)
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 3)
            Button(action: quit) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Quit Keyflow")
            .help("Quit Keyflow")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var writeError: String? {
        guard let message = status.applicationMessage, message.hasPrefix("Could not") else { return nil }
        return message
    }
}

private struct PopoverMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
    }
}
