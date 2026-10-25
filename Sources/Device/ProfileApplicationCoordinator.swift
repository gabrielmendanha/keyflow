import Combine
import Foundation

final class ProfileApplicationCoordinator {
    private struct SavedState: Codable {
        let slots: [String: String]
        let led: Int?
    }

    private static let stateKey = "keyflow.lastSuccessfullyAppliedLayout.v1"

    private let status: DeviceStatus
    private let catalog: ProfileCatalogStore
    private let transport = MacropadTransport()
    private let writeQueue = DispatchQueue(label: "com.nacifsoftware.keyflow.profile-writes")
    private let requestLock = NSLock()
    private var subscriptions = Set<AnyCancellable>()
    private var requestGeneration = 0
    private var knownSlots: [String: String]?
    private var knownLED: Int?

    init(status: DeviceStatus, catalog: ProfileCatalogStore) {
        self.status = status
        self.catalog = catalog
        if let data = UserDefaults.standard.data(forKey: Self.stateKey),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            knownSlots = saved.slots
            knownLED = saved.led
        }
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        Publishers.CombineLatest(catalog.$selectedProfileID, status.$isConnected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profileID, connected in
                guard let self else { return }
                guard connected else {
                    self.status.applicationMessage = nil
                    return
                }
                guard let profileID,
                      let profile = self.catalog.profiles.first(where: { $0.id == profileID }) else {
                    self.status.applicationMessage = "Macropad connected · no profile selected"
                    return
                }
                self.requestApply(profile)
            }
            .store(in: &subscriptions)
    }

    private func requestApply(_ profile: CatalogProfile) {
        requestLock.lock()
        requestGeneration += 1
        let generation = requestGeneration
        requestLock.unlock()
        status.applicationMessage = "Applying \(profile.name)…"

        writeQueue.async { [weak self] in
            guard let self else { return }
            self.requestLock.lock()
            let isCurrent = generation == self.requestGeneration
            self.requestLock.unlock()
            guard isCurrent else { return }

            do {
                let full = self.knownSlots == nil
                let packets = try ProfilePacketEncoder.packets(
                    for: profile.layout,
                    full: full,
                    comparedTo: self.knownSlots,
                    previousLED: self.knownLED
                )
                try self.transport.write(packets)

                self.knownSlots = ProfilePacketEncoder.canonicalState(for: profile.layout)
                if let led = profile.layout.led { self.knownLED = led }
                let saved = SavedState(slots: self.knownSlots!, led: self.knownLED)
                if let data = try? JSONEncoder().encode(saved) {
                    UserDefaults.standard.set(data, forKey: Self.stateKey)
                }
                DispatchQueue.main.async {
                    self.status.applicationMessage = packets.isEmpty
                        ? "Macropad already has \(profile.name)"
                        : "Applied \(profile.name) to macropad"
                }
            } catch {
                self.knownSlots = nil
                self.knownLED = nil
                UserDefaults.standard.removeObject(forKey: Self.stateKey)
                let message = "Could not apply \(profile.name): \(error.localizedDescription)"
                DispatchQueue.main.async { self.status.applicationMessage = message }
            }
        }
    }
}
