import Foundation
import Combine

final class DeviceStatus: ObservableObject {
    @Published private(set) var isConnected = false
    @Published var monitoringWarning: String?
    @Published var applicationMessage: String?

    func updateConnection(_ connected: Bool) {
        isConnected = connected
    }
}
