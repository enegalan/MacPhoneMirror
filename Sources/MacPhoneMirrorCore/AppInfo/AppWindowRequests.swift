import Combine
import Foundation

@MainActor
public enum AppWindowRequests {
    public static let aboutWindowOpenPublisher = PassthroughSubject<Void, Never>()

    public static func requestAboutWindow() {
        aboutWindowOpenPublisher.send(())
    }
}
