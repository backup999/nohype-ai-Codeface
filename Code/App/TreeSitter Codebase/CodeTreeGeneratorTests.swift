import Testing
import SwiftyToolz
@testable import Codeface

struct CodeTreeGeneratorTests {
    @Test func testSwift() throws {
        let code = """
        struct Foo: Bar {
            var x: Qux
            func baz(y: Wom) {
                qux()
            }
        }
        """
        
        let tree = try CodeTreeGenerator.generateTree(from: code,
                                                      language: .swift)
        
        let expected = TreeSitterCodeSymbol(
            role: .declaration,
            kind: "class_declaration",
            name: "Foo",
            attributes: ["declaration_kind": "struct"],
            children: [
                TreeSitterCodeSymbol(role: .reference, kind: "inheritance_specifier", name: "Bar"),
                TreeSitterCodeSymbol(
                    role: .declaration,
                    kind: "property_declaration",
                    name: "x",
                    children: [
                        TreeSitterCodeSymbol(role: .reference, kind: "user_type", name: "Qux"),
                    ]
                ),
                TreeSitterCodeSymbol(
                    role: .declaration,
                    kind: "function_declaration",
                    name: "baz",
                    children: [
                        TreeSitterCodeSymbol(role: .reference, kind: "user_type", name: "Wom"),
                        TreeSitterCodeSymbol(role: .reference, kind: "call_expression", name: "qux"),
                    ]
                ),
            ]
        )
        
        #expect(tree.count == 1)
        #expect(tree[0].isStructurallyEqual(to: expected))
        #expect(tree[0].range.start.line == 0)
    }
    
    @Test func testPython() throws {
        let code = """
        class Foo(Bar):
            def baz(self, y: Wom) -> Qux:
                qux()
        """
        
        let tree = try CodeTreeGenerator.generateTree(from: code, language: .python)
        
        let expected = TreeSitterCodeSymbol(
            role: .declaration,
            kind: "class_definition",
            name: "Foo",
            children: [
                TreeSitterCodeSymbol(role: .reference, kind: "identifier", name: "Bar"),
                TreeSitterCodeSymbol(
                    role: .declaration,
                    kind: "function_definition",
                    name: "baz",
                    children: [
                        TreeSitterCodeSymbol(role: .reference, kind: "type", name: "Wom"),
                        TreeSitterCodeSymbol(role: .reference, kind: "type", name: "Qux"),
                        TreeSitterCodeSymbol(role: .reference, kind: "call", name: "qux"),
                    ]
                ),
            ]
        )
        
        #expect(tree.count == 1)
        #expect(tree[0].isStructurallyEqual(to: expected))
    }
    
    @Test func testArchitectureFromTreeSitterForest() async throws {
        let code = """
        struct Foo {
            func bar() {}
        }
        """
        
        let file = try TreeSitterFile(
            name: "Foo.swift",
            code: code,
            nodes: CodeTreeGenerator.generateTree(from: code, language: .swift)
        )
        let forest = TreeSitterFolder(name: "Demo", files: [file])
        
        let architecture = await BackgroundActor.run {
            CodeFolderArtifact(treeSitterFolder: forest)
        }
        
        #expect(architecture.name == "Demo")
        #expect(architecture.partGraph.nodesByID.count == 1)
        
        guard let part = architecture.partGraph.values.first,
              case .file(let fileArtifact) = part.kind
        else {
            Issue.record("Expected one file part")
            return
        }
        
        #expect(fileArtifact.symbolGraph.nodesByID.count == 1)
        guard let foo = fileArtifact.symbolGraph.values.first else {
            Issue.record("Expected Foo")
            return
        }
        #expect(foo.name == "Foo")
        #expect(foo.kind == "Struct")
        #expect(foo.subsymbolGraph.nodesByID.count == 1)
        #expect(foo.subsymbolGraph.edgesByID.isEmpty)
        #expect(foo.subsymbolGraph.values.first?.name == "bar")
    }
}
