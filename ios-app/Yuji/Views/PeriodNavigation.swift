import SwiftUI
import UIKit
import YujiCore

/// Complete, shared time header: period modes, adjacent periods, and direct date selection.
struct PeriodNavigation: View {
    private enum Mode: String, CaseIterable { case month = "月", year = "年", all = "全部", range = "范围" }
    private struct PickerRequest: Identifiable {
        let id = UUID()
        let initial: BrowsingPeriod
        var selectingRange = false
    }

    @EnvironmentObject private var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @State private var picker: PickerRequest?
    let prefix: String

    private var period: BrowsingPeriod { state.browsingPeriod }
    private var canStep: Bool { period.month(today: state.today) != nil || period.year(today: state.today) != nil }
    private var mode: Mode {
        if picker?.selectingRange == true { return .range }
        switch period {
        case .currentMonth, .month: return .month
        case .currentYear, .year: return .year
        case .all: return .all
        case .custom: return .range
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Picker("查看周期", selection: Binding(get: { mode }, set: selectMode)) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("\(prefix).periodMode")
            HStack(spacing: 8) {
                if canStep { stepButton(-1) }
                Spacer(minLength: 0)
                dateButton
                Spacer(minLength: 0)
                if canStep { stepButton(1) }
            }.frame(minHeight: 44)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
        .background(Color(.systemBackground))
        .sheet(item: $picker) { request in
            PeriodPicker(initial: request.initial, today: state.today, bounds: state.browsingBounds) {
                state.browsingPeriod = $0
            }
        }
        .onChange(of: state.activeLedger?.id) { _ in picker = nil }
    }

    private var dateButton: some View {
        Button { picker = PickerRequest(initial: period) } label: {
            Text(displayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).layoutPriority(1)
            .accessibilityLabel(period.title(today: state.today))
            .accessibilityHint("选择月份、年份或日期范围").accessibilityIdentifier("\(prefix).date")
    }

    private var displayTitle: String {
        if let month = period.month(today: state.today) {
            return typeSize.isAccessibilitySize ? String(format: "%04d.%02d", month.year, month.month)
                : "\(month.year)年\(month.month)月"
        }
        if let year = period.year(today: state.today) { return "\(year)年" }
        return period.title(today: state.today)
    }

    private func selectMode(_ mode: Mode) {
        let anchor = period.range(today: state.today)?.lowerBound ?? state.today
        switch mode {
        case .month:
            let value = MonthKey(year: anchor.year, month: period.year(today: state.today) == nil ? anchor.month : state.today.month)
            state.browsingPeriod = value == state.today.monthKey ? .currentMonth : .month(value)
        case .year:
            state.browsingPeriod = anchor.year == state.today.year ? .currentYear : .year(anchor.year)
        case .all: state.browsingPeriod = .all
        case .range:
            picker = PickerRequest(initial: .custom(period.range(today: state.today) ?? state.browsingBounds), selectingRange: true)
        }
    }

    private func stepButton(_ delta: Int) -> some View {
        let next = adjacent(delta)
        let unit = period.month(today: state.today) != nil ? "月" : "年"
        return Button {
            guard let next else { return }
            state.browsingPeriod = next
            if state.store.data.settings.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        } label: {
            Image(systemName: delta < 0 ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(Design.primary(scheme))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(next == nil)
            .accessibilityLabel((delta < 0 ? "上一" : "下一") + unit)
            .accessibilityIdentifier("\(prefix).\(delta < 0 ? "previous" : "next")")
    }

    private func adjacent(_ delta: Int) -> BrowsingPeriod? {
        if let month = period.month(today: state.today) {
            let value = delta < 0 ? month.previous : month.next
            guard (1...9999).contains(value.year) else { return nil }
            return value == state.today.monthKey ? .currentMonth : .month(value)
        }
        if let year = period.year(today: state.today) {
            let value = year + delta
            guard (1...9999).contains(value) else { return nil }
            return value == state.today.year ? .currentYear : .year(value)
        }
        return nil
    }
}
