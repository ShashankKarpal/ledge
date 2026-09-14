// Merge-as-edit tests. The rule is narrow on purpose: related texts collapse
// with checkboxes unioned, unrelated texts stay two entries, and spool drains
// never merge at all.
// Built by Claude (Anthropic).

import XCTest
@testable import LedgeCore

final class EditMergeTests: XCTestCase {

    func date(_ stamp: String) -> Date {
        LedgeFormat.spoolFormatter.date(from: stamp)!
    }

    func makeTempStore() throws -> LedgeStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LedgeEditMergeTests-" + UUID().uuidString, isDirectory: true)
        let store = LedgeStore(root: root)
        try store.bootstrap(now: date("2026-09-01 09:00"))
        return store
    }

    // MARK: Relatedness

    func testRelatedness() {
        XCTAssertTrue(EditMerge.areRelated("- [ ] call the bank", "- [x] call the bank"), "a toggle")
        XCTAssertTrue(EditMerge.areRelated("call the bnk", "call the bank"), "a small fix")
        XCTAssertTrue(EditMerge.areRelated("call the bank", "call the bank about the card"), "typing continued")
        XCTAssertTrue(EditMerge.areRelated("- [ ] milk\n- [ ] eggs\n- [ ] bread", "- [x] milk\n- [ ] eggs\n- [ ] bread\n- [ ] butter"), "a list grew")
        XCTAssertFalse(EditMerge.areRelated("call mom", "buy milk"), "two thoughts in one minute")
        XCTAssertFalse(EditMerge.areRelated("book the dentist", "cancel the gym"), "two thoughts, similar length")
        XCTAssertFalse(EditMerge.areRelated("", "anything"))
    }

    func testMergedUnionsCheckboxes() {
        let preferred = "- [ ] milk\n- [x] eggs\nnote"
        let other = "- [x] milk\n- [ ] eggs\nnote"
        XCTAssertEqual(EditMerge.merged(preferred: preferred, other: other), "- [x] milk\n- [x] eggs\nnote")
        XCTAssertEqual(EditMerge.merged(preferred: "  * [ ] indented", other: "* [x] indented"), "  * [x] indented")
        XCTAssertEqual(EditMerge.merged(preferred: "plain", other: "plain"), "plain")
    }

    // MARK: Fold policies

    func testIncomingWinsReplacesRelatedTwin() {
        var inbox = Inbox.parse("## 2026-09-14\n### 09:00 · MacBook M4\ncall the bnk\n")
        let added = inbox.fold([(date: date("2026-09-14 09:00"), text: "call the bank", device: "MacBook M4")], policy: .incomingWins)
        XCTAssertEqual(added, 0)
        XCTAssertEqual(inbox.allEntries().count, 1)
        XCTAssertEqual(inbox.allEntries().first?.entry.text, "call the bank")
    }

    func testExistingWinsKeepsCurrentTextButTicksBoxes() {
        var inbox = Inbox.parse("## 2026-09-14\n### 09:00 · iPhone\n- [ ] call the bank about the card\n")
        let added = inbox.fold([(date: date("2026-09-14 09:00"), text: "- [x] call the bank", device: "iPhone")], policy: .existingWins)
        XCTAssertEqual(added, 0)
        XCTAssertEqual(inbox.allEntries().count, 1)
        // The current wording survives; the tick from the other side does too
        // only when the line matches, and here it does not, so it stays open.
        XCTAssertEqual(inbox.allEntries().first?.entry.text, "- [ ] call the bank about the card")

        var toggled = Inbox.parse("## 2026-09-14\n### 09:00 · iPhone\n- [ ] call the bank\n")
        toggled.fold([(date: date("2026-09-14 09:00"), text: "- [x] call the bank", device: "iPhone")], policy: .existingWins)
        XCTAssertEqual(toggled.allEntries().first?.entry.text, "- [x] call the bank", "a completion is never undone by a merge")
    }

    func testUnrelatedTextsStayTwoEntriesUnderEveryPolicy() {
        for policy in [EditPolicy.keepBoth, .incomingWins, .existingWins] {
            var inbox = Inbox.parse("## 2026-09-14\n### 09:00 · iPhone\ncall mom\n")
            let added = inbox.fold([(date: date("2026-09-14 09:00"), text: "buy milk", device: "iPhone")], policy: policy)
            XCTAssertEqual(added, 1, "\(policy)")
            XCTAssertEqual(inbox.allEntries().count, 2, "\(policy)")
        }
    }

    func testDifferentDeviceNeverMerges() {
        var inbox = Inbox.parse("## 2026-09-14\n### 09:00 · iPhone\ncall the bnk\n")
        let added = inbox.fold([(date: date("2026-09-14 09:00"), text: "call the bank", device: "MacBook M4")], policy: .incomingWins)
        XCTAssertEqual(added, 1, "same minute on two devices is two captures, the 0.5.0 rule")
        XCTAssertEqual(inbox.allEntries().count, 2)
    }

    func testSpoolDrainKeepsBothRelatedCaptures() throws {
        // Two Siri captures inside one minute that happen to look alike are
        // two thoughts. The drain path must never apply an edit policy.
        let store = try makeTempStore()
        let at = date("2026-09-14 09:00")
        try store.appendSpoolLine(Spool.line(for: "call the bank", at: at, device: "iPhone", id: "a"))
        try store.appendSpoolLine(Spool.line(for: "call the bank about the card", at: at, device: "iPhone", id: "b"))
        var inbox = try store.loadInbox()
        let batch = try store.drainSpool(into: &inbox)
        try store.saveInbox(inbox)
        try batch.commit()
        XCTAssertEqual(batch.added, 2)
        let texts = inbox.allEntries().map(\.entry.text)
        XCTAssertTrue(texts.contains("call the bank"))
        XCTAssertTrue(texts.contains("call the bank about the card"))
    }

    // MARK: The bug this exists for

    func testCompletedLoopDoesNotReappearAfterCrossDeviceSave() throws {
        // Device A ticks a loop and writes. Device B still holds the unticked
        // copy in memory and saves something else. Before: B's merge folded
        // its unticked twin next to A's ticked one, and the loop "came back".
        let store = try makeTempStore()
        var inbox = try store.loadInbox()
        inbox.prepend(text: "- [ ] renew the passport", at: date("2026-09-14 09:00"), device: "MacBook M4")
        try store.saveInbox(inbox)

        // B reads the same state.
        let deviceB = LedgeStore(root: store.root)
        var inboxB = try deviceB.loadInbox()
        XCTAssertEqual(inboxB.allEntries().first?.entry.text, "- [ ] renew the passport")

        // A ticks the box and writes (disk moves on).
        var inboxA = try store.loadInbox()
        inboxA.days[0].entries[0].text = "- [x] renew the passport"
        try store.saveInbox(inboxA)
        // Make sure the disk stamp differs from B's read stamp even on a
        // coarse filesystem clock.
        let attrs: [FileAttributeKey: Any] = [.modificationDate: Date().addingTimeInterval(5)]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: store.inboxURL.path)

        // B, still holding the unticked copy, captures something new and saves.
        inboxB.prepend(text: "water the plants", at: date("2026-09-14 09:05"), device: "MacBook M4")
        try deviceB.saveInbox(inboxB)

        let final = Inbox.parse(try String(contentsOf: store.inboxURL, encoding: .utf8))
        let passport = final.allEntries().filter { $0.entry.text.contains("renew the passport") }
        XCTAssertEqual(passport.count, 1, "one passport entry, not a ticked and an unticked twin:\n\(final.serialized())")
        XCTAssertEqual(passport.first?.entry.text, "- [x] renew the passport", "the completion survives B's stale copy")
        XCTAssertTrue(final.allEntries().contains { $0.entry.text == "water the plants" })
    }

    func testTypoFixDoesNotDoubleAfterCrossDeviceSave() throws {
        let store = try makeTempStore()
        var inbox = try store.loadInbox()
        inbox.prepend(text: "call the bnk", at: date("2026-09-14 09:00"), device: "MacBook M4")
        try store.saveInbox(inbox)

        // Another writer lands an unrelated capture, so disk moves on.
        let other = LedgeStore(root: store.root)
        var otherInbox = try other.loadInbox()
        otherInbox.prepend(text: "buy stamps", at: date("2026-09-14 09:03"), device: "iPhone")
        try other.saveInbox(otherInbox)
        let attrs: [FileAttributeKey: Any] = [.modificationDate: Date().addingTimeInterval(5)]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: store.inboxURL.path)

        // We fix the typo on our stale copy and save.
        inbox.days[0].entries[0].text = "call the bank"
        try store.saveInbox(inbox)

        let final = Inbox.parse(try String(contentsOf: store.inboxURL, encoding: .utf8))
        let bank = final.allEntries().filter { $0.entry.text.hasPrefix("call the b") }
        XCTAssertEqual(bank.count, 1, "\(final.serialized())")
        XCTAssertEqual(bank.first?.entry.text, "call the bank")
        XCTAssertTrue(final.allEntries().contains { $0.entry.text == "buy stamps" })
    }
}
