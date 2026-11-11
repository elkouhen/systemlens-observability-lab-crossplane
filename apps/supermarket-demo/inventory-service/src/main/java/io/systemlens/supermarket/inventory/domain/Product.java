package io.systemlens.supermarket.inventory.domain;

/** Agrégat racine du catalogue et gardien des invariants du stock. */
public final class Product {
    private final String id;
    private final String name;
    private int stockQuantity;

    public Product(String id, String name, int stockQuantity) {
        this.id = requireText(id, "L'identifiant produit est obligatoire.");
        this.name = requireText(name, "Le nom du produit est obligatoire.");
        if (stockQuantity < 0) {
            throw new IllegalArgumentException("Le stock initial ne peut pas etre negatif.");
        }
        this.stockQuantity = stockQuantity;
    }

    public StockReservation reserve(Quantity quantity) {
        if (stockQuantity < quantity.value()) {
            throw new OutOfStockException(id, quantity.value(), stockQuantity);
        }
        stockQuantity -= quantity.value();
        return new StockReservation(id, name, quantity, stockQuantity);
    }

    public void restock(Quantity quantity) {
        stockQuantity += quantity.value();
    }

    public String id() { return id; }
    public String name() { return name; }
    public int stockQuantity() { return stockQuantity; }

    private static String requireText(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(message);
        }
        return value;
    }
}
