CREATE DATABASE markerting_campaigns;
GO
use markerting_campaigns
----------------------------------------------
----------------------------------------------
----------------------------------------------

-- mapping table structure
CREATE TABLE dim_Channel_Mapping (
    Raw_Channel_Name VARCHAR(50) PRIMARY KEY,
    Clean_Channel_Name VARCHAR(50),
    Channel_Group VARCHAR(50),
    Is_Paid BIT 
);


INSERT INTO dim_Channel_Mapping (Raw_Channel_Name, Clean_Channel_Name, Channel_Group, Is_Paid)
VALUES 
('Facebook',   'Facebook',    'Paid Social', 1),
('Google Ads', 'Google Ads',  'Paid Search', 1),
('Email',      'Email',       'Email Marketing', 1),
('Organic',    'Organic',     'Organic Search', 1);


-- Mapping table for Geographic cleanup
CREATE TABLE dim_Country_Mapping (
    Raw_Country_Name VARCHAR(50) PRIMARY KEY,
    Clean_Country_Name VARCHAR(50),
    Region VARCHAR(50)
);

INSERT INTO dim_Country_Mapping (Raw_Country_Name, Clean_Country_Name, Region)
VALUES 
('Egypt', 'Egypt', 'MENA'),
('EG', 'Egypt', 'MENA'),
('UAE', 'United Arab Emirates', 'MENA'),
('Dubai', 'United Arab Emirates', 'MENA'), -- Standardizing City-level entry to Country
('Saudi Arabia', 'Saudi Arabia', 'MENA'),
('KSA', 'Saudi Arabia', 'MENA');

CREATE OR ALTER VIEW vw_stg_customers AS
SELECT 
    c.customer_id,
    CAST(c.first_seen_date AS DATE) AS first_seen_date,
    COALESCE(m.clean_country_name, c.country) AS country, -- Use mapping if exists
    m.region, -- New categorical column from mapping
    c.city,
    c.device_type,
    COALESCE(ch.clean_channel_name, c.acquisition_channel) AS acquisition_channel,
    ch.channel_group -- e.g., 'Paid Social', 'Retention'
FROM customers c
LEFT JOIN dim_country_mapping m ON c.country = m.raw_country_name
LEFT JOIN dim_channel_mapping ch ON c.acquisition_channel = ch.raw_channel_name
WHERE c.customer_id IS NOT NULL;

CREATE OR ALTER VIEW vw_stg_campaigns AS
SELECT 
    campaign_id,
    campaign_name,
    channel,
    campaign_type,
    CAST(start_date AS DATE) AS start_date,
    CAST(end_date AS DATE) AS end_date,
    budget
FROM campaigns;

CREATE OR ALTER VIEW vw_stg_ad_spend AS
SELECT 
    spend_id,
    campaign_id,
    CAST([date] AS DATE) AS spend_date,
    CAST(spend_amount AS DECIMAL(12,2)) AS spend_amount,
    impressions,
    clicks
FROM ad_spend;

CREATE OR ALTER VIEW vw_stg_touchpoints AS
SELECT 
    t.touchpoint_id,
    t.customer_id,
    t.campaign_id,
    COALESCE(ch.clean_channel_name, t.channel) AS channel,
    ch.is_paid, -- Very important for ROAS math later
    CAST(t.touchpoint_date AS DATETIME) AS touchpoint_date,
    t.interaction_type
FROM touchpoints t
LEFT JOIN dim_channel_mapping ch ON t.channel = ch.raw_channel_name
WHERE t.customer_id IS NOT NULL;

CREATE OR ALTER VIEW vw_stg_conversions AS
SELECT 
    conversion_id,
    customer_id,
    CAST(conversion_date AS DATETIME) AS conversion_date,
    CAST(revenue AS DECIMAL(12,2)) AS revenue,
    order_id
FROM conversions;

CREATE OR ALTER VIEW vw_stg_orders AS
SELECT 
    order_id,
    customer_id,
    CAST(order_date AS DATETIME) AS order_date,
    CAST(revenue AS DECIMAL(12,2)) AS revenue
FROM orders;

CREATE OR ALTER VIEW vw_customer_ltv AS
SELECT 
    customer_id,
    SUM(revenue) AS total_ltv,
    COUNT(*) AS total_orders
FROM vw_stg_orders
GROUP BY customer_id;


CREATE OR ALTER VIEW customer_journey AS
SELECT  
    t.customer_id,
    conv.conversion_id,
    t.touchpoint_id,
    t.campaign_id,
    t.channel,
    t.interaction_type,
    t.touchpoint_date,
    conv.conversion_date,

    ROW_NUMBER() OVER (
        PARTITION BY conv.conversion_id 
        ORDER BY t.touchpoint_date
    ) AS touch_sequence,

    COUNT(*) OVER (
        PARTITION BY conv.conversion_id
    ) AS total_touches,

    DATEDIFF(day, t.touchpoint_date, conv.conversion_date) AS days_to_conversion

FROM vw_stg_touchpoints t
JOIN vw_stg_conversions conv 
    ON t.customer_id = conv.customer_id
    AND t.touchpoint_date <= conv.conversion_date
    AND t.touchpoint_date >= DATEADD(day, -30, conv.conversion_date); 


CREATE OR ALTER VIEW vw_marketing_attribution AS
WITH attribution_calculated AS (
    SELECT 
        cj.touchpoint_date,
        cj.channel,
        cj.campaign_id,
        cj.conversion_id,

        c.revenue AS first_order_revenue,
        ltv.total_ltv,

        CASE WHEN cj.touch_sequence = 1 THEN ltv.total_ltv ELSE 0 END AS first_touch_revenue,
        CASE WHEN cj.touch_sequence = cj.total_touches THEN ltv.total_ltv ELSE 0 END AS last_touch_revenue,

        ltv.total_ltv / CAST(cj.total_touches AS DECIMAL(10,4)) AS linear_revenue,

        -- TIME DECAY
        CASE 
            WHEN POWER(2.0, -(cj.days_to_conversion / 7.0)) < 0.0001 
            THEN 0.0001 
            ELSE POWER(2.0, -(cj.days_to_conversion / 7.0)) 
        END AS time_decay_raw_weight
        
    FROM customer_journey cj
    JOIN vw_stg_conversions c 
        ON cj.conversion_id = c.conversion_id
    JOIN vw_customer_ltv ltv
        ON cj.customer_id = ltv.customer_id
),

time_decay_normalized AS (
    SELECT 
        *,
        time_decay_raw_weight 
        / SUM(time_decay_raw_weight) OVER (PARTITION BY conversion_id) 
        AS normalized_weight
    FROM attribution_calculated
),

/* =====================================================
6. AGGREGATE BOTH SIDES INDEPENDENTLY
===================================================== */
daily_spend AS (
    SELECT 
        s.spend_date,
        c.channel,
        c.campaign_id,
        SUM(s.spend_amount) AS daily_spend,
        SUM(s.impressions) AS daily_impressions,
        SUM(s.clicks) AS daily_clicks
    FROM vw_stg_ad_spend s
    JOIN vw_stg_campaigns c ON s.campaign_id = c.campaign_id
    GROUP BY s.spend_date, c.channel, c.campaign_id
),

daily_attribution AS (
    SELECT 
        CAST(touchpoint_date AS DATE) AS attr_date,
        channel,
        campaign_id,
        COUNT(DISTINCT conversion_id) AS conversions_count,
        SUM(first_touch_revenue) AS total_first_touch_revenue,
        SUM(last_touch_revenue) AS total_last_touch_revenue,
        SUM(linear_revenue) AS total_linear_revenue,
        SUM(total_ltv * normalized_weight) AS total_time_decay_revenue
    FROM time_decay_normalized
    GROUP BY CAST(touchpoint_date AS DATE), channel, campaign_id
)

/* =====================================================
7. FINAL OUTPUT (FULL OUTER JOIN)
===================================================== */
SELECT 
    COALESCE(a.attr_date, ds.spend_date) AS date,
    COALESCE(a.channel, ds.channel) AS channel,
    COALESCE(a.campaign_id, ds.campaign_id) AS campaign_id,

    COALESCE(a.conversions_count, 0) AS conversions_count,
    COALESCE(a.total_first_touch_revenue, 0) AS total_first_touch_revenue,
    COALESCE(a.total_last_touch_revenue, 0) AS total_last_touch_revenue,
    COALESCE(a.total_linear_revenue, 0) AS total_linear_revenue,
    COALESCE(a.total_time_decay_revenue, 0) AS total_time_decay_revenue,

    COALESCE(ds.daily_spend, 0) AS daily_spend,
    COALESCE(ds.daily_impressions, 0) AS daily_impressions,
    COALESCE(ds.daily_clicks, 0) AS daily_clicks

FROM daily_attribution a
FULL OUTER JOIN daily_spend ds
    ON a.attr_date = ds.spend_date
    AND a.channel = ds.channel
    AND a.campaign_id = ds.campaign_id;















