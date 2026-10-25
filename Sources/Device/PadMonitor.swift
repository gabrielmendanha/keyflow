import Foundation
import IOKit

final class PadMonitor {
    private static let vendorID = 0x1189
    private static let productID = 0x8890
    private static let reconciliationInterval: TimeInterval = 30

    private let status: DeviceStatus
    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var reconciliationTimer: Timer?

    init(status: DeviceStatus) {
        self.status = status
    }

    func start() {
        if let notificationPort = IONotificationPortCreate(kIOMainPortDefault) {
            self.notificationPort = notificationPort
            IONotificationPortSetDispatchQueue(notificationPort, .main)
            registerDeviceNotifications(on: notificationPort)
        } else {
            status.monitoringWarning = "USB notifications unavailable; checking periodically."
        }

        reconcile()
        reconciliationTimer = Timer.scheduledTimer(
            withTimeInterval: Self.reconciliationInterval,
            repeats: true
        ) { [weak self] _ in self?.reconcile() }
    }

    private func registerDeviceNotifications(on port: IONotificationPortRef) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        var added: io_iterator_t = 0
        let addResult = IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, Self.matchingDictionary(), padDidAppear, context, &added
        )
        if addResult == KERN_SUCCESS {
            iterators.append(added)
            consume(added, appeared: true)
        }

        var removed: io_iterator_t = 0
        let removeResult = IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, Self.matchingDictionary(), padDidDisappear, context, &removed
        )
        if removeResult == KERN_SUCCESS {
            iterators.append(removed)
            consume(removed, appeared: false)
        }

        if addResult != KERN_SUCCESS || removeResult != KERN_SUCCESS {
            status.monitoringWarning = "USB change notifications are limited; checking periodically."
        }
    }

    fileprivate func consume(_ iterator: io_iterator_t, appeared: Bool) {
        var found = false
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            found = true
            IOObjectRelease(service)
        }

        if appeared, found {
            status.updateConnection(true)
        } else if !appeared, found {
            reconcile()
        }
    }

    fileprivate func reconcile() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOUSBHostDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            status.monitoringWarning = "Could not query USB devices; checking again shortly."
            return
        }
        defer { IOObjectRelease(iterator) }

        var found = false
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            if Self.isSupportedPad(service) {
                found = true
                break
            }
        }
        status.updateConnection(found)
        if found { status.monitoringWarning = nil }
    }

    private static func matchingDictionary() -> CFMutableDictionary {
        let dictionary = IOServiceMatching("IOUSBHostDevice")! as NSMutableDictionary
        dictionary["idVendor"] = NSNumber(value: vendorID)
        dictionary["idProduct"] = NSNumber(value: productID)
        return dictionary as CFMutableDictionary
    }

    private static func isSupportedPad(_ service: io_service_t) -> Bool {
        property(service, "idVendor")?.intValue == vendorID &&
            property(service, "idProduct")?.intValue == productID
    }

    private static func property(_ service: io_service_t, _ key: String) -> NSNumber? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return nil }
        return value as? NSNumber
    }
}

private let padDidAppear: IOServiceMatchingCallback = { context, iterator in
    guard let context else { return }
    Unmanaged<PadMonitor>.fromOpaque(context).takeUnretainedValue().consume(iterator, appeared: true)
}

private let padDidDisappear: IOServiceMatchingCallback = { context, iterator in
    guard let context else { return }
    Unmanaged<PadMonitor>.fromOpaque(context).takeUnretainedValue().consume(iterator, appeared: false)
}
