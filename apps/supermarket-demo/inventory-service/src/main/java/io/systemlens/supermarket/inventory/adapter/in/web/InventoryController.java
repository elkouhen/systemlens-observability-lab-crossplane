package io.systemlens.supermarket.inventory.adapter.in.web;

import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.systemlens.supermarket.inventory.application.InventoryReservationWorkflow;
import io.systemlens.supermarket.inventory.domain.OutOfStockException;
import io.systemlens.supermarket.inventory.domain.ProductNotFoundException;
import io.systemlens.supermarket.inventory.generated.api.StocksApi;
import io.systemlens.supermarket.inventory.generated.model.HealthStatus;
import io.systemlens.supermarket.inventory.generated.model.OrderPlaced;
import io.systemlens.supermarket.inventory.generated.model.ReservationResult;
import io.systemlens.supermarket.inventory.generated.model.ProductResponse;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
public class InventoryController implements StocksApi {
    private final InventoryUseCase inventory;
    private final InventoryReservationWorkflow reservationWorkflow;
    public InventoryController(InventoryUseCase inventory, InventoryReservationWorkflow reservationWorkflow) {
        this.inventory = inventory;
        this.reservationWorkflow = reservationWorkflow;
    }
    @Override
    public HealthStatus health() { return new HealthStatus("ok"); }

    @Override
    @GetMapping("/api/products/{productId}")
    public ProductResponse product(@PathVariable String productId) {
        ProductResponseDto dto = ProductResponseDto.from(inventory.findProduct(productId));
        return new ProductResponse().id(dto.id()).name(dto.name()).stockQuantity(dto.stockQuantity());
    }

    @Override
    public ReservationResult reserve(OrderPlaced order) {
        InventoryUseCase.ReservationResult result = reservationWorkflow.reserve(
            order.getOrderId().toString(), order.getProductId(), order.getQuantity(), "rest", order.getRequestedAt().toInstant());
        return new ReservationResult(result.orderId(), result.productId(), result.productName(), result.quantity(),
            result.remainingStock(), result.channel(), result.durationMs());
    }
    @ExceptionHandler(OutOfStockException.class) @ResponseStatus(HttpStatus.CONFLICT)
    Map<String,String> handleOutOfStock(OutOfStockException e) { return Map.of("error", e.getMessage()); }
    @ExceptionHandler(ProductNotFoundException.class) @ResponseStatus(HttpStatus.NOT_FOUND)
    Map<String,String> handleNotFound(ProductNotFoundException e) { return Map.of("error", e.getMessage()); }
    @ExceptionHandler(IllegalArgumentException.class) @ResponseStatus(HttpStatus.BAD_REQUEST)
    Map<String,String> handleInvalid(IllegalArgumentException e) { return Map.of("error", e.getMessage()); }
}
