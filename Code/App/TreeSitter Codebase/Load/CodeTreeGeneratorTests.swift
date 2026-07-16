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
    
    /// Nested callee inside an outer call’s trailing closure must be projected
    /// under the outer `call_expression` (opensChildren), not dropped as a leaf.
    @Test func testSwiftNestedCallInsideTrailingClosure() throws {
        let code = """
        func outer() {
            container { child() }
        }
        """
        
        let tree = try CodeTreeGenerator.generateTree(from: code, language: .swift)
        
        let expected = TreeSitterCodeSymbol(
            role: .declaration,
            kind: "function_declaration",
            name: "outer",
            children: [
                TreeSitterCodeSymbol(
                    role: .reference,
                    kind: "call_expression",
                    name: "container",
                    children: [
                        TreeSitterCodeSymbol(
                            role: .reference,
                            kind: "call_expression",
                            name: "child"
                        ),
                    ]
                ),
            ]
        )
        
        #expect(tree.count == 1)
        #expect(tree[0].isStructurallyEqual(to: expected))
    }
}
