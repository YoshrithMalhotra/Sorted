import SortedKit
import SwiftData
import SwiftUI

/// Every shopping list, with how many items are left on each.
struct ListsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingList.sortOrder) private var lists: [ShoppingList]

    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(lists) { list in
                NavigationLink(value: list) {
                    LabeledContent(list.name, value: "\(list.uncheckedCount)")
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(lists[index]) }
                try? context.save()
            }
        }
        .navigationTitle("Lists")
        .navigationDestination(for: ShoppingList.self) { ShoppingListView(list: $0) }
        .toolbar {
            Button("New list", systemImage: "plus") { isNaming = true }
        }
        .alert("New List", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Add") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    context.insert(ShoppingList(name: name, sortOrder: (lists.last?.sortOrder ?? -1) + 1))
                    try? context.save()
                }
                newName = ""
            }
        }
    }
}

/// One list, grouped by aisle. Checked items sink to the bottom.
struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingList.sortOrder) private var lists: [ShoppingList]
    let list: ShoppingList

    @State private var newItem = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        let unchecked = list.items.filter { !$0.isChecked }
        let checked = list.items.filter(\.isChecked).sorted { ($0.checkedAt ?? .now) > ($1.checkedAt ?? .now) }
        let aisles = Dictionary(grouping: unchecked, by: \.category)
            .sorted { lhs, rhs in
                // "Other" goes last; the rest are alphabetical.
                (lhs.key == AisleClassifier.other ? 1 : 0, lhs.key) < (rhs.key == AisleClassifier.other ? 1 : 0, rhs.key)
            }

        List {
            Section {
                TextField("Add an item", text: $newItem)
                    .focused($isAdding)
                    .submitLabel(.done)
                    .onSubmit(add)
            }
            ForEach(aisles, id: \.key) { aisle, items in
                Section(aisle) {
                    ForEach(items.sorted { $0.createdAt < $1.createdAt }) { item in
                        ItemRow(item: item, otherLists: lists.filter { $0 != list }, save: save)
                    }
                }
            }
            if !checked.isEmpty {
                Section("Checked") {
                    ForEach(checked) { item in
                        ItemRow(item: item, otherLists: lists.filter { $0 != list }, save: save)
                    }
                }
            }
        }
        .animation(.default, value: list.items.map(\.checkedAt))
        .navigationTitle(list.name)
        .toolbar {
            Button("Clear checked") {
                withAnimation { list.clearChecked(in: context) }
                save()
            }
            .disabled(checked.isEmpty)
        }
        .overlay {
            if list.items.isEmpty {
                ContentUnavailableView("Empty list", systemImage: "cart", description: Text("Say \u{201C}add milk, eggs and dish soap\u{201D}."))
            }
        }
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        list.add(name)
        save()
        newItem = ""
        isAdding = true
    }

    private func save() {
        try? context.save()
    }
}

private struct ItemRow: View {
    let item: ShoppingItem
    var otherLists: [ShoppingList]
    var save: () -> Void

    var body: some View {
        Button {
            item.isChecked.toggle()
            save()
        } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .imageScale(.large)
                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                if let quantity = item.quantity {
                    Text(quantity).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !otherLists.isEmpty {
                Menu("Move to") {
                    ForEach(otherLists) { list in
                        Button(list.name) {
                            item.list = list
                            save()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { ListsView() }
        .modelContainer(PreviewData.container)
}
