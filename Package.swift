// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jarvis",
    platforms: [.macOS(.v14)],
    targets: [
        // whisper.h includes ggml.h, which Homebrew installs from a separate formula; both are found through pkg-config.
        .systemLibrary(name: "CGGML", pkgConfig: "ggml", providers: [.brew(["ggml"])]),
        .systemLibrary(name: "CWhisper", pkgConfig: "whisper", providers: [.brew(["whisper-cpp"])]),
        .target(name: "JarvisCore"),
        .target(name: "JarvisKit", dependencies: ["JarvisCore", "CWhisper", "CGGML"]),
        .executableTarget(name: "Jarvis", dependencies: ["JarvisKit", "JarvisCore"]),
        .testTarget(name: "JarvisCoreTests", dependencies: ["JarvisCore"], exclude: ["Fixtures"]),
        .testTarget(name: "JarvisKitTests", dependencies: ["JarvisKit", "JarvisCore"], exclude: ["Fixtures"]),
    ],
    swiftLanguageModes: [.v5]
)
