// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WordShelf", platforms: [.macOS("26.0")], products: [.executable(name: "WordShelf", targets: ["WordShelf"])], targets: [.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"), .executableTarget(name: "WordShelf", dependencies: ["CSQLite"], resources: [.copy("Assets/AppIcon.icns"), .copy("Assets/MWLogo.png")]), .testTarget(name: "WordShelfTests", dependencies: ["WordShelf"])])
