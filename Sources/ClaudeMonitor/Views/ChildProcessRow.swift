import SwiftUI

struct ChildProcessRow: View {
    let process: ChildProcess

    var body: some View {
        HStack(spacing: 6) {
            // Visual thread connector — indented to align under parent accent strip
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color(white: 0.5).opacity(0.25))
                .frame(width: 1, height: 14)
                .padding(.leading, 6)

            Image(systemName: "cpu")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.quaternary)

            Text(process.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text("PID \(process.pid)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 3)
        .padding(.trailing, 12)
    }
}
