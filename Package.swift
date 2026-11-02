// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZvukMusicIOS",
    platforms: [.iOS(.v17)],
    products: [.executable(name: "ZvukMusicIOS", targets: ["ZvukMusicIOS"])],
    targets: [.executableTarget(name: "ZvukMusicIOS", path: "Sources")]
)
