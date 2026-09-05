-- 1. Первинна перевірка сирих даних
SELECT *
FROM `mornhouse-test-environment.test_app_dataset.ad_revenue_raw`
LIMIT 10;

SELECT *
FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report`
LIMIT 10;

SELECT *
FROM `mornhouse-test-environment.test_app_dataset.in_app_events_report`
LIMIT 10;

SELECT *
FROM `mornhouse-test-environment.test_app_dataset.cost_table`
LIMIT 10;


WITH 
-- 2. Агрегація витрат за датою, джерелом та кампанією
costs AS (
    SELECT 
        DATE(date) AS date, 
        media_source, 
        CAST(campaign_id AS STRING) AS campaign_id, 
        campaign AS campaign_name, 
        SUM(cost) AS total_cost
    FROM `mornhouse-test-environment.test_app_dataset.cost_table`
    GROUP BY 1, 2, 3, 4
),

-- 3. Агрегація неорганічних установок за датою, джерелом та кампанією
installs AS (
    SELECT 
        DATE(install_date) AS date, 
        media_source, 
        CAST(campaign_id AS STRING) AS campaign_id, 
        campaign_name, 
        COUNT(*) AS total_installs
    FROM `mornhouse-test-environment.test_app_dataset.non_org_installs_report`
    GROUP BY 1, 2, 3, 4
),

-- 4. Агрегація доходів від внутрішньододаткових покупок (In-App Revenue)
in_app_revenue AS (
    SELECT 
        DATE(event_date) AS date, 
        media_source, 
        CAST(campaign_id AS STRING) AS campaign_id, 
        SUM(event_revenue_usd) AS in_app_revenue
    FROM `mornhouse-test-environment.test_app_dataset.in_app_events_report`
    GROUP BY 1, 2, 3
),

-- 5. Агрегація доходів від реклами (Ad Revenue)
ad_revenue AS (
    SELECT 
        DATE(event_date) AS date, 
        media_source, 
        CAST(campaign_id AS STRING) AS campaign_id, 
        SUM(event_revenue_usd) AS ad_revenue
    FROM `mornhouse-test-environment.test_app_dataset.ad_revenue_raw`
    GROUP BY 1, 2, 3
),

-- 6. Зведення результативності кампаній (установки + обидва види доходів)
campaign_performance AS (
    SELECT 
        COALESCE(i.date, r.date, a.date) AS date, 
        COALESCE(i.media_source, r.media_source, a.media_source) AS media_source, 
        COALESCE(i.campaign_id, r.campaign_id, a.campaign_id) AS campaign_id, 
        i.campaign_name AS campaign_name, 
        COALESCE(i.total_installs, 0) AS total_installs, 
        COALESCE(r.in_app_revenue, 0) AS in_app_revenue, 
        COALESCE(a.ad_revenue, 0) AS ad_revenue
    FROM installs i
    -- Зберігаємо кампанії, присутні лише в одному з джерел через FULL JOIN
    FULL OUTER JOIN in_app_revenue r 
        ON i.date = r.date 
       AND i.media_source = r.media_source 
       AND i.campaign_id = r.campaign_id
    FULL OUTER JOIN ad_revenue a 
        ON COALESCE(i.date, r.date) = a.date 
       AND COALESCE(i.media_source, r.media_source) = a.media_source 
       AND COALESCE(i.campaign_id, r.campaign_id) = a.campaign_id
),

-- 7. Формування базової вітрини: об'єднання витрат із результативністю та розрахунок загального доходу
marketing_mart AS (
    SELECT 
        COALESCE(c.date, p.date) AS date, 
        COALESCE(c.media_source, p.media_source) AS media_source, 
        COALESCE(c.campaign_id, p.campaign_id) AS campaign_id, 
        COALESCE(c.campaign_name, p.campaign_name) AS campaign_name, 
        COALESCE(c.total_cost, 0) AS total_cost, 
        COALESCE(p.total_installs, 0) AS total_installs, 
        COALESCE(p.in_app_revenue, 0) AS in_app_revenue, 
        COALESCE(p.ad_revenue, 0) AS ad_revenue, 
        COALESCE(p.in_app_revenue, 0) + COALESCE(p.ad_revenue, 0) AS total_revenue
    FROM costs c
    FULL OUTER JOIN campaign_performance p 
        ON c.date = p.date 
       AND c.media_source = p.media_source 
       AND c.campaign_id = p.campaign_id
)

-- 8. Фінальний вибір з розрахунком ключових бізнес-метрик (Profit, ROAS, CPI)
SELECT 
    date, 
    media_source, 
    campaign_id, 
    campaign_name, 
    total_cost, 
    total_installs, 
    in_app_revenue, 
    ad_revenue, 
    total_revenue, 
    -- Прибуток (Profit) = Загальний дохід - Витрати
    total_revenue - total_cost AS profit, 
    -- Окупність (ROAS %) = (Загальний дохід / Витрати) * 100
    SAFE_DIVIDE(total_revenue, total_cost) * 100 AS roas_percent, 
    -- Вартість установки (CPI) = Витрати / Кількість установок
    SAFE_DIVIDE(total_cost, total_installs) AS cpi
FROM marketing_mart
ORDER BY date DESC, total_revenue DESC;
