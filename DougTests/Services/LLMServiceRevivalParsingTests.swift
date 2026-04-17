@testable import Doug
import Foundation
import Testing

struct LLMServiceRevivalParsingTests {
    @Test func parsesWellFormedResponse() {
        let text = """
        OPENING: Your starter has been asleep for a while but looks viable.
        STEP 0 TITLE: Feed 1 — wake it up
        STEP 0 BULLETS: Retain 20 g | Add 40 g flour | Add 40 g water | Stir until smooth
        STEP 0 WATCH: Domed top with bubbles
        STEP 0 WAIT: ~8 hours
        STEP 1 TITLE: Feed 2 — build consistency
        STEP 1 BULLETS: Discard to 20 g | Feed 40 + 40 | Mark the jar
        STEP 1 WATCH: Bubbles within 90 min
        STEP 1 WAIT: ~6 hours
        STEP 2 TITLE: Feed 3 — confirm
        STEP 2 BULLETS: Discard to 20 g | Feed 40 + 40
        STEP 2 WATCH: Reliable double in 4h
        STEP 2 WAIT: ~5 hours
        """
        let result = LLMService.parseRevivalText(text, stepCount: 3)
        #expect(result != nil)
        #expect(result?.openingRead.contains("asleep") == true)
        #expect(result?.steps.count == 3)
        #expect(result?.steps[0].bullets.count == 4)
        #expect(result?.steps[1].title.contains("Feed 2") == true)
        #expect(result?.steps[2].expectedWait == "~5 hours")
    }

    @Test func abortReturnsNil() {
        #expect(LLMService.parseRevivalText("ABORT", stepCount: 3) == nil)
    }

    @Test func abortWithTrailingContentStillAborts() {
        #expect(LLMService.parseRevivalText("ABORT\nsome more text", stepCount: 3) == nil)
    }

    @Test func missingStepFieldsReturnsNil() {
        let text = """
        OPENING: Looks okay.
        STEP 0 TITLE: Feed 1
        STEP 0 BULLETS: Retain 20 g | Add 40 + 40
        STEP 0 WATCH: Domed top
        """
        // Missing STEP 0 WAIT — parser should reject.
        #expect(LLMService.parseRevivalText(text, stepCount: 1) == nil)
    }

    @Test func missingOpeningReturnsNil() {
        let text = """
        STEP 0 TITLE: Feed 1
        STEP 0 BULLETS: A | B
        STEP 0 WATCH: Watch
        STEP 0 WAIT: 6h
        """
        #expect(LLMService.parseRevivalText(text, stepCount: 1) == nil)
    }

    @Test func stepCountMismatchReturnsNil() {
        let text = """
        OPENING: Okay.
        STEP 0 TITLE: Feed 1
        STEP 0 BULLETS: A | B
        STEP 0 WATCH: Watch
        STEP 0 WAIT: 6h
        """
        // Request 3 steps but only 1 present.
        #expect(LLMService.parseRevivalText(text, stepCount: 3) == nil)
    }
}
