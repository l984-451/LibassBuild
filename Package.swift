// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LibassBuild",
    platforms: [.tvOS("26.0")],
    products: [
        .library(name: "Libass", targets: ["Libass"]),
    ],
    targets: [
        // libass 0.17.5 with FreeType VER-2-14-3, HarfBuzz 14.2.0,
        // FriBidi v1.0.16 and libunibreak 6.1, one static archive.
        .binaryTarget(
            name: "Libass",
            url: "https://github.com/l984-451/LibassBuild/releases/download/0.17.5-1/Libass.xcframework.zip",
            checksum: "0045ab962f5bb9f68c90d2be2a3076eedcd1fc023301a95078be448adcb67d55"
        ),
    ]
)
