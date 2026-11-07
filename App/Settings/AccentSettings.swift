import LogeCore
import SwiftUI

/// The colour of the app's highlights: the primary button, progress, focus and selection.
/// Each one is light enough for the black text drawn on it and stands out on the canvas.
extension Accent {
    var color: Color {
        switch self {
        case .white: .white
        case .amber: Color(red: 0.96, green: 0.72, blue: 0.25)
        case .coral: Color(red: 1, green: 0.54, blue: 0.46)
        case .mint: Color(red: 0.37, green: 0.83, blue: 0.63)
        case .sky: Color(red: 0.42, green: 0.76, blue: 0.96)
        }
    }
}

struct AccentSettingsSection: View {
    @AppStorage(Accent.storageKey) private var accent = Accent.white

    var body: some View {
        Section {
            #if os(tvOS)
            // tvOS draws an inline picker's rows without marking the chosen one.
            ForEach(Accent.allCases) { option in
                Button { accent = option } label: {
                    HStack {
                        label(for: option)
                        Spacer()
                        if option == accent {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityAddTraits(option == accent ? .isSelected : [])
            }
            #else
            Picker("Accent color", selection: $accent) {
                ForEach(Accent.allCases) { label(for: $0).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            #endif
        }
    }

    private func label(for accent: Accent) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accent.color)
                .frame(width: Self.swatchSize, height: Self.swatchSize)
            Text(accent.name)
        }
    }

    #if os(tvOS)
    private static let swatchSize: CGFloat = 28
    #else
    private static let swatchSize: CGFloat = 14
    #endif
}
