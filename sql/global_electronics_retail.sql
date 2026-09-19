CREATE DATABASE global_electronics_retail;
USE global_electronics_retail;

-- ============================================================
-- Global Electronics Retail Sales & Operations Analytics
-- MySQL analysis script
-- Assumes original Maven CSV column names and table names:
-- sales, products, customers, stores
-- ============================================================

USE global_electronics_retail;

-- ------------------------------------------------------------
-- 0. OPTIONAL VALIDATION
-- ------------------------------------------------------------
SELECT COUNT(*) AS sales_rows FROM sales;
SELECT COUNT(*) AS customer_rows FROM customers;
SELECT COUNT(*) AS product_rows FROM products;
SELECT COUNT(*) AS store_rows FROM stores;


-- ------------------------------------------------------------
-- 1. OVERALL SALES KPIs
-- Business question:
-- How is the business performing overall?
-- ------------------------------------------------------------
SELECT
    ROUND(SUM(
        CAST(s.Quantity AS DECIMAL(12,2)) *
        CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
    ), 2) AS Total_Revenue_USD,

    COUNT(DISTINCT s.`Order Number`) AS Total_Orders,

    SUM(CAST(s.Quantity AS UNSIGNED)) AS Quantity_Sold,

    ROUND(
        SUM(
            CAST(s.Quantity AS DECIMAL(12,2)) *
            CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
        ) / COUNT(DISTINCT s.`Order Number`),
        2
    ) AS Average_Order_Value
FROM sales s
JOIN products p
    ON s.ProductKey = p.ProductKey;


-- ------------------------------------------------------------
-- 2. MONTHLY SALES TREND + MoM %
-- Business question:
-- How are revenue and orders changing over time?
-- Note: 2021 is partial through February 20.
-- ------------------------------------------------------------
WITH monthly_sales AS (
    SELECT
        DATE_FORMAT(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y'), '%Y-%m') AS Month,
        SUM(
            CAST(s.Quantity AS DECIMAL(12,2)) *
            CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
        ) AS Revenue,
        COUNT(DISTINCT s.`Order Number`) AS Orders
    FROM sales s
    JOIN products p
        ON s.ProductKey = p.ProductKey
    GROUP BY DATE_FORMAT(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y'), '%Y-%m')
),
monthly_with_previous AS (
    SELECT
        Month,
        Revenue,
        Orders,
        LAG(Revenue) OVER (ORDER BY Month) AS Previous_Month_Revenue
    FROM monthly_sales
)
SELECT
    Month,
    ROUND(Revenue, 2) AS Revenue,
    Orders,
    ROUND(
        (Revenue - Previous_Month_Revenue) /
        NULLIF(Previous_Month_Revenue, 0) * 100,
        2
    ) AS MoM_Revenue_Pct
FROM monthly_with_previous
ORDER BY Month;


-- ------------------------------------------------------------
-- 3. CATEGORY PERFORMANCE
-- Business question:
-- Which product categories drive sales?
-- ------------------------------------------------------------
SELECT
    p.Category,
    ROUND(SUM(
        CAST(s.Quantity AS DECIMAL(12,2)) *
        CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
    ), 2) AS Revenue,
    COUNT(DISTINCT s.`Order Number`) AS Orders,
    SUM(CAST(s.Quantity AS UNSIGNED)) AS Quantity_Sold
FROM sales s
JOIN products p
    ON s.ProductKey = p.ProductKey
GROUP BY p.Category
ORDER BY Revenue DESC;


-- ------------------------------------------------------------
-- 4. TOP 10 PRODUCTS BY REVENUE
-- Business question:
-- Which individual products contribute the most revenue?
-- ------------------------------------------------------------
WITH product_sales AS (
    SELECT
        p.ProductKey,
        p.`Product Name`,
        p.Category,
        SUM(
            CAST(s.Quantity AS DECIMAL(12,2)) *
            CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
        ) AS Revenue
    FROM sales s
    JOIN products p
        ON s.ProductKey = p.ProductKey
    GROUP BY
        p.ProductKey,
        p.`Product Name`,
        p.Category
)
SELECT
    DENSE_RANK() OVER (ORDER BY Revenue DESC) AS Revenue_Rank,
    `Product Name`,
    Category,
    ROUND(Revenue, 2) AS Revenue
FROM product_sales
ORDER BY Revenue_Rank
LIMIT 10;


-- ------------------------------------------------------------
-- 5. CATEGORY CHANGE: 2019 vs 2020
-- Business question:
-- Which categories declined the most between two complete years?
-- We deliberately avoid comparing full-year 2020 with partial-year 2021.
-- ------------------------------------------------------------
SELECT
    p.Category,

    ROUND(SUM(
        CASE
            WHEN YEAR(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y')) = 2019
            THEN CAST(s.Quantity AS DECIMAL(12,2)) *
                 CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
            ELSE 0
        END
    ), 2) AS Revenue_2019,

    ROUND(SUM(
        CASE
            WHEN YEAR(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y')) = 2020
            THEN CAST(s.Quantity AS DECIMAL(12,2)) *
                 CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
            ELSE 0
        END
    ), 2) AS Revenue_2020,

    ROUND(
        (
            SUM(
                CASE
                    WHEN YEAR(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y')) = 2020
                    THEN CAST(s.Quantity AS DECIMAL(12,2)) *
                         CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
                    ELSE 0
                END
            )
            -
            SUM(
                CASE
                    WHEN YEAR(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y')) = 2019
                    THEN CAST(s.Quantity AS DECIMAL(12,2)) *
                         CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
                    ELSE 0
                END
            )
        )
        /
        NULLIF(
            SUM(
                CASE
                    WHEN YEAR(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y')) = 2019
                    THEN CAST(s.Quantity AS DECIMAL(12,2)) *
                         CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
                    ELSE 0
                END
            ),
            0
        ) * 100,
        2
    ) AS Revenue_Change_Pct

FROM sales s
JOIN products p
    ON s.ProductKey = p.ProductKey
WHERE YEAR(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y')) IN (2019, 2020)
GROUP BY p.Category
ORDER BY Revenue_Change_Pct ASC;


-- ------------------------------------------------------------
-- 6. ONLINE vs PHYSICAL STORE PERFORMANCE
-- Business question:
-- Is there a difference in revenue and AOV by sales channel?
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN s.StoreKey = 0 THEN 'Online'
        ELSE 'Physical Store'
    END AS Store_Type,

    ROUND(SUM(
        CAST(s.Quantity AS DECIMAL(12,2)) *
        CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
    ), 2) AS Revenue,

    COUNT(DISTINCT s.`Order Number`) AS Orders,

    SUM(CAST(s.Quantity AS UNSIGNED)) AS Quantity_Sold,

    ROUND(
        SUM(
            CAST(s.Quantity AS DECIMAL(12,2)) *
            CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
        )
        / COUNT(DISTINCT s.`Order Number`),
        2
    ) AS AOV

FROM sales s
JOIN products p
    ON s.ProductKey = p.ProductKey
GROUP BY Store_Type
ORDER BY Revenue DESC;


-- ------------------------------------------------------------
-- 7. CUSTOMER COUNTRY PERFORMANCE
-- Business question:
-- Which customer markets generate the most sales?
-- ------------------------------------------------------------
SELECT
    c.Country,
    c.Continent,

    ROUND(SUM(
        CAST(s.Quantity AS DECIMAL(12,2)) *
        CAST(REPLACE(REPLACE(p.`Unit Price USD`, '$', ''), ',', '') AS DECIMAL(12,2))
    ), 2) AS Revenue,

    COUNT(DISTINCT s.`Order Number`) AS Orders,

    COUNT(DISTINCT s.CustomerKey) AS Customers

FROM sales s
JOIN customers c
    ON s.CustomerKey = c.CustomerKey
JOIN products p
    ON s.ProductKey = p.ProductKey
GROUP BY
    c.Country,
    c.Continent
ORDER BY Revenue DESC;


-- ------------------------------------------------------------
-- 8. ONLINE DELIVERY PERFORMANCE BY YEAR
-- Business question:
-- How long does online delivery take, and has it changed over time?
-- Delivery Date is only applicable to online transactions.
-- ------------------------------------------------------------
SELECT
    YEAR(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y')) AS Order_Year,

    ROUND(
        AVG(
            DATEDIFF(
                STR_TO_DATE(s.`Delivery Date`, '%m/%d/%Y'),
                STR_TO_DATE(s.`Order Date`, '%m/%d/%Y')
            )
        ),
        2
    ) AS Avg_Delivery_Days,

    COUNT(DISTINCT s.`Order Number`) AS Online_Orders

FROM sales s
WHERE
    s.StoreKey = 0
    AND s.`Delivery Date` IS NOT NULL
    AND s.`Delivery Date` <> ''
GROUP BY
    YEAR(STR_TO_DATE(s.`Order Date`, '%m/%d/%Y'))
ORDER BY Order_Year;
