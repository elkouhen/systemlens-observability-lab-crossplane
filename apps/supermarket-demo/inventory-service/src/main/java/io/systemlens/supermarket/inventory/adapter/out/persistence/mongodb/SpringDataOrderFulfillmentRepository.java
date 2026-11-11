package io.systemlens.supermarket.inventory.adapter.out.persistence.mongodb;

import org.springframework.data.mongodb.repository.MongoRepository;

interface SpringDataOrderFulfillmentRepository extends MongoRepository<OrderFulfillmentDocument, String> {}
