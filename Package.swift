// swift-tools-version:5.9
// Platine : widget de bureau macOS pour Apple Music (piste en cours à gauche, file d'attente à droite).
// Build sans projet Xcode : ./build.sh assemble Platine.app, l'adaptateur MediaRemote et le widget embarqué.
import PackageDescription

let package = Package(
    name: "Platine",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "Platine", targets: ["Platine"]),
        .executable(name: "PlatineWidget", targets: ["PlatineWidget"]),
    ],
    targets: [
        // Modèles, fichier d'état partagé, calcul de la timeline du widget.
        .target(name: "PlatineCore", path: "Sources/PlatineCore"),
        // Vues SwiftUI, communes au widget et au rendu d'aperçu de l'app.
        .target(name: "PlatineUI", dependencies: ["PlatineCore"], path: "Sources/PlatineUI"),
        // Agent sans interface : écoute Musique, prépare les pochettes, écrit l'état, recharge le widget.
        .executableTarget(name: "Platine", dependencies: ["PlatineCore", "PlatineUI"], path: "Sources/Platine"),
        // Extension WidgetKit : lit l'état partagé et l'affiche sur le bureau.
        .executableTarget(
            name: "PlatineWidget",
            dependencies: ["PlatineCore", "PlatineUI"],
            path: "Sources/PlatineWidget",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .linkedFramework("WidgetKit"),
                .linkedFramework("SwiftUI"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"]),
            ]
        ),
        .testTarget(name: "PlatineCoreTests", dependencies: ["PlatineCore"], path: "Tests/PlatineCoreTests"),
    ],
    swiftLanguageVersions: [.v5]
)
