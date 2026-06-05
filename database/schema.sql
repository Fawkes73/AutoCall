-- AI Travel Agency Voice Receptionist PostgreSQL Schema
-- PostgreSQL 15+ recommended. Requires pgcrypto and pgvector.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TYPE user_status AS ENUM ('active', 'inactive', 'locked', 'invited');
CREATE TYPE call_status AS ENUM ('initiated', 'ringing', 'in_progress', 'transferred', 'completed', 'failed', 'missed');
CREATE TYPE lead_status AS ENUM ('new', 'qualified', 'contacted', 'proposal_sent', 'converted', 'lost', 'invalid');
CREATE TYPE lead_source AS ENUM ('voice_ai', 'manual', 'website', 'crm_import');
CREATE TYPE transcript_speaker AS ENUM ('customer', 'ai', 'agent', 'system');
CREATE TYPE crm_provider AS ENUM ('zoho');
CREATE TYPE sync_status AS ENUM ('pending', 'success', 'failed', 'retrying');
CREATE TYPE kb_content_type AS ENUM ('faq', 'travel_package', 'visa_rule', 'seasonal_offer', 'policy', 'business_hours', 'contact_info');

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(80) NOT NULL UNIQUE,
    description TEXT,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(120) NOT NULL UNIQUE,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE role_permissions (
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL REFERENCES roles(id),
    email CITEXT UNIQUE,
    phone_number VARCHAR(20) UNIQUE,
    password_hash TEXT NOT NULL,
    full_name VARCHAR(160) NOT NULL,
    status user_status NOT NULL DEFAULT 'active',
    last_login_at TIMESTAMPTZ,
    failed_login_attempts INTEGER NOT NULL DEFAULT 0 CHECK (failed_login_attempts >= 0),
    locked_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (email IS NOT NULL OR phone_number IS NOT NULL)
);

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    family_id UUID NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    replaced_by_token_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_ip INET,
    user_agent TEXT
);

CREATE TABLE agents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    display_name VARCHAR(160) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    is_available BOOLEAN NOT NULL DEFAULT FALSE,
    skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    languages TEXT[] NOT NULL DEFAULT ARRAY['en-IN']::TEXT[],
    current_call_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(160),
    phone_number VARCHAR(20) NOT NULL,
    email CITEXT,
    preferred_language VARCHAR(12),
    is_vip BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (phone_number)
);

CREATE TABLE package_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(120) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE destinations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(160) NOT NULL,
    country VARCHAR(120),
    region VARCHAR(120),
    tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (name, country)
);

CREATE TABLE travel_packages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id UUID REFERENCES package_categories(id),
    destination_id UUID REFERENCES destinations(id),
    title VARCHAR(220) NOT NULL,
    description TEXT NOT NULL,
    duration_days INTEGER NOT NULL CHECK (duration_days > 0),
    duration_nights INTEGER NOT NULL CHECK (duration_nights >= 0),
    starting_price_inr NUMERIC(12,2) CHECK (starting_price_inr >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    hotel_category VARCHAR(80),
    inclusions TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    exclusions TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    valid_from DATE,
    valid_to DATE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    source_of_truth VARCHAR(120) NOT NULL DEFAULT 'internal',
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(id),
    owner_agent_id UUID REFERENCES agents(id),
    source lead_source NOT NULL DEFAULT 'voice_ai',
    status lead_status NOT NULL DEFAULT 'new',
    intent VARCHAR(80) NOT NULL,
    destination VARCHAR(160),
    departure_city VARCHAR(160),
    travel_date DATE,
    return_date DATE,
    travelers_count INTEGER CHECK (travelers_count IS NULL OR travelers_count > 0),
    adults INTEGER CHECK (adults IS NULL OR adults >= 0),
    children INTEGER CHECK (children IS NULL OR children >= 0),
    budget_inr NUMERIC(12,2) CHECK (budget_inr IS NULL OR budget_inr >= 0),
    preferred_hotel_category VARCHAR(80),
    travel_type VARCHAR(80),
    qualification_score NUMERIC(5,2) CHECK (qualification_score IS NULL OR qualification_score BETWEEN 0 AND 100),
    next_follow_up_at TIMESTAMPTZ,
    zoho_lead_id VARCHAR(120),
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (return_date IS NULL OR travel_date IS NULL OR return_date >= travel_date)
);

CREATE TABLE calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customers(id),
    lead_id UUID REFERENCES leads(id),
    provider VARCHAR(40) NOT NULL DEFAULT 'exotel',
    provider_call_id VARCHAR(160) NOT NULL,
    from_number VARCHAR(20) NOT NULL,
    to_number VARCHAR(20) NOT NULL,
    status call_status NOT NULL DEFAULT 'initiated',
    detected_language VARCHAR(12),
    primary_intent VARCHAR(80),
    confidence_score NUMERIC(5,2) CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 100),
    sentiment VARCHAR(40),
    frustration_detected BOOLEAN NOT NULL DEFAULT FALSE,
    urgency_detected BOOLEAN NOT NULL DEFAULT FALSE,
    escalation_reason TEXT,
    transferred_to_agent_id UUID REFERENCES agents(id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    answered_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
    extracted_entities JSONB NOT NULL DEFAULT '{}'::JSONB,
    provider_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_call_id)
);

ALTER TABLE agents ADD CONSTRAINT fk_agents_current_call FOREIGN KEY (current_call_id) REFERENCES calls(id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE call_recordings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    provider_recording_id VARCHAR(160),
    storage_url TEXT,
    duration_seconds INTEGER CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
    size_bytes BIGINT CHECK (size_bytes IS NULL OR size_bytes >= 0),
    mime_type VARCHAR(80),
    checksum_sha256 CHAR(64),
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE call_transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    sequence_number INTEGER NOT NULL CHECK (sequence_number >= 0),
    speaker transcript_speaker NOT NULL,
    language VARCHAR(12),
    text TEXT NOT NULL,
    confidence_score NUMERIC(5,2) CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 100),
    started_at_ms INTEGER CHECK (started_at_ms IS NULL OR started_at_ms >= 0),
    ended_at_ms INTEGER CHECK (ended_at_ms IS NULL OR ended_at_ms >= 0),
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (call_id, sequence_number)
);

CREATE TABLE call_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    summary TEXT NOT NULL,
    action_items JSONB NOT NULL DEFAULT '[]'::JSONB,
    detected_intents TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    extracted_entities JSONB NOT NULL DEFAULT '{}'::JSONB,
    handoff_required BOOLEAN NOT NULL DEFAULT FALSE,
    handoff_reason TEXT,
    model_name VARCHAR(120),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE knowledge_base (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type kb_content_type NOT NULL,
    title VARCHAR(240) NOT NULL,
    body TEXT NOT NULL,
    language VARCHAR(12) NOT NULL DEFAULT 'en-IN',
    source VARCHAR(160) NOT NULL DEFAULT 'internal',
    source_reference TEXT,
    is_published BOOLEAN NOT NULL DEFAULT FALSE,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    embedding vector(1536),
    search_vector TSVECTOR GENERATED ALWAYS AS (to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(body,''))) STORED,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_by UUID REFERENCES users(id),
    approved_by UUID REFERENCES users(id),
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE faqs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    knowledge_base_id UUID REFERENCES knowledge_base(id) ON DELETE SET NULL,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    language VARCHAR(12) NOT NULL DEFAULT 'en-IN',
    category VARCHAR(120),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE crm_sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider crm_provider NOT NULL DEFAULT 'zoho',
    entity_type VARCHAR(80) NOT NULL,
    entity_id UUID NOT NULL,
    operation VARCHAR(80) NOT NULL,
    idempotency_key VARCHAR(180) NOT NULL UNIQUE,
    status sync_status NOT NULL DEFAULT 'pending',
    provider_object_id VARCHAR(160),
    request_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    response_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    error_message TEXT,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_retry_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    channel VARCHAR(40) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(160) NOT NULL,
    entity_type VARCHAR(120),
    entity_id UUID,
    ip_address INET,
    user_agent TEXT,
    before_state JSONB,
    after_state JSONB,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_key VARCHAR(160) NOT NULL UNIQUE,
    setting_value JSONB NOT NULL,
    is_secret BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT,
    updated_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_role_status ON users(role_id, status);
CREATE INDEX idx_agents_available ON agents(is_available) WHERE is_available = TRUE;
CREATE INDEX idx_customers_phone ON customers(phone_number);
CREATE INDEX idx_leads_status_created ON leads(status, created_at DESC);
CREATE INDEX idx_leads_destination ON leads(destination) WHERE destination IS NOT NULL;
CREATE INDEX idx_leads_travel_date ON leads(travel_date) WHERE travel_date IS NOT NULL;
CREATE INDEX idx_calls_status_started ON calls(status, started_at DESC);
CREATE INDEX idx_calls_provider_call ON calls(provider, provider_call_id);
CREATE INDEX idx_calls_customer_started ON calls(customer_id, started_at DESC);
CREATE INDEX idx_call_transcripts_call_seq ON call_transcripts(call_id, sequence_number);
CREATE INDEX idx_call_recordings_call ON call_recordings(call_id);
CREATE INDEX idx_travel_packages_active_destination ON travel_packages(destination_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_kb_embedding ON knowledge_base USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100) WHERE embedding IS NOT NULL;
CREATE INDEX idx_kb_search_vector ON knowledge_base USING GIN (search_vector);
CREATE INDEX idx_kb_published_type_lang ON knowledge_base(content_type, language, is_published);
CREATE INDEX idx_crm_sync_status_retry ON crm_sync_logs(status, next_retry_at);
CREATE INDEX idx_notifications_user_unread ON notifications(user_id, created_at DESC) WHERE read_at IS NULL;
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id, created_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs(actor_user_id, created_at DESC);
