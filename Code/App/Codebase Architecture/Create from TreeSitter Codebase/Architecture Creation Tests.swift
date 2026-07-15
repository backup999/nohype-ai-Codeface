import Foundation
import Testing
import SwiftyToolz
@testable import Codeface

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
        CodeFolderArtifact.generateArchitecture(from: forest)
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
        CodeFolderArtifact.generateArchitecture(from: forest)
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
