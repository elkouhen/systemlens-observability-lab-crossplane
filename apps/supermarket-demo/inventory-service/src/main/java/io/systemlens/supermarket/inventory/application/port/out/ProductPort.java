package io.systemlens.supermarket.inventory.application.port.out;

import io.systemlens.supermarket.inventory.domain.Product;
import java.util.List;
import java.util.Optional;

public interface ProductPort {
    Optional<Product> findById(String id);
    Product save(Product product);
    long count();
    void saveAll(List<Product> products);
}
