import Testing
@testable import Hana

@Suite("Cloudflare completion polling")
struct CloudflareCompletionPollingStateTests {
    @Test("Polling continues beyond the former 60-check limit")
    func continuesBeyondFormerLimit() {
        var state = CloudflareCompletionPollingState()

        for _ in 0..<120 {
            let didSchedule = state.schedule()
            #expect(didSchedule)
            state.beginCheck()
        }

        let didScheduleAgain = state.schedule()
        #expect(didScheduleAgain)
    }

    @Test("Only one check is scheduled and finishing stops future checks")
    func schedulingAndFinish() {
        var state = CloudflareCompletionPollingState()

        let firstSchedule = state.schedule()
        let duplicateSchedule = state.schedule()
        #expect(firstSchedule)
        #expect(!duplicateSchedule)

        state.beginCheck()
        let nextSchedule = state.schedule()
        #expect(nextSchedule)

        state.finish()
        let scheduleAfterFinish = state.schedule()
        #expect(state.isFinished)
        #expect(!state.isScheduled)
        #expect(!scheduleAfterFinish)
    }
}
