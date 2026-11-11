package io.systemlens.supermarket.inventory.domain;

public class ProductNotFoundException extends RuntimeException {
    public ProductNotFoundException(String productId) {
        super("Produit introuvable au catalogue : " + productId);
    }
}
