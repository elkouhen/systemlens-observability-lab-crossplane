package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.inventory.domain.OutOfStockException;
import io.systemlens.supermarket.inventory.domain.Product;
import io.systemlens.supermarket.inventory.domain.Quantity;
import io.systemlens.supermarket.inventory.domain.StockReservation;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class ProductTest {

    @Test
    void reservationIsAnAggregateOperationAndReturnsItsOutcome() {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 3);

        StockReservation reservation = product.reserve(Quantity.of(2));

        assertEquals("PASTA-500G", reservation.productId());
        assertEquals(2, reservation.quantity().value());
        assertEquals(1, reservation.remainingStock());
        assertEquals(1, product.stockQuantity());
    }

    @Test
    void rejectsNonPositiveQuantitiesInTheDomain() {
        assertThrows(IllegalArgumentException.class, () -> Quantity.of(0));
        assertThrows(IllegalArgumentException.class, () -> Quantity.of(-1));
    }

    @Test
    void doesNotAllowRestockWithAnInvalidQuantity() {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 3);

        assertThrows(IllegalArgumentException.class, () -> product.restock(Quantity.of(0)));
        assertEquals(3, product.stockQuantity());
    }

    @Test
    void rejectsReservationWhenTheAggregateHasInsufficientStock() {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 1);

        assertThrows(OutOfStockException.class, () -> product.reserve(Quantity.of(2)));
        assertEquals(1, product.stockQuantity());
    }
}
