import Testing

@testable import VoiceChangerKit

@Test func sliderFractionIsClampedPositionInRange() {
    #expect(SliderScale.fraction(of: 0, in: -12...12) == 0.5)
    #expect(SliderScale.fraction(of: 20, in: -12...12) == 1)
    #expect(SliderScale.fraction(of: -20, in: -12...12) == 0)
}

@Test func sliderValueFollowsPointerAndClamps() {
    #expect(SliderScale.value(atX: 50, width: 200, in: 0...1) == 0.25)
    #expect(SliderScale.value(atX: -10, width: 200, in: 0...1) == 0)
    #expect(SliderScale.value(atX: 500, width: 200, in: 0...1) == 1)
    #expect(SliderScale.value(atX: 100, width: 200, in: -12...12) == 0)
    #expect(SliderScale.value(atX: 10, width: 0, in: 20...1000) == 20)
}

@Test func sliderStepsByTwentiethOfRangeAndClamps() {
    #expect(abs(SliderScale.stepped(0, by: 1, in: -12...12) - 1.2) < 0.0001)
    #expect(abs(SliderScale.stepped(0.5, by: -1, in: 0...1) - 0.45) < 0.0001)
    #expect(SliderScale.stepped(0.98, by: 1, in: 0...1) == 1)
    #expect(SliderScale.stepped(-12, by: -1, in: -12...12) == -12)
}

@Test func levelFractionSpansSixtyDecibels() {
    #expect(LevelScale.fraction(forPeak: 1) == 1)
    #expect(LevelScale.fraction(forPeak: 2) == 1)
    #expect(LevelScale.fraction(forPeak: 0.001) == 0)
    #expect(LevelScale.fraction(forPeak: 0) == 0)
    #expect(abs(LevelScale.fraction(forPeak: 0.0316) - 0.5) < 0.01)
}
