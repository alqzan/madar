import XCTest
import UIKit

/// M5-V05: synthetic Shortcut messages through the real intake; «اعتمد الواضح» skips the duplicate, the statement
/// updates its card once, and an unread message is ignored from «تحتاج نظرة».
@MainActor final class MoneyMessagesUITests: XCTestCase {
    private struct LocalCorpusLine: Codable { let sender: String; let date: String; let text: String }

    func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }

    private func localCorpusSamples() throws -> [LocalCorpusLine] {
        let madar = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = madar.appendingPathComponent("Private/bank-messages", isDirectory: true)
        let selectors: [(String, [String])] = [
            ("alrajhibank.jsonl", ["شراء"]),
            ("barq_app.jsonl", ["money added", "add funds", "تمت إضافة", "إضافة أموال", "اضافة اموال"]),
            ("stcpay.jsonl", ["wallet top up", "wallet top-up", "تغذية محفظة", "شحن المحفظة", "تعبئة المحفظة"])
        ]
        var selected: [LocalCorpusLine] = []
        for (filename, needles) in selectors {
            let file = folder.appendingPathComponent(filename)
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { throw XCTSkip("Local bank-message corpus is unavailable") }
            let sample = contents.split(whereSeparator: \.isNewline).compactMap { raw -> LocalCorpusLine? in
                guard let line = try? JSONDecoder().decode(LocalCorpusLine.self, from: Data(raw.utf8)) else { return nil }
                return needles.contains(where: { line.text.localizedCaseInsensitiveContains($0) }) ? line : nil
            }.first
            guard let sample else { throw XCTSkip("A needed local parser example is unavailable") }
            selected.append(sample)
        }
        return selected
    }

    func testCategorizationFailureKeepsPerPurchaseChoiceForRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "messages",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00",
            "MADAR_UI_MONEY_CATEGORIZE_FAILURE_ONCE": "1"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        let draft = app.otherElements["money-draft-مخبز الحي"].firstMatch
        let chip = draft.buttons["money-draft-category"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<7 where !chip.isHittable { app.swipeUp(velocity: .slow) }
        chip.tap()
        let perPurchase = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "لهذه العملية فقط")).firstMatch
        XCTAssertTrue(perPurchase.waitForExistence(timeout: 5))
        shot(app, "M5-category-choice-L")
        let grocery = app.buttons["money-categorize-بقالة"]
        XCTAssertTrue(grocery.waitForExistence(timeout: 5)); grocery.tap()
        let error = app.staticTexts["money-categorize-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8), "A failed save must leave the sheet open for retry")
        XCTAssertTrue(grocery.isEnabled)
        XCTAssertTrue(grocery.label.contains("حاول مرة أخرى"), grocery.label)
        shot(app, "M5-category-failure-L")
        grocery.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.label.contains("بقالة"), chip.label)
        XCTAssertTrue(app.descendants(matching: .any)["money-messages-review"].label.contains("٦"), "Choosing a category never confirms the message")
        shot(app, "M5-category-saved-L")
        app.terminate()
        app.launch()
        let reopenedTab = app.buttons["tab-customize"]; XCTAssertTrue(reopenedTab.waitForExistence(timeout: 20)); reopenedTab.tap()
        let reopenedSearch = app.textFields["settings-search"]; XCTAssertTrue(reopenedSearch.waitForExistence(timeout: 10)); reopenedSearch.tap(); reopenedSearch.typeText("المال")
        app.buttons["money-open"].tap()
        let reopenedTray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(reopenedTray.waitForExistence(timeout: 10)); reopenedTray.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertTrue(chip.label.contains("بقالة"), "The successful retry persists the category")
    }

    func testDeleteFailureShowsDeleteMessageAndKeepsDraftForRetry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "messages",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00",
            "MADAR_UI_MONEY_DELETE_FAILURE_ONCE": "1"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        let draft = app.descendants(matching: .any)["money-draft-مخبز الحي"]
        let delete = draft.buttons["money-draft-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10), app.debugDescription)
        delete.tap()
        let note = app.staticTexts["money-draft-delete-error"]
        XCTAssertTrue(note.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(note.label, "تعذّر حذف الحركة.")
        for _ in 0..<6 where !note.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(note.isHittable, app.debugDescription)
        XCTAssertTrue(draft.exists, "A failed delete must leave the draft available")
        shot(app, "AU-73-draft-delete-failure-L")
        draft.buttons["money-draft-delete"].tap()
        XCTAssertTrue(draft.waitForNonExistence(timeout: 10), app.debugDescription)
    }

    func testPasteOverFiveHundredMessagesIsRejectedWithoutPartialImport() throws {
        continueAfterFailure = false
        let sample = "شراء مدى\n*3333\n18.00 SAR\nلدى: Coffee\n2026-10-16 12:00"
        UIPasteboard.general.string = Array(repeating: sample, count: 501).joined(separator: "\n\n")
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "empty", "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
                                "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))

        let paste = app.descendants(matching: .any)["money-messages-paste"]
        for _ in 0..<8 where !paste.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(paste.isHittable, app.debugDescription)
        paste.tap()

        let note = app.staticTexts["money-messages-note"]
        let rejected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "٥٠١"), object: note)
        XCTAssertEqual(XCTWaiter.wait(for: [rejected], timeout: 10), .completed, "The full count must be explained instead of silently truncating")
        XCTAssertTrue(note.label.contains("٥٠٠") && note.label.contains("لم تُستورد أي رسالة"), note.label)
        let review = app.descendants(matching: .any)["money-messages-review"]
        XCTAssertTrue(review.label.contains("٠"), "Rejecting the oversized paste must leave the inbox unchanged: \(review.label)")
        shot(app, "M5-E03-paste-over-limit-L")

        UIPasteboard.general.string = Array(repeating: sample, count: 500).joined(separator: "\n\n")
        for _ in 0..<8 where !paste.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(paste.isHittable, app.debugDescription)
        paste.tap()
        let imported = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "٥٠٠"), object: review)
        XCTAssertEqual(XCTWaiter.wait(for: [imported], timeout: 60), .completed, "A complete in-limit batch must still reach review")
        shot(app, "M5-E03-paste-500-L")
    }

    func testClearDraftsStatementAndLookAreDecidedHere() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "messages",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-16T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        let review = app.descendants(matching: .any)["money-messages-review"]
        let clear = app.buttons["money-confirm-clear"]
        XCTAssertTrue(review.label.contains("٦"), review.label)
        XCTAssertTrue(app.descendants(matching: .any)["money-statement"].exists)
        let statementCard = app.descendants(matching: .any)["money-statement-card-preview"]
        XCTAssertTrue(statementCard.exists)
        XCTAssertTrue(statementCard.label.contains("تنتهي بـ"))
        shot(app, "M5-V05-msg-L")
        var sawDuplicate = app.descendants(matching: .any)["money-draft-duplicate"].exists
        for _ in 0..<8 where !clear.isHittable {
            app.swipeUp(velocity: .slow)
            sawDuplicate = sawDuplicate || app.descendants(matching: .any)["money-draft-duplicate"].exists
        }
        XCTAssertTrue(sawDuplicate)
        XCTAssertTrue(clear.isHittable)
        XCTAssertTrue(clear.label.contains("(٢)"), "An incoming transfer still needs an explicit income/salary choice")
        shot(app, "M5-V05-msg-s1-L")
        clear.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 10))
        for _ in 0..<5 where !app.buttons["money-messages-close"].isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(review.label.contains("٤"), review.label)
        let spent = app.descendants(matching: .any)["money-messages-spent"]
        XCTAssertTrue(spent.label.contains("٢") && spent.label.contains("٦٠٫٥٠"), spent.label)
        let incoming = app.otherElements["money-draft-سالم"].buttons["money-draft-confirm"]
        for _ in 0..<4 where !incoming.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(incoming.isHittable); incoming.tap()
        let confirmIncome = app.buttons["اعتمده كدخل"]; XCTAssertTrue(confirmIncome.waitForExistence(timeout: 5)); confirmIncome.tap()
        for _ in 0..<5 where !app.buttons["money-messages-close"].isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(review.label.contains("٣"), review.label)
        XCTAssertTrue(app.descendants(matching: .any)["money-messages-incoming"].label.contains("١٢٠"))
        app.swipeDown(velocity: .fast)
        let apply = app.buttons["money-statement-apply"]; XCTAssertTrue(apply.waitForExistence(timeout: 5)); apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10)); XCTAssertTrue(review.label.contains("٢"), review.label)
        let ignore = app.buttons["money-look-ignore"]; for _ in 0..<3 where !ignore.isHittable { app.swipeUp(velocity: .slow) }
        ignore.tap(); XCTAssertTrue(ignore.waitForNonExistence(timeout: 10))
        for _ in 0..<5 where !app.buttons["money-messages-close"].isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(review.label.contains("١"), review.label)
        app.swipeDown(velocity: .fast); shot(app, "M5-V05-msg-decided-L")
    }

    func testSalarySourceIsLearnedOnlyAfterConfirmation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "salarySourceFlow",
            "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light", "MADAR_UI_NOW": "2026-10-27T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["راتب مقترح"].exists, "The source has not been learned before the owner's first confirmation")

        let firstIncoming = app.descendants(matching: .any)["money-draft-confirm"].firstMatch
        XCTAssertTrue(firstIncoming.waitForExistence(timeout: 10), app.debugDescription); firstIncoming.tap()
        let chooseSalary = app.buttons["اعتبره راتبًا"]; XCTAssertTrue(chooseSalary.waitForExistence(timeout: 5), app.debugDescription); chooseSalary.tap()
        let salaryConfirm = app.buttons["money-salary-confirm"]; XCTAssertTrue(salaryConfirm.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 where !salaryConfirm.isHittable { app.swipeUp(velocity: .slow) }
        salaryConfirm.tap()

        let firstSuggestion = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "راتب مقترح")).firstMatch
        XCTAssertTrue(firstSuggestion.waitForExistence(timeout: 10), app.debugDescription)

        // A fresh app session clears the transient undo banner while proving the learned source persisted.
        app.terminate(); app.launchEnvironment["MADAR_UI_NOW"] = "2026-10-27T20:11:00+03:00"; app.launch()
        let resumedTab = app.buttons["tab-customize"]; XCTAssertTrue(resumedTab.waitForExistence(timeout: 20)); resumedTab.tap()
        let resumedSearch = app.textFields["settings-search"]; XCTAssertTrue(resumedSearch.waitForExistence(timeout: 10)); resumedSearch.tap(); resumedSearch.typeText("المال")
        let resumedMoney = app.buttons["money-open"]; XCTAssertTrue(resumedMoney.waitForExistence(timeout: 5)); resumedMoney.tap()
        let resumedTray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(resumedTray.waitForExistence(timeout: 10)); resumedTray.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))
        let suggestion = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "راتب مقترح")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<5 { app.swipeDown(velocity: .slow) }
        shot(app, "M5-V27-msg-salary-source-L")
        let suggestionCard = app.otherElements["money-draft-شركة المدار"].firstMatch
        let suggestedMenu = suggestionCard.buttons["money-draft-confirm"]
        XCTAssertTrue(suggestedMenu.waitForExistence(timeout: 5)); suggestedMenu.tap()
        XCTAssertTrue(app.buttons["راجع الراتب المقترح"].waitForExistence(timeout: 5))
        let incomeChoice = app.buttons["اعتمده كدخل"]; XCTAssertTrue(incomeChoice.exists); incomeChoice.tap()
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 10), "A salary suggestion can still be explicitly confirmed as ordinary income")
    }

    func testSelectedLocalCorpusMessagesReachReviewTray() throws {
        continueAfterFailure = false
        let corpus = try localCorpusSamples()
        let serialized = try JSONEncoder().encode(corpus)
        let packed = try (serialized as NSData).compressed(using: .lzfse) as Data
        let app = XCUIApplication()
        app.launchEnvironment = [
            "MADAR_UI_STORE_ID": UUID().uuidString,
            "MADAR_UI_MONEY_FIXTURE": "bankCorpus",
            "MADAR_UI_BANK_CORPUS_LZFSE": packed.base64EncodedString(),
            "MADAR_UI_SIZE": "L",
            "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-27T20:00:00+03:00"
        ]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 5)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 10)); tray.tap()
        XCTAssertTrue(app.staticTexts["money-messages-title"].waitForExistence(timeout: 10))

        let title = app.staticTexts["money-messages-title"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", String(corpus.count)), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 30), .completed, "Selected messages did not all reach the review tray")
        XCTAssertTrue(app.descendants(matching: .any)["money-messages-review"].label.contains("٣"))
        // Tail questions now sit above the drafts and the list is lazy: scroll until the first draft is built.
        let firstDraft = app.buttons.matching(identifier: "money-draft-confirm").firstMatch
        for _ in 0..<10 where !firstDraft.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(firstDraft.exists, app.debugDescription)
        shot(app, "M5-E03-local-corpus-L")
    }

    /// Private inputs stay on this Mac and in the isolated simulator store; no real text enters Git.
    func testAllLocalCorpusMessagesReachReviewTray() throws {
        continueAfterFailure = false
        let madar = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = madar.appendingPathComponent("Private/bank-messages", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "jsonl" }), !files.isEmpty else { throw XCTSkip("Local bank-message corpus is unavailable") }
        let corpus = try files.sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap { file in
            try String(contentsOf: file, encoding: .utf8).split(whereSeparator: \.isNewline).map { raw in
                try JSONDecoder().decode(LocalCorpusLine.self, from: Data(raw.utf8))
            }
        }
        XCTAssertGreaterThan(corpus.count, 500, "Exercise more than one intake batch")
        let packed = try (JSONEncoder().encode(corpus) as NSData).compressed(using: .lzfse) as Data
        let app = XCUIApplication()
        app.launchEnvironment = ["MADAR_UI_STORE_ID": UUID().uuidString, "MADAR_UI_MONEY_FIXTURE": "bankCorpus",
            "MADAR_UI_BANK_CORPUS_LZFSE": packed.base64EncodedString(), "MADAR_UI_SIZE": "L", "MADAR_UI_THEME": "light",
            "MADAR_UI_NOW": "2026-10-27T20:00:00+03:00"]
        app.launch()
        let tab = app.buttons["tab-customize"]; XCTAssertTrue(tab.waitForExistence(timeout: 60)); tab.tap()
        let search = app.textFields["settings-search"]; XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("المال")
        let money = app.buttons["money-open"]; XCTAssertTrue(money.waitForExistence(timeout: 10)); money.tap()
        let tray = app.descendants(matching: .any)["money-pending"]; XCTAssertTrue(tray.waitForExistence(timeout: 30)); tray.tap()
        let title = app.staticTexts["money-messages-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", String(corpus.count)), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 60), .completed, "Every batch must finish successfully before the screen trial")
        let review = app.descendants(matching: .any)["money-messages-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        let pendingDigits = review.label.compactMap(\.wholeNumberValue).map(String.init).joined()
        XCTAssertGreaterThan(Int(pendingDigits) ?? 0, 500, "The review count must cover the large inbox")
        shot(app, "M5-E03-complete-local-corpus-L")
        // Statements precede movement drafts, so this corpus may have many statement cards first.
        app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow)
        shot(app, "M5-E03-complete-local-corpus-scrolled-L")
        XCTAssertFalse(title.isHittable, "The large inbox scrolls without blocking interaction")
        for _ in 0..<6 where !app.buttons["money-messages-close"].isHittable { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(app.buttons["money-messages-close"].isHittable)
        app.buttons["money-messages-close"].tap()
        XCTAssertTrue(tray.waitForExistence(timeout: 10), "The large inbox can return to the money room")
    }

}
