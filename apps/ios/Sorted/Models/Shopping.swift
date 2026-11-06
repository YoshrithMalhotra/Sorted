import Foundation
import SortedKit
import SwiftData

/// A row of `shopping_lists`: Groceries, Pharmacy and so on.
@Model
final class ShoppingList {
    @Attribute(.unique) var id: UUID
    var householdID: UUID?
    var name: String
    var sortOrder: Int
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ShoppingItem.list)
    var items: [ShoppingItem] = []

    init(name: String, sortOrder: Int) {
        id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        updatedAt = .now
    }

    static let defaultNames = ["Groceries", "Pharmacy"]

    var uncheckedCount: Int { items.count { $0.checkedAt == nil } }

    func add(_ name: String, quantity: String? = nil, category: String? = nil) {
        let item = ShoppingItem(name: name, quantity: quantity, category: category ?? AisleClassifier.category(for: name))
        items.append(item)
        updatedAt = .now
    }

    func clearChecked(in context: ModelContext) {
        for item in items where item.checkedAt != nil {
            context.delete(item)
        }
        updatedAt = .now
    }
}

/// A row of `shopping_items`.
@Model
final class ShoppingItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var quantity: String?
    /// The aisle: Dairy, Produce and so on.
    var category: String
    var checkedAt: Date?
    var createdAt: Date
    var list: ShoppingList?

    init(name: String, quantity: String? = nil, category: String) {
        id = UUID()
        self.name = name
        self.quantity = quantity
        self.category = category
        createdAt = .now
    }

    var isChecked: Bool {
        get { checkedAt != nil }
        set { checkedAt = newValue ? .now : nil }
    }
}
