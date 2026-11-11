package io.systemlens.supermarket.inventory.domain;

/** Résultat métier d'une réservation réalisée par l'agrégat Product. */
public record StockReservation(String productId, String productName, Quantity quantity,
                               int remainingStock) {
    public StockReservation {
        if (remainingStock < 0) {
            throw new IllegalArgumentException("Le stock restant ne peut pas etre negatif.");
        }
    }
}
