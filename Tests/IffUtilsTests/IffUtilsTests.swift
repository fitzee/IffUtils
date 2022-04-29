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
    
    // check that we read the same amount of bytes as the file size
    func testCheckFileSize() throws {
        let fURL = Bundle.module.url(forResource: "test_image", withExtension: "iff")
        var fileSize: Int = 0
        
        do {
            // this will get the file size from the resource URL
            let resources = try fURL?.resourceValues(forKeys: [.fileSizeKey])
            fileSize = (resources?.fileSize)!
        } catch {
            fatalError()
        }
        
        //XCTAssertEqual(try IffUtils.processFile(fileURL: fURL!).count, fileSize)
    }
}
