import Testing
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
        
        #expect(
            tree == [
                CodeNode(
                    role: .declaration,
                    kind: "class_declaration",
                    name: "Foo",
                    attributes: ["declaration_kind": "struct"],
                    children: [
                        CodeNode(
                            role: .reference,
                            kind: "inheritance_specifier",
                            name: "Bar"
                        ),
                        CodeNode(
                            role: .declaration,
                            kind: "property_declaration",
                            name: "x",
                            children: [
                                CodeNode(
                                    role: .reference,
                                    kind: "user_type",
                                    name: "Qux"
                                ),
                            ]
                        ),
                        CodeNode(
                            role: .declaration,
                            kind: "function_declaration",
                            name: "baz",
                            children: [
                                CodeNode(
                                    role: .reference,
                                    kind: "user_type",
                                    name: "Wom"
                                ),
                                CodeNode(
                                    role: .reference,
                                    kind: "call_expression",
                                    name: "qux"
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )
    }
    
    @Test func testPython() throws {
        let code = """
        class Foo(Bar):
            def baz(self, y: Wom) -> Qux:
                qux()
        """
        
        let tree = try CodeTreeGenerator.generateTree(from: code,
                                                      language: .python)
        
        #expect(
            tree == [
                CodeNode(
                    role: .declaration,
                    kind: "class_definition",
                    name: "Foo",
                    children: [
                        CodeNode(
                            role: .reference,
                            kind: "identifier",
                            name: "Bar"
                        ),
                        CodeNode(
                            role: .declaration,
                            kind: "function_definition",
                            name: "baz",
                            children: [
                                CodeNode(
                                    role: .reference,
                                    kind: "type",
                                    name: "Wom"
                                ),
                                CodeNode(
                                    role: .reference,
                                    kind: "type",
                                    name: "Qux"
                                ),
                                CodeNode(
                                    role: .reference,
                                    kind: "call",
                                    name: "qux"
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )
    }
}
