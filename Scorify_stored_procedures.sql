-- =============================================================================
-- MVP STORED PROCEDURES
-- =============================================================================
-- Sections:
--   1. Rubric Management
--   2. Submission Management
--   3. Grading
--   4. User & Subscription
--   5. Billing / Orders & Payments
--   6. Dashboard / Analytics
-- =============================================================================


-- =============================================================================
-- 1. RUBRIC MANAGEMENT
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Get a full rubric with all its criteria
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_rubric_with_criteria(p_rubric_id UUID)
RETURNS TABLE (
    rubric_id             UUID,
    rubric_name           TEXT,
    rubric_description    TEXT,
    max_score             NUMERIC,
    rubric_create_time    TIMESTAMPTZ,
    rubric_last_edit      TIMESTAMPTZ,
    creator_profile_id    UUID,
    criteria_id           UUID,
    criteria_name         TEXT,
    criteria_description  TEXT,
    weight                NUMERIC,
    criteria_max_score    NUMERIC,
    display_order         INT
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.rubric_id,
        r.rubric_name,
        r.rubric_description,
        r.max_score,
        r.rubric_create_time,
        r.rubric_last_edit,
        r.creator_profile_id,
        rc.criteria_id,
        rc.name           AS criteria_name,
        rc.description    AS criteria_description,
        rc.weight,
        rc.max_score      AS criteria_max_score,
        rc.display_order
    FROM rubric r
    LEFT JOIN rubric_criteria rc ON rc.rubric_id = r.rubric_id
    WHERE r.rubric_id = p_rubric_id
    ORDER BY rc.display_order;
END;
$$;


-- -----------------------------------------------------------------------------
-- List all rubrics created by a profile
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_rubrics_by_profile(p_profile_id UUID)
RETURNS TABLE (
    rubric_id           UUID,
    rubric_name         TEXT,
    rubric_description  TEXT,
    max_score           NUMERIC,
    criteria_count      BIGINT,
    rubric_create_time  TIMESTAMPTZ,
    rubric_last_edit    TIMESTAMPTZ
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.rubric_id,
        r.rubric_name,
        r.rubric_description,
        r.max_score,
        COUNT(rc.criteria_id) AS criteria_count,
        r.rubric_create_time,
        r.rubric_last_edit
    FROM rubric r
    LEFT JOIN rubric_criteria rc ON rc.rubric_id = r.rubric_id
    WHERE r.creator_profile_id = p_profile_id
    GROUP BY r.rubric_id
    ORDER BY r.rubric_last_edit DESC;
END;
$$;


-- -----------------------------------------------------------------------------
-- Create a rubric with criteria in one call
-- p_criteria: JSON array of {name, description, weight, max_score, display_order}
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_rubric_with_criteria(
    p_creator_profile_id  UUID,
    p_rubric_name         TEXT,
    p_rubric_description  TEXT,
    p_max_score           NUMERIC,
    p_criteria            JSONB
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_rubric_id  UUID := gen_random_uuid();
    v_criterion  JSONB;
BEGIN
    INSERT INTO rubric (
        rubric_id, creator_profile_id, rubric_name,
        rubric_description, max_score,
        rubric_create_time, rubric_last_edit
    ) VALUES (
        v_rubric_id, p_creator_profile_id, p_rubric_name,
        p_rubric_description, p_max_score,
        NOW(), NOW()
    );

    FOR v_criterion IN SELECT * FROM jsonb_array_elements(p_criteria)
    LOOP
        INSERT INTO rubric_criteria (
            criteria_id, rubric_id, name, description,
            weight, max_score, display_order
        ) VALUES (
            gen_random_uuid(),
            v_rubric_id,
            v_criterion->>'name',
            v_criterion->>'description',
            (v_criterion->>'weight')::NUMERIC,
            (v_criterion->>'max_score')::NUMERIC,
            (v_criterion->>'display_order')::INT
        );
    END LOOP;

    RETURN v_rubric_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Update a rubric's metadata
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_rubric(
    p_rubric_id          UUID,
    p_rubric_name        TEXT,
    p_rubric_description TEXT,
    p_max_score          NUMERIC
)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE rubric SET
        rubric_name        = p_rubric_name,
        rubric_description = p_rubric_description,
        max_score          = p_max_score,
        rubric_last_edit   = NOW()
    WHERE rubric_id = p_rubric_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rubric % not found', p_rubric_id;
    END IF;
END;
$$;


-- -----------------------------------------------------------------------------
-- Delete a rubric and all its criteria (cascades grade results via app logic)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION delete_rubric(p_rubric_id UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM rubric_criteria WHERE rubric_id = p_rubric_id;
    DELETE FROM rubric           WHERE rubric_id = p_rubric_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rubric % not found', p_rubric_id;
    END IF;
END;
$$;


-- =============================================================================
-- 2. SUBMISSION MANAGEMENT
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Create a submission with files in one call
-- p_files: JSON array of {file_name, file_type, path}
-- Returns the new submission_id
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_submission(
    p_profile_id       UUID,
    p_submission_title TEXT,
    p_status           TEXT,   -- e.g. 'pending', 'graded'
    p_files            JSONB
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_submission_id  UUID := gen_random_uuid();
    v_file           JSONB;
BEGIN
    INSERT INTO submission (
        submission_id, profile_id, submission_time,
        status, submission_title
    ) VALUES (
        v_submission_id, p_profile_id, NOW(),
        p_status, p_submission_title
    );

    FOR v_file IN SELECT * FROM jsonb_array_elements(p_files)
    LOOP
        INSERT INTO submission_file (
            file_id, submission_id, file_name,
            file_type, upload_time, path
        ) VALUES (
            gen_random_uuid(),
            v_submission_id,
            v_file->>'file_name',
            v_file->>'file_type',
            NOW(),
            v_file->>'path'
        );
    END LOOP;

    RETURN v_submission_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Get a submission with its files and latest grade result
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_submission_detail(p_submission_id UUID)
RETURNS TABLE (
    submission_id     UUID,
    profile_id        UUID,
    profile_name      TEXT,
    submission_title  TEXT,
    submission_time   TIMESTAMPTZ,
    status            TEXT,
    file_id           UUID,
    file_name         TEXT,
    file_type         TEXT,
    upload_time       TIMESTAMPTZ,
    path              TEXT,
    grade_result_id   UUID,
    rubric_id         UUID,
    overall_score     NUMERIC,
    grade_feedback    TEXT,
    graded_at         TIMESTAMPTZ
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.submission_id,
        s.profile_id,
        p.name            AS profile_name,
        s.submission_title,
        s.submission_time,
        s.status,
        sf.file_id,
        sf.file_name,
        sf.file_type,
        sf.upload_time,
        sf.path,
        gr.grade_result_id,
        gr.rubric_id,
        gr.overall_score,
        gr.feedback       AS grade_feedback,
        gr.created_time   AS graded_at
    FROM submission s
    JOIN profiles p            ON p.id = s.profile_id
    LEFT JOIN submission_file sf ON sf.submission_id = s.submission_id
    LEFT JOIN LATERAL (
        SELECT * FROM grade_result
        WHERE grade_result.submission_id = s.submission_id
        ORDER BY created_time DESC
        LIMIT 1
    ) gr ON TRUE
    WHERE s.submission_id = p_submission_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- List submissions for a profile (paginated)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_submissions_by_profile(
    p_profile_id  UUID,
    p_limit       INT     DEFAULT 20,
    p_offset      INT     DEFAULT 0,
    p_status      TEXT    DEFAULT NULL   -- optional filter
)
RETURNS TABLE (
    submission_id     UUID,
    submission_title  TEXT,
    submission_time   TIMESTAMPTZ,
    status            TEXT,
    file_count        BIGINT,
    overall_score     NUMERIC,
    graded_at         TIMESTAMPTZ
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.submission_id,
        s.submission_title,
        s.submission_time,
        s.status,
        COUNT(sf.file_id)  AS file_count,
        gr.overall_score,
        gr.created_time    AS graded_at
    FROM submission s
    LEFT JOIN submission_file sf ON sf.submission_id = s.submission_id
    LEFT JOIN LATERAL (
        SELECT overall_score, created_time FROM grade_result
        WHERE grade_result.submission_id = s.submission_id
        ORDER BY created_time DESC
        LIMIT 1
    ) gr ON TRUE
    WHERE s.profile_id = p_profile_id
      AND (p_status IS NULL OR s.status = p_status)
    GROUP BY s.submission_id, gr.overall_score, gr.created_time
    ORDER BY s.submission_time DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;


-- -----------------------------------------------------------------------------
-- Update submission status
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_submission_status(
    p_submission_id  UUID,
    p_status         TEXT
)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE submission
    SET status = p_status
    WHERE submission_id = p_submission_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Submission % not found', p_submission_id;
    END IF;
END;
$$;


-- =============================================================================
-- 3. GRADING
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Save a grade result with per-criterion scores in one transaction
-- p_criterion_scores: JSON array of {criteria_id, score, feedback}
-- Returns the new grade_result_id
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION save_grade_result(
    p_rubric_id            UUID,
    p_submission_id        UUID,
    p_overall_score        NUMERIC,
    p_feedback             TEXT,
    p_criterion_scores     JSONB
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_grade_result_id  UUID := gen_random_uuid();
    v_item             JSONB;
BEGIN
    INSERT INTO grade_result (
        grade_result_id, rubric_id, submission_id,
        overall_score, feedback, created_time
    ) VALUES (
        v_grade_result_id, p_rubric_id, p_submission_id,
        p_overall_score, p_feedback, NOW()
    );

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_criterion_scores)
    LOOP
        INSERT INTO criterion_result (
            result_id, criteria_id, grade_result_id,
            score, feedback
        ) VALUES (
            gen_random_uuid(),
            (v_item->>'criteria_id')::UUID,
            v_grade_result_id,
            (v_item->>'score')::NUMERIC,
            v_item->>'feedback'
        );
    END LOOP;

    -- Mark submission as graded
    UPDATE submission
    SET status = 'graded'
    WHERE submission_id = p_submission_id;

    RETURN v_grade_result_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Get a full grade result with per-criterion breakdown
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_grade_result_detail(p_grade_result_id UUID)
RETURNS TABLE (
    grade_result_id   UUID,
    rubric_id         UUID,
    rubric_name       TEXT,
    submission_id     UUID,
    submission_title  TEXT,
    overall_score     NUMERIC,
    rubric_max_score  NUMERIC,
    feedback          TEXT,
    created_time      TIMESTAMPTZ,
    criteria_id       UUID,
    criteria_name     TEXT,
    criteria_weight   NUMERIC,
    criteria_max      NUMERIC,
    criterion_score   NUMERIC,
    criterion_feedback TEXT
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        gr.grade_result_id,
        gr.rubric_id,
        r.rubric_name,
        gr.submission_id,
        s.submission_title,
        gr.overall_score,
        r.max_score        AS rubric_max_score,
        gr.feedback,
        gr.created_time,
        rc.criteria_id,
        rc.name            AS criteria_name,
        rc.weight          AS criteria_weight,
        rc.max_score       AS criteria_max,
        cr.score           AS criterion_score,
        cr.feedback        AS criterion_feedback
    FROM grade_result gr
    JOIN rubric r              ON r.rubric_id      = gr.rubric_id
    JOIN submission s          ON s.submission_id  = gr.submission_id
    LEFT JOIN criterion_result cr ON cr.grade_result_id = gr.grade_result_id
    LEFT JOIN rubric_criteria rc  ON rc.criteria_id    = cr.criteria_id
    WHERE gr.grade_result_id = p_grade_result_id
    ORDER BY rc.display_order;
END;
$$;


-- -----------------------------------------------------------------------------
-- Get all grade results for a submission (history)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_grade_history(p_submission_id UUID)
RETURNS TABLE (
    grade_result_id  UUID,
    rubric_id        UUID,
    rubric_name      TEXT,
    overall_score    NUMERIC,
    max_score        NUMERIC,
    feedback         TEXT,
    created_time     TIMESTAMPTZ
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        gr.grade_result_id,
        gr.rubric_id,
        r.rubric_name,
        gr.overall_score,
        r.max_score,
        gr.feedback,
        gr.created_time
    FROM grade_result gr
    JOIN rubric r ON r.rubric_id = gr.rubric_id
    WHERE gr.submission_id = p_submission_id
    ORDER BY gr.created_time DESC;
END;
$$;


-- =============================================================================
-- 4. USER & SUBSCRIPTION
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Get a user profile with their active subscription
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_profile_with_subscription(p_profile_id UUID)
RETURNS TABLE (
    profile_id              UUID,
    name                    TEXT,
    profile_picture         TEXT,
    created_at              TIMESTAMPTZ,
    user_subscription_id    UUID,
    plan_id                 UUID,
    plan_name               TEXT,
    plan_price              NUMERIC,
    billing_period          TEXT,
    submission_limit        INT,
    file_size_limit         BIGINT,
    subscription_status     TEXT,
    subscription_start      DATE,
    subscription_end        DATE
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id              AS profile_id,
        p.name,
        p.profile_picture,
        p.created_at,
        us.user_subscription_id,
        sp.plan_id,
        sp.name           AS plan_name,
        sp.price          AS plan_price,
        sp.billing_period,
        sp.submission_limit,
        sp.file_size_limit,
        us.status         AS subscription_status,
        us.start_date     AS subscription_start,
        us.end_date       AS subscription_end
    FROM profiles p
    LEFT JOIN user_subscription us
           ON us.profile_id = p.id
          AND us.status = 'active'
    LEFT JOIN subscription_plan sp ON sp.plan_id = us.plan_id
    WHERE p.id = p_profile_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Assign or switch a subscription plan for a user
-- Closes any existing active subscription and opens a new one
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION upsert_user_subscription(
    p_profile_id  UUID,
    p_plan_id     UUID,
    p_start_date  DATE DEFAULT CURRENT_DATE
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_new_sub_id  UUID := gen_random_uuid();
    v_end_date    DATE;
    v_period      TEXT;
BEGIN
    -- Resolve billing period for the new plan
    SELECT billing_period INTO v_period
    FROM subscription_plan WHERE plan_id = p_plan_id;

    v_end_date := CASE v_period
        WHEN 'monthly' THEN p_start_date + INTERVAL '1 month'
        WHEN 'yearly'  THEN p_start_date + INTERVAL '1 year'
        ELSE NULL  -- lifetime / no expiry
    END;

    -- Expire any existing active subscription
    UPDATE user_subscription
    SET status   = 'cancelled',
        end_date = CURRENT_DATE
    WHERE profile_id = p_profile_id
      AND status     = 'active';

    -- Insert the new subscription
    INSERT INTO user_subscription (
        user_subscription_id, profile_id, plan_id,
        start_date, end_date, status
    ) VALUES (
        v_new_sub_id, p_profile_id, p_plan_id,
        p_start_date, v_end_date::DATE, 'active'
    );

    RETURN v_new_sub_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Cancel a user's active subscription
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_user_subscription(p_profile_id UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE user_subscription
    SET status   = 'cancelled',
        end_date = CURRENT_DATE
    WHERE profile_id = p_profile_id
      AND status     = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active subscription found for profile %', p_profile_id;
    END IF;
END;
$$;


-- -----------------------------------------------------------------------------
-- Check whether a user is within their submission limit
-- Returns TRUE if they can still submit
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_submission_limit(p_profile_id UUID)
RETURNS TABLE (
    can_submit         BOOLEAN,
    submissions_used   BIGINT,
    submission_limit   INT,
    plan_name          TEXT
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    WITH active_plan AS (
        SELECT sp.submission_limit, sp.name AS plan_name
        FROM user_subscription us
        JOIN subscription_plan sp ON sp.plan_id = us.plan_id
        WHERE us.profile_id = p_profile_id
          AND us.status = 'active'
        LIMIT 1
    ),
    usage AS (
        SELECT COUNT(*) AS cnt
        FROM submission
        WHERE profile_id = p_profile_id
    )
    SELECT
        CASE
            WHEN ap.submission_limit IS NULL THEN TRUE  -- unlimited
            ELSE usage.cnt < ap.submission_limit
        END                    AS can_submit,
        usage.cnt              AS submissions_used,
        ap.submission_limit,
        ap.plan_name
    FROM active_plan ap, usage;
END;
$$;


-- =============================================================================
-- 5. BILLING — ORDERS & PAYMENTS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Create an order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_order(
    p_profile_id  UUID,
    p_amount      NUMERIC,
    p_status      TEXT DEFAULT 'pending'
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_order_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO orders (id, profile_id, amount, status, created_at)
    VALUES (v_order_id, p_profile_id, p_amount, p_status, NOW());

    RETURN v_order_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Record a payment against an order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_payment(
    p_order_id           UUID,
    p_provider           TEXT,
    p_provider_payment_id TEXT,
    p_amount             NUMERIC,
    p_currency           TEXT,
    p_status             TEXT DEFAULT 'pending'
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_payment_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO payments (
        id, order_id, provider, provider_payment_id,
        amount, currency, status, created_at
    ) VALUES (
        v_payment_id, p_order_id, p_provider, p_provider_payment_id,
        p_amount, p_currency, p_status, NOW()
    );

    RETURN v_payment_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Mark a payment as completed and update the parent order
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION complete_payment(p_payment_id UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_order_id UUID;
BEGIN
    UPDATE payments
    SET status       = 'completed',
        completed_at = NOW()
    WHERE id = p_payment_id
    RETURNING order_id INTO v_order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment % not found', p_payment_id;
    END IF;

    UPDATE orders SET status = 'completed'
    WHERE id = v_order_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Get order history for a profile
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_order_history(
    p_profile_id  UUID,
    p_limit       INT DEFAULT 20,
    p_offset      INT DEFAULT 0
)
RETURNS TABLE (
    order_id        UUID,
    order_amount    NUMERIC,
    order_status    TEXT,
    order_created   TIMESTAMPTZ,
    payment_id      UUID,
    provider        TEXT,
    payment_amount  NUMERIC,
    currency        TEXT,
    payment_status  TEXT,
    completed_at    TIMESTAMPTZ
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        o.id              AS order_id,
        o.amount          AS order_amount,
        o.status          AS order_status,
        o.created_at      AS order_created,
        p.id              AS payment_id,
        p.provider,
        p.amount          AS payment_amount,
        p.currency,
        p.status          AS payment_status,
        p.completed_at
    FROM orders o
    LEFT JOIN payments p ON p.order_id = o.id
    WHERE o.profile_id = p_profile_id
    ORDER BY o.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;


-- =============================================================================
-- 6. DASHBOARD / ANALYTICS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Summary dashboard stats for a profile
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_dashboard_stats(p_profile_id UUID)
RETURNS TABLE (
    total_submissions     BIGINT,
    graded_submissions    BIGINT,
    pending_submissions   BIGINT,
    total_rubrics         BIGINT,
    avg_score             NUMERIC,
    active_plan           TEXT
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*)
         FROM submission
         WHERE profile_id = p_profile_id)                                AS total_submissions,

        (SELECT COUNT(*)
         FROM submission
         WHERE profile_id = p_profile_id AND status = 'graded')         AS graded_submissions,

        (SELECT COUNT(*)
         FROM submission
         WHERE profile_id = p_profile_id AND status = 'pending')        AS pending_submissions,

        (SELECT COUNT(*)
         FROM rubric
         WHERE creator_profile_id = p_profile_id)                       AS total_rubrics,

        (SELECT ROUND(AVG(gr.overall_score), 2)
         FROM grade_result gr
         JOIN submission s ON s.submission_id = gr.submission_id
         WHERE s.profile_id = p_profile_id)                             AS avg_score,

        (SELECT sp.name
         FROM user_subscription us
         JOIN subscription_plan sp ON sp.plan_id = us.plan_id
         WHERE us.profile_id = p_profile_id AND us.status = 'active'
         LIMIT 1)                                                        AS active_plan;
END;
$$;


-- -----------------------------------------------------------------------------
-- Score distribution across all graded submissions for a profile
-- Bucketed into 10-point ranges (0-9, 10-19, … 90-100)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_score_distribution(p_profile_id UUID)
RETURNS TABLE (
    bucket  TEXT,
    count   BIGINT
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        (FLOOR(gr.overall_score / 10) * 10)::INT::TEXT
            || '-'
            || LEAST(FLOOR(gr.overall_score / 10) * 10 + 9, 100)::INT::TEXT
                                              AS bucket,
        COUNT(*)                              AS count
    FROM grade_result gr
    JOIN submission s ON s.submission_id = gr.submission_id
    WHERE s.profile_id = p_profile_id
      AND gr.overall_score IS NOT NULL
    GROUP BY FLOOR(gr.overall_score / 10)
    ORDER BY FLOOR(gr.overall_score / 10);
END;
$$;