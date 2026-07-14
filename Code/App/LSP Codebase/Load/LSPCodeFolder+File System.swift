import FoundationToolz
import Foundation
import SwiftyToolz

extension LSPCodeFolder
{
    convenience init?(_ folderURL: URL, codeFileEndings: [String]) throws
    {
        let fileManager = FileManager.default
        
        let urls = fileManager.items(inDirectory: folderURL, recursive: false)
        
        var files = [LSPCodeFile]()
        var subfolders = [LSPCodeFolder]()
        
        for url in urls
        {
            if url.isDirectory
            {
                if let subfolder = try LSPCodeFolder(url, codeFileEndings: codeFileEndings)
                {
                    subfolders += subfolder
                }
            }
            else if codeFileEndings.contains(url.pathExtension)
            {
                files += try LSPCodeFile(url)
            }
        }
        
        if files.count + subfolders.count == 0 { return nil }
        
        self.init(name: folderURL.lastPathComponent,
                  files: files,
                  subfolders: subfolders)
    }
    
    // TODO: make throwing instead of using optional try inside
    func printSize()
    {
        if let encoded = try? encode()
        {
            log(name + " size: \(Double(encoded.count) / 1000_000) MB")
        }
    }
}

private extension LSPCodeFile
{
    convenience init(_ file: URL) throws
    {
        self.init(name: file.lastPathComponent,
                  code: try String(contentsOf: file, encoding: .utf8))
    }
}
