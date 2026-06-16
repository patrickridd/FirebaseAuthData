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
        .package(url: "https://github.com/patrickridd/AuthDomain.git", from: "1.4.1"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.14.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk.git", from: "18.0.0"),
    ],
    targets: [
        .target(
            name: "FirebaseAuthData",
            dependencies: [
                .product(name: "AuthDomain", package: "AuthDomain"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GoogleSignInSwift", package: "GoogleSignIn-iOS"),
                .product(name: "FacebookLogin", package: "facebook-ios-sdk"),
            ]
        ),
        .testTarget(
            name: "FirebaseAuthDataTests",
            dependencies: ["FirebaseAuthData"]
        ),
    ]
)
