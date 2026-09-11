import SwiftUI
import UIKit
import YujiCore

/// A native collection view supplies long-press lifting, insertion feedback and cancellation.
/// The layout deliberately fills rows rather than UICollectionView's default horizontal columns.
struct InlineCategoryStrip: UIViewRepresentable {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    private var accent: UIColor { UIColor(Design.themeAccent(state.store.data.settings, scheme)) }
    var nodes: [CategoryNode]
    var parentStyle = false
    var tileHeight: CGFloat = 62
    var selectedID: EntityID?
    var isEditing = false
    var pageRequest = 0
    var hapticsEnabled = true
    var reduceMotion = false
    var onSelect: (CategoryNode) -> Void
    var onReorder: ([EntityID]) -> Bool
    var onDragBegan: () -> Void
    var onPageChange: (Int, Int) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = CategoryRowLayout()
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceHorizontal = false
        view.decelerationRate = .fast
        view.contentInsetAdjustmentBehavior = .never
        view.clipsToBounds = true
        view.register(InlineCategoryCell.self, forCellWithReuseIdentifier: "category")
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.accessibilityIdentifier = parentStyle ? "entry.parents" : "entry.children"
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        hold.minimumPressDuration = 0.42
        view.addGestureRecognizer(hold)
        context.coordinator.collection = view
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let previous = coordinator.owner
        coordinator.owner = self
        guard !coordinator.moving else { return }
        let changed = coordinator.nodes != nodes || previous.isEditing != isEditing || previous.selectedID != selectedID || view.tintColor != accent
        view.tintColor = accent
        coordinator.nodes = nodes
        view.contentInset.right = parentStyle && isEditing ? 44 : 0
        let layout = view.collectionViewLayout as! CategoryRowLayout
        layout.parentStyle = parentStyle
        layout.tileHeight = tileHeight
        layout.names = nodes.map(\.name)
        layout.invalidateLayout()
        if changed { view.reloadData() }
        view.layoutIfNeeded()
        let maximum = max(0, view.contentSize.width - view.bounds.width)
        if view.contentOffset.x < 0 || view.contentOffset.x > maximum {
            view.contentOffset.x = min(maximum, max(0, view.contentOffset.x))
        }
        if pageRequest != coordinator.lastPageRequest {
            coordinator.lastPageRequest = pageRequest
            let page = Int(round(view.contentOffset.x / max(1, view.bounds.width)))
            let next = (page + 1) % max(1, (nodes.count + 7) / 8)
            view.setContentOffset(CGPoint(x: CGFloat(next) * view.bounds.width, y: 0), animated: !reduceMotion && !UIAccessibility.isReduceMotionEnabled)
        } else {
            coordinator.revealSelectionIfNeeded()
            // SwiftUI may call updateUIView before assigning the collection's width.
            DispatchQueue.main.async { [weak coordinator] in coordinator?.revealSelectionIfNeeded() }
        }
    }

    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.tearDown()
        view.delegate = nil
        view.dataSource = nil
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var owner: InlineCategoryStrip
        var nodes: [CategoryNode]
        weak var collection: UICollectionView?
        var moving = false
        var lastPageRequest = 0
        var lastRevealedID: EntityID?
        var lastRevealedWidth: CGFloat = 0
        private var displayLink: CADisplayLink?
        private weak var activeGesture: UILongPressGestureRecognizer?

        init(_ owner: InlineCategoryStrip) { self.owner = owner; nodes = owner.nodes }
        deinit { displayLink?.invalidate() }

        /// A display link retains its target, so deinit alone cannot stop an interrupted drag.
        func tearDown() {
            if moving { collection?.cancelInteractiveMovement() }
            finishMovement()
            collection = nil
        }

        func revealSelectionIfNeeded() {
            guard let view = collection, !moving, view.bounds.width > 1,
                  lastRevealedID != owner.selectedID || abs(lastRevealedWidth - view.bounds.width) > 0.5,
                  let index = nodes.firstIndex(where: { $0.id == owner.selectedID }) else { return }
            view.layoutIfNeeded()
            lastRevealedID = owner.selectedID; lastRevealedWidth = view.bounds.width
            let maximum = max(0, view.contentSize.width - view.bounds.width)
            let target: CGFloat
            if owner.parentStyle, let frame = view.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame {
                target = min(maximum, max(0, frame.midX - view.bounds.width / 2))
            } else { target = CGFloat(index / 8) * view.bounds.width }
            view.setContentOffset(CGPoint(x: target, y: 0), animated: false)
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { nodes.count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "category", for: indexPath) as! InlineCategoryCell
            let node = nodes[indexPath.item]
            cell.configure(node, parent: owner.parentStyle, selected: owner.selectedID == node.id, editing: owner.isEditing, accent: owner.accent, dark: owner.scheme == .dark)
            cell.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "向前移动", actionHandler: { [weak self] _ in self?.accessibleMove(node.id, by: -1) ?? false }),
                UIAccessibilityCustomAction(name: "向后移动", actionHandler: { [weak self] _ in self?.accessibleMove(node.id, by: 1) ?? false })
            ]
            return cell
        }
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard !moving, nodes.indices.contains(indexPath.item) else { return }
            owner.onSelect(nodes[indexPath.item])
        }
        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool { nodes.count > 1 }
        func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
            guard sourceIndexPath.item != destinationIndexPath.item else { return }
            var reordered = nodes
            reordered.insert(reordered.remove(at: sourceIndexPath.item), at: destinationIndexPath.item)
            let moveSucceeded = owner.onReorder(reordered.map(\.id))
            if moveSucceeded {
                nodes = reordered
                if owner.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
            }
            // Collection view finishes its move animation before a possible disk-error rollback.
            DispatchQueue.main.async { [weak self, weak collectionView] in
                guard let self else { return }
                (collectionView?.collectionViewLayout as? CategoryRowLayout)?.names = self.nodes.map(\.name)
                collectionView?.reloadData()
            }
        }
        private func accessibleMove(_ id: EntityID, by offset: Int) -> Bool {
            guard let from = nodes.firstIndex(where: { $0.id == id }), nodes.indices.contains(from + offset) else { return false }
            var next = nodes; next.insert(next.remove(at: from), at: from + offset)
            return owner.onReorder(next.map(\.id))
        }
        @objc func longPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = collection else { return }
            switch recognizer.state {
            case .began:
                guard let index = view.indexPathForItem(at: recognizer.location(in: view)), nodes.count > 1 else { return }
                moving = view.beginInteractiveMovementForItem(at: index)
                guard moving else { return }
                activeGesture = recognizer
                if owner.hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                owner.onDragBegan()
                displayLink = CADisplayLink(target: self, selector: #selector(scrollAtEdge))
                displayLink?.add(to: .main, forMode: .common)
            case .changed:
                if moving { view.updateInteractiveMovementTargetPosition(recognizer.location(in: view)) }
            case .ended:
                if moving { view.endInteractiveMovement() }
                finishMovement()
            case .cancelled, .failed:
                if moving { view.cancelInteractiveMovement() }
                finishMovement()
            default: break
            }
        }
        private func finishMovement() {
            displayLink?.invalidate(); displayLink = nil; activeGesture = nil; moving = false
            collection?.reloadData()
        }
        @objc private func scrollAtEdge() {
            guard moving, let view = collection, let gesture = activeGesture else { return }
            let point = gesture.location(in: view)
            let relativeX = point.x - view.contentOffset.x
            let velocity: CGFloat = relativeX < 26 ? -3 : (relativeX > view.bounds.width - 26 ? 3 : 0)
            let maximum = max(0, view.contentSize.width - view.bounds.width)
            let next = min(maximum, max(0, view.contentOffset.x + velocity))
            if next != view.contentOffset.x {
                view.contentOffset.x = next
                view.updateInteractiveMovementTargetPosition(gesture.location(in: view))
            }
        }
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            guard !owner.parentStyle else { return }
            let width = max(1, scrollView.bounds.width)
            targetContentOffset.pointee.x = round(targetContentOffset.pointee.x / width) * width
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !owner.parentStyle else { return }
            let page = Int(round(scrollView.contentOffset.x / max(1, scrollView.bounds.width)))
            let count = max(1, (nodes.count + 7) / 8)
            DispatchQueue.main.async { [weak self] in self?.owner.onPageChange(page, count) }
        }
    }
}

final class CategoryRowLayout: UICollectionViewLayout {
    var parentStyle = false
    var tileHeight: CGFloat = 62
    var names: [String] = []
    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var size: CGSize = .zero

    override func prepare() {
        guard let view = collectionView else { return }
        let width = max(1, view.bounds.width)
        var x: CGFloat = 0
        attributes = names.enumerated().map { index, name in
            let item = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
            if parentStyle {
                let measured = (name as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]).width
                let itemWidth = max(52, measured + 24)
                item.frame = CGRect(x: x, y: 0, width: itemWidth, height: 44)
                x += itemWidth
            } else {
                let columnWidth = (width - 12) / 4
                let slot = index % 8
                item.frame = CGRect(x: CGFloat(index / 8) * width + CGFloat(slot % 4) * (columnWidth + 4),
                                    y: CGFloat(slot / 4) * (tileHeight + 6), width: columnWidth, height: tileHeight)
            }
            return item
        }
        size = CGSize(width: parentStyle ? x : CGFloat(max(1, (names.count + 7) / 8)) * width, height: view.bounds.height)
    }
    override var collectionViewContentSize: CGSize { size }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? { attributes.filter { $0.frame.intersects(rect) } }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? { attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { newBounds.size != collectionView?.bounds.size }
    override func targetIndexPath(forInteractivelyMovingItem previousIndexPath: IndexPath, withPosition position: CGPoint) -> IndexPath {
        attributes.min { hypot($0.center.x-position.x, $0.center.y-position.y) < hypot($1.center.x-position.x, $1.center.y-position.y) }?.indexPath ?? previousIndexPath
    }
}

private final class InlineCategoryCell: UICollectionViewCell {
    private let title = UILabel()
    private let symbol = UIImageView()
    private let underline = UIView()
    private let editMark = UIImageView(image: UIImage(systemName: "pencil.circle.fill"))
    private var parent = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        title.textAlignment = .center; title.numberOfLines = 1
        title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.8
        symbol.contentMode = .scaleAspectFit
        for view in [title, symbol, underline, editMark] { contentView.addSubview(view) }
        contentView.layer.cornerRadius = 13
        underline.layer.cornerRadius = 1.5
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ node: CategoryNode, parent: Bool, selected: Bool, editing: Bool, accent: UIColor, dark: Bool) {
        self.parent = parent
        title.text = node.name; title.font = .systemFont(ofSize: parent ? 14 : 11, weight: selected ? .semibold : .regular)
        title.textColor = selected ? accent : .secondaryLabel
        symbol.image = UIImage(systemName: CategorySymbol.name(for: node)); symbol.tintColor = selected ? accent : .label
        symbol.isHidden = parent; underline.isHidden = !parent || !selected; underline.backgroundColor = accent
        editMark.isHidden = !editing || parent; editMark.tintColor = .tertiaryLabel
        contentView.backgroundColor = parent ? .clear : selected ? accent.withAlphaComponent(dark ? 0.16 : 0.10) : editing ? .tertiarySystemFill : .clear
        accessibilityLabel = node.name
        accessibilityIdentifier = "category.\(parent ? "parent" : "child").\(node.name)"
        accessibilityTraits = selected ? [.button, .selected] : [.button]
        accessibilityHint = "轻点\(editing ? "编辑" : "选择")，长按拖动排序"
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width, height = contentView.bounds.height
        if parent { title.frame = CGRect(x: 2, y: 0, width: width-4, height: height-7) }
        else {
            symbol.frame = CGRect(x: (width-23)/2, y: 7, width: 23, height: 23)
            title.frame = CGRect(x: 1, y: height-22, width: width-2, height: 18)
        }
        underline.frame = CGRect(x: (width-16)/2, y: height-5, width: 16, height: 3)
        editMark.frame = CGRect(x: width-13, y: 1, width: 12, height: 12)
    }
}
