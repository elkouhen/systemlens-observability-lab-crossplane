package io.systemlens.supermarket.inventory.adapter.out.persistence.jpa;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import java.util.Optional;

interface SpringDataProductRepository extends JpaRepository<ProductEntity, String> {
    @Override @Lock(LockModeType.PESSIMISTIC_WRITE) Optional<ProductEntity> findById(String id);
}
