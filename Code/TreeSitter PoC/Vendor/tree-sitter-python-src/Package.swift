// swift-tools-version:5.3

import PackageDescription

// Fixed packaging: always compile scanner.c (upstream Package.swift uses a
// cwd-relative FileManager check that often drops the external scanner).
let package = Package(
    name: "TreeSitterPython",
    products: [
        .library(name: "TreeSitterPython", targets: ["TreeSitterPython"]),
    ],
    targets: [
        .target(
            name: "TreeSitterPython",
            path: ".",
            exclude: [
                "CMakeLists.txt",
                "Cargo.lock",
                "Cargo.toml",
                "LICENSE",
                "Makefile",
                "Package.resolved",
                "Package.swift",
                "README.md",
                "binding.gyp",
                "bindings/c",
                "bindings/go",
                "bindings/node",
                "bindings/python",
                "bindings/rust",
                "bindings/swift/TreeSitterPythonTests",
                "eslint.config.mjs",
                "examples",
                "go.mod",
                "go.sum",
                "grammar.js",
                "package-lock.json",
                "package.json",
                "pyproject.toml",
                "setup.py",
                "test",
                "tree-sitter.json",
                ".editorconfig",
                ".github",
                ".gitignore",
                ".gitattributes",
            ],
            sources: [
                "src/parser.c",
                "src/scanner.c",
            ],
            resources: [
                .copy("queries"),
            ],
            publicHeadersPath: "bindings/swift/TreeSitterPython",
            cSettings: [.headerSearchPath("src")]
        ),
    ],
    cLanguageStandard: .c11
)
