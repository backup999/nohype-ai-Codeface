import Foundation
import Testing
import SwiftyToolz
@testable import Codeface

struct TreeSitterReferenceLinkerTests {
    
    // MARK: - Same-file mutual recursion (register-before-process)
    
    @Test func testMutualLocalsOrderIndependent() throws {
        let code = """
        func a() { b() }
        func b() { a() }
        """
        
        let symbols = try CodeTreeGenerator.generateTree(from: code, language: .swift)
        let file = TreeSitterFile(name: "AB.swift", code: code, nodes: symbols)
        let linked = TreeSitterFolder(name: "Demo", files: [file]).withLinkedReferences()
        
        let a = try #require(linked.files[0].symbols.first { $0.name == "a" })
        let b = try #require(linked.files[0].symbols.first { $0.name == "b" })
        
        #expect((a.references ?? []).count == 1)
        #expect((b.references ?? []).count == 1)
        #expect(a.references?.first?.filePathRelativeToRoot == "AB.swift")
        #expect(b.references?.first?.filePathRelativeToRoot == "AB.swift")
    }
    
    // MARK: - Nested shadowing (inner wins)
    
    @Test func testNestedShadowingInnerWins() throws {
        let code = """
        func foo() {}
        func bar() {
            func foo() {}
            foo()
        }
        """
        
        let symbols = try CodeTreeGenerator.generateTree(from: code, language: .swift)
        let file = TreeSitterFile(name: "Shadow.swift", code: code, nodes: symbols)
        let linked = TreeSitterFolder(name: "Demo", files: [file]).withLinkedReferences()
        
        let outerFoo = try #require(linked.files[0].symbols.first { $0.name == "foo" })
        let bar = try #require(linked.files[0].symbols.first { $0.name == "bar" })
        let innerFoo = try #require(bar.children.first { $0.role == .declaration && $0.name == "foo" })
        
        #expect((outerFoo.references ?? []).isEmpty)
        #expect((innerFoo.references ?? []).count == 1)
        #expect(innerFoo.references?.first?.filePathRelativeToRoot == "Shadow.swift")
    }
    
    // MARK: - Cross-file unique top-level
    
    @Test func testCrossFileUniqueTopLevel() throws {
        let aCode = """
        func a() { b() }
        """
        let bCode = """
        func b() {}
        """
        
        let aSymbols = try CodeTreeGenerator.generateTree(from: aCode, language: .swift)
        let bSymbols = try CodeTreeGenerator.generateTree(from: bCode, language: .swift)
        
        let forest = TreeSitterFolder(
            name: "Demo",
            files: [
                TreeSitterFile(name: "A.swift", code: aCode, nodes: aSymbols),
                TreeSitterFile(name: "B.swift", code: bCode, nodes: bSymbols),
            ]
        )
        let linked = forest.withLinkedReferences()
        
        let b = try #require(
            linked.files.first { $0.name == "B.swift" }?.symbols.first { $0.name == "b" }
        )
        
        #expect((b.references ?? []).count == 1)
        #expect(b.references?.first?.filePathRelativeToRoot == "A.swift")
    }
    
    // MARK: - Ambiguous root names never bind
    
    @Test func testAmbiguousRootNamesDoNotBind() throws {
        let aCode = """
        func foo() {}
        """
        let bCode = """
        func foo() {}
        func bar() { foo() }
        """
        
        let forest = TreeSitterFolder(
            name: "Demo",
            files: [
                TreeSitterFile(
                    name: "A.swift",
                    code: aCode,
                    nodes: try CodeTreeGenerator.generateTree(from: aCode, language: .swift)
                ),
                TreeSitterFile(
                    name: "B.swift",
                    code: bCode,
                    nodes: try CodeTreeGenerator.generateTree(from: bCode, language: .swift)
                ),
            ]
        )
        let linked = forest.withLinkedReferences()
        
        let foos = linked.files.flatMap(\.symbols).filter { $0.name == "foo" }
        #expect(foos.count == 2)
        #expect(foos.allSatisfy { ($0.references ?? []).isEmpty })
    }
    
    // MARK: - Architecture sibling edge after link
    
    @Test func testArchitectureSiblingEdgeAfterLink() async throws {
        let code = """
        struct Container {
            func bar() { qux() }
            func qux() {}
        }
        """
        
        let symbols = try CodeTreeGenerator.generateTree(from: code, language: .swift)
        let forest = TreeSitterFolder(
            name: "Demo",
            files: [TreeSitterFile(name: "Container.swift", code: code, nodes: symbols)]
        )
        
        let architecture = await BackgroundActor.run {
            CodebaseProcessorSteps.generateArchitecture(from: forest)
        }
        
        guard let part = architecture.partGraph.values.first,
              case .file(let fileArtifact) = part.kind,
              let container = fileArtifact.symbolGraph.values.first
        else {
            Issue.record("Expected Container file/symbol")
            return
        }
        
        #expect(container.name == "Container")
        #expect(container.subsymbolGraph.nodesByID.count == 2)
        #expect(container.subsymbolGraph.edgesByID.count >= 1)
        
        let subsymbols = Array(container.subsymbolGraph.values)
        let names = Set(subsymbols.map(\.name))
        #expect(names == ["bar", "qux"])
        
        // bar depends on qux → edge from bar to qux
        let bar = try #require(subsymbols.first { $0.name == "bar" })
        let qux = try #require(subsymbols.first { $0.name == "qux" })
        let edge = container.subsymbolGraph.edge(from: bar.id, to: qux.id)
        #expect(edge != nil)
    }
    
    // MARK: - Sanity: CodeRange under App/ (repro: works in Basic Types alone)
    
    /// Mirrors opening **App** vs **Basic Types** only.
    ///
    /// Under full App, `CodeRange+LSPRange.swift` also has `extension CodePosition`
    /// (Tree-sitter: another root `class_declaration` named CodePosition). v0 root
    /// scope treats that as **ambiguous** and never binds the name → no used-by →
    /// no Architecture edge. Basic Types alone has a single CodePosition → works.
    ///
    /// Stages: (1) linker used-by (2) Architecture edge on CodeRange.swift.
    @Test func testCodeRangeDepsWhenNestedUnderAppWithExtensionElsewhere() async throws {
        let appDir = try #require(appSourceRootURL())
        let codeRangeURL = appDir.appendingPathComponent("Basic Types/CodeRange.swift")
        let extensionURL = appDir.appendingPathComponent(
            "Codebase Architecture/Create from LSP Codebase/CodeRange+LSPRange.swift"
        )
        #expect(FileManager.default.fileExists(atPath: codeRangeURL.path))
        #expect(FileManager.default.fileExists(atPath: extensionURL.path))
        
        let codeRangeCode = try String(contentsOf: codeRangeURL, encoding: .utf8)
        let extensionCode = try String(contentsOf: extensionURL, encoding: .utf8)
        #expect(codeRangeCode.contains("let start: CodePosition"))
        #expect(extensionCode.contains("extension CodePosition"))
        
        let basicTypes = TreeSitterFolder(
            name: "Basic Types",
            files: [
                TreeSitterFile(
                    name: "CodeRange.swift",
                    code: codeRangeCode,
                    nodes: try CodeTreeGenerator.generateTree(from: codeRangeCode, language: .swift)
                ),
            ]
        )
        let lspCreate = TreeSitterFolder(
            name: "Create from LSP Codebase",
            files: [
                TreeSitterFile(
                    name: "CodeRange+LSPRange.swift",
                    code: extensionCode,
                    nodes: try CodeTreeGenerator.generateTree(from: extensionCode, language: .swift)
                ),
            ]
        )
        let architectureFolder = TreeSitterFolder(
            name: "Codebase Architecture",
            subfolders: [lspCreate]
        )
        // Minimal App: Basic Types + the one sibling path that re-declares CodePosition.
        let app = TreeSitterFolder(
            name: "App",
            subfolders: [basicTypes, architectureFolder]
        )
        
        // ── Stage 1: linker ──────────────────────────────────────────────
        let linked = app.withLinkedReferences()
        let linkedCodeRangeFile = try #require(
            linked.subfolders
                .first { $0.name == "Basic Types" }?
                .files.first { $0.name == "CodeRange.swift" }
        )
        let linkedPosition = try #require(linkedCodeRangeFile.symbols.first {
            $0.name == "CodePosition" && $0.attributes["declaration_kind"] == "struct"
        })
        let usedByCount = (linkedPosition.references ?? []).count
        #expect(
            usedByCount >= 1,
            """
            Stage 1 (linker): CodePosition should still get used-by for same-file \
            property types even when another file has `extension CodePosition` \
            (v0 root ambiguity currently drops the name entirely)
            """
        )
        
        // ── Stage 2: Architecture ────────────────────────────────────────
        let architecture = await BackgroundActor.run {
            var extra = [TreeSitterCodeSymbol.ReferenceLocation]()
            return CodeFolderArtifact(
                codeFolder: linked,
                pathInRootFolder: .root,
                additionalReferences: &extra
            )
        }
        
        let fileArtifact = try #require(
            findFileArtifact(named: "CodeRange.swift", under: architecture),
            "Stage 2: CodeRange.swift not found under Architecture tree"
        )
        let fileSymbols = Array(fileArtifact.symbolGraph.values)
        let codeRangeArt = try #require(
            fileSymbols.first { $0.name == "CodeRange" && $0.kind == "Struct" }
        )
        let codePositionArt = try #require(
            fileSymbols.first { $0.name == "CodePosition" && $0.kind == "Struct" }
        )
        #expect(
            fileArtifact.symbolGraph.edge(from: codeRangeArt.id, to: codePositionArt.id) != nil,
            """
            Stage 2 (Architecture): no edge CodeRange → CodePosition \
            (linker used-by count=\(usedByCount); edgeCount=\(fileArtifact.symbolGraph.edgesByID.count))
            """
        )
    }
    
    /// `#file` → `App/` source root.
    private func appSourceRootURL() -> URL? {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Link
            .deletingLastPathComponent() // TreeSitter Codebase
            .deletingLastPathComponent() // App
        return FileManager.default.fileExists(atPath: appDir.path) ? appDir : nil
    }
    
    private func findFileArtifact(named name: String,
                                  under folder: CodeFolderArtifact) -> CodeFileArtifact? {
        for part in folder.partGraph.values {
            switch part.kind {
            case .file(let file) where file.name == name:
                return file
            case .subfolder(let sub):
                if let found = findFileArtifact(named: name, under: sub) {
                    return found
                }
            default:
                continue
            }
        }
        return nil
    }
    
    // MARK: - Same-file type mention + call (basic used-by)
    
    @Test func testSameFileCallAndTypeMention() throws {
        let code = """
        struct Qux {}
        func qux() {}
        struct Foo {
            var x: Qux
            func baz() {
                qux()
            }
        }
        """
        
        let symbols = try CodeTreeGenerator.generateTree(from: code, language: .swift)
        let file = TreeSitterFile(name: "Demo.swift", code: code, nodes: symbols)
        let linked = TreeSitterFolder(name: "Root", files: [file]).withLinkedReferences()
        
        let quxType = try #require(linked.files[0].symbols.first { $0.name == "Qux" })
        let quxFunc = try #require(linked.files[0].symbols.first { $0.name == "qux" })
        
        #expect((quxType.references ?? []).count >= 1)
        #expect((quxFunc.references ?? []).count >= 1)
        #expect(quxType.references?.allSatisfy { $0.filePathRelativeToRoot == "Demo.swift" } == true)
        #expect(quxFunc.references?.allSatisfy { $0.filePathRelativeToRoot == "Demo.swift" } == true)
    }
}
