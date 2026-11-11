package io.systemlens.supermarket.inventory.domain;

public class OutOfStockException extends RuntimeException {
    public OutOfStockException(String productId, int requested, int available) {
        super("Rupture de stock pour %s : %d demandé(s), %d disponible(s)".formatted(productId, requested, available));
    }
}
