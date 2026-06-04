//
//  DougDriverUITests.swift
//  DougUITests
//
//  Generic, data-driven UI driver for the `doug-simulator` skill.
//  Runs an ordered list of steps supplied via the DOUG_DRIVER_STEPS environment
//  variable (forwarded by xcodebuild as TEST_RUNNER_DOUG_DRIVER_STEPS), then
//  emits a structured JSON result between markers that scripts/drive.sh parses.
//
//  This replaces the unmaintained IDB dependency with first-party XCUITest:
//  element lookup is accessibility-driven (by identifier or visible label),
//  not pixel coordinates.
//
//  Step schema (JSON array). Each step has an "action":
//    {"action":"tap",        "id":"startButton"}        — tap by accessibility id
//    {"action":"tap",        "label":"Feed & Refrigerate"} — tap by visible label
//    {"action":"typeText",   "id":"amountField", "text":"100"}
//    {"action":"swipe",      "direction":"up|down|left|right"}
//    {"action":"wait",       "seconds":2}
//    {"action":"assertExists","label":"Levain Ready"}    — fail if not present
//    {"action":"describe"}                                — snapshot the a11y tree
//

import XCTest

final class DougDriverUITests: XCTestCase {

    /// Marker strings so drive.sh can extract the result from xcodebuild's log.
    private static let resultBegin = "===DOUG_DRIVER_RESULT==="
    private static let resultEnd = "===END_DOUG_DRIVER_RESULT==="

    /// Max characters of the accessibility tree to emit, to bound log size.
    private static let treeCharLimit = 6000

    override func setUpWithError() throws {
        // Record every step's outcome rather than aborting on the first failure.
        continueAfterFailure = true
    }

    @MainActor
    func testRunSteps() throws {
        let env = ProcessInfo.processInfo.environment
        let stepsJSON = env["DOUG_DRIVER_STEPS"] ?? "[]"
        let steps = parseSteps(stepsJSON)

        let app = XCUIApplication()
        if let raw = env["DOUG_DRIVER_LAUNCH_ARGS"], !raw.isEmpty {
            app.launchArguments = raw.split(separator: " ").map(String.init)
        }
        app.launch()

        var results: [[String: Any]] = []
        var anyFailed = false

        for (index, step) in steps.enumerated() {
            let action = step["action"] as? String ?? ""
            var status = "ok"
            var detail = ""

            switch action {
            case "tap":
                if let el = resolve(app, step), el.waitForExistence(timeout: 5) {
                    el.tap()
                    detail = describeTarget(step)
                } else {
                    status = "fail"; detail = "element not found: \(describeTarget(step))"
                }
            case "typeText":
                let text = step["text"] as? String ?? ""
                if let el = resolve(app, step), el.waitForExistence(timeout: 5) {
                    el.tap()
                    el.typeText(text)
                    detail = "typed \"\(text)\" into \(describeTarget(step))"
                } else {
                    status = "fail"; detail = "field not found: \(describeTarget(step))"
                }
            case "swipe":
                let dir = step["direction"] as? String ?? "up"
                switch dir {
                case "down": app.swipeDown()
                case "left": app.swipeLeft()
                case "right": app.swipeRight()
                default: app.swipeUp()
                }
                detail = "swiped \(dir)"
            case "wait":
                let seconds = (step["seconds"] as? NSNumber)?.doubleValue ?? 1
                Thread.sleep(forTimeInterval: seconds)
                detail = "waited \(seconds)s"
            case "assertExists":
                if let el = resolve(app, step), el.waitForExistence(timeout: 5) {
                    detail = "exists: \(describeTarget(step))"
                } else {
                    status = "fail"; detail = "missing: \(describeTarget(step))"
                }
            case "describe":
                detail = "(tree captured)"
            default:
                status = "fail"; detail = "unknown action: \(action)"
            }

            if status == "fail" { anyFailed = true }
            results.append(["index": index, "action": action, "status": status, "detail": detail])
        }

        emit(results: results, tree: snapshotTree(app))

        // Reflect overall success in the test's exit status for drive.sh.
        if anyFailed { XCTFail("one or more driver steps failed (see emitted result)") }
    }

    // MARK: - Element resolution

    /// Find an element by accessibility `id` (any type) or visible `label`.
    @MainActor
    private func resolve(_ app: XCUIApplication, _ step: [String: Any]) -> XCUIElement? {
        if let id = step["id"] as? String {
            return app.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        if let label = step["label"] as? String {
            // Match buttons, static text, and other labelled controls by label.
            let predicate = NSPredicate(format: "label == %@", label)
            return app.descendants(matching: .any).matching(predicate).firstMatch
        }
        return nil
    }

    private func describeTarget(_ step: [String: Any]) -> String {
        if let id = step["id"] as? String { return "id=\(id)" }
        if let label = step["label"] as? String { return "label=\"\(label)\"" }
        return "<no target>"
    }

    // MARK: - JSON in/out

    private func parseSteps(_ json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr
    }

    @MainActor
    private func snapshotTree(_ app: XCUIApplication) -> String {
        let tree = app.debugDescription
        if tree.count > Self.treeCharLimit {
            return String(tree.prefix(Self.treeCharLimit)) + "\n…(truncated)"
        }
        return tree
    }

    private func emit(results: [[String: Any]], tree: String) {
        let payload: [String: Any] = ["steps": results, "tree": tree]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]))
            ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
        print(Self.resultBegin)
        print(json)
        print(Self.resultEnd)
    }
}
