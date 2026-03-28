import Foundation
import XCTest
@testable import VoiceInputMac

final class MicrophoneDeviceChangeMonitorTests: XCTestCase {
    func testConnectedNotificationTriggersCallback() {
        let center = NotificationCenter()
        let connectedName = Notification.Name("test.microphone.connected")
        let disconnectedName = Notification.Name("test.microphone.disconnected")
        let monitor = AVFoundationMicrophoneDeviceChangeMonitor(
            notificationCenter: center,
            connectedNotification: connectedName,
            disconnectedNotification: disconnectedName
        )

        let expectation = expectation(description: "connected callback")
        let received = LockedValueBox<MicrophoneDeviceChangeEvent?>(nil)
        monitor.startObserving { event in
            received.withLock { $0 = event }
            expectation.fulfill()
        }

        center.post(name: connectedName, object: nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received.value?.kind, .connected)
    }

    func testDisconnectedNotificationTriggersCallback() {
        let center = NotificationCenter()
        let connectedName = Notification.Name("test.microphone.connected")
        let disconnectedName = Notification.Name("test.microphone.disconnected")
        let monitor = AVFoundationMicrophoneDeviceChangeMonitor(
            notificationCenter: center,
            connectedNotification: connectedName,
            disconnectedNotification: disconnectedName
        )

        let expectation = expectation(description: "disconnected callback")
        let received = LockedValueBox<MicrophoneDeviceChangeEvent?>(nil)
        monitor.startObserving { event in
            received.withLock { $0 = event }
            expectation.fulfill()
        }

        center.post(name: disconnectedName, object: nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received.value?.kind, .disconnected)
    }

    func testRepeatedNotificationsDoNotPreventFurtherCallbacks() {
        let center = NotificationCenter()
        let connectedName = Notification.Name("test.microphone.connected")
        let disconnectedName = Notification.Name("test.microphone.disconnected")
        let monitor = AVFoundationMicrophoneDeviceChangeMonitor(
            notificationCenter: center,
            connectedNotification: connectedName,
            disconnectedNotification: disconnectedName
        )

        let callbackCount = LockedValueBox(0)
        let expectation = expectation(description: "all callbacks")
        expectation.expectedFulfillmentCount = 3
        monitor.startObserving { _ in
            callbackCount.withLock { $0 += 1 }
            expectation.fulfill()
        }

        center.post(name: connectedName, object: nil)
        center.post(name: connectedName, object: nil)
        center.post(name: disconnectedName, object: nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(callbackCount.value, 3)
    }

    func testStopObservingPreventsFurtherCallbacks() {
        let center = NotificationCenter()
        let connectedName = Notification.Name("test.microphone.connected")
        let disconnectedName = Notification.Name("test.microphone.disconnected")
        let monitor = AVFoundationMicrophoneDeviceChangeMonitor(
            notificationCenter: center,
            connectedNotification: connectedName,
            disconnectedNotification: disconnectedName
        )

        let callbackCount = LockedValueBox(0)
        monitor.startObserving { _ in
            callbackCount.withLock { $0 += 1 }
        }
        monitor.stopObserving()

        center.post(name: connectedName, object: nil)
        center.post(name: disconnectedName, object: nil)

        XCTAssertEqual(callbackCount.value, 0)
    }
}

private final class LockedValueBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ storage: Value) {
        self.storage = storage
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withLock(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}
