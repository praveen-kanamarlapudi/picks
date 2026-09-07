import XCTest
@testable import KeepCore

final class PairingTests: XCTestCase {
    func testPairPrefersRAWAsCanonical() {
        let files = [
            DiscoveredFile(relativePath: "03 Wedding/Candid Photos/JPG/M3F0001.jpg", ext: "jpg", size: 100),
            DiscoveredFile(relativePath: "03 Wedding/Candid Photos/RAW/M3F0001.ARW", ext: "arw", size: 200),
        ]
        let drafts = Pairing.pair(files: files)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].photoID, "M3F0001")
        XCTAssertEqual(drafts[0].canonicalKind, .raw)
        XCTAssertEqual(drafts[0].canonicalPath, "03 Wedding/Candid Photos/RAW/M3F0001.ARW")
        XCTAssertEqual(drafts[0].jpegPath, "03 Wedding/Candid Photos/JPG/M3F0001.jpg")
        XCTAssertEqual(drafts[0].rawPath, "03 Wedding/Candid Photos/RAW/M3F0001.ARW")
    }

    func testJPEGOnlyWhenRAWMissing() {
        let files = [
            DiscoveredFile(relativePath: "01 Engagement/Candid Photos/JPG/AKHI0001.JPG", ext: "jpg", size: 50),
        ]
        let drafts = Pairing.pair(files: files)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].canonicalKind, .jpeg)
        XCTAssertEqual(drafts[0].canonicalPath, "01 Engagement/Candid Photos/JPG/AKHI0001.JPG")
        XCTAssertNil(drafts[0].rawPath)
    }

    func testRAWOnlyIsReviewable() {
        let files = [
            DiscoveredFile(relativePath: "03 Wedding/Candid Photos/RAW/M3F0002.ARW", ext: "arw", size: 200),
        ]
        let drafts = Pairing.pair(files: files)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].canonicalKind, .raw)
        XCTAssertNil(drafts[0].jpegPath)
    }

    func testSameStemIsOnePhoto() {
        let files = [
            DiscoveredFile(relativePath: "03 Wedding/Candid Photos/JPG/M3F0001.jpg", ext: "jpg", size: 100),
            DiscoveredFile(relativePath: "03 Wedding/Candid Photos/RAW/M3F0001.ARW", ext: "arw", size: 200),
            DiscoveredFile(relativePath: "03 Wedding/Traditional Photos/RAW/M3F0001.ARW", ext: "arw", size: 200),
        ]
        let drafts = Pairing.pair(files: files)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertTrue(drafts[0].canonicalPath.contains("Candid"))
    }

    func testSkipsAlternateExportsAndThumbs() {
        let files = [
            DiscoveredFile(relativePath: "03 Wedding/Traditional Photos/JPG/Alternate Exports/M3F0001.jpg", ext: "jpg", size: 80),
            DiscoveredFile(relativePath: "03 Wedding/Traditional Video/Thumbnails/C0001T01.JPG", ext: "jpg", size: 20),
        ]
        XCTAssertTrue(Pairing.pair(files: files).isEmpty)
    }

    func testDifferentCeremoniesStaySeparate() {
        let files = [
            DiscoveredFile(relativePath: "01 Engagement/Candid Photos/JPG/C0001T01.JPG", ext: "jpg", size: 10),
            DiscoveredFile(relativePath: "06 Groom/Traditional Photos/JPG/C0001T01.JPG", ext: "jpg", size: 11),
        ]
        let drafts = Pairing.pair(files: files)
        XCTAssertEqual(drafts.count, 2)
    }

    func testFlatDumpIsOneCeremony() {
        let files = [
            DiscoveredFile(relativePath: "SAB09390.JPG", ext: "jpg", size: 10),
            DiscoveredFile(relativePath: "SAB09395.JPG", ext: "jpg", size: 11),
            DiscoveredFile(relativePath: "SAB09390.ARW", ext: "arw", size: 20),
        ]
        let drafts = Pairing.pair(files: files, eventName: "Newborn Photoshoot Raw")
        XCTAssertEqual(drafts.count, 2)
        XCTAssertTrue(drafts.allSatisfy { $0.ceremony == "Newborn Photoshoot Raw" })
        let paired = drafts.first { $0.photoID == "SAB09390" }
        XCTAssertEqual(paired?.canonicalKind, .raw)
    }
}
