import SwiftUI
import SwiftyToolz

struct LogView: View
{
    var body: some View
    {
        VStack(alignment: .leading, spacing: 0)
        {
            List
            {
                Text("Log Messages")
                    .font(.title2)
                
                ForEach(logViewModel.filteredLogEntries)
                {
                    entry in
                    
                    Label
                    {
                        VStack(alignment: .leading)
                        {
                            Text(entry.message)
                            
                            Text(entry.context)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        LogIcon(logLevel: entry.level)
                    }
                }
            }
            .textSelection(.enabled)
            .animation(.default, value: logViewModel.minimumLogLevel)
        }
        .toolbar
        {
            ToolbarItemGroup(placement: .primaryAction)
            {
                Picker("Minimum Log Level", selection: $logViewModel.minimumLogLevel)
                {
                    ForEach(Log.Level.allCases)
                    {
                        Text($0.displayName).tag($0)
                    }
                }
                .lineLimit(1)
                .frame(minWidth: 100)
                .help("Minimum Log Level")
                
                Button {
                    logViewModel.clear()
                } label: {
                    Label("Clear Logs", systemImage: "trash")
                }
                .help("Clear Logs")
            }
        }
    }
    
    @Bindable private var logViewModel = LogViewModel.shared
}

struct LogIcon: View
{
    init(logLevel: Log.Level)
    {
        switch logLevel
        {
        case .error:
            imageName = "xmark.octagon.fill"
            color = .red
        case .warning:
            imageName = "exclamationmark.triangle.fill"
            color = .yellow
        case .info:
            imageName = "info.circle.fill"
            color = .green
        case .verbose:
            imageName = "info.circle"
            color = .secondary
        }
    }
    
    var body: some View
    {
        Image(systemName: imageName).foregroundColor(color)
    }
    
    private let imageName: String
    private let color: SwiftUI.Color
}

@MainActor
@Observable
class LogViewModel
{
    static let shared = LogViewModel()
    
    /// just a way to create the instance that allows starting the log observation on app launch
    func startObservingLog() {}
    
    private init()
    {
        // Log is an actor; registration must be awaited.
        // Pass a hop closure — never a main-actor method reference.
        Task
        {
            await Log.shared.add(observer: self) { entry in
                Task { @MainActor in
                    LogViewModel.shared.logEntries.insertSorted(entry)
                }
            }
        }
    }
    
    func clear()
    {
        logEntries.removeAll()
    }
    
    var filteredLogEntries: [Log.Entry]
    {
        logEntries.filter { $0.level >= minimumLogLevel }
    }
    
    #if DEBUG
    var minimumLogLevel = Log.Level.verbose
    #else
    var minimumLogLevel = Log.Level.info
    #endif
    
    var logEntries = [Log.Entry]()
}
