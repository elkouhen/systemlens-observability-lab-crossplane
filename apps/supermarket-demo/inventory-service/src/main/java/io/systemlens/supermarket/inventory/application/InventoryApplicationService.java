package io.systemlens.supermarket.inventory.application;

import io.systemlens.supermarket.contract.generated.event.StockDepleted;
import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.systemlens.supermarket.inventory.application.port.out.OrderFulfillmentPort;
import io.systemlens.supermarket.inventory.application.port.out.ProductPort;
import io.systemlens.supermarket.inventory.application.port.out.StockDepletedPort;
import io.systemlens.supermarket.inventory.application.port.out.StockMovementPort;
import io.systemlens.supermarket.inventory.domain.Product;
import io.systemlens.supermarket.inventory.domain.ProductNotFoundException;
import io.systemlens.supermarket.inventory.domain.Quantity;
import io.systemlens.supermarket.inventory.domain.StockReservation;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Tags;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.Clock;
import java.time.ZoneOffset;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class InventoryApplicationService implements InventoryUseCase {
    private static final Logger LOGGER = LoggerFactory.getLogger(InventoryApplicationService.class);
    private final ProductPort products;
    private final OrderFulfillmentPort fulfillments;
    private final StockMovementPort movements;
    private final StockDepletedPort stockDepleted;
    private final Clock clock;
    private final MeterRegistry meterRegistry;
    private final Counter restocksCompleted;
    private final ConcurrentHashMap<String, AtomicInteger> stockGauges = new ConcurrentHashMap<>();

    @Autowired
    public InventoryApplicationService(ProductPort products, OrderFulfillmentPort fulfillments,
                                       StockMovementPort movements, StockDepletedPort stockDepleted,
                                       MeterRegistry meterRegistry) {
        this(products, fulfillments, movements, stockDepleted, Clock.systemUTC(), meterRegistry);
    }

    public InventoryApplicationService(ProductPort products, OrderFulfillmentPort fulfillments,
                                       StockMovementPort movements, StockDepletedPort stockDepleted,
                                       Clock clock) {
        this(products, fulfillments, movements, stockDepleted, clock, new SimpleMeterRegistry());
    }

    public InventoryApplicationService(ProductPort products, OrderFulfillmentPort fulfillments,
                                       StockMovementPort movements, StockDepletedPort stockDepleted,
                                       Clock clock, MeterRegistry meterRegistry) {
        this.products = products;
        this.fulfillments = fulfillments;
        this.movements = movements;
        this.stockDepleted = stockDepleted;
        this.clock = clock;
        this.meterRegistry = meterRegistry;
        this.restocksCompleted = Counter.builder("business.stock.restock.completed").description("Réassorts terminés").register(meterRegistry);
    }

    @Override
    public Product findProduct(String productId) {
        return products.findById(productId).orElseThrow(() -> new ProductNotFoundException(productId));
    }

    @Override
    @Transactional
    public ReservationResult reserve(String orderId, String productId, int quantity, String channel,
                                     Instant requestedAt) {
        long startedAt = System.nanoTime();
        if (orderId == null || orderId.isBlank() || productId == null || productId.isBlank()
                || channel == null || channel.isBlank() || requestedAt == null) {
            LOGGER.warn("Reservation refusee: orderId={}, productId={}, quantity={}, reason=invalid_quantity", orderId, productId, quantity);
            throw new IllegalArgumentException("Les donnees de reservation sont invalides.");
        }
        Quantity requestedQuantity = Quantity.of(quantity);
        Product product = products.findById(productId).orElseThrow(() -> {
            LOGGER.warn("Reservation refusee: orderId={}, productId={}, quantity={}, reason=product_not_found", orderId, productId, quantity);
            return new ProductNotFoundException(productId);
        });
        StockReservation reservation = product.reserve(requestedQuantity);
        products.save(product);
        int remainingStock = reservation.remainingStock();
        updateStockGauge(product, remainingStock);
        Instant createdAt = clock.instant();
        fulfillments.save(orderId, productId, reservation.productName(), reservation.quantity().value(), remainingStock, channel, requestedAt, createdAt);
        try {
            movements.save(orderId, productId, reservation.quantity().value(), channel, requestedAt, createdAt);
        } catch (RuntimeException exception) {
            fulfillments.deleteById(orderId);
            throw exception;
        }
        if ("kafka".equalsIgnoreCase(channel)) {
            meterRegistry.counter("business.orders.completed", "channel", "kafka").increment();
        } else {
            meterRegistry.counter("business.orders.completed", "channel", "rest").increment();
        }
        LOGGER.atInfo()
                .addKeyValue("event.action", "product_sale_completed")
                .addKeyValue("order.id", orderId)
                .addKeyValue("product.id", reservation.productId())
                .addKeyValue("product.name", reservation.productName())
                .addKeyValue("business.units_sold", reservation.quantity().value())
                .addKeyValue("sales.channel", channel)
                .log("Reservation effectuee: orderId={}, productId={}, quantity={}, remainingStock={}, channel={}",
                        orderId, productId, quantity, remainingStock, channel);
        if (remainingStock == 0) {
            stockDepleted.publish(new StockDepleted(productId, createdAt.atOffset(ZoneOffset.UTC)));
            LOGGER.info("Stock epuise: productId={}", productId);
        }
        return new ReservationResult(orderId, reservation.productId(), reservation.productName(),
                reservation.quantity().value(), remainingStock, channel,
                (System.nanoTime() - startedAt) / 1_000_000L);
    }

    @Override
    @Transactional
    public void restock(String productId, int quantity) {
        Product product = products.findById(productId).orElseThrow(() -> new ProductNotFoundException(productId));
        product.restock(Quantity.of(quantity));
        products.save(product);
        updateStockGauge(product, product.stockQuantity());
        restocksCompleted.increment();
        LOGGER.info("Reassort effectue: productId={}, quantity={}, stockQuantity={}", productId, quantity, product.stockQuantity());
    }

    private void updateStockGauge(Product product, int stockQuantity) {
        AtomicInteger value = stockGauges.computeIfAbsent(product.id(), id ->
                meterRegistry.gauge("business.stock.quantity",
                        Tags.of("product_id", product.id(), "product_name", product.name()),
                        new AtomicInteger(stockQuantity)));
        value.set(stockQuantity);
    }
}
