import Foundation
import os

/// Central OSLog categories. Feature code does `Log.auth.debug("...")`.
enum Log {
    private static let subsystem = "com.carai.kabuto"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let net = Logger(subsystem: subsystem, category: "net")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
