enum ToolMode: String, CaseIterable {
    case selection
    case blade

    var label: String {
        switch self {
        case .selection: "選取"
        case .blade: "剪刀"
        }
    }

    var systemImage: String {
        switch self {
        case .selection: "cursorarrow"
        case .blade: "scissors"
        }
    }
}
