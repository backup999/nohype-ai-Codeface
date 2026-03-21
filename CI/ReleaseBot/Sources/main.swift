import Foundation

try changeDirectory(to: "/Users/seb/Desktop/Repos/nohype-ai/apps/Codeface")

let codefaceScheme = XcodeSchemeLocation(projectFolderPath: "XcodeProject",
                                         projectName: "Codeface",
                                         name: "Codeface")

try uploadBuild(of: codefaceScheme, withCredentials: .retrieve())
