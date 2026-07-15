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
    
    // MARK: - Extension collides with type at root (same-file type mention)
    
    /// Tree-sitter models `extension T` as another root `class_declaration` named `T`.
    /// v0 root policy: duplicate root name → **ambiguous, never bind**.
    /// Same-file property type mentions of `T` should still resolve to the struct
    /// (real-world: `CodePosition` + `extension CodePosition` under App/).
    @Test func testSameFileTypeMentionDespiteRootExtensionElsewhere() throws {
        let typeCode = """
        struct T {
            var x: T
        }
        """
        let extensionCode = """
        extension T {}
        """
        
        let forest = TreeSitterFolder(
            name: "Demo",
            files: [
                TreeSitterFile(
                    name: "T.swift",
                    code: typeCode,
                    nodes: try CodeTreeGenerator.generateTree(from: typeCode, language: .swift)
                ),
                TreeSitterFile(
                    name: "T+Ext.swift",
                    code: extensionCode,
                    nodes: try CodeTreeGenerator.generateTree(from: extensionCode, language: .swift)
                ),
            ]
        )
        let linked = forest.withLinkedReferences()
        
        let t = try #require(
            linked.files.first { $0.name == "T.swift" }?.symbols.first {
                $0.name == "T" && $0.attributes["declaration_kind"] == "struct"
            }
        )
        #expect(
            (t.references ?? []).count >= 1,
            """
            Same-file property type `T` should produce used-by on struct T even when \
            another file has `extension T` (v0 root ambiguity currently drops the name)
            """
        )
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
