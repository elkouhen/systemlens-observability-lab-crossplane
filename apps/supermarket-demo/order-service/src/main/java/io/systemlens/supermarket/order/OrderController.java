package io.systemlens.supermarket.order;

import io.systemlens.supermarket.order.generated.api.CommandesApi;
import io.systemlens.supermarket.order.generated.model.HealthStatus;
import io.systemlens.supermarket.order.generated.model.OrderRequest;
import io.systemlens.supermarket.order.generated.model.ReservationResult;
import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.HttpClientErrorException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

/** Commandes passées en caisse : réservation de stock synchrone auprès d'inventory-service. */
@RestController
public class OrderController implements CommandesApi {

    private static final Logger LOGGER = LoggerFactory.getLogger(OrderController.class);

    private final OrderPlacementWorkflow placementWorkflow;

    public OrderController(OrderPlacementWorkflow placementWorkflow) {
        this.placementWorkflow = placementWorkflow;
    }

    @Override
    public HealthStatus health() {
        return new HealthStatus("ok");
    }

    @Override
    public ReservationResult placeOrder(OrderRequest request) {
        OrderPlaced order =
            new OrderPlaced(
                UUID.randomUUID().toString(), request.getProductId(), request.getQuantity(), OffsetDateTime.now());
        LOGGER.info("Commande recue: orderId={}, productId={}, quantity={}",
            order.getOrderId(), order.getProductId(), order.getQuantity());
        ReservationResult reservation = placementWorkflow.reserve(order);
        LOGGER.info("Commande reservee: orderId={}, productId={}, quantity={}, remainingStock={}",
            order.getOrderId(), order.getProductId(), order.getQuantity(), reservation.getRemainingStock());
        return reservation;
    }

    @Override
    public void triggerOutOfStock() {
        // Quantité garantie supérieure au stock initial : démontre la
        // propagation d'une rupture de stock d'inventory-service vers
        // order-service (scénario d'erreur contrôlé pour l'observabilité).
        OrderPlaced order =
            new OrderPlaced(
                UUID.randomUUID().toString(), "PASTA-500G", 999_999, OffsetDateTime.now());
        try {
            placementWorkflow.reserve(order);
        } catch (HttpClientErrorException exception) {
            LOGGER.warn("Rupture de stock: orderId={}, productId={}, quantity={}",
                order.getOrderId(), order.getProductId(), order.getQuantity());
            throw new OutOfStockException("Rupture de stock signalée par inventory-service : " + exception.getMessage());
        }
    }

    @ExceptionHandler(OutOfStockException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    Map<String, String> handleOutOfStock(OutOfStockException exception) {
        return Map.of("error", exception.getMessage());
    }

    static class OutOfStockException extends RuntimeException {
        OutOfStockException(String message) {
            super(message);
        }
    }
}
