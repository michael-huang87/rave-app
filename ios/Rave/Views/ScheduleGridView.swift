import SwiftUI

struct ScheduleGridView: View {
    let layout: ScheduleDayLayout
    let stageOrder: [String]
    let visible: Set<String>
    let planned: Set<String>
    let selected: Set<String>
    var onTap: (ScheduleSlot) -> Void

    private let columnWidth: CGFloat = 118
    private let gutterWidth: CGFloat = 40
    private let pointsPerMinute: CGFloat = 1
    private let minimumBlockHeight: CGFloat = 34
    private let blockGap: CGFloat = 2
    private let headerHeight: CGFloat = 26

    /// Columns run in palette-assignment order, not alphabetically. The palette only validated as an
    /// adjacent pairlist, so neighbouring columns holding neighbouring palette slots is the whole
    /// guarantee. Sorting these another way silently breaks it.
    private var columns: [(stage: String, blocks: [ScheduleDayLayout.Block])] {
        layout.columns.compactMap { column in
            let blocks = column.blocks.filter { visible.contains($0.slot.id) }
            return blocks.isEmpty ? nil : (column.stage, blocks)
        }
    }

    private var gridHeight: CGFloat { CGFloat(layout.end - layout.start) * pointsPerMinute }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                header
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        gutter
                        ZStack(alignment: .topLeading) {
                            rules
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(columns, id: \.stage) { self.column($0) }
                            }
                        }
                    }
                    // The first hour label is drawn 6pt above the axis and would sit under the header.
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(RaveTheme.bg)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth, height: headerHeight)
            ForEach(columns, id: \.stage) { column in
                HStack(spacing: 4) {
                    Circle()
                        .fill(StagePalette.color(column.stage, in: stageOrder))
                        .frame(width: 8, height: 8)
                    Text(column.stage)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: columnWidth, height: headerHeight)
            }
        }
        .background(RaveTheme.bg)
    }

    private var gutter: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: gutterWidth, height: gridHeight)
            ForEach(layout.hourMarks, id: \.self) { minute in
                Text(layout.hourLabel(minute))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .offset(y: offset(minute) - 6)
            }
        }
    }

    private var rules: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: columnWidth * CGFloat(columns.count), height: gridHeight)
            ForEach(layout.hourMarks, id: \.self) { minute in
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .offset(y: offset(minute))
            }
        }
    }

    private func column(_ column: (stage: String, blocks: [ScheduleDayLayout.Block])) -> some View {
        let color = StagePalette.color(column.stage, in: stageOrder)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: columnWidth, height: gridHeight)
            ForEach(column.blocks) { block in
                self.block(block, stage: column.stage, color: color)
                    .frame(width: columnWidth - 6, height: height(block))
                    .offset(x: 3, y: offset(block.start))
            }
        }
    }

    private func block(_ block: ScheduleDayLayout.Block, stage: String, color: Color) -> some View {
        let isSeen = selected.contains(block.slot.id)
        let isPlanned = planned.contains(block.slot.id)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 4) {
                Text(block.slot.startTime ?? layout.hourLabel(block.start))
                    .font(.caption2.monospacedDigit())
                Spacer(minLength: 0)
                if isSeen {
                    Image(systemName: "checkmark").font(.caption2.weight(.black))
                }
            }
            Text(block.slot.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.55), radius: 1)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(isSeen ? 0.95 : 0.3), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isPlanned ? Color.white : color.opacity(0.85), lineWidth: isPlanned ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap(block.slot) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.slot.title), \(stage)\(isPlanned ? ", planned" : "")\(isSeen ? ", seen" : "")")
    }

    private func offset(_ minute: Int) -> CGFloat {
        CGFloat(minute - layout.start) * pointsPerMinute
    }

    private func height(_ block: ScheduleDayLayout.Block) -> CGFloat {
        max(CGFloat(block.length) * pointsPerMinute - blockGap, minimumBlockHeight)
    }
}
