import SwiftUI

enum BFMotion {
    static let fast: Double = 0.15
    static let normal: Double = 0.20
    static let slow: Double = 0.30
    static let xslow: Double = 0.50
    static let entrance: Double = 1.0

    static let easingDefault: Animation = .easeOut(duration: fast)
    static let easingInOut: Animation = .easeInOut(duration: fast)
    static let easingSlow: Animation = .easeOut(duration: slow)
    static let easingEntrance: Animation = .easeOut(duration: entrance)
}
