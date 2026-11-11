package io.systemlens.supermarket.inventory.adapter.out.persistence.jpa;

import org.springframework.data.jpa.repository.JpaRepository;

interface SpringDataStockMovementRepository extends JpaRepository<StockMovementEntity, String> {}
