package io.systemlens.supermarket.inventory.adapter.out.persistence.jpa;

import io.systemlens.supermarket.inventory.domain.Product;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "products")
public class ProductEntity {
    @Id private String id;
    private String name;
    private int stockQuantity;
    protected ProductEntity() {}
    private ProductEntity(String id, String name, int stockQuantity) { this.id=id; this.name=name; this.stockQuantity=stockQuantity; }
    static ProductEntity from(Product p) { return new ProductEntity(p.id(), p.name(), p.stockQuantity()); }
    Product toDomain() { return new Product(id, name, stockQuantity); }
    void update(Product p) { this.name=p.name(); this.stockQuantity=p.stockQuantity(); }
    public String getId() { return id; }
}
