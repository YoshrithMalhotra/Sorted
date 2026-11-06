import Foundation

/// Guesses the aisle for a shopping item typed by hand. Items from the AI
/// parser already come with a category.
public enum AisleClassifier {
    public static let other = "Other"

    static let aisles: [(String, [String])] = [
        ("Produce", ["apple", "banana", "onion", "potato", "tomato", "lettuce", "spinach", "carrot", "lemon", "lime", "garlic", "ginger", "avocado", "fruit", "vegetable", "berries", "grape", "orange", "cucumber", "pepper", "coriander", "cilantro", "herb"]),
        ("Dairy", ["milk", "cheese", "yogurt", "yoghurt", "butter", "cream", "egg", "paneer", "curd", "ghee"]),
        ("Bakery", ["bread", "bagel", "bun", "croissant", "tortilla", "roll", "cake"]),
        ("Meat & Fish", ["chicken", "beef", "pork", "fish", "salmon", "tuna", "shrimp", "prawn", "mutton", "lamb", "turkey", "bacon", "sausage"]),
        ("Pantry", ["rice", "pasta", "flour", "sugar", "salt", "oil", "cereal", "oats", "beans", "lentil", "dal", "sauce", "spice", "coffee", "tea", "honey", "jam", "peanut", "nuts", "noodle"]),
        ("Frozen", ["frozen", "ice cream", "peas"]),
        ("Drinks", ["juice", "soda", "water", "beer", "wine", "cola"]),
        ("Household", ["soap", "detergent", "paper towel", "toilet paper", "tissue", "trash bag", "garbage bag", "sponge", "bleach", "cleaner", "foil", "battery", "batteries", "bulb"]),
        ("Personal Care", ["shampoo", "conditioner", "toothpaste", "toothbrush", "deodorant", "razor", "lotion", "sunscreen"]),
        ("Pharmacy", ["vitamin", "paracetamol", "ibuprofen", "aspirin", "medicine", "bandage", "tablet", "syrup"]),
    ]

    public static func category(for name: String) -> String {
        let lowered = name.lowercased()
        // Check longer keywords first, so "dish soap" isn't caught by a shorter word.
        let matches = aisles.flatMap { aisle, keywords in keywords.map { (aisle, $0) } }
            .sorted { $0.1.count > $1.1.count }
        return matches.first { lowered.contains($0.1) }?.0 ?? other
    }
}
