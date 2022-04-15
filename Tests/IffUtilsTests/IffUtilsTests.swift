import XCTest
@testable import IffUtils

final class IffUtilsTests: XCTestCase {
    // test our Motorola to Intel long number conversion function
    func testBigEndianToLittleEndian() throws {
        XCTAssertEqual(IffUtils.m2i(l: 0x00546500), 0x00655400)
        XCTAssertEqual(IffUtils.m2i(l: 0x00655400), 0x00546500)
        XCTAssertEqual(IffUtils.m2i(n: 0xf123), 0x23f1)
        XCTAssertEqual(IffUtils.m2i(n: 0x23f1), 0xf123)
    }
    
    func testCheckFileSize() throws {
        let testBundle = Bundle(for: type(of: self))
        let fURL = testBundle.url(forResource: "test_image", withExtension: "iff")
        let fileSize = 14155
        
        XCTAssert(try fURL!.checkResourceIsReachable())
        XCTAssertEqual(IffUtils.openIFF(fileURL: fURL!).count, fileSize)
    }
}
