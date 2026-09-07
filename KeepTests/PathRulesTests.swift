import XCTest
@testable import KeepCore

final class PathRulesTests: XCTestCase {
    func testPhotoIDStripsDupAndAltSuffixes() {
        XCTAssertEqual(PathRules.photoID(filename: "M3F03442.ARW"), "M3F03442")
        XCTAssertEqual(PathRules.photoID(filename: "M3F03442__dup2.ARW"), "M3F03442")
        XCTAssertEqual(PathRules.photoID(filename: "M3F03442_1.jpg"), "M3F03442")
        XCTAssertEqual(PathRules.photoID(filename: "M3F03442__ALT.jpg"), "M3F03442")
        XCTAssertEqual(PathRules.photoID(filename: "_MG_6420.JPG"), "_MG_6420")
        XCTAssertEqual(PathRules.photoID(filename: "AKHI0355.JPG"), "AKHI0355")
    }

    func testCameraPrefix() {
        XCTAssertEqual(PathRules.cameraPrefix(photoID: "AKHI0355"), "AKHI")
        XCTAssertEqual(PathRules.cameraPrefix(photoID: "M3F03442"), "M3F")
        XCTAssertEqual(PathRules.cameraPrefix(photoID: "DMB04998"), "DMB")
        XCTAssertEqual(PathRules.cameraPrefix(photoID: "_S9A7954"), "S9A")
        XCTAssertEqual(PathRules.cameraPrefix(photoID: "_MG_6420"), "MG")
        XCTAssertEqual(PathRules.cameraPrefix(photoID: "_DSC4613"), "DSC")
        XCTAssertEqual(PathRules.cameraPrefix(photoID: "CRU02467"), "CRU")
    }

    func testClassifySkipsVideoThumbsAndVideos() {
        XCTAssertEqual(
            PathRules.classify(relativePath: "03 Wedding/Traditional Video/Thumbnails/C0001T01.JPG"),
            .videoThumb
        )
        XCTAssertEqual(
            PathRules.classify(relativePath: "03 Wedding/Candid Video/C0001.MP4"),
            .video
        )
        XCTAssertEqual(
            PathRules.classify(relativePath: "01 Engagement/Candid Photos/JPG/AKHI0355.JPG"),
            .jpeg
        )
        XCTAssertEqual(
            PathRules.classify(relativePath: "03 Wedding/Candid Photos/RAW/M3F03442.ARW"),
            .raw
        )
        XCTAssertEqual(
            PathRules.classify(relativePath: "_duplicate_report/SUMMARY.txt"),
            .junk
        )
    }

    func testCeremonyAndStyle() {
        XCTAssertEqual(
            PathRules.ceremony(relativePath: "01 Engagement/Candid Photos/JPG/AKHI0355.JPG"),
            "01 Engagement"
        )
        XCTAssertEqual(
            PathRules.ceremony(
                relativePath: "SAB09390.JPG",
                eventName: "Newborn Photoshoot Raw"
            ),
            "Newborn Photoshoot Raw"
        )
        XCTAssertEqual(
            PathRules.ceremony(relativePath: "RAW/SAB09390.ARW", eventName: "Newborn"),
            "Newborn"
        )
        XCTAssertEqual(
            PathRules.ceremony(relativePath: "Traditional Photos/DSC00002.ARW", eventName: "Naming Ceremony"),
            "Traditional Photos"
        )
        XCTAssertEqual(
            PathRules.ceremony(
                relativePath: "03 Wedding/Candid Photos/RAW/M3F03442.ARW",
                eventName: "WEDDING"
            ),
            "03 Wedding"
        )
        XCTAssertEqual(
            PathRules.style(relativePath: "03 Wedding/Candid Photos/RAW/M3F03442.ARW"),
            "Candid"
        )
        XCTAssertEqual(
            PathRules.style(relativePath: "03 Wedding/Traditional Photos/JPG/M3F01351.jpg"),
            "Traditional"
        )
    }

    func testStylePreferencePutsTraditionalFirst() {
        XCTAssertEqual(
            StylePreference.sortedStyles(["Candid", "Traditional", "Other"]),
            ["Traditional", "Other", "Candid"]
        )
        XCTAssertEqual(StylePreference.defaultStyle(in: ["Candid", "Traditional"]), "Traditional")
        XCTAssertEqual(StylePreference.defaultStyle(in: ["Candid"]), "Candid")
        XCTAssertEqual(
            StylePreference.defaultCeremony(session: "Candid Photos", all: ["Candid Photos", "Traditional Photos"]),
            "Traditional Photos"
        )
        XCTAssertEqual(
            StylePreference.defaultCeremony(session: "01 Engagement", all: ["01 Engagement", "03 Wedding"]),
            "01 Engagement"
        )
    }
}
