CREATE TABLE IF NOT EXISTS products (
    id VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    stock_quantity INTEGER NOT NULL,
    CONSTRAINT pk_products PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS stock_movements (
    order_id VARCHAR(255) NOT NULL,
    product_id VARCHAR(255),
    quantity INTEGER NOT NULL,
    channel VARCHAR(255),
    requested_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT pk_stock_movements PRIMARY KEY (order_id)
);
