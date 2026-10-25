import Foundation
import USBTransport

struct MacropadTransport {
    func write(_ packets: [[UInt8]]) throws {
        guard !packets.isEmpty else { return }
        guard let libraryURL = Bundle.main.url(forResource: "libusb-1.0", withExtension: "dylib") else {
            throw MacropadTransportError(message: "Bundled libusb is missing from app resources", notConnected: false)
        }
        let bytes = packets.flatMap { $0 }
        var errorBuffer = [CChar](repeating: 0, count: 256)
        let result = libraryURL.path.withCString { libraryPath in
            bytes.withUnsafeBufferPointer { packetBuffer in
                errorBuffer.withUnsafeMutableBufferPointer { error in
                    keyflow_usb_write_packets(libraryPath, packetBuffer.baseAddress, packets.count,
                                          error.baseAddress, error.count)
                }
            }
        }
        guard result == 0 else {
            let message = errorBuffer.withUnsafeBufferPointer { buffer in
                String(cString: buffer.baseAddress!)
            }
            throw MacropadTransportError(message: message, notConnected: result == -2)
        }
    }
}

struct MacropadTransportError: LocalizedError {
    let message: String
    let notConnected: Bool
    var errorDescription: String? { message }
}
