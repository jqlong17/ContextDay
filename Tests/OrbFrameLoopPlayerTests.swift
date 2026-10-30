import XCTest
import AppKit
@testable import ContextDay

final class OrbFrameLoopPlayerTests: XCTestCase {
    func testSetFramesRequiresTwoForMeaningfulLoop() {
        let player = OrbFrameLoopPlayer()
        XCTAssertEqual(player.frameCount, 0)
        XCTAssertFalse(player.isRunning)

        func makeImage() -> CGImage {
            var pixel = [UInt8](repeating: 255, count: 4)
            let ctx = CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            return ctx.makeImage()!
        }
        let a = makeImage()
        let b = makeImage()
        player.setFrames([a])
        XCTAssertEqual(player.frameCount, 1)
        player.setFrames([a, b])
        XCTAssertEqual(player.frameCount, 2)
    }
}
