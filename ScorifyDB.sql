-- ============================================================
-- ScorifyDB - PostgreSQL Schema
-- Schemas: auth (managed by Supabase), public, private
-- ============================================================


-- ============================================================
-- NOTE: auth.users is managed by Supabase Auth.
-- Shown here for reference only — do NOT run this in production.
-- ============================================================
-- CREATE TABLE auth.users (
--     id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--     email     TEXT,
--     phone     TEXT
-- );


-- ============================================================
-- SCHEMA: public
-- ============================================================

-- ------------------------------------------------------------
-- public.profiles
-- ------------------------------------------------------------
CREATE TABLE public.profiles (
    id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name            TEXT,
    profile_picture TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- public.subscription_plan
-- ------------------------------------------------------------
CREATE TABLE public.subscription_plan (
    plan_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name             TEXT        NOT NULL,
    price            NUMERIC(10, 2) NOT NULL,
    file_size_limit  BIGINT,          -- in bytes
    submission_limit INT,
    billing_period   TEXT,            -- e.g. 'monthly', 'yearly'
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- public.user_subscription
-- ------------------------------------------------------------
CREATE TABLE public.user_subscription (
    user_subscription_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id           UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    plan_id              UUID        NOT NULL REFERENCES public.subscription_plan(plan_id) ON DELETE RESTRICT,
    start_date           DATE        NOT NULL,
    end_date             DATE,
    status               TEXT        NOT NULL DEFAULT 'active'  -- e.g. 'active', 'expired', 'cancelled'
);

-- ------------------------------------------------------------
-- public.rubric
-- ------------------------------------------------------------
CREATE TABLE public.rubric (
    rubric_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_profile_id UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
    rubric_name        TEXT        NOT NULL,
    rubric_description TEXT,
    rubric_create_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rubric_last_edit   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    max_score          NUMERIC(6, 2)
);

-- ------------------------------------------------------------
-- public.rubric_criteria
-- ------------------------------------------------------------
CREATE TABLE public.rubric_criteria (
    criteria_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    rubric_id     UUID        NOT NULL REFERENCES public.rubric(rubric_id) ON DELETE CASCADE,
    name          TEXT        NOT NULL,
    description   TEXT,
    weight        NUMERIC(5, 2),
    max_score     NUMERIC(6, 2),
    display_order INT         NOT NULL DEFAULT 0
);

-- ------------------------------------------------------------
-- public.submission  (preserving original spelling from diagram)
-- ------------------------------------------------------------
CREATE TABLE public.submission (
    submission_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    submission_time  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status           TEXT        NOT NULL DEFAULT 'pending',  -- e.g. 'pending', 'graded', 'failed'
    submission_title TEXT                                    
);

-- ------------------------------------------------------------
-- public.submission_file
-- ------------------------------------------------------------
CREATE TABLE public.submission_file (
    file_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    submission_id UUID        NOT NULL REFERENCES public.submission(submission_id) ON DELETE CASCADE,
    file_name     TEXT        NOT NULL,
    file_type     TEXT,
    upload_time   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    path          TEXT        NOT NULL
);

-- ------------------------------------------------------------
-- public.grade_result
-- ------------------------------------------------------------
CREATE TABLE public.grade_result (
    grade_result_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    rubric_id       UUID        NOT NULL REFERENCES public.rubric(rubric_id) ON DELETE RESTRICT,
    submission_id   UUID        NOT NULL REFERENCES public.submission(submission_id) ON DELETE CASCADE,
    overall_score   NUMERIC(6, 2),
    feedback        TEXT,
    created_time    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- public.criterion_result
-- ------------------------------------------------------------
CREATE TABLE public.criterion_result (
    result_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    criteria_id     UUID        NOT NULL REFERENCES public.rubric_criteria(criteria_id) ON DELETE RESTRICT,
    grade_result_id UUID        NOT NULL REFERENCES public.grade_result(grade_result_id) ON DELETE CASCADE,
    score           NUMERIC(6, 2),
    feedback        TEXT
);


-- ============================================================
-- SCHEMA: private
-- ============================================================

CREATE SCHEMA IF NOT EXISTS private;

-- ------------------------------------------------------------
-- private.ai_evaluation
-- ------------------------------------------------------------
CREATE TABLE private.ai_evaluation (
    evaluation_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    submission_id   UUID        NOT NULL REFERENCES public.submission(submission_id) ON DELETE CASCADE,
    model_name     TEXT        NOT NULL,
    model_version  TEXT,
    token_used     INT,
    cost           NUMERIC(10, 6),
    prompt_version  TEXT,                    -- preserving original spelling
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    execution_time  NUMERIC(10, 3)           -- preserving original spelling (execution time in seconds)
);


-- ============================================================
-- INDEXES (recommended for FK columns used in joins/filters)
-- ============================================================

CREATE INDEX idx_profiles_id                    ON public.profiles(id);
CREATE INDEX idx_user_subscription_profile_id   ON public.user_subscription(profile_id);
CREATE INDEX idx_user_subscription_plan_id      ON public.user_subscription(plan_id);
CREATE INDEX idx_rubric_creator_profile_id      ON public.rubric(creator_profile_id);
CREATE INDEX idx_rubric_criteria_rubric_id      ON public.rubric_criteria(rubric_id);
CREATE INDEX idx_submission_profile_id          ON public.submission(profile_id);
CREATE INDEX idx_submission_file_submission_id  ON public.submission_file(submission_id);
CREATE INDEX idx_grade_result_submission_id     ON public.grade_result(submission_id);
CREATE INDEX idx_grade_result_rubric_id         ON public.grade_result(rubric_id);
CREATE INDEX idx_criterion_result_grade_result  ON public.criterion_result(grade_result_id);
CREATE INDEX idx_criterion_result_criteria_id   ON public.criterion_result(criteria_id);
CREATE INDEX idx_ai_evaluation_submission_id    ON private.ai_evaluation(submission_id);


-- ============================================================
-- ROW LEVEL SECURITY (Supabase recommended baseline)
-- ============================================================

ALTER TABLE public.profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_subscription ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rubric            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rubric_criteria   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submission        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submission_file   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grade_result      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.criterion_result  ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.ai_evaluation    ENABLE ROW LEVEL SECURITY;

-- Example RLS policy: users can only read/write their own profile
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (id = auth.uid());

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (id = auth.uid());

-- subscription_plan is publicly readable
CREATE POLICY "Anyone can read subscription plans"
    ON public.subscription_plan FOR SELECT
    USING (true);