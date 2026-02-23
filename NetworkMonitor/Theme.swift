import SwiftUI

struct AppTheme {
    let name: String
    let bg, bg2, border, accent, accent2, text, dim: Color
    let online, offline, warn: Color
    let graphOk, graphMid, graphBad: Color

    static let green = AppTheme(name:"green",
        bg:.hex("#0d1117"), bg2:.hex("#161b22"), border:.hex("#30a14e"),
        accent:.hex("#3fb950"), accent2:.hex("#56d364"), text:.hex("#e6edf3"), dim:.hex("#8b949e"),
        online:.hex("#3fb950"), offline:.hex("#f85149"), warn:.hex("#d29922"),
        graphOk:.hex("#3fb950"), graphMid:.hex("#d29922"), graphBad:.hex("#f85149"))

    static let amber = AppTheme(name:"amber",
        bg:.hex("#13100a"), bg2:.hex("#1e1810"), border:.hex("#d4820a"),
        accent:.hex("#e8920a"), accent2:.hex("#f5a623"), text:.hex("#f0e6d3"), dim:.hex("#9e8060"),
        online:.hex("#e8920a"), offline:.hex("#f85149"), warn:.hex("#d29922"),
        graphOk:.hex("#e8920a"), graphMid:.hex("#c0781a"), graphBad:.hex("#f85149"))

    static let blue = AppTheme(name:"blue",
        bg:.hex("#0d1117"), bg2:.hex("#0d1f2d"), border:.hex("#1f6feb"),
        accent:.hex("#388bfd"), accent2:.hex("#79c0ff"), text:.hex("#e6edf3"), dim:.hex("#8b949e"),
        online:.hex("#388bfd"), offline:.hex("#f85149"), warn:.hex("#d29922"),
        graphOk:.hex("#388bfd"), graphMid:.hex("#9ecbff"), graphBad:.hex("#f85149"))

    static let red = AppTheme(name:"red",
        bg:.hex("#130d0d"), bg2:.hex("#1e1010"), border:.hex("#b91c1c"),
        accent:.hex("#ef4444"), accent2:.hex("#f87171"), text:.hex("#f0e6e6"), dim:.hex("#9e7070"),
        online:.hex("#3fb950"), offline:.hex("#ef4444"), warn:.hex("#d29922"),
        graphOk:.hex("#3fb950"), graphMid:.hex("#d29922"), graphBad:.hex("#ef4444"))

    static func named(_ n: String) -> AppTheme {
        switch n { case "amber": return .amber; case "blue": return .blue; case "red": return .red; default: return .green }
    }
}

extension Color {
    static func hex(_ h: String) -> Color {
        var rgb: UInt64 = 0
        Scanner(string: h.trimmingCharacters(in: CharacterSet(charactersIn:"#"))).scanHexInt64(&rgb)
        return Color(red: Double((rgb>>16)&0xFF)/255, green: Double((rgb>>8)&0xFF)/255, blue: Double(rgb&0xFF)/255)
    }
}
