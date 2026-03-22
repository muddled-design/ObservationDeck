import SwiftUI

enum SessionStatus: String, Comparable {
    case running
    case needsInput
    case idle
    case finished

    // Primary icon color
    var color: Color {
        switch self {
        case .running:    return Color(hue: 0.37, saturation: 0.75, brightness: 0.85)   // green
        case .needsInput: return Color(hue: 0.09, saturation: 0.90, brightness: 0.98)   // amber-orange
        case .idle:       return Color(hue: 0.58, saturation: 0.45, brightness: 0.80)   // soft blue
        case .finished:   return Color(white: 0.55)
        }
    }

    // Soft tinted background for the badge pill
    var glowColor: Color {
        switch self {
        case .running:    return Color(hue: 0.37, saturation: 0.70, brightness: 0.80).opacity(0.14)
        case .needsInput: return Color(hue: 0.09, saturation: 0.85, brightness: 0.95).opacity(0.14)
        case .idle:       return Color(hue: 0.58, saturation: 0.40, brightness: 0.75).opacity(0.12)
        case .finished:   return Color(white: 0.50).opacity(0.10)
        }
    }

    // Left-edge accent strip color
    var accentColor: Color {
        switch self {
        case .running:    return Color(hue: 0.37, saturation: 0.65, brightness: 0.75).opacity(0.70)
        case .needsInput: return Color(hue: 0.09, saturation: 0.80, brightness: 0.90).opacity(0.70)
        case .idle:       return Color(hue: 0.58, saturation: 0.40, brightness: 0.70).opacity(0.50)
        case .finished:   return Color(white: 0.40).opacity(0.35)
        }
    }

    var label: String {
        switch self {
        case .running:    return "Running"
        case .needsInput: return "Needs Input"
        case .idle:       return "Idle"
        case .finished:   return "Finished"
        }
    }

    var icon: String {
        switch self {
        case .running:    return "circle.fill"
        case .needsInput: return "exclamationmark.circle.fill"
        case .idle:       return "pause.circle.fill"
        case .finished:   return "checkmark.circle.fill"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .running:    return 0
        case .needsInput: return 1
        case .idle:       return 2
        case .finished:   return 3
        }
    }

    static func < (lhs: SessionStatus, rhs: SessionStatus) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
