package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.contract.generated.event.StockDepleted;
import io.systemlens.supermarket.inventory.application.InventoryApplicationService;
import io.systemlens.supermarket.inventory.application.port.out.*;
import io.systemlens.supermarket.inventory.domain.Product;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class ReservationServiceTest {

    private final ProductPort productRepository = mock(ProductPort.class);
    private final OrderFulfillmentPort orderFulfillmentRepository = mock(OrderFulfillmentPort.class);
    private final StockMovementPort stockMovementRepository = mock(StockMovementPort.class);
    private final StockDepletedPort stockDepletedPort = mock(StockDepletedPort.class);
    private final SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
    private final InventoryApplicationService reservationService = new InventoryApplicationService(
            productRepository, orderFulfillmentRepository, stockMovementRepository, stockDepletedPort,
            java.time.Clock.systemUTC(), meterRegistry
    );

    @Test
    void rejectsNonPositiveQuantityBeforeAccessingStorage() {
        assertThrows(IllegalArgumentException.class, () -> reservationService.reserve(
                "order-1", "PASTA-500G", 0, "rest", Instant.now()
        ));

        verifyNoInteractions(productRepository, orderFulfillmentRepository, stockMovementRepository, stockDepletedPort);
    }

    @Test
    void publishesStockDepletedWhenReservationConsumesLastUnit() throws InterruptedException {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 1);
        when(productRepository.findById("PASTA-500G")).thenReturn(Optional.of(product));

        reservationService.reserve("order-1", "PASTA-500G", 1, "rest", Instant.now());

        assertEquals(0, product.stockQuantity());
        verify(stockDepletedPort).publish(org.mockito.ArgumentMatchers.any(StockDepleted.class));
    }

    @Test
    void incrementsCompletedOrdersMetricAfterSuccessfulReservation() {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 3);
        when(productRepository.findById("PASTA-500G")).thenReturn(Optional.of(product));

        reservationService.reserve("order-1", "PASTA-500G", 1, "kafka", Instant.now());

        assertEquals(1.0, meterRegistry.get("business.orders.completed")
                .tag("channel", "kafka").counter().count());
    }

    @Test
    void incrementsCompletedRestockMetricAfterSuccessfulRestock() {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 3);
        when(productRepository.findById("PASTA-500G")).thenReturn(Optional.of(product));

        reservationService.restock("PASTA-500G", 500);

        assertEquals(1.0, meterRegistry.get("business.stock.restock.completed").counter().count());
    }

    @Test
    void doesNotIncrementCompletedOrdersMetricWhenPersistenceFails() {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 3);
        when(productRepository.findById("PASTA-500G")).thenReturn(Optional.of(product));
        doThrow(new IllegalStateException("postgres indisponible")).when(stockMovementRepository)
                .save(org.mockito.ArgumentMatchers.anyString(), org.mockito.ArgumentMatchers.anyString(),
                        org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyString(),
                        org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any());

        assertThrows(IllegalStateException.class, () -> reservationService.reserve(
                "order-1", "PASTA-500G", 1, "rest", Instant.now()));

        assertEquals(0, meterRegistry.getMeters().stream()
                .filter(meter -> meter.getId().getName().equals("business.orders.completed"))
                .count());
    }
}
