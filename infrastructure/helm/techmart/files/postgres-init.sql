CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    emoji VARCHAR(10) NOT NULL DEFAULT '📦',
    category VARCHAR(100),
    stock INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    customer_name VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255) NOT NULL,
    shipping_address TEXT NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL
);

INSERT INTO products (name, description, price, emoji, category, stock) VALUES
    ('Wireless Noise-Cancelling Headphones',
     'Premium over-ear headphones with 30-hour battery life and active noise cancellation.',
     79.99, '🎧', 'Audio', 85),
    ('Smart Watch Pro',
     'Track fitness, notifications, and more. Waterproof with 7-day battery.',
     199.99, '⌚', 'Wearables', 42),
    ('Portable Bluetooth Speaker',
     '360° surround sound, IPX7 waterproof, 20-hour playtime. Perfect for outdoors.',
     49.99, '🔊', 'Audio', 120),
    ('7-in-1 USB-C Hub',
     'Expand connectivity with HDMI 4K, 3x USB-A, SD card, and 100W PD charging.',
     39.99, '🔌', 'Accessories', 200),
    ('Mechanical Gaming Keyboard',
     'TKL layout, Cherry MX Red switches, RGB per-key lighting, aluminum frame.',
     129.99, '⌨️', 'Peripherals', 60),
    ('4K Webcam',
     'Auto-focus, built-in ring light, dual stereo mic. Plug-and-play USB-C.',
     59.99, '📷', 'Peripherals', 75),
    ('Ergonomic Wireless Mouse',
     'Vertical design reduces wrist strain. 90-day battery, silent click.',
     44.99, '🖱️', 'Peripherals', 150),
    ('Adjustable Laptop Stand',
     'Aluminum, 6 height settings, folds flat for travel. Fits 10–17" laptops.',
     34.99, '💻', 'Accessories', 300);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);

-- Product search indexes
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_name_lower ON products(LOWER(name));

-- Reviews table
CREATE TABLE IF NOT EXISTS reviews (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    reviewer_name VARCHAR(255) NOT NULL,
    comment TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reviews_product_id ON reviews(product_id);

INSERT INTO reviews (product_id, rating, reviewer_name, comment) VALUES
    (1, 5, 'Alice', 'Best headphones I have ever owned. Noise cancellation is incredible.'),
    (1, 4, 'Bob', 'Great sound quality but a little tight on larger heads.'),
    (2, 5, 'Carlos', 'Battery lasts forever and the fitness tracking is spot on.'),
    (2, 3, 'Diana', 'Good watch but the app could use some work.'),
    (3, 4, 'Eve', 'Impressive bass for such a small speaker. Love the waterproofing.'),
    (5, 5, 'Frank', 'Cherry MX Reds are buttery smooth. Build quality is top notch.'),
    (5, 4, 'Alice', 'Great keyboard, wish it had a numpad option though.'),
    (6, 5, 'Bob', 'Crystal clear picture. The ring light is a nice touch for calls.'),
    (7, 4, 'Carlos', 'Vertical design took some getting used to but my wrist pain is gone.'),
    (8, 5, 'Diana', 'Sturdy and portable. Use it every day with my MacBook.');
