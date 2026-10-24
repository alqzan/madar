import XCTest
import WebKit
import MadarCommands

@MainActor final class MihbaraQuotationScriptTests: XCTestCase {
    private final class Navigation: NSObject, WKNavigationDelegate {
        let ready: XCTestExpectation
        init(_ ready: XCTestExpectation) { self.ready = ready }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready.fulfill() }
    }

    func testWholeAyahAcrossInlineTagsPreservesTextLinksAndIsIdempotent() async throws {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: QuranQuotationScript.source(index: try QuranQuotationIndex.bundled()), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        let ready = expectation(description: "Book document loaded")
        let navigation = Navigation(ready); view.navigationDelegate = navigation
        let quote = "لَقَدْ خَلَقْنَا الْإِنْسَانَ فِي أَحْسَنِ تَقْوِيمٍ"
        view.loadHTMLString("""
        <html dir="rtl"><body>
        <p id="full">قال: لَقَدْ <em id="inline">خَلَقْنَا الْإِنْسَانَ</em> فِي أَحْسَنِ تَقْوِيمٍ، ثم علّق.</p>
        <p id="marked">﴿إن <a href="#full">مع العسر</a> يسرا﴾</p>
        <p id="short">قل هو الله أحد</p>
        <p id="part1">لقد خلقنا الإنسان</p><p id="part2">في أحسن تقويم</p>
        <p id="unclosed">﴿نص لم يُغلق</p><p id="ordinary">كلام عادي.</p>
        <pre id="code">لقد خلقنا الإنسان في أحسن تقويم</pre>
        </body></html>
        """, baseURL: nil)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 15)
        XCTAssertEqual(result, .completed)
        let markedText = try await view.evaluateJavaScript("Array.from(document.querySelectorAll('#full .madar-ayah')).map(n => n.textContent).join('')") as? String
        XCTAssertEqual(markedText, quote)
        let original = try await view.evaluateJavaScript("document.querySelector('#full').textContent") as? String
        XCTAssertEqual(original, "قال: " + quote + "، ثم علّق.")
        let link = try await view.evaluateJavaScript("document.querySelector('#marked a').getAttribute('href')") as? String
        XCTAssertEqual(link, "#full")
        let ordinary = try await view.evaluateJavaScript("document.querySelectorAll('#short .madar-ayah, #part1 .madar-ayah, #part2 .madar-ayah, #unclosed .madar-ayah, #ordinary .madar-ayah, #code .madar-ayah').length") as? Int
        XCTAssertEqual(ordinary, 0)
        let before = try await view.evaluateJavaScript("document.body.innerHTML") as? String
        _ = try await view.evaluateJavaScript("window.madarMarkQuranQuotations()")
        let after = try await view.evaluateJavaScript("document.body.innerHTML") as? String
        XCTAssertEqual(after, before, "Reapplying never nests spans or changes text/markup")
        view.stopLoading(); view.navigationDelegate = nil
    }
}
