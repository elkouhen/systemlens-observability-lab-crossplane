package io.systemlens.supermarket.inventory.adapter.in.web;

import io.systemlens.supermarket.inventory.domain.Product;

/** API mapping model kept separate from the business Product aggregate. */
public record ProductResponseDto(String id, String name, int stockQuantity) {
    public static ProductResponseDto from(Product product) {
        return new ProductResponseDto(product.id(), product.name(), product.stockQuantity());
    }
}
