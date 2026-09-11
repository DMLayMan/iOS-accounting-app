import SwiftUI
import YujiCore

enum CategorySymbol {
    static func name(for node: CategoryNode) -> String {
        if let symbol = node.symbolName, CategoryIcon.all.contains(where: { $0.id == symbol }) { return symbol }
        return name(for: node.name)
    }

    static func name(for name: String) -> String {
        switch name {
        case "早餐", "午餐晚餐": return "fork.knife"
        case "咖啡茶饮": return "cup.and.saucer"
        case "零食": return "carrot"
        case "水果": return "leaf"
        case "外卖", "日用百货": return "bag"
        case "饮品": return "cup.and.saucer"
        case "买菜": return "basket"
        case "甜品": return "birthday.cake"
        case "火锅": return "flame"
        case "聚餐": return "person.2"
        case "夜宵": return "moon"
        case "服饰": return "tshirt"
        case "数码": return "desktopcomputer"
        case "房租水电": return "house"
        case "家居用品": return "sofa"
        case "门诊药品": return "cross.case"
        case "电影演出", "影音游戏": return "play.rectangle"
        case "游戏": return "gamecontroller"
        case "运动健身": return "heart"
        case "旅行休闲": return "suitcase"
        case "公共交通": return "tram"
        case "打车": return "car"
        case "加油停车": return "fuelpump"
        case "工资", "奖金": return "banknote"
        case "理财收益": return "chart.line.uptrend.xyaxis"
        default: return "square.grid.2x2"
        }
    }
}
