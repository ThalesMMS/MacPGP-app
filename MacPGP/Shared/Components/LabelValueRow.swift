import SwiftUI

struct LabelValueRow: View {
    enum Orientation {
        case vertical
        case horizontal(labelWidth: CGFloat, showsColon: Bool = false, fillsAvailableWidth: Bool = false)
    }

    struct Style {
        let orientation: Orientation
        let labelFont: Font?
        let valueFont: Font?
        let valueFontDesign: Font.Design?
        let valueTextSelection: Bool

        init(
            orientation: Orientation = .vertical,
            labelFont: Font? = nil,
            valueFont: Font? = nil,
            valueFontDesign: Font.Design? = nil,
            valueTextSelection: Bool = false
        ) {
            self.orientation = orientation
            self.labelFont = labelFont
            self.valueFont = valueFont
            self.valueFontDesign = valueFontDesign
            self.valueTextSelection = valueTextSelection
        }

        static let keyDetails = Style(
            labelFont: .caption,
            valueFont: .body,
            valueFontDesign: .monospaced,
            valueTextSelection: true
        )

        static let paperKey = Style(
            orientation: .horizontal(labelWidth: 80),
            labelFont: .subheadline,
            valueFont: .subheadline,
            valueTextSelection: true
        )

        static let quickLookMetadata = Style(
            orientation: .horizontal(labelWidth: 140, showsColon: true, fillsAvailableWidth: true)
        )
    }

    private let label: Text
    private let value: String
    private let style: Style

    init(
        verbatimLabel label: String,
        value: String,
        style: Style = Style()
    ) {
        self.label = Text(verbatim: label)
        self.value = value
        self.style = style
    }

    init(
        localizedLabel label: LocalizedStringKey,
        value: String,
        style: Style = Style()
    ) {
        self.label = Text(label)
        self.value = value
        self.style = style
    }

    var body: some View {
        switch style.orientation {
        case .vertical:
            VStack(alignment: .leading, spacing: 4) {
                labelView(showsColon: false)
                valueView
            }
        case let .horizontal(labelWidth, showsColon, fillsAvailableWidth):
            HStack(alignment: .top) {
                labelView(showsColon: showsColon)
                    .frame(width: labelWidth, alignment: .leading)

                valueView

                if fillsAvailableWidth {
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func labelView(showsColon: Bool) -> some View {
        if showsColon {
            HStack(spacing: 0) {
                label
                Text(":")
            }
            .font(style.labelFont)
            .foregroundStyle(.secondary)
        } else {
            label
                .font(style.labelFont)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var valueView: some View {
        let text = Text(value)
            .font(style.valueFont)
            .fontDesign(style.valueFontDesign)
            .foregroundStyle(.primary)

        if style.valueTextSelection {
            text.textSelection(.enabled)
        } else {
            text
        }
    }
}
