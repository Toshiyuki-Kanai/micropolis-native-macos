// swift-tools-version: 5.9
import PackageDescription

// C header module only: consumers do not need Swift C++ interoperability.
let package = Package(
    name: "MicropolisNative",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MicropolisNative", targets: ["MicropolisNative"]),
        .executable(name: "NativeSmoke", targets: ["NativeSmoke"])
    ],
    targets: [
        .target(
            name: "MicropolisNative",
            path: ".",
            exclude: ["tests", "examples", "makefile", "native.mk", "package.json",
                      "README.native.md", "src/emscripten.cpp", "src/callback.cpp",
                      "src/js_callback.h", "src/micropolisengine_lib.js",
                      "src/micropolisengine_template.html"],
            sources: [
                "src/allocate.cpp",
                "src/animate.cpp",
                "src/budget.cpp",
                "src/connect.cpp",
                "src/disasters.cpp",
                "src/evaluate.cpp",
                "src/fileio.cpp",
                "src/frontendmessage.cpp",
                "src/generate.cpp",
                "src/graph.cpp",
                "src/initialize.cpp",
                "src/map.cpp",
                "src/message.cpp",
                "src/micropolis.cpp",
                "src/position.cpp",
                "src/power.cpp",
                "src/random.cpp",
                "src/scan.cpp",
                "src/simulate.cpp",
                "src/sprite.cpp",
                "src/tool.cpp",
                "src/traffic.cpp",
                "src/update.cpp",
                "src/utilities.cpp",
                "src/zone.cpp",
                "native/callback.cpp", "native/api.cpp"
            ],
            publicHeadersPath: "native/include",
            cxxSettings: [.headerSearchPath("src")]
        ),
        .executableTarget(
            name: "NativeSmoke",
            dependencies: ["MicropolisNative"],
            path: "examples/swift"
        )
    ],
    cxxLanguageStandard: .cxx17
)
