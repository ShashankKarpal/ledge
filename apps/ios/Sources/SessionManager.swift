// Phone side of the watch relay. Receives ["text": String, "stamp": String]
// payloads and appends them to the capture spool via SpoolWriter.
// Built by Claude (Anthropic).

import Foundation
import WatchConnectivity
import LedgeCore

final class SessionManager: NSObject, WCSessionDelegate {

    static let shared = SessionManager()

    /// Watch payloads arrive on background threads; funnel writes through one queue.
    private let writeQueue = DispatchQueue(label: "ledge.watch-relay")

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func handle(_ payload: [String: Any]) {
        guard let text = payload["text"] as? String, !text.isEmpty else { return }
        let stamp = payload["stamp"] as? String
        let date = stamp.flatMap { LedgeFormat.spoolFormatter.date(from: $0) } ?? Date()
        // The watch's delivery id rides along into the spool line so the drain
        // can drop a second delivery of the same capture (live message whose
        // reply timed out, then the queued fallback).
        let id = payload["id"] as? String
        writeQueue.async {
            SpoolWriter.append(text: text, at: date, device: "Apple Watch", id: id)
        }
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Nothing to do; queued transfers deliver on their own.
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Required on iOS; nothing to do.
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch keeps working.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handle(message)
        replyHandler(["received": true])
    }
}
