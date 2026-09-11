import Foundation

/// A small, offline library available on the minimum supported iOS version.
public struct CategoryIcon: Identifiable, Sendable {
    public let id: String
    public let name: String
    public static let all: [CategoryIcon] = [
        .init(id: "fork.knife", name: "餐饮"), .init(id: "cup.and.saucer", name: "咖啡"),
        .init(id: "carrot", name: "买菜"), .init(id: "birthday.cake", name: "甜点"),
        .init(id: "house", name: "居家"), .init(id: "lightbulb", name: "水电"),
        .init(id: "bus", name: "公交"), .init(id: "car", name: "出行"),
        .init(id: "airplane", name: "旅行"), .init(id: "bag", name: "购物"),
        .init(id: "tshirt", name: "服饰"), .init(id: "desktopcomputer", name: "数码"),
        .init(id: "gamecontroller", name: "游戏"), .init(id: "film", name: "电影"),
        .init(id: "music.note", name: "音乐"), .init(id: "book", name: "学习"),
        .init(id: "cross.case", name: "健康"), .init(id: "dumbbell", name: "运动"),
        .init(id: "pawprint", name: "宠物"), .init(id: "gift", name: "礼物"),
        .init(id: "heart", name: "心意"), .init(id: "leaf", name: "生活"),
        .init(id: "briefcase", name: "工作"), .init(id: "banknote", name: "收入"),
        .init(id: "building.columns", name: "理财"), .init(id: "wrench.and.screwdriver", name: "维修"),
        .init(id: "sparkles", name: "美护"), .init(id: "square.grid.2x2", name: "其他")
    ]
}
