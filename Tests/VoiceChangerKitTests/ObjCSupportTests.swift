import Foundation
import ObjCSupport
import Testing

@Test func catcherReturnsReasonOfRaisedException() {
    let reason = VCCatchException {
        NSException(name: .internalInconsistencyException, reason: "boom", userInfo: nil).raise()
    }
    #expect(reason == "boom")
}

@Test func catcherReturnsNilWhenNothingIsRaised() {
    var ran = false
    let reason = VCCatchException { ran = true }
    #expect(reason == nil)
    #expect(ran)
}
