import SwiftUI
import YujiCore

struct AccountPickerView: View {
    let accounts: [Account]
    @Binding var selected: EntityID?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(accounts) { acc in
                Button {
                    selected = acc.id; dismiss()
                } label: {
                    HStack {
                        Text(acc.name).foregroundColor(.primary)
                        Spacer()
                        if selected == acc.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
            .navigationTitle("选择账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

struct DatePickerSheet: View {
    @Binding var date: Day
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = Date()
    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("发生日期", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                Spacer()
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        date = Day(from: pickerDate); onChange(); dismiss()
                    }.bold()
                }
            }
            .onAppear { pickerDate = date.date() }
        }.modifier(CleanSheetSurface())
    }
}
