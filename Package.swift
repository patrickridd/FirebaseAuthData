// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FirebaseAuthData",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FirebaseAuthData",
            targets: ["FirebaseAuthData"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/patrickridd/AuthDomain.git", from: "1.0.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0"),
    ],
    targets: [
        .target(
            name: "FirebaseAuthData",
            dependencies: [
                .product(name: "AuthDomain", package: "AuthDomain"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
            ]
        ),
        .testTarget(
            name: "FirebaseAuthDataTests",
            dependencies: ["FirebaseAuthData"]
        ),
    ]
)
