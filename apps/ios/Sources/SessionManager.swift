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

    /// Write the payload and report where it landed. Synchronous on the write
    /// queue on purpose: the reply handler must not acknowledge a capture that
    /// is still in flight.
    @discardableResult
    private func handle(_ payload: [String: Any]) -> SpoolWriter.Landing {
        guard let text = payload["text"] as? String, !text.isEmpty else { return .spool }
        let stamp = payload["stamp"] as? String
        let date = stamp.flatMap { LedgeFormat.spoolFormatter.date(from: $0) } ?? Date()
        // The watch's delivery id rides along into the spool line so the drain
        // can drop a second delivery of the same capture (live message whose
        // reply timed out, then the queued fallback).
        let id = payload["id"] as? String
        return writeQueue.sync {
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
        // Acknowledge ONLY what is durable. The old code queued the append
        // asynchronously and replied "received: true" immediately, so the
        // watch stopped retrying while the write was still in flight; if that
        // write and the pending-queue fallback both failed, the thought was
        // gone with nothing left to retry (review 2026-09-03).
        let landing = handle(message)
        replyHandler(["received": landing != .failed])
    }
}
