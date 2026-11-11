package io.systemlens.supermarket.inventory.adapter.out.persistence.jpa;

import io.systemlens.supermarket.inventory.application.port.out.ProductPort;
import io.systemlens.supermarket.inventory.domain.Product;
import org.springframework.stereotype.Component;
import java.util.List;
import java.util.Optional;

@Component
class ProductPersistenceAdapter implements ProductPort {
    private final SpringDataProductRepository repository;
    ProductPersistenceAdapter(SpringDataProductRepository repository) { this.repository=repository; }
    public Optional<Product> findById(String id) { return repository.findById(id).map(ProductEntity::toDomain); }
    public Product save(Product product) {
        ProductEntity entity = repository.findById(product.id()).orElseGet(() -> ProductEntity.from(product));
        entity.update(product); return repository.save(entity).toDomain();
    }
    public long count() { return repository.count(); }
    public void saveAll(List<Product> products) { repository.saveAll(products.stream().map(ProductEntity::from).toList()); }
}
