package io.systemlens.supermarket.order;

import io.systemlens.supermarket.contract.generated.event.OrderPlaced;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Simule les commandes passées en ligne par les clients du supermarché,
 * traitées par lots de façon asynchrone via Kafka par inventory-service.
 */
@Component
public class ScheduledOrderPublisher {

    // Références du catalogue également connues d'inventory-service : deux
    // services indépendants partagent le contrat d'échange, pas leur modèle
    // de données interne.
    private static final List<String> CATALOG_PRODUCT_IDS = List.of(
            "PASTA-500G", "BREAD-WHOLE", "MILK-1L", "COFFEE-250G", "EGGS-12"
    );

    private final OrderPublicationWorkflow publicationWorkflow;

    public ScheduledOrderPublisher(OrderPublicationWorkflow publicationWorkflow) {
        this.publicationWorkflow = publicationWorkflow;
    }

    @Scheduled(cron = "${order-service.cron}")
    public void publishOnlineOrder() {
        ThreadLocalRandom random = ThreadLocalRandom.current();
        String productId = CATALOG_PRODUCT_IDS.get(random.nextInt(CATALOG_PRODUCT_IDS.size()));
        int quantity = random.nextInt(1, 6);
        OrderPlaced order = new OrderPlaced(UUID.randomUUID().toString(), productId, quantity, OffsetDateTime.now());
        publicationWorkflow.publish(order);
    }
}
