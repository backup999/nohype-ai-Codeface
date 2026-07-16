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
    
    // MARK: - Duplicate root names must not erase a real use
    
    /// Two top-level `foo`s make the root index mark `foo` **ambiguous and unbound**.
    /// Then `bar() { foo() }` in the same file as one `foo` gets **no** used-by at all —
    /// a miss caused only by the other file also declaring `foo`, not by a missing decl.
    @Test func testDuplicateRootNameStillLinksSameFileUse() throws {
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
        
        let bFoo = try #require(
            linked.files.first { $0.name == "B.swift" }?.symbols.first { $0.name == "foo" }
        )
        #expect(
            (bFoo.references ?? []).count >= 1,
            """
            Same-file call `bar() { foo() }` should still produce used-by on B.swift’s foo \
            even when A.swift also declares foo (root “ambiguous → never bind” drops the name)
            """
        )
    }
    
    // MARK: - Same-folder cross-file preference (folder scopes)
    
    /// Folder scopes register each subtree: a name unique under `A/` still resolves
    /// for cross-file uses in `A/` when another folder also declares the same name
    /// (outer/root scope marks it ambiguous; closer folder scope still binds).
    @Test func testSameFolderCrossFileUseDespiteDuplicateElsewhere() throws {
        let fooCode = """
        func foo() {}
        """
        let barCode = """
        func bar() { foo() }
        """
        let otherFooCode = """
        func foo() {}
        """
        
        let forest = TreeSitterFolder(
            name: "Demo",
            subfolders: [
                TreeSitterFolder(
                    name: "A",
                    files: [
                        TreeSitterFile(
                            name: "Foo.swift",
                            code: fooCode,
                            nodes: try CodeTreeGenerator.generateTree(from: fooCode, language: .swift)
                        ),
                        TreeSitterFile(
                            name: "Bar.swift",
                            code: barCode,
                            nodes: try CodeTreeGenerator.generateTree(from: barCode, language: .swift)
                        ),
                    ]
                ),
                TreeSitterFolder(
                    name: "B",
                    files: [
                        TreeSitterFile(
                            name: "OtherFoo.swift",
                            code: otherFooCode,
                            nodes: try CodeTreeGenerator.generateTree(
                                from: otherFooCode,
                                language: .swift
                            )
                        ),
                    ]
                ),
            ]
        )
        let linked = forest.withLinkedReferences()
        
        let aFoo = try #require(
            linked.subfolders
                .first { $0.name == "A" }?
                .files.first { $0.name == "Foo.swift" }?
                .symbols.first { $0.name == "foo" }
        )
        #expect(
            (aFoo.references ?? []).count >= 1,
            """
            Cross-file call in A/Bar.swift → A/Foo.swift’s foo should still produce used-by \
            even when B/OtherFoo.swift also declares foo (folder scope for A uniquely binds foo)
            """
        )
        #expect(aFoo.references?.first?.filePathRelativeToRoot == "A/Bar.swift")
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
    
    // MARK: - Depend on extension via a member it declares
    
    /// Type A extended by extension B; symbol C (outside A and B) uses a function
    /// declared in B → used-by on that function (and thereby a dep onto B).
    /// That path must **not** require A, and must **not** invent a reference to A
    /// (A may be absent from the analyzed codebase entirely).
    @Test func testExternalUseOfExtensionMember() throws {
        // A is intentionally absent — only extension B and external caller C.
        let code = """
        extension A {
            func foo() {}
        }
        func c() {
            foo()
        }
        """
        
        let symbols = try CodeTreeGenerator.generateTree(from: code, language: .swift)
        let file = TreeSitterFile(name: "Demo.swift", code: code, nodes: symbols)
        let linked = TreeSitterFolder(name: "Demo", files: [file]).withLinkedReferences()
        
        let extB = try #require(
            linked.files[0].symbols.first {
                $0.name == "A" && $0.attributes["declaration_kind"] == "extension"
            }
        )
        let foo = try #require(extB.children.first { $0.name == "foo" && $0.role == .declaration })
        let c = try #require(linked.files[0].symbols.first { $0.name == "c" && $0.role == .declaration })
        
        // No primary type A in this forest — only the extension named A.
        #expect(linked.files[0].symbols.filter { $0.name == "A" }.count == 1)
        #expect(extB.attributes["declaration_kind"] == "extension")
        
        #expect(
            (foo.references ?? []).count >= 1,
            """
            External caller `c` uses `foo` declared in extension B → used-by on foo \
            (and thereby a dependency onto B). A need not be present.
            """
        )
        // Mechanism is used-by on the member in B, not a synthetic used-by on type A.
        #expect((extB.references ?? []).isEmpty)
        // Sanity: C itself is not the resolution target of the call.
        #expect((c.references ?? []).isEmpty)
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

    // MARK: - Nested call inside outer call trailing closure (SwiftUI composition)
    
    /// Real-world: `CodebaseAnalysisView.body` composes sibling views as
    /// nested constructor calls inside another call’s trailing closure:
    /// ```
    /// NavigationSplitView { CodebaseNavigatorView(...) }
    /// detail: { CodebaseCentralView(...) }
    /// .inspector { CodebaseInspectorView(...) }
    /// ```
    /// Those nested type initializers must still produce used-by edges onto the
    /// sibling types (and thereby folder deps onto Navigator / Central / Inspector).
    ///
    /// Suspected gap: `call_expression` is a reference **leaf** in the code tree,
    /// so callees nested in arguments / trailing closures of an outer call are
    /// never projected as references.
    @Test func testNestedCallInsideTrailingClosureLinksCrossFile() throws {
        // Minimal SwiftUI-style composition: outer container call + nested child init.
        let rootCode = """
        struct RootView {
            var body: some View {
                Container {
                    ChildView()
                }
            }
        }
        """
        let childCode = """
        struct ChildView {}
        """
        
        let forest = TreeSitterFolder(
            name: "AnalysisView",
            files: [
                TreeSitterFile(
                    name: "RootView.swift",
                    code: rootCode,
                    nodes: try CodeTreeGenerator.generateTree(from: rootCode, language: .swift)
                ),
            ],
            subfolders: [
                TreeSitterFolder(
                    name: "Child",
                    files: [
                        TreeSitterFile(
                            name: "ChildView.swift",
                            code: childCode,
                            nodes: try CodeTreeGenerator.generateTree(
                                from: childCode,
                                language: .swift
                            )
                        ),
                    ]
                ),
            ]
        )
        let linked = forest.withLinkedReferences()
        
        // Control: the nested init must appear as a reference in RootView’s tree
        // (if this fails, the linker never sees the use).
        let rootRefs = linked.files
            .first { $0.name == "RootView.swift" }?
            .symbols
            .flatMap { Self.collectReferences(in: $0) } ?? []
        #expect(
            rootRefs.contains("ChildView"),
            """
            Nested constructor `ChildView()` inside `Container { … }` trailing closure \
            must be projected as a call_expression reference; got refs \(rootRefs)
            """
        )
        
        let child = try #require(
            linked.subfolders
                .first { $0.name == "Child" }?
                .files.first { $0.name == "ChildView.swift" }?
                .symbols.first { $0.name == "ChildView" && $0.role == .declaration }
        )
        #expect(
            (child.references ?? []).contains { $0.filePathRelativeToRoot == "RootView.swift" },
            """
            RootView’s nested `ChildView()` use should produce used-by on ChildView \
            (CodebaseAnalysisView → sibling view folders). Got \
            \(child.references?.map(\.filePathRelativeToRoot) ?? [])
            """
        )
    }
    
    // MARK: - Subscript base must not link as a free call to a same-named property
    
    /// Real-world: `CodeRange.getCode(fromLines lines:)` → `lines[...].joined(...)`.
    /// Tree-sitter emits a `call_expression` named `lines` for the subscript;
    /// exact-name lookup then attaches used-by to an unrelated property `lines`
    /// elsewhere (CodeFileArtifact.lines) → false Basic Types → Architecture.
    ///
    /// Fixture:
    /// ```text
    /// Range.swift  ← func getCode(fromLines lines:) { lines[0] }
    /// File.swift   ← class File { let lines: [String] }
    /// ```
    @Test func testSubscriptBaseDoesNotLinkToUnrelatedProperty() throws {
        let rangeCode = """
        func getCode(fromLines lines: [String]) -> String {
            lines[0]
        }
        """
        let fileCode = """
        class File {
            let lines: [String]
        }
        """
        
        let forest = TreeSitterFolder(
            name: "App",
            files: [
                TreeSitterFile(
                    name: "Range.swift",
                    code: rangeCode,
                    nodes: try CodeTreeGenerator.generateTree(from: rangeCode, language: .swift)
                ),
                TreeSitterFile(
                    name: "File.swift",
                    code: fileCode,
                    nodes: try CodeTreeGenerator.generateTree(from: fileCode, language: .swift)
                ),
            ]
        )
        let linked = forest.withLinkedReferences()
        
        // Control: the subscript must appear as a call_expression named `lines`
        // (if this fails, the false positive mechanism has changed).
        let rangeRefs = linked.files
            .first { $0.name == "Range.swift" }?
            .symbols
            .flatMap { Self.collectReferences(in: $0) } ?? []
        #expect(
            rangeRefs.contains("lines"),
            """
            Subscript `lines[...]` is currently projected as call_expression named lines; \
            got refs \(rangeRefs)
            """
        )
        
        let fileType = try #require(
            linked.files.first { $0.name == "File.swift" }?.symbols.first {
                $0.name == "File" && $0.role == .declaration
            }
        )
        let linesProp = try #require(
            fileType.children.first { $0.name == "lines" && $0.role == .declaration }
        )
        #expect(
            (linesProp.references ?? []).isEmpty,
            """
            Parameter subscript `lines[...]` must not produce used-by on File.lines \
            (would create false dependency onto File’s file/folder). Got \
            \(linesProp.references?.map(\.filePathRelativeToRoot) ?? [])
            """
        )
    }
    
    // MARK: - Member / qualified call names must match the method decl
    
    /// Real-world: `TreeSitterReferenceLinkerTests` → `TreeSitterReferenceLinker`
    /// via `forest.withLinkedReferences()` and `TreeSitterReferenceLinker.link`.
    /// Member/static call refs must use the method base name (not the full
    /// navigation path) so exact-name lookup hits the declaration.
    @Test func testQualifiedCallResolvesToMethodName() throws {
        let implCode = """
        enum Linker {
            static func link(_ x: Int) -> Int { x }
        }
        extension Host {
            func withLinkedReferences() {
                Linker.link(0)
            }
        }
        """
        let clientCode = """
        func client(_ host: Host) {
            host.withLinkedReferences()
        }
        """
        
        let forest = TreeSitterFolder(
            name: "Link",
            files: [
                TreeSitterFile(
                    name: "Impl.swift",
                    code: implCode,
                    nodes: try CodeTreeGenerator.generateTree(from: implCode, language: .swift)
                ),
                TreeSitterFile(
                    name: "Client.swift",
                    code: clientCode,
                    nodes: try CodeTreeGenerator.generateTree(from: clientCode, language: .swift)
                ),
            ]
        )
        let linked = forest.withLinkedReferences()
        let impl = try #require(linked.files.first { $0.name == "Impl.swift" })
        
        // Surface the name mismatch the linker sees (not just empty used-by).
        let clientRefs = linked.files
            .first { $0.name == "Client.swift" }?
            .symbols
            .flatMap { Self.collectReferences(in: $0) } ?? []
        let withLinkedCall = clientRefs.first { $0.contains("withLinkedReferences") }
        #expect(
            withLinkedCall == "withLinkedReferences",
            """
            Call ref name should be the method base `withLinkedReferences` for exact-name \
            lookup; got \(withLinkedCall ?? "nil")
            """
        )
        
        let hostExt = try #require(
            impl.symbols.first {
                $0.name == "Host" && $0.attributes["declaration_kind"] == "extension"
            }
        )
        let withLinked = try #require(
            hostExt.children.first { $0.name == "withLinkedReferences" && $0.role == .declaration }
        )
        #expect(
            (withLinked.references ?? []).contains { $0.filePathRelativeToRoot == "Client.swift" },
            "Client’s host.withLinkedReferences() should produce used-by on the method decl"
        )
        
        let linker = try #require(impl.symbols.first { $0.name == "Linker" && $0.role == .declaration })
        let link = try #require(
            linker.children.first { $0.name == "link" && $0.role == .declaration }
        )
        #expect(
            (link.references ?? []).contains { $0.filePathRelativeToRoot == "Impl.swift" },
            "Linker.link(0) inside withLinkedReferences should produce used-by on static link"
        )
    }
    
    /// Reference names under a symbol tree (call / type / etc.).
    private static func collectReferences(in symbol: TreeSitterCodeSymbol) -> [String] {
        var names: [String] = []
        if symbol.role == .reference { names.append(symbol.name) }
        for child in symbol.children {
            names.append(contentsOf: collectReferences(in: child))
        }
        return names
    }
}
