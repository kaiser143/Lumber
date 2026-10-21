import XCTest
@testable import Lumber

final class AssetCatalogParserTests: XCTestCase {
    func testParsesImageSetColorSetAndDataSet() throws {
        let temp = try TempDirectory()
        try temp.bytes("Assets.xcassets/icon.imageset/icon.png", count: 120)
        try temp.bytes("Assets.xcassets/icon.imageset/icon@2x.png", count: 40)
        try temp.file("Assets.xcassets/icon.imageset/Contents.json", contents: """
        {
          "images" : [
            { "filename" : "icon.png", "idiom" : "universal", "scale" : "1x" },
            { "filename" : "icon@2x.png", "idiom" : "universal", "scale" : "2x" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """)

        try temp.file("Assets.xcassets/brand.colorset/Contents.json", contents: """
        {
          "colors" : [
            { "color" : { "color-space" : "srgb", "components" : { "alpha" : "1.000", "blue" : "0.200", "green" : "0.400", "red" : "0.800" } }, "idiom" : "universal" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """)

        try temp.bytes("Assets.xcassets/data.dataset/data.pdf", count: 50)
        try temp.file("Assets.xcassets/data.dataset/Contents.json", contents: """
        { "data" : [ { "filename" : "data.pdf", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }
        """)

        let catalogURL = try temp.directory("Assets.xcassets")
        let catalog = AssetCatalogParser.parse(catalogURL: catalogURL, relativePath: "Assets.xcassets")

        XCTAssertEqual(catalog.entries.count, 3)
        XCTAssertEqual(catalog.imageSetCount, 1)

        let byName = Dictionary(uniqueKeysWithValues: catalog.entries.map { ($0.name, $0) })

        let icon = try XCTUnwrap(byName["icon"])
        XCTAssertEqual(icon.kind, .imageSet)
        XCTAssertEqual(icon.kind.resourceType, .image)
        XCTAssertEqual(icon.representativeURL?.lastPathComponent, "icon.png")
        XCTAssertGreaterThanOrEqual(icon.totalSizeBytes, 160)
        XCTAssertTrue(icon.fileNames.contains("icon.png"))
        XCTAssertTrue(icon.fileNames.contains("icon@2x.png"))

        let brand = try XCTUnwrap(byName["brand"])
        XCTAssertEqual(brand.kind, .colorSet)
        XCTAssertEqual(brand.kind.resourceType, .color)
        XCTAssertNil(brand.representativeURL)
        XCTAssertGreaterThan(brand.totalSizeBytes, 0)

        let data = try XCTUnwrap(byName["data"])
        XCTAssertEqual(data.kind, .dataSet)
        XCTAssertEqual(data.kind.resourceType, .data)
        XCTAssertEqual(data.representativeURL?.lastPathComponent, "data.pdf")
    }

    func testNestedGroupKeepsEntryNames() throws {
        let temp = try TempDirectory()
        try temp.bytes("Assets.xcassets/Icons/star.imageset/star.png", count: 10)
        let catalogURL = try temp.directory("Assets.xcassets")
        let catalog = AssetCatalogParser.parse(catalogURL: catalogURL, relativePath: "Assets.xcassets")
        XCTAssertEqual(catalog.entries.map(\.name), ["star"])
    }

    func testUnscannableKindsAreExcludedFromResourceMapping() {
        XCTAssertNil(AssetEntry.Kind.appIconSet.resourceType)
        XCTAssertNil(AssetEntry.Kind.symbolSet.resourceType)
        XCTAssertNil(AssetEntry.Kind.launchImage.resourceType)
        XCTAssertEqual(AssetEntry.Kind.imageStack.resourceType, .image)
        XCTAssertEqual(AssetEntry.Kind.spriteAtlas.resourceType, .image)
    }
}
