import SwiftLSP

extension CodeRange
{
    init(_ lspRange: LSPRange)
    {
        self.init(start: CodePosition(lspRange.start),
                  end: CodePosition(lspRange.end))
    }
}

extension CodePosition
{
    init(_ lspPosition: LSPPosition)
    {
        self.init(line: lspPosition.line, character: lspPosition.character)
    }
}
