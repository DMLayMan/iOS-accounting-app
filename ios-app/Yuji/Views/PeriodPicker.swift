import SwiftUI
import YujiCore

struct PeriodPicker: View {
    private enum Mode: String, CaseIterable { case month = "月", year = "年", custom = "自定", all = "全部" }
    let initial: BrowsingPeriod
    let today: Day
    let bounds: ClosedRange<Day>
    let apply: (BrowsingPeriod) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @State private var mode: Mode
    @State private var year: Int
    @State private var start: Date
    @State private var end: Date

    init(initial: BrowsingPeriod, today: Day, bounds: ClosedRange<Day>, apply: @escaping (BrowsingPeriod) -> Void) {
        self.initial = initial; self.today = today; self.bounds = bounds; self.apply = apply
        let range = initial.range(today: today) ?? bounds
        _year = State(initialValue: initial.year(today: today) ?? initial.month(today: today)?.year ?? today.year)
        _start = State(initialValue: range.lowerBound.date()); _end = State(initialValue: range.upperBound.date())
        let mode: Mode
        switch initial {
        case .currentMonth, .month: mode = .month
        case .currentYear, .year: mode = .year
        case .custom: mode = .custom
        case .all: mode = .all
        }
        _mode = State(initialValue: mode)
    }

    private var years: [Int] { Array(max(1, min(bounds.lowerBound.year - 1, year, today.year - 4))...min(9999, max(bounds.upperBound.year, year))) }
    private var selectedMonth: MonthKey? { initial.month(today: today) }
    private var validRange: Bool { Day(from: start) <= Day(from: end) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("查看方式", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("period.mode")
                    switch mode {
                    case .month: months
                    case .year: yearGrid
                    case .custom: customRange
                    case .all:
                        Text("查看当前账本的全部记录。统计仅计算截至今天的已发生收支。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("查看全部时间") { finish(.all) }.buttonStyle(SolidActionStyle())
                            .accessibilityIdentifier("period.all")
                    }
                }.padding(20)
            }
            .navigationTitle("选择时间").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.accessibilityIdentifier("period.cancel")
            } }
            .safeAreaInset(edge: .bottom) {
                if mode == .custom {
                    Button("应用日期范围") { finish(.custom(Day(from: start)...Day(from: end))) }
                        .buttonStyle(SolidActionStyle()).disabled(!validRange)
                        .accessibilityIdentifier("period.applyRange").padding(20).background(Color(.systemBackground))
                }
            }
            .onChange(of: mode) { value in if value == .all { finish(.all) } }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.65), .large])
        .presentationDragIndicator(.visible).modifier(CleanSheetSurface())
    }

    private var months: some View {
        VStack(spacing: 18) {
            HStack {
                Menu {
                    ForEach(years.reversed(), id: \.self) { value in
                        Button { year = value } label: {
                            if value == year { Label("\(String(value)) 年", systemImage: "checkmark") }
                            else { Text("\(String(value)) 年") }
                        }.accessibilityIdentifier("period.chooseYear.\(value)")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(typeSize.isAccessibilitySize ? String(year) : "\(String(year)) 年")
                            .font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("period.year")
                Spacer()
                Button("本月") { finish(.currentMonth) }.font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("period.thisMonth")
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...12, id: \.self) { month in
                    let selected = selectedMonth == MonthKey(year: year, month: month)
                    choice("\(month) 月", selected: selected, id: "period.month.\(month)") {
                        finish(.month(MonthKey(year: year, month: month)))
                    }
                }
            }
        }
    }
    private var yearGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择年份").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("本年") { finish(.currentYear) }.frame(minHeight: 44).accessibilityIdentifier("period.thisYear")
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(years.reversed(), id: \.self) { year in
                    choice(String(year), selected: initial.year(today: today) == year, id: "period.fullYear.\(year)") {
                        finish(.year(year))
                    }
                }
            }
        }
    }
    private var customRange: some View {
        VStack(alignment: .leading, spacing: 18) {
            DatePicker("开始日期", selection: $start, displayedComponents: .date).accessibilityIdentifier("period.start")
            Divider()
            DatePicker("结束日期", selection: $end, displayedComponents: .date).accessibilityIdentifier("period.end")
            Text(validRange ? "包含开始和结束当天。" : "开始日期不能晚于结束日期")
                .font(.subheadline).foregroundStyle(validRange ? Color.secondary : .red)
                .accessibilityIdentifier("period.rangeHint")
        }
    }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 2 : 4) }
    private func choice(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.body.weight(selected ? .semibold : .regular))
                if selected { Image(systemName: "checkmark").font(.caption) }
            }.frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(selected ? Design.primary(scheme) : .primary)
                .background(selected ? Design.selectedFill(scheme) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier(id).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private func finish(_ value: BrowsingPeriod) { apply(value); dismiss() }
}
