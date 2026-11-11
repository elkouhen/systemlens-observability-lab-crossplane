package io.systemlens.supermarket.inventory.domain;

/** Quantité strictement positive utilisée par les opérations de stock. */
public record Quantity(int value) {
    public Quantity {
        if (value <= 0) {
            throw new IllegalArgumentException("La quantite doit etre strictement positive.");
        }
    }

    public static Quantity of(int value) {
        return new Quantity(value);
    }
}
