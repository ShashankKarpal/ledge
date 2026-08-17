// Watch side of the capture relay. Reachable phone: sendMessage with a
// transferUserInfo fallback. Unreachable: transferUserInfo, which queues
// and delivers on its own. Capture is never blocked by sync state.
// Built by Claude (Anthropic).

import Foundation
import WatchConnectivity
import LedgeCore

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    /// Captures still queued for the phone, shown as a muted line in the UI.
    @Published private(set) var outstandingCount = 0

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ text: String) {
        // The id makes retries safe: the live path and the queued fallback can
        // both deliver the same capture (a received message whose reply timed
        // out looks like a failure here), and the phone's drain drops the
        // second copy by id.
        let payload: [String: Any] = [
            "text": text,
            "stamp": LedgeFormat.spoolFormatter.string(from: Date()),
            "id": UUID().uuidString
        ]
        let session = WCSession.default
        if session.activationState != .activated {
            session.activate()
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in
                self.refreshOutstanding()
            }, errorHandler: { _ in
                // Live delivery failed; the queued path always works.
                session.transferUserInfo(payload)
                self.refreshOutstanding()
            })
        } else {
            session.transferUserInfo(payload)
        }
        refreshOutstanding()
    }

    private func refreshOutstanding() {
        DispatchQueue.main.async {
            self.outstandingCount = WCSession.default.outstandingUserInfoTransfers.count
        }
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        refreshOutstanding()
    }

    func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        // A transfer that finished WITH an error was not delivered. Put the
        // capture straight back in the queue; it only counts as delivered when
        // didFinish reports success. (A capture was silently dropped here on
        // 2026-08-17.) If the error was spurious and the phone did get it, the
        // payload id lets the drain drop the extra copy.
        if error != nil, userInfoTransfer.userInfo["text"] != nil {
            session.transferUserInfo(userInfoTransfer.userInfo)
        }
        refreshOutstanding()
    }
}
