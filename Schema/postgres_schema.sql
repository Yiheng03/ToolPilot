-- PostgreSQL schema for blade tool quotation field catalog and quote values.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE SCHEMA IF NOT EXISTS blade_quote;
SET search_path = blade_quote, public;

DO $$ BEGIN
  CREATE TYPE field_value_kind AS ENUM ('enum', 'percent', 'number', 'grade', 'index', 'integer', 'angle', 'boolean', 'tolerance', 'money', 'duration', 'multiplier', 'days', 'text', 'json');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TYPE field_value_kind ADD VALUE IF NOT EXISTS 'json';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE field_impact_level AS ENUM ('high', 'medium', 'low');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE quote_calculation_status AS ENUM ('queued', 'running', 'succeeded', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_sections (
  section_id text PRIMARY KEY,
  sort_order integer NOT NULL UNIQUE,
  title_zh text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quote_field_groups (
  group_id bigserial PRIMARY KEY,
  section_id text NOT NULL REFERENCES quote_sections(section_id) ON DELETE RESTRICT,
  sort_order integer NOT NULL,
  name_zh text NOT NULL,
  name_en text,
  icon text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (section_id, name_zh),
  UNIQUE (section_id, sort_order)
);

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'quote_field_groups'
      AND column_name = 'name_en'
  ) THEN
    ALTER TABLE quote_field_groups ADD COLUMN name_en text;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS quote_impact_tags (
  tag_code text PRIMARY KEY,
  sort_order integer NOT NULL UNIQUE,
  name_zh text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_impact_tags' AND column_name = 'updated_at') THEN
    ALTER TABLE quote_impact_tags ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS quote_field_definitions (
  field_id bigserial PRIMARY KEY,
  field_code text NOT NULL UNIQUE,
  group_id bigint NOT NULL REFERENCES quote_field_groups(group_id) ON DELETE RESTRICT,
  sort_order integer NOT NULL,
  name_zh text NOT NULL,
  name_en text,
  description text,
  value_kind field_value_kind NOT NULL,
  raw_type_zh text NOT NULL,
  impact_level field_impact_level NOT NULL,
  is_filterable boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, name_zh),
  UNIQUE (group_id, sort_order)
);

WITH legacy_field_code_map(old_code, new_code) AS (
  VALUES
    ('physics_a_12', 'porosity_percent'),
    ('physics_a_13', 'transverse_rupture_strength'),
    ('physics_a_14', 'fracture_toughness_kic'),
    ('physics_a_15', 'hardness_hra_hv'),
    ('physics_a_16', 'thermal_conductivity'),
    ('physics_a_17', 'thermal_expansion_compatibility'),
    ('physics_a_18', 'recycled_tungsten_ratio'),
    ('physics_a_19', 'recycled_cobalt_ratio'),
    ('physics_a_20', 'recoatable_substrate_life'),
    ('physics_a_23', 'residual_strength_after_stripping'),
    ('physics_b_01', 'tool_diameter_d'),
    ('physics_b_02', 'overall_length_oal'),
    ('physics_b_03', 'cutting_length_loc'),
    ('physics_b_04', 'length_to_diameter_ratio'),
    ('physics_b_05', 'flute_count_z'),
    ('physics_b_14', 'helix_flute_depth_coupling'),
    ('physics_b_15', 'grinding_deflection_compensation'),
    ('physics_b_20', 'chamfer_size'),
    ('physics_c_10', 'coolant_hole_sealing_process'),
    ('physics_d_04', 'edge_k_factor_bias'),
    ('physics_d_06', 'k_land_hone_interaction_tolerance'),
    ('physics_d_07', 'edge_hone_radius_tolerance'),
    ('physics_d_08', 'chamfer_hone_overlap_accuracy'),
    ('physics_e_02', 'coating_process_pvd_cvd'),
    ('physics_e_05', 'coating_surface_roughness'),
    ('physics_e_13', 'coating_thickness_uniformity_risk'),
    ('physics_f_01', 'heat_treatment_state'),
    ('physics_f_03', 'artificial_aging_process'),
    ('physics_f_05', 'grinding_residual_stress'),
    ('physics_f_06', 'thermal_cycle_stability'),
    ('physics_f_07', 'dimensional_aging_stability'),
    ('physics_g_08', 'gauge_setup_cost'),
    ('physics_h_03', 'runout'),
    ('physics_h_04', 'coaxiality'),
    ('physics_h_05', 'ball_profile_error'),
    ('physics_h_06', 'surface_roughness_ra'),
    ('physics_h_08', 'batch_traceability'),
    ('market_b_10', 'energy_price_sensitivity'),
    ('market_d_07', 'vmi_ownership_retention_days'),
    ('market_f_11', 'incoterms')
)
UPDATE quote_field_definitions f
SET field_code = m.new_code,
    updated_at = now()
FROM legacy_field_code_map m
WHERE f.field_code = m.old_code
  AND NOT EXISTS (
    SELECT 1
    FROM quote_field_definitions existing
    WHERE existing.field_code = m.new_code
  );

CREATE TABLE IF NOT EXISTS quote_field_definition_tags (
  field_id bigint NOT NULL REFERENCES quote_field_definitions(field_id) ON DELETE CASCADE,
  tag_code text NOT NULL REFERENCES quote_impact_tags(tag_code) ON DELETE RESTRICT,
  PRIMARY KEY (field_id, tag_code)
);

CREATE TABLE IF NOT EXISTS quote_units (
  unit_code text PRIMARY KEY,
  name_zh text NOT NULL,
  name_en text,
  dimension text NOT NULL,
  canonical_unit_code text,
  conversion_factor_to_canonical numeric(24,12),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quote_field_units (
  field_id bigint NOT NULL REFERENCES quote_field_definitions(field_id) ON DELETE CASCADE,
  unit_code text NOT NULL REFERENCES quote_units(unit_code) ON DELETE RESTRICT,
  is_default boolean NOT NULL DEFAULT false,
  PRIMARY KEY (field_id, unit_code)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_quote_field_units_default
ON quote_field_units(field_id)
WHERE is_default;

CREATE TABLE IF NOT EXISTS quote_field_options (
  option_id bigserial PRIMARY KEY,
  field_id bigint NOT NULL REFERENCES quote_field_definitions(field_id) ON DELETE CASCADE,
  option_code text NOT NULL,
  label_zh text NOT NULL,
  label_en text,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (field_id, option_code),
  UNIQUE (field_id, label_zh)
);

CREATE TABLE IF NOT EXISTS quote_field_validation_rules (
  rule_id bigserial PRIMARY KEY,
  field_id bigint NOT NULL REFERENCES quote_field_definitions(field_id) ON DELETE CASCADE,
  rule_code text NOT NULL,
  rule_type text NOT NULL,
  severity text NOT NULL DEFAULT 'error',
  rule_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  error_message_zh text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (field_id, rule_code)
);

DO $$ BEGIN
  ALTER TABLE quote_field_validation_rules
    ADD CONSTRAINT chk_quote_field_validation_rules_type
    CHECK (rule_type IN ('min', 'max', 'range', 'regex', 'option_set', 'json_schema', 'custom')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_field_validation_rules
    ADD CONSTRAINT chk_quote_field_validation_rules_severity
    CHECK (severity IN ('info', 'warning', 'error')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_index_definitions (
  index_id bigserial PRIMARY KEY,
  index_code text NOT NULL UNIQUE,
  name_en text,
  name_zh text NOT NULL,
  layer_zh text,
  description text,
  formula_text text,
  source_field_names text[] NOT NULL DEFAULT ARRAY[]::text[],
  is_active boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quote_index_definition_tags (
  index_id bigint NOT NULL REFERENCES quote_index_definitions(index_id) ON DELETE CASCADE,
  tag_code text NOT NULL REFERENCES quote_impact_tags(tag_code) ON DELETE RESTRICT,
  PRIMARY KEY (index_id, tag_code)
);

CREATE TABLE IF NOT EXISTS quote_index_source_fields (
  index_id bigint NOT NULL REFERENCES quote_index_definitions(index_id) ON DELETE CASCADE,
  field_id bigint NOT NULL REFERENCES quote_field_definitions(field_id) ON DELETE CASCADE,
  weight numeric(12,6),
  role text,
  PRIMARY KEY (index_id, field_id)
);

CREATE TABLE IF NOT EXISTS customers (
  customer_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_code text UNIQUE,
  canonical_name text NOT NULL UNIQUE,
  legal_name text,
  country_code char(2),
  region text,
  customer_status text NOT NULL DEFAULT 'active',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE customers
    ADD CONSTRAINT chk_customers_status
    CHECK (customer_status IN ('active', 'inactive', 'prospect', 'blocked')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE customers
    ADD CONSTRAINT chk_customers_country_code
    CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS customer_aliases (
  alias_id bigserial PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
  alias_name text NOT NULL,
  normalized_alias text NOT NULL UNIQUE,
  alias_type text NOT NULL DEFAULT 'name',
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  source text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (customer_id, alias_name)
);

CREATE TABLE IF NOT EXISTS brands (
  brand_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_code text UNIQUE,
  canonical_name text NOT NULL UNIQUE,
  owner_company text,
  country_code char(2),
  brand_status text NOT NULL DEFAULT 'active',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE brands
    ADD CONSTRAINT chk_brands_status
    CHECK (brand_status IN ('active', 'inactive', 'deprecated', 'unknown')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE brands
    ADD CONSTRAINT chk_brands_country_code
    CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS brand_aliases (
  alias_id bigserial PRIMARY KEY,
  brand_id uuid NOT NULL REFERENCES brands(brand_id) ON DELETE CASCADE,
  alias_name text NOT NULL,
  normalized_alias text NOT NULL UNIQUE,
  alias_type text NOT NULL DEFAULT 'name',
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  source text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (brand_id, alias_name)
);

CREATE TABLE IF NOT EXISTS quote_requests (
  quote_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_no text UNIQUE,
  customer_id uuid REFERENCES customers(customer_id) ON DELETE SET NULL,
  customer_name text,
  requested_at timestamptz,
  status text NOT NULL DEFAULT 'draft',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE quote_requests DROP CONSTRAINT IF EXISTS chk_quote_requests_status;
  ALTER TABLE quote_requests
    ADD CONSTRAINT chk_quote_requests_status
    CHECK (status IN ('draft', 'submitted', 'in_review', 'parsed', 'priced', 'quoted', 'approved', 'accepted', 'rejected', 'cancelled', 'closed', 'archived')) NOT VALID;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_requests' AND column_name = 'customer_id') THEN
    ALTER TABLE quote_requests ADD COLUMN customer_id uuid REFERENCES customers(customer_id) ON DELETE SET NULL;
  END IF;
END $$;

INSERT INTO customers (canonical_name)
SELECT DISTINCT btrim(customer_name)
FROM quote_requests
WHERE customer_id IS NULL
  AND NULLIF(btrim(customer_name), '') IS NOT NULL
ON CONFLICT (canonical_name) DO NOTHING;

INSERT INTO customer_aliases (customer_id, alias_name, normalized_alias, alias_type, source)
SELECT c.customer_id,
       c.canonical_name,
       lower(regexp_replace(c.canonical_name, '\s+', '', 'g')),
       'name',
       'quote_requests.customer_name'
FROM customers c
WHERE NOT EXISTS (
  SELECT 1
  FROM customer_aliases a
  WHERE a.normalized_alias = lower(regexp_replace(c.canonical_name, '\s+', '', 'g'))
)
ON CONFLICT DO NOTHING;

UPDATE quote_requests q
SET customer_id = c.customer_id
FROM customers c
WHERE q.customer_id IS NULL
  AND NULLIF(btrim(q.customer_name), '') IS NOT NULL
  AND btrim(q.customer_name) = c.canonical_name;

CREATE TABLE IF NOT EXISTS raw_quote_files (
  file_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id uuid REFERENCES quote_requests(quote_id) ON DELETE SET NULL,
  file_name text NOT NULL,
  file_type text,
  file_url text,
  source_type text,
  upload_time timestamptz NOT NULL DEFAULT now(),
  ocr_text text,
  parse_status text NOT NULL DEFAULT 'pending',
  parse_confidence numeric(5,4) CHECK (parse_confidence IS NULL OR parse_confidence BETWEEN 0 AND 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE raw_quote_files DROP CONSTRAINT IF EXISTS chk_raw_quote_files_parse_status;
  ALTER TABLE raw_quote_files
    ADD CONSTRAINT chk_raw_quote_files_parse_status
    CHECK (parse_status IN ('pending', 'processing', 'parsed', 'failed', 'needs_review', 'review_required')) NOT VALID;
END $$;

CREATE TABLE IF NOT EXISTS tool_master (
  tool_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id uuid REFERENCES brands(brand_id) ON DELETE SET NULL,
  normalized_name text,
  normalized_model text,
  spec_fingerprint text,
  tool_category text,
  tool_subcategory text,
  structure_type text,
  standard_or_custom text,
  iso_code text,
  application_material_group text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'tool_master' AND column_name = 'brand_id') THEN
    ALTER TABLE tool_master ADD COLUMN brand_id uuid REFERENCES brands(brand_id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'tool_master' AND column_name = 'spec_fingerprint') THEN
    ALTER TABLE tool_master ADD COLUMN spec_fingerprint text;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS suppliers (
  supplier_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_code text UNIQUE,
  canonical_name text NOT NULL UNIQUE,
  legal_name text,
  country_code char(2),
  website text,
  supplier_status text NOT NULL DEFAULT 'active',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE suppliers
    ADD CONSTRAINT chk_suppliers_status
    CHECK (supplier_status IN ('active', 'inactive', 'blocked', 'prospect')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE suppliers
    ADD CONSTRAINT chk_suppliers_country_code
    CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS supplier_aliases (
  alias_id bigserial PRIMARY KEY,
  supplier_id uuid NOT NULL REFERENCES suppliers(supplier_id) ON DELETE CASCADE,
  alias_name text NOT NULL,
  normalized_alias text NOT NULL UNIQUE,
  alias_type text NOT NULL DEFAULT 'name',
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  source text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (supplier_id, alias_name)
);

CREATE TABLE IF NOT EXISTS quote_items (
  quote_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id uuid NOT NULL REFERENCES quote_requests(quote_id) ON DELETE CASCADE,
  line_no integer NOT NULL,
  tool_id uuid REFERENCES tool_master(tool_id) ON DELETE SET NULL,
  source_file_id uuid REFERENCES raw_quote_files(file_id) ON DELETE SET NULL,
  supplier_id uuid REFERENCES suppliers(supplier_id) ON DELETE SET NULL,
  supplier_name text,
  raw_item_name text,
  product_name text,
  tool_family text,
  drawing_no text,
  customer_part_no text,
  supplier_part_no text,
  quantity integer CHECK (quantity IS NULL OR quantity > 0),
  unit text,
  currency char(3),
  quoted_unit_price numeric(18,6),
  quoted_total_price numeric(18,6),
  lead_time_days integer,
  moq integer,
  tax_included boolean,
  item_status text NOT NULL DEFAULT 'draft',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (quote_id, line_no)
);

DO $$ BEGIN
  ALTER TABLE quote_items DROP CONSTRAINT IF EXISTS chk_quote_items_status;
  ALTER TABLE quote_items
    ADD CONSTRAINT chk_quote_items_status
    CHECK (item_status IN ('draft', 'parsed', 'validated', 'normalized', 'priced', 'review_required', 'approved', 'accepted', 'rejected', 'cancelled')) NOT VALID;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_items' AND column_name = 'source_file_id') THEN
    ALTER TABLE quote_items ADD COLUMN source_file_id uuid REFERENCES raw_quote_files(file_id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_items' AND column_name = 'supplier_id') THEN
    ALTER TABLE quote_items ADD COLUMN supplier_id uuid REFERENCES suppliers(supplier_id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_items' AND column_name = 'quoted_unit_price') THEN
    ALTER TABLE quote_items ADD COLUMN quoted_unit_price numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_items' AND column_name = 'quoted_total_price') THEN
    ALTER TABLE quote_items ADD COLUMN quoted_total_price numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_items' AND column_name = 'lead_time_days') THEN
    ALTER TABLE quote_items ADD COLUMN lead_time_days integer;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_items' AND column_name = 'moq') THEN
    ALTER TABLE quote_items ADD COLUMN moq integer;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_items' AND column_name = 'tax_included') THEN
    ALTER TABLE quote_items ADD COLUMN tax_included boolean;
  END IF;
END $$;

INSERT INTO suppliers (canonical_name)
SELECT DISTINCT btrim(supplier_name)
FROM quote_items
WHERE supplier_id IS NULL
  AND NULLIF(btrim(supplier_name), '') IS NOT NULL
ON CONFLICT (canonical_name) DO NOTHING;

INSERT INTO supplier_aliases (supplier_id, alias_name, normalized_alias, alias_type, source)
SELECT s.supplier_id,
       s.canonical_name,
       lower(regexp_replace(s.canonical_name, '\s+', '', 'g')),
       'name',
       'quote_items.supplier_name'
FROM suppliers s
WHERE NOT EXISTS (
  SELECT 1
  FROM supplier_aliases a
  WHERE a.normalized_alias = lower(regexp_replace(s.canonical_name, '\s+', '', 'g'))
)
ON CONFLICT DO NOTHING;

UPDATE quote_items qi
SET supplier_id = s.supplier_id
FROM suppliers s
WHERE qi.supplier_id IS NULL
  AND NULLIF(btrim(qi.supplier_name), '') IS NOT NULL
  AND btrim(qi.supplier_name) = s.canonical_name;

DO $$ BEGIN
  ALTER TABLE quote_items
    ADD CONSTRAINT chk_quote_items_currency
    CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_items
    ADD CONSTRAINT chk_quote_items_price_nonnegative
    CHECK (quoted_unit_price IS NULL OR quoted_unit_price >= 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_items
    ADD CONSTRAINT chk_quote_items_total_nonnegative
    CHECK (quoted_total_price IS NULL OR quoted_total_price >= 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_items
    ADD CONSTRAINT chk_quote_items_lead_time_nonnegative
    CHECK (lead_time_days IS NULL OR lead_time_days >= 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_items
    ADD CONSTRAINT chk_quote_items_moq_positive
    CHECK (moq IS NULL OR moq > 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_commercial_terms (
  quote_item_id uuid PRIMARY KEY REFERENCES quote_items(quote_item_id) ON DELETE CASCADE,
  incoterms text,
  payment_terms text,
  valid_until date,
  quote_validity_days integer,
  tax_rate numeric(8,4),
  discount_rate numeric(8,4),
  freight_cost numeric(18,6),
  price_basis text,
  warranty_terms text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE quote_commercial_terms
    ADD CONSTRAINT chk_quote_commercial_terms_rates
    CHECK (
      (tax_rate IS NULL OR tax_rate BETWEEN 0 AND 1) AND
      (discount_rate IS NULL OR discount_rate BETWEEN 0 AND 1)
    ) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_commercial_terms
    ADD CONSTRAINT chk_quote_commercial_terms_amounts
    CHECK (
      (quote_validity_days IS NULL OR quote_validity_days >= 0) AND
      (freight_cost IS NULL OR freight_cost >= 0)
    ) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_request_commercial_terms (
  quote_id uuid PRIMARY KEY REFERENCES quote_requests(quote_id) ON DELETE CASCADE,
  incoterms text,
  payment_terms text,
  valid_until date,
  tax_rate numeric(8,4),
  freight_cost numeric(18,6),
  price_basis text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE quote_request_commercial_terms
    ADD CONSTRAINT chk_quote_request_commercial_terms_rates
    CHECK (tax_rate IS NULL OR tax_rate BETWEEN 0 AND 1) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_request_commercial_terms
    ADD CONSTRAINT chk_quote_request_commercial_terms_amounts
    CHECK (freight_cost IS NULL OR freight_cost >= 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS tool_specs_normalized (
  spec_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_item_id uuid REFERENCES quote_items(quote_item_id) ON DELETE CASCADE,
  tool_id uuid REFERENCES tool_master(tool_id) ON DELETE SET NULL,
  tool_category text,
  tool_subcategory text,
  structure_type text,
  diameter_mm numeric(18,6),
  overall_length_mm numeric(18,6),
  cutting_length_mm numeric(18,6),
  flute_count integer,
  helix_angle_deg numeric(18,6),
  corner_radius_mm numeric(18,6),
  ball_radius_mm numeric(18,6),
  substrate_type text,
  carbide_grade text,
  coating_type text,
  coating_process text,
  internal_coolant boolean,
  standard_or_custom text,
  precision_grade text,
  raw_spec_text text,
  derived_from_field_values boolean NOT NULL DEFAULT true,
  derivation_version text,
  last_derived_at timestamptz,
  manual_override_reason text,
  spec_parse_confidence numeric(5,4) CHECK (spec_parse_confidence IS NULL OR spec_parse_confidence BETWEEN 0 AND 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'tool_specs_normalized' AND column_name = 'derived_from_field_values') THEN
    ALTER TABLE tool_specs_normalized ADD COLUMN derived_from_field_values boolean NOT NULL DEFAULT true;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'tool_specs_normalized' AND column_name = 'derivation_version') THEN
    ALTER TABLE tool_specs_normalized ADD COLUMN derivation_version text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'tool_specs_normalized' AND column_name = 'last_derived_at') THEN
    ALTER TABLE tool_specs_normalized ADD COLUMN last_derived_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'tool_specs_normalized' AND column_name = 'manual_override_reason') THEN
    ALTER TABLE tool_specs_normalized ADD COLUMN manual_override_reason text;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION validate_tool_specs_normalized_derivation()
RETURNS trigger AS $$
BEGIN
  IF NEW.derived_from_field_values IS FALSE AND NULLIF(btrim(NEW.manual_override_reason), '') IS NULL THEN
    RAISE EXCEPTION 'manual tool_specs_normalized overrides require manual_override_reason';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_tool_specs_normalized_validate_derivation' AND tgrelid = 'tool_specs_normalized'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_tool_specs_normalized_validate_derivation ON tool_specs_normalized';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_tool_specs_normalized_validate_derivation BEFORE INSERT OR UPDATE ON tool_specs_normalized FOR EACH ROW EXECUTE FUNCTION validate_tool_specs_normalized_derivation()';
END $$;

DO $$ BEGIN
  ALTER TABLE tool_specs_normalized
    ADD CONSTRAINT chk_tool_specs_positive_dimensions
    CHECK (
      (diameter_mm IS NULL OR diameter_mm > 0) AND
      (overall_length_mm IS NULL OR overall_length_mm > 0) AND
      (cutting_length_mm IS NULL OR cutting_length_mm > 0) AND
      (corner_radius_mm IS NULL OR corner_radius_mm >= 0) AND
      (ball_radius_mm IS NULL OR ball_radius_mm >= 0)
    ) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE tool_specs_normalized
    ADD CONSTRAINT chk_tool_specs_flute_count
    CHECK (flute_count IS NULL OR flute_count > 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE tool_specs_normalized
    ADD CONSTRAINT chk_tool_specs_helix_angle
    CHECK (helix_angle_deg IS NULL OR helix_angle_deg BETWEEN 0 AND 90) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_field_values (
  quote_item_id uuid NOT NULL REFERENCES quote_items(quote_item_id) ON DELETE CASCADE,
  field_id bigint NOT NULL REFERENCES quote_field_definitions(field_id) ON DELETE RESTRICT,
  source_file_id uuid REFERENCES raw_quote_files(file_id) ON DELETE SET NULL,
  value_text text,
  value_numeric numeric(18,6),
  value_boolean boolean,
  value_json jsonb,
  unit text,
  unit_code text REFERENCES quote_units(unit_code) ON DELETE RESTRICT,
  source text,
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (quote_item_id, field_id),
  CHECK (value_text IS NOT NULL OR value_numeric IS NOT NULL OR value_boolean IS NOT NULL OR value_json IS NOT NULL)
);

CREATE OR REPLACE FUNCTION validate_quote_field_value()
RETURNS trigger AS $$
DECLARE
  expected_kind field_value_kind;
  populated_value_count integer;
  has_option_set boolean;
  option_is_valid boolean;
  validation_rule record;
BEGIN
  SELECT value_kind INTO expected_kind
  FROM quote_field_definitions
  WHERE field_id = NEW.field_id;

  IF expected_kind IS NULL THEN
    RAISE EXCEPTION 'Unknown quote field_id %', NEW.field_id;
  END IF;

  populated_value_count :=
    (NEW.value_text IS NOT NULL)::integer +
    (NEW.value_numeric IS NOT NULL)::integer +
    (NEW.value_boolean IS NOT NULL)::integer +
    (NEW.value_json IS NOT NULL)::integer;

  IF populated_value_count <> 1 THEN
    RAISE EXCEPTION 'quote_field_values requires exactly one canonical value column, got %', populated_value_count;
  END IF;

  IF expected_kind IN ('enum', 'grade', 'text') AND NEW.value_text IS NULL THEN
    RAISE EXCEPTION 'field value_kind % must use value_text', expected_kind;
  ELSIF expected_kind IN ('number', 'percent', 'money', 'days', 'integer', 'angle', 'index', 'multiplier', 'duration') AND NEW.value_numeric IS NULL THEN
    RAISE EXCEPTION 'field value_kind % must use value_numeric', expected_kind;
  ELSIF expected_kind = 'boolean' AND NEW.value_boolean IS NULL THEN
    RAISE EXCEPTION 'field value_kind boolean must use value_boolean';
  ELSIF expected_kind IN ('tolerance', 'json') AND NEW.value_json IS NULL THEN
    RAISE EXCEPTION 'field value_kind % must use value_json', expected_kind;
  END IF;

  IF expected_kind = 'percent' AND (NEW.value_numeric < 0 OR NEW.value_numeric > 100) THEN
    RAISE EXCEPTION 'percent field_id % value % must be between 0 and 100', NEW.field_id, NEW.value_numeric;
  END IF;

  IF expected_kind IN ('integer', 'days') AND NEW.value_numeric <> trunc(NEW.value_numeric) THEN
    RAISE EXCEPTION 'field value_kind % must be an integer numeric value', expected_kind;
  END IF;

  FOR validation_rule IN
    SELECT rule_code, rule_type, rule_config, error_message_zh
    FROM quote_field_validation_rules
    WHERE field_id = NEW.field_id
      AND is_active
      AND severity = 'error'
      AND rule_type IN ('min', 'max', 'range')
  LOOP
    IF validation_rule.rule_type = 'min'
       AND NEW.value_numeric IS NOT NULL
       AND validation_rule.rule_config ? 'min'
       AND NEW.value_numeric < (validation_rule.rule_config->>'min')::numeric THEN
      RAISE EXCEPTION 'field_id % failed validation rule %: %', NEW.field_id, validation_rule.rule_code, COALESCE(validation_rule.error_message_zh, 'value below minimum');
    ELSIF validation_rule.rule_type = 'max'
       AND NEW.value_numeric IS NOT NULL
       AND validation_rule.rule_config ? 'max'
       AND NEW.value_numeric > (validation_rule.rule_config->>'max')::numeric THEN
      RAISE EXCEPTION 'field_id % failed validation rule %: %', NEW.field_id, validation_rule.rule_code, COALESCE(validation_rule.error_message_zh, 'value above maximum');
    ELSIF validation_rule.rule_type = 'range'
       AND NEW.value_numeric IS NOT NULL
       AND validation_rule.rule_config ? 'min'
       AND validation_rule.rule_config ? 'max'
       AND (NEW.value_numeric < (validation_rule.rule_config->>'min')::numeric OR NEW.value_numeric > (validation_rule.rule_config->>'max')::numeric) THEN
      RAISE EXCEPTION 'field_id % failed validation rule %: %', NEW.field_id, validation_rule.rule_code, COALESCE(validation_rule.error_message_zh, 'value outside allowed range');
    END IF;
  END LOOP;

  IF expected_kind = 'enum' THEN
    SELECT EXISTS (
      SELECT 1
      FROM quote_field_options
      WHERE field_id = NEW.field_id
        AND is_active
    ) INTO has_option_set;

    IF NOT has_option_set THEN
      RAISE EXCEPTION 'enum field_id % has no active option set', NEW.field_id;
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM quote_field_options
      WHERE field_id = NEW.field_id
        AND option_code = NEW.value_text
        AND is_active
    ) INTO option_is_valid;

    IF NOT option_is_valid THEN
      RAISE EXCEPTION 'enum field_id % value % is not an active option_code', NEW.field_id, NEW.value_text;
    END IF;
  END IF;

  IF NEW.unit_code IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM quote_field_units
    WHERE field_id = NEW.field_id
      AND unit_code = NEW.unit_code
  ) THEN
    RAISE EXCEPTION 'unit_code % is not allowed for field_id %', NEW.unit_code, NEW.field_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_field_values_validate' AND tgrelid = 'quote_field_values'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_field_values_validate ON quote_field_values';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_field_values_validate BEFORE INSERT OR UPDATE ON quote_field_values FOR EACH ROW EXECUTE FUNCTION validate_quote_field_value()';
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'source_file_id') THEN
    ALTER TABLE quote_field_values ADD COLUMN source_file_id uuid REFERENCES raw_quote_files(file_id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'unit_code') THEN
    ALTER TABLE quote_field_values ADD COLUMN unit_code text REFERENCES quote_units(unit_code) ON DELETE RESTRICT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'raw_value_text') THEN
    ALTER TABLE quote_field_values ADD COLUMN raw_value_text text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'normalized_value_text') THEN
    ALTER TABLE quote_field_values ADD COLUMN normalized_value_text text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'source_page') THEN
    ALTER TABLE quote_field_values ADD COLUMN source_page integer;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'source_cell') THEN
    ALTER TABLE quote_field_values ADD COLUMN source_cell text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'source_bbox') THEN
    ALTER TABLE quote_field_values ADD COLUMN source_bbox jsonb;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'extraction_method') THEN
    ALTER TABLE quote_field_values ADD COLUMN extraction_method text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'validation_status') THEN
    ALTER TABLE quote_field_values ADD COLUMN validation_status text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_field_values' AND column_name = 'normalization_rule_version') THEN
    ALTER TABLE quote_field_values ADD COLUMN normalization_rule_version text;
  END IF;
END $$;

DO $$ BEGIN
  ALTER TABLE quote_field_values DROP CONSTRAINT IF EXISTS chk_quote_field_values_validation_status;
  ALTER TABLE quote_field_values
    ADD CONSTRAINT chk_quote_field_values_validation_status
    CHECK (validation_status IS NULL OR validation_status IN ('unvalidated', 'valid', 'warning', 'error', 'needs_review', 'review_required')) NOT VALID;
END $$;

DO $$ BEGIN
  ALTER TABLE quote_field_values
    ADD CONSTRAINT chk_quote_field_values_single_canonical_value
    CHECK (num_nonnulls(value_text, value_numeric, value_boolean, value_json) = 1) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_field_value_candidates (
  candidate_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_item_id uuid NOT NULL REFERENCES quote_items(quote_item_id) ON DELETE CASCADE,
  field_id bigint NOT NULL REFERENCES quote_field_definitions(field_id) ON DELETE RESTRICT,
  source_file_id uuid REFERENCES raw_quote_files(file_id) ON DELETE SET NULL,
  raw_value_text text,
  candidate_value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  extraction_method text,
  source_page integer,
  source_cell text,
  source_bbox jsonb,
  is_selected boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quote_calculation_runs (
  run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id uuid NOT NULL REFERENCES quote_requests(quote_id) ON DELETE CASCADE,
  ruleset_version text NOT NULL,
  model_version text,
  input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by text,
  status quote_calculation_status NOT NULL DEFAULT 'queued',
  error_message text,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE IF NOT EXISTS quote_index_values (
  run_id uuid NOT NULL REFERENCES quote_calculation_runs(run_id) ON DELETE CASCADE,
  quote_item_id uuid NOT NULL REFERENCES quote_items(quote_item_id) ON DELETE CASCADE,
  index_id bigint NOT NULL REFERENCES quote_index_definitions(index_id) ON DELETE RESTRICT,
  score numeric(18,6),
  value_numeric numeric(18,6),
  cost_multiplier numeric(18,6),
  risk_level text,
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  top_driver_fields jsonb NOT NULL DEFAULT '[]'::jsonb,
  calculation_version text,
  explanation text,
  input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id, quote_item_id, index_id)
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_index_values' AND column_name = 'run_id') THEN
    ALTER TABLE quote_index_values ADD COLUMN run_id uuid REFERENCES quote_calculation_runs(run_id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_index_values' AND column_name = 'cost_multiplier') THEN
    ALTER TABLE quote_index_values ADD COLUMN cost_multiplier numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_index_values' AND column_name = 'risk_level') THEN
    ALTER TABLE quote_index_values ADD COLUMN risk_level text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_index_values' AND column_name = 'confidence') THEN
    ALTER TABLE quote_index_values ADD COLUMN confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_index_values' AND column_name = 'top_driver_fields') THEN
    ALTER TABLE quote_index_values ADD COLUMN top_driver_fields jsonb NOT NULL DEFAULT '[]'::jsonb;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_index_values' AND column_name = 'calculation_version') THEN
    ALTER TABLE quote_index_values ADD COLUMN calculation_version text;
  END IF;
END $$;

DO $$ BEGIN
  ALTER TABLE quote_index_values
    ADD CONSTRAINT chk_quote_index_values_risk_level
    CHECK (risk_level IS NULL OR risk_level IN ('low', 'medium', 'high', 'critical')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_price_outputs (
  price_output_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES quote_calculation_runs(run_id) ON DELETE CASCADE,
  quote_item_id uuid NOT NULL REFERENCES quote_items(quote_item_id) ON DELETE CASCADE,
  currency char(3),
  base_cost numeric(18,6),
  material_cost numeric(18,6),
  manufacturing_cost numeric(18,6),
  coating_cost numeric(18,6),
  inspection_cost numeric(18,6),
  logistics_cost numeric(18,6),
  setup_cost numeric(18,6),
  nre_cost numeric(18,6),
  tooling_consumable_cost numeric(18,6),
  packaging_cost numeric(18,6),
  finance_cost numeric(18,6),
  compliance_cost numeric(18,6),
  tariff_cost numeric(18,6),
  fx_adjustment numeric(18,6),
  risk_premium numeric(18,6),
  commercial_adjustment numeric(18,6),
  margin numeric(18,6),
  price_lower_bound numeric(18,6),
  price_upper_bound numeric(18,6),
  price_reasonableness text,
  recommendation text,
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  calculation_version text,
  final_unit_price numeric(18,6),
  breakdown jsonb NOT NULL DEFAULT '{}'::jsonb,
  calculated_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_quote_price_outputs_run_item UNIQUE (run_id, quote_item_id)
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'price_output_id') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN price_output_id uuid DEFAULT gen_random_uuid();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'run_id') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN run_id uuid REFERENCES quote_calculation_runs(run_id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'currency') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN currency char(3);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'setup_cost') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN setup_cost numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'nre_cost') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN nre_cost numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'tooling_consumable_cost') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN tooling_consumable_cost numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'packaging_cost') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN packaging_cost numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'finance_cost') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN finance_cost numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'compliance_cost') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN compliance_cost numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'tariff_cost') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN tariff_cost numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'fx_adjustment') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN fx_adjustment numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'margin') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN margin numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'price_lower_bound') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN price_lower_bound numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'price_upper_bound') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN price_upper_bound numeric(18,6);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'price_reasonableness') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN price_reasonableness text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'recommendation') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN recommendation text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'confidence') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'calculation_version') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN calculation_version text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_outputs' AND column_name = 'updated_at') THEN
    ALTER TABLE quote_price_outputs ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;
END $$;

DO $$
DECLARE
  current_pk_name text;
  current_pk_cols text[];
BEGIN
  INSERT INTO quote_calculation_runs (quote_id, ruleset_version, input_snapshot, created_by, status, started_at, finished_at)
  SELECT DISTINCT qi.quote_id, 'legacy-migration', '{}'::jsonb, 'schema_migration', 'succeeded'::quote_calculation_status, now(), now()
  FROM quote_index_values qiv
  JOIN quote_items qi ON qi.quote_item_id = qiv.quote_item_id
  WHERE qiv.run_id IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM quote_calculation_runs r
      WHERE r.quote_id = qi.quote_id
        AND r.ruleset_version = 'legacy-migration'
        AND r.created_by = 'schema_migration'
    );

  INSERT INTO quote_calculation_runs (quote_id, ruleset_version, input_snapshot, created_by, status, started_at, finished_at)
  SELECT DISTINCT qi.quote_id, 'legacy-migration', '{}'::jsonb, 'schema_migration', 'succeeded'::quote_calculation_status, now(), now()
  FROM quote_price_outputs qpo
  JOIN quote_items qi ON qi.quote_item_id = qpo.quote_item_id
  WHERE qpo.run_id IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM quote_calculation_runs r
      WHERE r.quote_id = qi.quote_id
        AND r.ruleset_version = 'legacy-migration'
        AND r.created_by = 'schema_migration'
    );

  UPDATE quote_index_values qiv
  SET run_id = r.run_id
  FROM quote_items qi
  JOIN LATERAL (
    SELECT run_id
    FROM quote_calculation_runs
    WHERE quote_id = qi.quote_id
      AND ruleset_version = 'legacy-migration'
      AND created_by = 'schema_migration'
    ORDER BY created_at DESC, started_at DESC
    LIMIT 1
  ) r ON true
  WHERE qiv.quote_item_id = qi.quote_item_id
    AND qiv.run_id IS NULL;

  UPDATE quote_price_outputs qpo
  SET run_id = r.run_id
  FROM quote_items qi
  JOIN LATERAL (
    SELECT run_id
    FROM quote_calculation_runs
    WHERE quote_id = qi.quote_id
      AND ruleset_version = 'legacy-migration'
      AND created_by = 'schema_migration'
    ORDER BY created_at DESC, started_at DESC
    LIMIT 1
  ) r ON true
  WHERE qpo.quote_item_id = qi.quote_item_id
    AND qpo.run_id IS NULL;

  UPDATE quote_price_outputs
  SET price_output_id = gen_random_uuid()
  WHERE price_output_id IS NULL;

  ALTER TABLE quote_index_values ALTER COLUMN run_id SET NOT NULL;
  ALTER TABLE quote_price_outputs ALTER COLUMN run_id SET NOT NULL;
  ALTER TABLE quote_price_outputs ALTER COLUMN quote_item_id SET NOT NULL;
  ALTER TABLE quote_price_outputs ALTER COLUMN price_output_id SET DEFAULT gen_random_uuid();
  ALTER TABLE quote_price_outputs ALTER COLUMN price_output_id SET NOT NULL;

  SELECT c.conname, array_agg(a.attname::text ORDER BY cols.ordinality)
  INTO current_pk_name, current_pk_cols
  FROM pg_constraint c
  JOIN unnest(c.conkey) WITH ORDINALITY AS cols(attnum, ordinality) ON true
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = cols.attnum
  WHERE c.conrelid = 'quote_index_values'::regclass
    AND c.contype = 'p'
  GROUP BY c.conname;

  IF current_pk_name IS NOT NULL AND current_pk_cols <> ARRAY['run_id', 'quote_item_id', 'index_id']::text[] THEN
    EXECUTE format('ALTER TABLE quote_index_values DROP CONSTRAINT %I', current_pk_name);
    current_pk_name := NULL;
  END IF;

  IF current_pk_name IS NULL THEN
    ALTER TABLE quote_index_values ADD CONSTRAINT quote_index_values_pkey PRIMARY KEY (run_id, quote_item_id, index_id);
  END IF;

  SELECT c.conname, array_agg(a.attname::text ORDER BY cols.ordinality)
  INTO current_pk_name, current_pk_cols
  FROM pg_constraint c
  JOIN unnest(c.conkey) WITH ORDINALITY AS cols(attnum, ordinality) ON true
  JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = cols.attnum
  WHERE c.conrelid = 'quote_price_outputs'::regclass
    AND c.contype = 'p'
  GROUP BY c.conname;

  IF current_pk_name IS NOT NULL AND current_pk_cols <> ARRAY['price_output_id']::text[] THEN
    EXECUTE format('ALTER TABLE quote_price_outputs DROP CONSTRAINT %I', current_pk_name);
    current_pk_name := NULL;
  END IF;

  IF current_pk_name IS NULL THEN
    ALTER TABLE quote_price_outputs ADD CONSTRAINT quote_price_outputs_pkey PRIMARY KEY (price_output_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN unnest(c.conkey) WITH ORDINALITY AS cols(attnum, ordinality) ON true
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = cols.attnum
    WHERE c.conrelid = 'quote_price_outputs'::regclass
      AND c.contype = 'u'
    GROUP BY c.oid
    HAVING array_agg(a.attname::text ORDER BY cols.ordinality) = ARRAY['run_id', 'quote_item_id']::text[]
  ) THEN
    ALTER TABLE quote_price_outputs
      ADD CONSTRAINT uq_quote_price_outputs_run_item UNIQUE (run_id, quote_item_id);
  END IF;
END $$;

DO $$ BEGIN
  ALTER TABLE quote_price_outputs
    ADD CONSTRAINT chk_quote_price_outputs_currency
    CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_price_outputs
    ADD CONSTRAINT chk_quote_price_outputs_nonnegative_amounts
    CHECK (
      (base_cost IS NULL OR base_cost >= 0) AND
      (material_cost IS NULL OR material_cost >= 0) AND
      (manufacturing_cost IS NULL OR manufacturing_cost >= 0) AND
      (coating_cost IS NULL OR coating_cost >= 0) AND
      (inspection_cost IS NULL OR inspection_cost >= 0) AND
      (logistics_cost IS NULL OR logistics_cost >= 0) AND
      (setup_cost IS NULL OR setup_cost >= 0) AND
      (nre_cost IS NULL OR nre_cost >= 0) AND
      (tooling_consumable_cost IS NULL OR tooling_consumable_cost >= 0) AND
      (packaging_cost IS NULL OR packaging_cost >= 0) AND
      (finance_cost IS NULL OR finance_cost >= 0) AND
      (compliance_cost IS NULL OR compliance_cost >= 0) AND
      (tariff_cost IS NULL OR tariff_cost >= 0) AND
      (risk_premium IS NULL OR risk_premium >= 0) AND
      (margin IS NULL OR margin >= 0) AND
      (price_lower_bound IS NULL OR price_lower_bound >= 0) AND
      (price_upper_bound IS NULL OR price_upper_bound >= 0) AND
      (final_unit_price IS NULL OR final_unit_price >= 0)
    ) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_price_outputs
    ADD CONSTRAINT chk_quote_price_outputs_price_bounds
    CHECK (price_lower_bound IS NULL OR price_upper_bound IS NULL OR price_lower_bound <= price_upper_bound) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_price_outputs
    ADD CONSTRAINT chk_quote_price_outputs_reasonableness
    CHECK (price_reasonableness IS NULL OR price_reasonableness IN ('below_market', 'fair', 'above_market', 'outlier', 'unknown')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_price_output_components (
  component_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  price_output_id uuid NOT NULL REFERENCES quote_price_outputs(price_output_id) ON DELETE CASCADE,
  component_code text NOT NULL,
  component_order integer,
  component_name_zh text,
  amount numeric(18,6),
  multiplier numeric(18,6),
  driver_field_id bigint REFERENCES quote_field_definitions(field_id) ON DELETE SET NULL,
  explanation text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'quote_price_output_components' AND column_name = 'component_order') THEN
    ALTER TABLE quote_price_output_components ADD COLUMN component_order integer;
  END IF;
END $$;

DO $$ BEGIN
  ALTER TABLE quote_price_output_components
    ADD CONSTRAINT chk_quote_price_output_components_amounts
    CHECK (
      (amount IS NULL OR amount >= 0) AND
      (multiplier IS NULL OR multiplier >= 0)
    ) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS historical_tool_prices (
  price_history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  price_type text NOT NULL,
  supplier_id uuid REFERENCES suppliers(supplier_id) ON DELETE SET NULL,
  supplier_name_raw text,
  tool_id uuid REFERENCES tool_master(tool_id) ON DELETE SET NULL,
  source_quote_item_id uuid REFERENCES quote_items(quote_item_id) ON DELETE SET NULL,
  source_document_id uuid REFERENCES raw_quote_files(file_id) ON DELETE SET NULL,
  observed_at timestamptz NOT NULL,
  effective_date date,
  currency char(3) NOT NULL,
  unit text,
  unit_price numeric(18,6) NOT NULL,
  total_price numeric(18,6),
  quantity numeric(18,6),
  moq integer,
  lead_time_days integer,
  payment_terms_days integer,
  incoterms text,
  market_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  feature_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_historical_tool_prices_source_quote_item_type
ON historical_tool_prices(price_type, source_quote_item_id)
WHERE source_quote_item_id IS NOT NULL;

DO $$ BEGIN
  ALTER TABLE historical_tool_prices
    ADD CONSTRAINT chk_historical_tool_prices_type
    CHECK (price_type IN ('supplier_quote', 'customer_quote', 'purchase_order', 'invoice', 'deal', 'manual_benchmark')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE historical_tool_prices
    ADD CONSTRAINT chk_historical_tool_prices_currency
    CHECK (currency ~ '^[A-Z]{3}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE historical_tool_prices
    ADD CONSTRAINT chk_historical_tool_prices_amounts
    CHECK (
      unit_price >= 0 AND
      (total_price IS NULL OR total_price >= 0) AND
      (quantity IS NULL OR quantity > 0) AND
      (moq IS NULL OR moq > 0) AND
      (lead_time_days IS NULL OR lead_time_days >= 0) AND
      (payment_terms_days IS NULL OR payment_terms_days >= 0)
    ) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

INSERT INTO historical_tool_prices (
  price_type,
  supplier_id,
  supplier_name_raw,
  tool_id,
  source_quote_item_id,
  source_document_id,
  observed_at,
  currency,
  unit,
  unit_price,
  total_price,
  quantity,
  moq,
  lead_time_days,
  notes
)
SELECT
  'supplier_quote',
  qi.supplier_id,
  qi.supplier_name,
  qi.tool_id,
  qi.quote_item_id,
  qi.source_file_id,
  COALESCE(q.requested_at, qi.created_at),
  qi.currency,
  qi.unit,
  qi.quoted_unit_price,
  qi.quoted_total_price,
  qi.quantity,
  qi.moq,
  qi.lead_time_days,
  'Migrated from quote_items quoted price'
FROM quote_items qi
JOIN quote_requests q ON q.quote_id = qi.quote_id
WHERE qi.quoted_unit_price IS NOT NULL
  AND qi.currency IS NOT NULL
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS market_price_series (
  series_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  commodity_code text NOT NULL,
  commodity_name text NOT NULL,
  price_date date NOT NULL,
  price numeric(18,6) NOT NULL,
  currency char(3) NOT NULL,
  unit text NOT NULL,
  source text,
  market_region text,
  price_kind text NOT NULL DEFAULT 'spot',
  contract_month date,
  tax_included boolean,
  quality_grade text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'market_price_series' AND column_name = 'market_region') THEN
    ALTER TABLE market_price_series ADD COLUMN market_region text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'market_price_series' AND column_name = 'price_kind') THEN
    ALTER TABLE market_price_series ADD COLUMN price_kind text NOT NULL DEFAULT 'spot';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'market_price_series' AND column_name = 'contract_month') THEN
    ALTER TABLE market_price_series ADD COLUMN contract_month date;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'market_price_series' AND column_name = 'tax_included') THEN
    ALTER TABLE market_price_series ADD COLUMN tax_included boolean;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'market_price_series' AND column_name = 'quality_grade') THEN
    ALTER TABLE market_price_series ADD COLUMN quality_grade text;
  END IF;
END $$;

DO $$ BEGIN
  ALTER TABLE market_price_series DROP CONSTRAINT IF EXISTS market_price_series_commodity_code_price_date_source_key;
END $$;

DO $$ BEGIN
  ALTER TABLE market_price_series
    ADD CONSTRAINT chk_market_price_series_currency
    CHECK (currency ~ '^[A-Z]{3}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE market_price_series
    ADD CONSTRAINT chk_market_price_series_price_nonnegative
    CHECK (price >= 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS fx_rates (
  rate_date date NOT NULL,
  base_currency char(3) NOT NULL,
  quote_currency char(3) NOT NULL,
  rate numeric(18,8) NOT NULL,
  source text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (rate_date, base_currency, quote_currency)
);

DO $$ BEGIN
  ALTER TABLE fx_rates
    ADD CONSTRAINT chk_fx_rates_currency
    CHECK (base_currency ~ '^[A-Z]{3}$' AND quote_currency ~ '^[A-Z]{3}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE fx_rates
    ADD CONSTRAINT chk_fx_rates_rate_positive
    CHECK (rate > 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS supplier_price_observations (
  observation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id uuid REFERENCES suppliers(supplier_id) ON DELETE SET NULL,
  tool_id uuid REFERENCES tool_master(tool_id) ON DELETE SET NULL,
  quote_item_id uuid REFERENCES quote_items(quote_item_id) ON DELETE SET NULL,
  observed_at timestamptz NOT NULL DEFAULT now(),
  currency char(3),
  unit_price numeric(18,6),
  quantity integer,
  lead_time_days integer,
  source text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE supplier_price_observations
    ADD CONSTRAINT chk_supplier_price_observations_currency
    CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE supplier_price_observations
    ADD CONSTRAINT chk_supplier_price_observations_amounts
    CHECK (
      (unit_price IS NULL OR unit_price >= 0) AND
      (quantity IS NULL OR quantity > 0) AND
      (lead_time_days IS NULL OR lead_time_days >= 0)
    ) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

INSERT INTO supplier_price_observations (
  supplier_id,
  tool_id,
  quote_item_id,
  observed_at,
  currency,
  unit_price,
  quantity,
  lead_time_days,
  source
)
SELECT
  qi.supplier_id,
  qi.tool_id,
  qi.quote_item_id,
  COALESCE(q.requested_at, qi.created_at),
  qi.currency,
  qi.quoted_unit_price,
  qi.quantity,
  qi.lead_time_days,
  'quote_items'
FROM quote_items qi
JOIN quote_requests q ON q.quote_id = qi.quote_id
WHERE qi.quoted_unit_price IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM supplier_price_observations spo
    WHERE spo.quote_item_id = qi.quote_item_id
  );

CREATE TABLE IF NOT EXISTS market_indicator_definitions (
  indicator_id bigserial PRIMARY KEY,
  indicator_code text NOT NULL UNIQUE,
  name_zh text NOT NULL,
  name_en text,
  category text NOT NULL,
  value_unit text NOT NULL,
  currency char(3),
  source_name text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE market_indicator_definitions
    ADD CONSTRAINT chk_market_indicator_definitions_currency
    CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS market_indicator_values (
  indicator_id bigint NOT NULL REFERENCES market_indicator_definitions(indicator_id) ON DELETE CASCADE,
  observed_at timestamptz NOT NULL,
  value_numeric numeric(24,8) NOT NULL,
  source_name text,
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (indicator_id, observed_at)
);

DO $$ BEGIN
  ALTER TABLE market_indicator_values
    ADD CONSTRAINT chk_market_indicator_values_nonnegative
    CHECK (value_numeric >= 0) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS prediction_models (
  model_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_code text NOT NULL,
  model_version text NOT NULL,
  model_type text NOT NULL,
  target_name text NOT NULL,
  artifact_uri text,
  training_data_range tstzrange,
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  feature_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'candidate',
  registered_by text,
  registered_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (model_code, model_version)
);

DO $$ BEGIN
  ALTER TABLE prediction_models
    ADD CONSTRAINT chk_prediction_models_status
    CHECK (status IN ('candidate', 'active', 'deprecated', 'archived')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS quote_feature_snapshots (
  feature_snapshot_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_item_id uuid REFERENCES quote_items(quote_item_id) ON DELETE CASCADE,
  run_id uuid REFERENCES quote_calculation_runs(run_id) ON DELETE SET NULL,
  feature_version text NOT NULL,
  feature_values jsonb NOT NULL,
  market_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_field_value_hash text,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quote_prediction_results (
  prediction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  feature_snapshot_id uuid NOT NULL REFERENCES quote_feature_snapshots(feature_snapshot_id) ON DELETE CASCADE,
  model_id uuid NOT NULL REFERENCES prediction_models(model_id) ON DELETE RESTRICT,
  run_id uuid REFERENCES quote_calculation_runs(run_id) ON DELETE SET NULL,
  prediction_type text NOT NULL,
  currency char(3),
  predicted_unit_price numeric(18,6),
  predicted_lower_bound numeric(18,6),
  predicted_upper_bound numeric(18,6),
  confidence numeric(5,4) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  prediction_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  explanation jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (feature_snapshot_id, model_id, prediction_type)
);

DO $$ BEGIN
  ALTER TABLE quote_prediction_results
    ADD CONSTRAINT chk_quote_prediction_results_type
    CHECK (prediction_type IN ('unit_price', 'price_reasonableness', 'lead_time', 'supplier_sensitivity', 'risk_score')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_prediction_results
    ADD CONSTRAINT chk_quote_prediction_results_currency
    CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$') NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE quote_prediction_results
    ADD CONSTRAINT chk_quote_prediction_results_bounds
    CHECK (
      (predicted_unit_price IS NULL OR predicted_unit_price >= 0) AND
      (predicted_lower_bound IS NULL OR predicted_lower_bound >= 0) AND
      (predicted_upper_bound IS NULL OR predicted_upper_bound >= 0) AND
      (predicted_lower_bound IS NULL OR predicted_upper_bound IS NULL OR predicted_lower_bound <= predicted_upper_bound)
    ) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION validate_calculation_run_quote_item()
RETURNS trigger AS $$
DECLARE
  run_quote_id uuid;
  item_quote_id uuid;
BEGIN
  SELECT quote_id INTO run_quote_id
  FROM quote_calculation_runs
  WHERE run_id = NEW.run_id;

  SELECT quote_id INTO item_quote_id
  FROM quote_items
  WHERE quote_item_id = NEW.quote_item_id;

  IF run_quote_id IS NULL OR item_quote_id IS NULL OR run_quote_id <> item_quote_id THEN
    RAISE EXCEPTION 'calculation run % does not belong to quote item %', NEW.run_id, NEW.quote_item_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_index_values_validate_run_item' AND tgrelid = 'quote_index_values'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_index_values_validate_run_item ON quote_index_values';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_index_values_validate_run_item BEFORE INSERT OR UPDATE ON quote_index_values FOR EACH ROW EXECUTE FUNCTION validate_calculation_run_quote_item()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_price_outputs_validate_run_item' AND tgrelid = 'quote_price_outputs'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_price_outputs_validate_run_item ON quote_price_outputs';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_price_outputs_validate_run_item BEFORE INSERT OR UPDATE ON quote_price_outputs FOR EACH ROW EXECUTE FUNCTION validate_calculation_run_quote_item()';
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'tool_specs_normalized'::regclass
      AND conname = 'uq_tool_specs_normalized_quote_item'
  ) AND to_regclass('blade_quote.uq_tool_specs_normalized_quote_item') IS NULL THEN
    ALTER TABLE tool_specs_normalized
      ADD CONSTRAINT uq_tool_specs_normalized_quote_item UNIQUE (quote_item_id);
  END IF;
END $$;

-- Seed sections from Datafield.txt
INSERT INTO quote_sections (section_id, sort_order, title_zh, description) VALUES ('physics', 1, '物理与制造层面', NULL) ON CONFLICT (section_id) DO UPDATE SET sort_order = EXCLUDED.sort_order, title_zh = EXCLUDED.title_zh, description = EXCLUDED.description, updated_at = now();
INSERT INTO quote_sections (section_id, sort_order, title_zh, description) VALUES ('market', 2, '市场与非物理层面', NULL) ON CONFLICT (section_id) DO UPDATE SET sort_order = EXCLUDED.sort_order, title_zh = EXCLUDED.title_zh, description = EXCLUDED.description, updated_at = now();

-- Seed impact tags from Dashboard.html
INSERT INTO quote_impact_tags (tag_code, sort_order, name_zh) VALUES ('tag_01', 1, '材料成本') ON CONFLICT (tag_code) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh;
INSERT INTO quote_impact_tags (tag_code, sort_order, name_zh) VALUES ('tag_02', 2, '加工难度') ON CONFLICT (tag_code) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh;
INSERT INTO quote_impact_tags (tag_code, sort_order, name_zh) VALUES ('tag_03', 3, '涂层分摊') ON CONFLICT (tag_code) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh;
INSERT INTO quote_impact_tags (tag_code, sort_order, name_zh) VALUES ('tag_04', 4, '检测质量') ON CONFLICT (tag_code) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh;
INSERT INTO quote_impact_tags (tag_code, sort_order, name_zh) VALUES ('tag_05', 5, '供应风险') ON CONFLICT (tag_code) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh;
INSERT INTO quote_impact_tags (tag_code, sort_order, name_zh) VALUES ('tag_06', 6, '商务摩擦') ON CONFLICT (tag_code) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh;
INSERT INTO quote_impact_tags (tag_code, sort_order, name_zh) VALUES ('tag_07', 7, '交付服务') ON CONFLICT (tag_code) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh;
INSERT INTO quote_impact_tags (tag_code, sort_order, name_zh) VALUES ('esg', 8, '合规ESG') ON CONFLICT (tag_code) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh;

INSERT INTO quote_units (unit_code, name_zh, name_en, dimension, canonical_unit_code, conversion_factor_to_canonical)
VALUES
  ('mm', '毫米', 'Millimeter', 'length', 'mm', 1),
  ('um', '微米', 'Micrometer', 'length', 'mm', 0.001),
  ('deg', '度', 'Degree', 'angle', 'deg', 1),
  ('pct', '百分比', 'Percent', 'ratio', 'pct', 1),
  ('day', '天', 'Day', 'duration', 'day', 1),
  ('min', '分钟', 'Minute', 'duration', 'min', 1),
  ('piece', '件', 'Piece', 'quantity', 'piece', 1),
  ('cny', '人民币', 'CNY', 'money', 'cny', 1),
  ('usd', '美元', 'USD', 'money', 'usd', 1),
  ('eur', '欧元', 'EUR', 'money', 'eur', 1),
  ('index', '指数', 'Index', 'index', 'index', 1)
ON CONFLICT (unit_code) DO UPDATE SET
  name_zh = EXCLUDED.name_zh,
  name_en = EXCLUDED.name_en,
  dimension = EXCLUDED.dimension,
  canonical_unit_code = EXCLUDED.canonical_unit_code,
  conversion_factor_to_canonical = EXCLUDED.conversion_factor_to_canonical;

INSERT INTO quote_units (unit_code, name_zh, name_en, dimension, canonical_unit_code, conversion_factor_to_canonical)
VALUES
  ('mpa', 'MPa', 'MPa', 'pressure', 'mpa', 1),
  ('gpa', 'GPa', 'GPa', 'pressure', 'mpa', 1000),
  ('hra', 'HRA', 'HRA', 'hardness', 'hra', 1),
  ('hv', 'HV', 'HV', 'hardness', 'hv', 1),
  ('w_mk', 'W/mK', 'W/mK', 'thermal_conductivity', 'w_mk', 1),
  ('kg', 'kg', 'Kilogram', 'mass', 'kg', 1)
ON CONFLICT (unit_code) DO UPDATE SET
  name_zh = EXCLUDED.name_zh,
  name_en = EXCLUDED.name_en,
  dimension = EXCLUDED.dimension,
  canonical_unit_code = EXCLUDED.canonical_unit_code,
  conversion_factor_to_canonical = EXCLUDED.conversion_factor_to_canonical;

-- Seed field groups and all base field definitions from Datafield.txt

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('physics', 1, '材料与基体', 'Substrate & Material System', 'A')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'substrate_material_class', group_id, 1, '基体材料类别', 'Substrate Material Class', '决定刀具的硬度、韧性、耐磨性和基础成本。', 'enum'::field_value_kind, '枚举', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'substrate_material_class'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'carbide_grade', group_id, 2, '硬质合金牌号', 'Carbide Grade', '不同 WC-Co 配方对应不同切削场景和价格区间。', 'enum'::field_value_kind, '枚举', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'carbide_grade'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'carbide_grade'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'wc_content', group_id, 3, 'WC 含量', 'WC Content', '钨碳化物含量越高，材料成本和耐磨属性越明显。', 'percent'::field_value_kind, '百分比', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'wc_content'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'wc_content'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'cobalt_binder_content', group_id, 4, 'Co 粘结相含量', 'Cobalt Binder Content', '钴含量影响韧性、抗崩刃能力和钴价敏感度。', 'percent'::field_value_kind, '百分比', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'cobalt_binder_content'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'cobalt_binder_content'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'grain_size', group_id, 5, '晶粒尺寸', 'Grain Size', '超细晶粒可提高硬度和刃口锋利性，但粉末和烧结控制成本更高。', 'number'::field_value_kind, '数值', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'grain_size'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'grain_size'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'grain_distribution_uniformity', group_id, 6, '晶粒分布均匀性', 'Grain Distribution Uniformity', '组织越均匀，寿命离散越小，制造控制成本越高。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'grain_distribution_uniformity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'grain_distribution_uniformity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'additive_phase_type', group_id, 7, '微量强化相类型', 'Additive Phase Type', 'VC、Cr₃C₂、TaC、NbC 等添加相会改变耐磨性、韧性和磨削难度。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'additive_phase_type'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'additive_phase_type'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'grindability_index', group_id, 8, '加工难度指数', 'Grindability Index', '即使硬度相同，不同配方对砂轮损耗、磨削热和加工节拍的影响也不同。', 'index'::field_value_kind, '指数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'wheel_wear_coefficient', group_id, 9, '砂轮磨耗系数', 'Wheel Wear Coefficient', '材料越难磨，金刚石砂轮消耗越快，制造成本越高。', 'number'::field_value_kind, '数值', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'wheel_wear_coefficient'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'wheel_wear_coefficient'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'grinding_heat_sensitivity', group_id, 10, '磨削热敏感性', 'Grinding Heat Sensitivity', '材料越容易因磨削热产生微裂纹或烧伤，加工窗口越窄。', 'text'::field_value_kind, '文本', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'grinding_heat_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'grinding_heat_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'grinding_heat_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'powder_purity', group_id, 11, '粉末纯度', 'Powder Purity', '杂质越少，性能越稳定，但原料价格更高。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'powder_purity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'powder_purity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'porosity_percent', group_id, 12, '孔隙率等级', NULL, '孔隙率越低，基体可靠性越高，烧结控制成本越高。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'porosity_percent'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'porosity_percent'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'porosity_percent'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'transverse_rupture_strength', group_id, 13, '抗弯强度 TRS', NULL, '决定刀具抵抗断裂的能力，高 TRS 通常需要更高材料和工艺控制水平。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'transverse_rupture_strength'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'transverse_rupture_strength'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'transverse_rupture_strength'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'fracture_toughness_kic', group_id, 14, '断裂韧性 KIC', NULL, '韧性越高，越适合断续切削和重载加工。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'fracture_toughness_kic'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'fracture_toughness_kic'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'fracture_toughness_kic'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'hardness_hra_hv', group_id, 15, '硬度 HRA/HV', NULL, '硬度越高，耐磨性越好，但磨削难度通常更高。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'hardness_hra_hv'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'hardness_hra_hv'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'hardness_hra_hv'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'thermal_conductivity', group_id, 16, '热导率', NULL, '影响切削热扩散能力，尤其影响钛合金、高温合金加工。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'thermal_conductivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'thermal_conductivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'thermal_conductivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'thermal_expansion_compatibility', group_id, 17, '热膨胀匹配性', NULL, '基体与涂层热膨胀不匹配会增加涂层开裂或剥落风险。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'thermal_expansion_compatibility'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'thermal_expansion_compatibility'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'thermal_expansion_compatibility'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'recycled_tungsten_ratio', group_id, 18, '回收钨比例', NULL, '影响原料成本、碳足迹和供应链合规属性。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'recycled_tungsten_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'recycled_tungsten_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'recycled_tungsten_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'recycled_cobalt_ratio', group_id, 19, '回收钴比例', NULL, '影响成本、ESG 属性和材料一致性控制。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'recycled_cobalt_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'recycled_cobalt_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'recycled_cobalt_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'recoatable_substrate_life', group_id, 20, '基体可重涂寿命', NULL, '表示基体在多次修磨、退涂和重涂后仍能保持性能的能力。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'recoatable_substrate_life'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'recoatable_substrate_life'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'recoatable_substrate_life'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'stripping_cycle_limit', group_id, 21, '剥涂层次数限制', 'Stripping Cycle Limit', '决定一个基体最多能承受几次退涂-重涂循环。', 'integer'::field_value_kind, '整数', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'stripping_cycle_limit'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'stripping_cycle_limit'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'stripping_cycle_limit'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'cobalt_leaching_risk', group_id, 22, '钴流失风险', 'Cobalt Leaching Risk', '退涂或腐蚀环境可能造成粘结相流失，降低基体韧性。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'cobalt_leaching_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'cobalt_leaching_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'cobalt_leaching_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'residual_strength_after_stripping', group_id, 23, '退涂后残余强度', NULL, '衡量退涂后基体是否仍能承受原设计切削负载。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'residual_strength_after_stripping'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'residual_strength_after_stripping'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'residual_strength_after_stripping'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'remaining_substrate_life', group_id, 24, '剩余基体寿命', 'Remaining Substrate Life', '用于评估修磨重涂后的刀具残值。', 'index'::field_value_kind, '指数', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '材料与基体'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'remaining_substrate_life'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'remaining_substrate_life'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('physics', 2, '几何与结构复杂度', 'Geometry & Structural Complexity', 'B')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'tool_diameter_d', group_id, 1, '刀具直径 D', NULL, '直接影响材料用量、磨削面积和刚性。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'tool_diameter_d'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'overall_length_oal', group_id, 2, '总长 OAL', NULL, '总长越长，毛坯成本、磨削稳定性和跳动控制难度越高。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'overall_length_oal'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'cutting_length_loc', group_id, 3, '刃长 LOC', NULL, '刃长越长，开槽磨削时间和几何一致性控制难度越高。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'cutting_length_loc'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'length_to_diameter_ratio', group_id, 4, '长径比 L/D', NULL, '长径比越大，刀具越容易变形、振动和断裂。', 'multiplier'::field_value_kind, '倍率', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'length_to_diameter_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'flute_count_z', group_id, 5, '刃数 Z', NULL, '刃数越多，磨削次数越多，排屑空间通常越小。', 'integer'::field_value_kind, '整数', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'flute_count_z'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'helix_angle', group_id, 6, '螺旋角', 'Helix Angle', '影响切削力、排屑方向和五轴磨削路径复杂度。', 'angle'::field_value_kind, '角度', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'helix_angle'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'variable_helix', group_id, 7, '不等螺旋角', 'Variable Helix', '可抑制振动，但编程、磨削和检测难度更高。', 'boolean'::field_value_kind, '布尔', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'variable_helix'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'variable_helix'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'variable_pitch', group_id, 8, '不等齿距', 'Variable Pitch', '可降低共振，但齿间几何控制成本更高。', 'boolean'::field_value_kind, '布尔', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'variable_pitch'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'core_diameter', group_id, 9, '芯厚', 'Core Diameter', '决定刀具刚性和排屑空间之间的平衡。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'core_diameter'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'core_to_diameter_ratio', group_id, 10, '芯厚直径比', 'Core-to-Diameter Ratio', '用于衡量刀具刚性和排屑能力的结构平衡。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'core_to_diameter_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'flute_depth', group_id, 11, '槽深', 'Flute Depth', '槽越深，排屑能力越强，但芯部刚性下降。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'flute_depth'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'chip_flute_volume_ratio', group_id, 12, '排屑空间比', 'Chip Flute Volume Ratio', '衡量容屑槽体积占比，是几何难度和排屑性能的核心字段。', 'percent'::field_value_kind, '百分比', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'chip_flute_volume_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'flute_removal_volume', group_id, 13, '槽磨去除体积', 'Flute Removal Volume', '表示磨削过程中需要去除多少硬质合金，直接影响节拍和砂轮消耗。', 'number'::field_value_kind, '数值', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'flute_removal_volume'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'flute_removal_volume'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'helix_flute_depth_coupling', group_id, 14, '螺旋角-槽深耦合系数', NULL, '大螺旋角叠加深槽会显著增加磨削变形和补偿难度。', 'index'::field_value_kind, '指数', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'helix_flute_depth_coupling'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'grinding_deflection_compensation', group_id, 15, '磨削弹性变形补偿量', NULL, '表示为了抵消磨削让刀而需要进行的程序补偿强度。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'grinding_deflection_compensation'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'rake_angle', group_id, 16, '前角', 'Rake Angle', '影响切削锋利性、切削力和刃口强度。', 'angle'::field_value_kind, '角度', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'rake_angle'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'relief_angle', group_id, 17, '后角', 'Relief Angle', '影响摩擦、发热和刃口支撑强度。', 'angle'::field_value_kind, '角度', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'relief_angle'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'ball_radius', group_id, 18, '球头半径', 'Ball Radius', '球头轮廓越精密，三维刃形磨削和检测成本越高。', 'number'::field_value_kind, '数值', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'ball_radius'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'ball_radius'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'corner_radius', group_id, 19, '圆鼻半径', 'Corner Radius', '圆角增强刃口强度，但增加成形磨削和检测成本。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'corner_radius'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'corner_radius'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'chamfer_size', group_id, 20, '倒角 Chamfer', NULL, '倒角结构增加刃口强度，也增加额外磨削工序。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'chamfer_size'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'neck_relief_length', group_id, 21, '颈部避空长度', 'Neck Relief Length', '避空越长，刚性越差，磨削变形和断刀风险越高。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'neck_relief_length'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'form_profile_complexity', group_id, 22, '成形轮廓复杂度', 'Form Profile Complexity', '轮廓越复杂，砂轮修整、程序开发和检测成本越高。', 'index'::field_value_kind, '指数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'form_profile_complexity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'form_profile_complexity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'multi_step_compound_geometry', group_id, 23, '多阶复合结构', 'Multi-step Compound Geometry', '一把刀集成多直径、倒角或成形功能时，制造和检测复杂度显著上升。', 'grade'::field_value_kind, '等级', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '几何与结构复杂度'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'multi_step_compound_geometry'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'multi_step_compound_geometry'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('physics', 3, '内冷结构', 'Coolant Channel System', 'C')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'internal_coolant', group_id, 1, '是否内冷', 'Internal Coolant', '内冷结构会增加毛坯、孔加工、检测和封堵成本。', 'boolean'::field_value_kind, '布尔', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'internal_coolant'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'internal_coolant'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coolant_hole_count', group_id, 2, '内冷孔数量', 'Coolant Hole Count', '孔数越多，毛坯制备和孔位控制越复杂。', 'integer'::field_value_kind, '整数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'coolant_hole_count'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coolant_hole_diameter', group_id, 3, '内冷孔直径', 'Coolant Hole Diameter', '孔径越小，加工和堵塞风险越高。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'coolant_hole_diameter'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coolant_hole_position_accuracy', group_id, 4, '内冷孔位置精度', 'Coolant Hole Position Accuracy', '孔位偏差会影响出水方向、刀具强度和动平衡。', 'tolerance'::field_value_kind, '公差', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'coolant_hole_position_accuracy'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coolant_channel_length', group_id, 5, '内冷孔长度', 'Coolant Channel Length', '通道越长，成形难度、堵塞风险和检测成本越高。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'coolant_channel_length'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'coolant_channel_length'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coolant_channel_geometry_and_length', group_id, 6, '内冷孔几何路径复杂度', 'Coolant Channel Geometry & Length', '中心直孔、斜孔、分支孔和螺旋内冷的制造成本差异很大。', 'index'::field_value_kind, '指数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'coolant_channel_geometry_and_length'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'helical_coolant_channel', group_id, 7, '螺旋内冷结构', 'Helical Coolant Channel', '螺旋冷却孔能更贴近切削刃，但毛坯成形和烧结控制成本高。', 'boolean'::field_value_kind, '布尔', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'helical_coolant_channel'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'branched_coolant_channel', group_id, 8, '分支冷却通道', 'Branched Coolant Channel', '多出口或定向喷射结构提升冷却效果，但增加孔道设计和封孔难度。', 'boolean'::field_value_kind, '布尔', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'branched_coolant_channel'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coolant_exit_angle', group_id, 9, '出水角度', 'Coolant Exit Angle', '出水角度越精准，越能提升断屑和冷却效果，但制造控制更难。', 'angle'::field_value_kind, '角度', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'coolant_exit_angle'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'coolant_exit_angle'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coolant_hole_sealing_process', group_id, 10, '封孔工艺', NULL, '复杂冷却通道可能需要封堵、钎焊或后处理，增加制造成本。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'coolant_hole_sealing_process'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'coolant_hole_sealing_process'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coolant_flow_inspection', group_id, 11, '冷却通道通畅率检测', 'Coolant Flow Inspection', '高端内冷刀具需要流量、压力或通孔检测。', 'boolean'::field_value_kind, '布尔', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '内冷结构'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'coolant_flow_inspection'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('physics', 4, '微观刃口质量', 'Edge Micro-Geometry', 'D')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'edge_radius_mean', group_id, 1, '平均刃口半径', 'Edge Radius Mean', '决定刀具锋利性、抗崩刃能力和切削力。', 'number'::field_value_kind, '数值', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'edge_radius_mean'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'edge_radius_mean'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'edge_radius_variation', group_id, 2, '刃口半径离散度', 'Edge Radius Variation', '多刃之间钝化半径越一致，寿命和表面质量越稳定。', 'number'::field_value_kind, '数值', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'edge_radius_variation'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'edge_symmetry_index', group_id, 3, '刃口微观形貌对称度', 'Edge Symmetry Index', '衡量各刃口在微观圆弧、钝化和形貌上的一致性。', 'index'::field_value_kind, '指数', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'edge_symmetry_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'edge_k_factor_bias', group_id, 4, 'K-factor 刃口钝化偏置系数', NULL, '表示刃口圆弧偏向前刀面还是后刀面。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'edge_k_factor_bias'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'edge_k_factor_bias'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'land_width', group_id, 5, '倒棱宽度', 'Land Width', '倒棱越宽，刃口强度越高，但切削力也可能增加。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'land_width'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'land_width'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'k_land_hone_interaction_tolerance', group_id, 6, 'K-land vs. Hone Interaction 特征参数协同公差', NULL, '倒棱宽度与钝化半径同时受控时，微观制造难度会非线性上升。', 'tolerance'::field_value_kind, '公差', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'k_land_hone_interaction_tolerance'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'k_land_hone_interaction_tolerance'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'edge_hone_radius_tolerance', group_id, 7, '刃口钝化半径公差', NULL, '钝化半径要求越窄，刃口制备和检测成本越高。', 'tolerance'::field_value_kind, '公差', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'edge_hone_radius_tolerance'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'edge_hone_radius_tolerance'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'chamfer_hone_overlap_accuracy', group_id, 8, '倒棱-钝化叠加精度', NULL, '小倒棱上叠加小半径钝化会显著降低制造良率。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'chamfer_hone_overlap_accuracy'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'chamfer_hone_overlap_accuracy'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'tooth_to_tooth_load_balance', group_id, 9, '齿间负载均衡度', 'Tooth-to-Tooth Load Balance', '综合跳动、刃口半径和刃形误差，反映每个齿实际切削负载是否均匀。', 'index'::field_value_kind, '指数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'tooth_to_tooth_load_balance'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'micro_chipping_count', group_id, 10, '微崩口数量', 'Micro-chipping Count', '微小崩口会影响初期寿命和高精度加工稳定性。', 'integer'::field_value_kind, '整数', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'micro_chipping_count'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'post_coating_edge_radius', group_id, 11, '涂层后刃口半径', 'Post-coating Edge Radius', '涂层会改变实际有效刃口，需要作为最终刃口状态评估。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'post_coating_edge_radius'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'post_coating_edge_radius'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'edge_preparation_method', group_id, 12, '刃口处理方式', 'Edge Preparation Method', '刷磨、喷砂、拖曳式钝化等工艺会影响刃口一致性和成本。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '微观刃口质量'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'edge_preparation_method'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('physics', 5, '涂层与批处理成本', 'Coating & Batch Cost', 'E')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coating_type', group_id, 1, '涂层类型', 'Coating Type', 'TiN、TiAlN、AlCrN、DLC、金刚石等涂层对应不同材料、工艺和成本。', 'enum'::field_value_kind, '枚举', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'coating_type'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'coating_type'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coating_process_pvd_cvd', group_id, 2, '涂层工艺 PVD/CVD', NULL, '不同沉积工艺的温度、膜厚、批量效率和适用场景不同。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'coating_process_pvd_cvd'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coating_thickness', group_id, 3, '涂层厚度', 'Coating Thickness', '厚涂层提高耐磨性，但可能钝化刃口并增加沉积时间。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'coating_thickness'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'adhesion', group_id, 4, '涂层附着力', 'Adhesion', '附着力越高，前处理和工艺控制要求越高。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'adhesion'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'adhesion'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coating_surface_roughness', group_id, 5, '涂层表面粗糙度', NULL, '涂层后越光滑，排屑和抗粘结性能越好，但可能需要后处理。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'coating_surface_roughness'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'post_coating_polishing', group_id, 6, '涂后抛光', 'Post-coating Polishing', '降低摩擦和粘屑风险，但增加人工或设备成本。', 'boolean'::field_value_kind, '布尔', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'post_coating_polishing'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'batch_furnace_cost', group_id, 7, '涂层炉次成本', 'Batch Furnace Cost', '涂层设备一次运行成本基本固定，需要按合格件数量分摊。', 'money'::field_value_kind, '金额', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'batch_furnace_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'batch_cavity_occupancy', group_id, 8, '腔体占用率', 'Batch Cavity Occupancy', '刀具形状越占空间，单炉可装数量越少，单件分摊成本越高。', 'percent'::field_value_kind, '百分比', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'batch_cavity_occupancy'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'effective_loading_density', group_id, 9, '有效装炉密度', 'Effective Loading Density', '一炉实际可装合格刀具数量越低，单件涂层成本越高。', 'number'::field_value_kind, '数值', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'effective_loading_density'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'fixture_compatibility', group_id, 10, '夹具兼容性', 'Fixture Compatibility', '是否能使用标准挂具会影响装炉效率和夹具成本。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'fixture_compatibility'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coating_batch_compatibility', group_id, 11, '混炉兼容性', 'Coating Batch Compatibility', '涂层体系、膜厚、基体和客户要求不一致时无法混炉，成本会上升。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'coating_batch_compatibility'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'coating_batch_compatibility'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'shadowing_risk', group_id, 12, '遮蔽风险', 'Shadowing Risk', '复杂形状可能导致局部膜厚不足或涂层不均匀。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'shadowing_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'shadowing_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coating_thickness_uniformity_risk', group_id, 13, '膜厚均匀性风险', NULL, '长刀、深槽和复杂刃形更难获得一致涂层厚度。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'coating_thickness_uniformity_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'minimum_coating_batch_cost', group_id, 14, '最小涂层批量成本', 'Minimum Coating Batch Cost', '小批量非标产品需要承担最低炉次分摊成本。', 'money'::field_value_kind, '金额', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '涂层与批处理成本'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'minimum_coating_batch_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'minimum_coating_batch_cost'
ON CONFLICT DO NOTHING;

UPDATE quote_field_groups
SET name_zh = '热处理、应力与稳定性',
    name_en = 'Stress, Aging & Stability',
    updated_at = now()
WHERE section_id = 'physics' AND name_zh = '热处理、应力与稳定性 Stress,';

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('physics', 6, '热处理、应力与稳定性', 'Stress, Aging & Stability', 'F')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'heat_treatment_state', group_id, 1, '热处理状态', NULL, 'HSS、刀体和刀杆的热处理直接影响硬度、韧性和寿命。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '热处理、应力与稳定性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'heat_treatment_state'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'heat_treatment_state'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'stress_relief_aging_cycles', group_id, 2, '应力消除循环次数', 'Stress Relief / Aging Cycles', '多次应力释放或时效处理可提升尺寸稳定性，但增加工艺时间和成本。', 'integer'::field_value_kind, '整数', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '热处理、应力与稳定性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'stress_relief_aging_cycles'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'stress_relief_aging_cycles'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'artificial_aging_process', group_id, 3, '人工时效处理', NULL, '用于释放加工或热处理残余应力，提升长刀和复杂刀具稳定性。', 'text'::field_value_kind, '文本', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '热处理、应力与稳定性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'artificial_aging_process'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'artificial_aging_process'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'cryogenic_treatment', group_id, 4, '深冷处理', 'Cryogenic Treatment', '可改善部分材料组织稳定性和耐磨性，但增加额外工艺成本。', 'boolean'::field_value_kind, '布尔', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '热处理、应力与稳定性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'cryogenic_treatment'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'cryogenic_treatment'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'grinding_residual_stress', group_id, 5, '磨削残余应力', NULL, '高速磨削会引入表层应力，影响刃口强度和寿命稳定性。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '热处理、应力与稳定性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'grinding_residual_stress'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'grinding_residual_stress'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'thermal_cycle_stability', group_id, 6, '热循环稳定性', NULL, '刀具在涂层、退涂、重涂或高温切削后的性能保持能力。', 'text'::field_value_kind, '文本', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '热处理、应力与稳定性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'thermal_cycle_stability'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'thermal_cycle_stability'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'dimensional_aging_stability', group_id, 7, '尺寸时效稳定性', NULL, '长刀、薄壁刀体或复杂刀具在加工后是否会发生微小变形。', 'boolean'::field_value_kind, '布尔', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '热处理、应力与稳定性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'dimensional_aging_stability'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'dimensional_aging_stability'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('physics', 7, '制造良率与小批量非线性', 'Yield & Setup Non-linearity', 'G')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'cycle_time', group_id, 1, '制造节拍', 'Cycle Time', '单件加工时间越长，设备折旧和人工成本越高。', 'duration'::field_value_kind, '时间', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'cycle_time'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'setup_time', group_id, 2, '换线时间', 'Setup Time', '小批量订单中，装夹、对刀、编程和首件确认会显著摊高单价。', 'duration'::field_value_kind, '时间', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'setup_time'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'setup_time'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'set_up_scrapping_risk', group_id, 3, '换线损失费', 'Set-up Scrapping Risk', '调机阶段报废的毛坯会直接进入小批量报价。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'set_up_scrapping_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'set_up_scrapping_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'first_article_cost', group_id, 4, '首件确认成本', 'First Article Cost', '首件检测、修正和确认在小批量订单中占比很高。', 'money'::field_value_kind, '金额', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'first_article_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'first_article_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'trial_grinding_quantity', group_id, 5, '试磨数量', 'Trial Grinding Quantity', '达到稳定尺寸前需要消耗的试制件越多，报价越高。', 'integer'::field_value_kind, '整数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'trial_grinding_quantity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'programming_cost', group_id, 6, '编程成本', 'Programming Cost', '五轴磨削路径、补偿参数和专用轮廓开发需要单独摊销。', 'money'::field_value_kind, '金额', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'programming_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'wheel_dressing_cost', group_id, 7, '砂轮修整成本', 'Wheel Dressing Cost', '特殊轮廓需要频繁修整砂轮，增加耗材和停机时间。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'wheel_dressing_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'gauge_setup_cost', group_id, 8, '检具设定成本', NULL, '非标轮廓或高精度要求可能需要专用检具和测量程序。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'gauge_setup_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'gauge_setup_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'mass_production_yield', group_id, 9, '量产良率', 'Mass Production Yield', '稳定生产中的合格率直接影响单位制造成本。', 'percent'::field_value_kind, '百分比', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'mass_production_yield'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'mass_production_yield'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'small_batch_cost_multiplier', group_id, 10, '小批量成本倍数', 'Small Batch Cost Multiplier', '数量越少，固定成本、试制损耗和涂层分摊越难摊薄。', 'multiplier'::field_value_kind, '倍数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '制造良率与小批量非线性'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'small_batch_cost_multiplier'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('physics', 8, '精度、检测与质量控制', 'Precision & Inspection', 'H')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'diameter_tolerance', group_id, 1, '直径公差', 'Diameter Tolerance', '公差越严，精磨和检测成本越高。', 'tolerance'::field_value_kind, '公差', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'diameter_tolerance'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'shank_tolerance', group_id, 2, '柄径公差', 'Shank Tolerance', '影响夹持精度，高等级公差需要更严格外圆磨削。', 'tolerance'::field_value_kind, '公差', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'shank_tolerance'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'runout', group_id, 3, '圆跳动 Runout', NULL, '跳动越低，多刃切削负载越均衡。', 'tolerance'::field_value_kind, '公差', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'runout'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coaxiality', group_id, 4, '同轴度', NULL, '刃部与柄部同轴度影响孔加工精度和铣削稳定性。', 'tolerance'::field_value_kind, '公差', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'coaxiality'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'ball_profile_error', group_id, 5, '球头轮廓误差', NULL, '模具和曲面加工对球头轮廓精度要求极高。', 'tolerance'::field_value_kind, '公差', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'ball_profile_error'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'surface_roughness_ra', group_id, 6, '表面粗糙度 Ra', NULL, '槽面、前刀面和后刀面粗糙度会影响摩擦与排屑。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'surface_roughness_ra'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'full_inspection_ratio', group_id, 7, '全检比例', 'Full Inspection Ratio', '全检能提升一致性，但显著增加质量成本。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'full_inspection_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'batch_traceability', group_id, 8, '批次追溯', NULL, '高端客户要求从粉末、烧结、磨削到涂层全流程可追溯。', 'text'::field_value_kind, '文本', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'batch_traceability'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'inspection_report_requirement', group_id, 9, '检测报告要求', 'Inspection Report Requirement', '材质、尺寸、涂层、硬度和显微组织报告都会增加文件与检测成本。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'physics' AND name_zh = '精度、检测与质量控制'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'inspection_report_requirement'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'inspection_report_requirement'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('market', 1, '品牌、渠道与技术溢价', 'Brand & Distribution', 'A')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'brand_tier', group_id, 1, '品牌等级', 'Brand Tier', '高端品牌包含研发、稳定性、应用数据库和服务溢价。', 'enum'::field_value_kind, '枚举', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '品牌、渠道与技术溢价'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'brand_tier'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'country_of_origin_perception', group_id, 2, '品牌原产地认知', 'Country-of-origin Perception', '不同产地在客户心中的质量和稳定性认知会影响价格。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '品牌、渠道与技术溢价'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'country_of_origin_perception'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'authorized_distribution', group_id, 3, '授权代理状态', 'Authorized Distribution', '授权渠道价格更高，但提供真伪、售后和技术保障。', 'boolean'::field_value_kind, '布尔', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '品牌、渠道与技术溢价'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'authorized_distribution'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'distribution_layer', group_id, 4, '渠道层级', 'Distribution Layer', '渠道层级越多，渠道毛利叠加越明显。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '品牌、渠道与技术溢价'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'distribution_layer'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'oem_odm_private_label', group_id, 5, 'OEM / ODM / 白牌属性', 'OEM / ODM / Private Label', '白牌价格低，但客户承担更多验证和应用风险。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '品牌、渠道与技术溢价'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'oem_odm_private_label'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'proprietary_technology', group_id, 6, '专利或专有技术', 'Proprietary Technology', '专有槽型、牌号或涂层会降低可替代性并提高溢价。', 'boolean'::field_value_kind, '布尔', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '品牌、渠道与技术溢价'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'proprietary_technology'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'alternative_supplier_count', group_id, 7, '替代品牌数量', 'Alternative Supplier Count', '可替代供应商越多，议价空间越大。', 'integer'::field_value_kind, '整数', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '品牌、渠道与技术溢价'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'alternative_supplier_count'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'customer_validation_status', group_id, 8, '客户验证状态', 'Customer Validation Status', '已通过产线验证的刀具具备切换成本溢价。', 'enum'::field_value_kind, '枚举', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '品牌、渠道与技术溢价'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'customer_validation_status'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('market', 2, '供应链与宏观风险', 'Supply Chain & Macro Risk', 'B')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'tungsten_price_sensitivity', group_id, 1, '钨价格敏感度', 'Tungsten Price Sensitivity', '硬质合金刀具对钨价波动高度敏感。', 'grade'::field_value_kind, '等级', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'tungsten_price_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'tungsten_price_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'cobalt_price_sensitivity', group_id, 2, '钴价格敏感度', 'Cobalt Price Sensitivity', '高钴牌号受钴价影响更明显。', 'grade'::field_value_kind, '等级', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'cobalt_price_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'cobalt_price_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'target_material_price_sensitivity', group_id, 3, '涂层靶材价格敏感度', 'Target Material Price Sensitivity', 'Al、Ti、Cr、Zr 等靶材价格会影响涂层成本。', 'index'::field_value_kind, '指数', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'target_material_price_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'target_material_price_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'rare_additive_supply_risk', group_id, 4, '稀有添加剂供应风险', 'Rare Additive Supply Risk', 'Ta、Nb、VC 等添加剂供应波动会影响特殊牌号成本。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'rare_additive_supply_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'supply_chain_geo_redundancy', group_id, 5, '供应链地理冗余度', 'Supply Chain Geo-Redundancy', '关键粉末、靶材或毛坯来源越单一，供应中断风险溢价越高。', 'grade'::field_value_kind, '等级', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'supply_chain_geo_redundancy'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'single_source_dependency', group_id, 6, '单一来源依赖度', 'Single-source Dependency', '依赖单一国家、矿山、粉末厂或涂层厂会增加长期协议风险。', 'grade'::field_value_kind, '等级', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'single_source_dependency'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'export_control_risk', group_id, 7, '出口管制风险', 'Export Control Risk', '关键原料或高端刀具技术受管制时，交付和价格风险上升。', 'grade'::field_value_kind, '等级', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'export_control_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'export_control_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'tariff_exposure', group_id, 8, '关税暴露度', 'Tariff Exposure', '进口成品、粉末、毛坯或涂层材料的关税会改变到岸成本。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'tariff_exposure'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'tariff_exposure'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'fx_risk', group_id, 9, '汇率风险', 'FX Risk', '外币计价的进口刀具或原料会受到汇率波动影响。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'fx_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'fx_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'energy_price_sensitivity', group_id, 10, '能源价格敏感度', NULL, '烧结、HIP、热处理和涂层都对能源成本敏感。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'energy_price_sensitivity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'capacity_utilization', group_id, 11, '产能利用率', 'Capacity Utilization', '供应商产能越满，折扣越少，交期和价格越硬。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '供应链与宏观风险'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'capacity_utilization'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'capacity_utilization'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('market', 3, 'ESG、碳足迹与合规', 'ESG & Compliance', 'C')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'product_carbon_footprint', group_id, 1, '产品碳足迹', 'Product Carbon Footprint', '单件刀具从原料到制造、涂层、运输的碳排放会影响高端客户采购评分。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'product_carbon_footprint'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'cbam_exposure', group_id, 2, 'CBAM 暴露度', 'CBAM Exposure', '出口欧洲或进入相关供应链时，碳成本和申报要求可能影响报价。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'cbam_exposure'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'cbam_exposure'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'electricity_carbon_factor', group_id, 3, '用电碳因子', 'Electricity Carbon Factor', '相同工艺在不同能源结构下对应不同碳排放强度。', 'number'::field_value_kind, '数值', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'electricity_carbon_factor'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'sintering_energy_intensity', group_id, 4, '烧结能耗强度', 'Sintering Energy Intensity', '烧结和 HIP 的能效会影响单件能耗和碳足迹。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'sintering_energy_intensity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'sintering_energy_intensity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'coating_energy_intensity', group_id, 5, '涂层能耗强度', 'Coating Energy Intensity', 'PVD/CVD 炉次能耗会进入高端客户的碳成本核算。', 'number'::field_value_kind, '数值', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'coating_energy_intensity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'coating_energy_intensity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'recycled_material_certificate', group_id, 6, '回收料证明', 'Recycled Material Certificate', '回收钨、回收钴比例需要文件支持，增加合规管理成本。', 'boolean'::field_value_kind, '布尔', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'recycled_material_certificate'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'rohs_reach_compliance', group_id, 7, 'RoHS / REACH 合规', 'RoHS / REACH Compliance', '进入电子、欧洲或高端制造供应链时常需要材料合规证明。', 'boolean'::field_value_kind, '布尔', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'rohs_reach_compliance'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'conflict_minerals_declaration', group_id, 8, '冲突矿产声明', 'Conflict Minerals Declaration', '钨、钴等原料可能需要供应链来源声明。', 'boolean'::field_value_kind, '布尔', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'conflict_minerals_declaration'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'certificate_of_origin', group_id, 9, '原产地证书', 'Certificate of Origin', '影响关税、合规准入和客户采购要求。', 'boolean'::field_value_kind, '布尔', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'certificate_of_origin'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'certificate_of_origin'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'esg_documentation_cost', group_id, 10, 'ESG 文件成本', 'ESG Documentation Cost', '碳足迹、材料来源和第三方认证文件都需要额外管理成本。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = 'ESG、碳足迹与合规'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '合规ESG' WHERE f.field_code = 'esg_documentation_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'esg_documentation_cost'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('market', 4, '交付、库存与服务', 'Logistics & Service', 'D')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'stock_availability', group_id, 1, '现货状态', 'Stock Availability', '现货占用库存资金，通常具备价格溢价。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'stock_availability'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'lead_time', group_id, 2, '交期', 'Lead Time', '交期越短，越可能涉及插单、加班、调拨或空运。', 'days'::field_value_kind, '天数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'lead_time'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'expedite_fee', group_id, 3, '加急费', 'Expedite Fee', '加急订单会打乱排产并提高制造和物流成本。', 'money'::field_value_kind, '金额', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'expedite_fee'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'expedite_fee'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'minimum_order_quantity', group_id, 4, 'MOQ 最小起订量', 'Minimum Order Quantity', '订单量越低，换线、涂层和检测分摊成本越高。', 'integer'::field_value_kind, '整数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'minimum_order_quantity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'local_warehousing_cost', group_id, 5, '本地仓储成本', 'Local Warehousing Cost', '本地仓能缩短交付时间，但增加库存资金和管理成本。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'local_warehousing_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'financial_carrying_cost_of_vmi', group_id, 6, 'VMI 资金占用费', 'Financial Carrying Cost of VMI', '寄售库存中供应商承担库存融资、呆滞和管理成本。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'financial_carrying_cost_of_vmi'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'financial_carrying_cost_of_vmi'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'vmi_ownership_retention_days', group_id, 7, 'VMI 所有权滞留周期', NULL, '刀具放在客户现场但未结算的时间越长，资金成本越高。', 'days'::field_value_kind, '天数', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'vmi_ownership_retention_days'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'tool_cabinet_service_cost', group_id, 8, '刀具柜服务成本', 'Tool Cabinet Service Cost', '自动刀具柜、补货、扫码和盘点系统都需要摊入价格。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'tool_cabinet_service_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'obsolete_inventory_risk', group_id, 9, '呆滞库存风险', 'Obsolete Inventory Risk', '客户项目变更或需求下降会导致专用库存无法消耗。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'obsolete_inventory_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'obsolete_inventory_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'used_tool_recycling_value', group_id, 10, '旧刀回收价值', 'Used Tool Recycling Value', '硬质合金回收可抵扣部分材料成本。', 'money'::field_value_kind, '金额', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE f.field_code = 'used_tool_recycling_value'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'used_tool_recycling_value'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'regrinding_service_cost', group_id, 11, '修磨服务成本', 'Regrinding Service Cost', '重磨、退涂、再涂和再检测构成刀具全生命周期服务成本。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '交付、库存与服务'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'regrinding_service_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE f.field_code = 'regrinding_service_cost'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('market', 5, '包装、运输与无损交付', 'Packaging & Damage Prevention', 'E')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'packaging_protection_grade', group_id, 1, '包装保护等级', 'Packaging Protection Grade', '微径刀、长刀和重型刀具需要更高等级防护包装。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'packaging_protection_grade'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'micro_tool_protection', group_id, 2, '微径刀具防护包装', 'Micro Tool Protection', '0.2mm 以下微刀具需要防振、防碰刃和单支固定设计。', 'boolean'::field_value_kind, '布尔', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'micro_tool_protection'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'heavy_tool_packaging', group_id, 3, '重型刀具包装结构', 'Heavy Tool Packaging', '大重量刀具需要抗冲击、承重和防松动包装。', 'boolean'::field_value_kind, '布尔', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'heavy_tool_packaging'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'vacuum_packaging', group_id, 4, '真空包装', 'Vacuum Packaging', '用于防潮、防氧化或洁净要求较高的刀具。', 'boolean'::field_value_kind, '布尔', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'vacuum_packaging'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'nitrogen_packaging', group_id, 5, '氮气保护包装', 'Nitrogen Packaging', '用于防氧化、防腐蚀或高端精密刀具长期储存。', 'boolean'::field_value_kind, '布尔', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'nitrogen_packaging'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'anti_rust_grade', group_id, 6, '防锈等级', 'Anti-rust Grade', '刀体、刀杆或钢制组件需要防锈油、VCI 纸或密封包装。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'anti_rust_grade'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'transport_vibration_risk', group_id, 7, '运输震动风险', 'Transport Vibration Risk', '长途运输中的振动可能导致微崩刃或涂层损伤。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'transport_vibration_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE f.field_code = 'transport_vibration_risk'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'single_piece_packaging_ratio', group_id, 8, '单支包装比例', 'Single-piece Packaging Ratio', '单支包装保护性更好，但包装和分拣成本更高。', 'percent'::field_value_kind, '百分比', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'single_piece_packaging_ratio'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'customer_label_requirement', group_id, 9, '客户标签要求', 'Customer Label Requirement', '条码、二维码、批次号和客户料号标签会增加包装作业成本。', 'enum'::field_value_kind, '枚举', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '包装、运输与无损交付'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'customer_label_requirement'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'customer_label_requirement'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_groups (section_id, sort_order, name_zh, name_en, icon)
VALUES ('market', 6, '商务条款与需求波动', 'Commercial Terms & Demand Variability', 'F')
ON CONFLICT (section_id, name_zh) DO UPDATE SET sort_order = EXCLUDED.sort_order, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon, updated_at = now();
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'purchase_quantity', group_id, 1, '采购数量', 'Purchase Quantity', '数量越大，固定成本和批处理成本越容易摊薄。', 'integer'::field_value_kind, '整数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'purchase_quantity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'annual_contract_volume', group_id, 2, '年度协议量', 'Annual Contract Volume', '年度锁量可降低供应商产能和库存不确定性。', 'integer'::field_value_kind, '整数', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'annual_contract_volume'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'forecast_accuracy', group_id, 3, '预测准确率', 'Forecast Accuracy', '客户预测越准确，供应商越容易规划材料、产能和库存。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'forecast_accuracy'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'forecast_accuracy'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'forecast_accuracy_buffering', group_id, 4, '年度协议弹性预测偏差', 'Forecast Accuracy Buffering', '承诺年用量很大但实际批次碎片化时，规模效应会被消耗掉。', 'percent'::field_value_kind, '百分比', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'forecast_accuracy_buffering'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'forecast_accuracy_buffering'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'order_fragmentation', group_id, 5, '需求碎片化程度', 'Order Fragmentation', '总量大但每批数量小，会导致频繁换线、分拣和发货成本上升。', 'grade'::field_value_kind, '等级', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'order_fragmentation'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'release_schedule', group_id, 6, '释放订单节奏', 'Release Schedule', '稳定释放订单有利于降低库存和排产风险。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'release_schedule'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'release_schedule'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'quote_validity', group_id, 7, '价格有效期', 'Quote Validity', '有效期越长，供应商承担的原料、汇率和能源波动风险越高。', 'days'::field_value_kind, '天数', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'quote_validity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'quote_validity'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'payment_terms', group_id, 8, '付款周期', 'Payment Terms', '账期越长，资金成本和坏账风险越高。', 'days'::field_value_kind, '天数', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'payment_terms'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'customer_credit_rating', group_id, 9, '客户信用等级', 'Customer Credit Rating', '信用风险越高，报价中风险溢价越高。', 'grade'::field_value_kind, '等级', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'customer_credit_rating'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'currency', group_id, 10, '币种', 'Currency', '不同币种带来不同汇率风险。', 'enum'::field_value_kind, '枚举', 'low'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'currency'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE f.field_code = 'currency'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'incoterms', group_id, 11, '贸易条款 Incoterms', NULL, 'EXW、FOB、CIF、DDP 会改变运费、保险、清关和税费承担方。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","inferred_metadata":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'incoterms'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE f.field_code = 'incoterms'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'rebate_policy', group_id, 12, '返利政策', 'Rebate Policy', '年返、季返和项目返利会改变表面单价和真实净价。', 'enum'::field_value_kind, '枚举', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'rebate_policy'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'nre_engineering_cost', group_id, 13, 'NRE 工程费', 'NRE Engineering Cost', '非标设计、试制、砂轮、夹具和检测程序需要一次性或分摊收费。', 'money'::field_value_kind, '金额', 'high'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'nre_engineering_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'nre_engineering_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'tooling_cost', group_id, 14, '模具费', 'Tooling Cost', '可转位刀片、专用刀体或成形刀可能涉及专用模具和夹具费用。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'tooling_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE f.field_code = 'tooling_cost'
ON CONFLICT DO NOTHING;
INSERT INTO quote_field_definitions (field_code, group_id, sort_order, name_zh, name_en, description, value_kind, raw_type_zh, impact_level, metadata)
SELECT 'sample_cost', group_id, 15, '样品费', 'Sample Cost', '样品无法摊薄固定成本，单价通常高于量产价格。', 'money'::field_value_kind, '金额', 'medium'::field_impact_level, '{"source":"Datafield.txt","enriched_from_dashboard":true}'::jsonb
FROM quote_field_groups WHERE section_id = 'market' AND name_zh = '商务条款与需求波动'
ON CONFLICT (field_code) DO UPDATE SET group_id = EXCLUDED.group_id, sort_order = EXCLUDED.sort_order, name_zh = EXCLUDED.name_zh, name_en = EXCLUDED.name_en, description = EXCLUDED.description, value_kind = EXCLUDED.value_kind, raw_type_zh = EXCLUDED.raw_type_zh, impact_level = EXCLUDED.impact_level, metadata = EXCLUDED.metadata, updated_at = now();
INSERT INTO quote_field_definition_tags (field_id, tag_code)
SELECT f.field_id, t.tag_code FROM quote_field_definitions f JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE f.field_code = 'sample_cost'
ON CONFLICT DO NOTHING;

INSERT INTO quote_field_units (field_id, unit_code, is_default)
SELECT field_id,
       CASE
         WHEN value_kind IN ('percent') THEN 'pct'
         WHEN value_kind IN ('days') THEN 'day'
         WHEN value_kind IN ('duration') THEN 'min'
         WHEN value_kind IN ('angle') THEN 'deg'
         WHEN value_kind IN ('money') THEN 'cny'
         WHEN value_kind IN ('index', 'multiplier') THEN 'index'
         ELSE 'mm'
       END AS unit_code,
       true
FROM quote_field_definitions
WHERE value_kind IN ('percent', 'days', 'duration', 'angle', 'money', 'index', 'multiplier')
   OR field_code IN (
     'grain_size', 'tool_diameter_d', 'overall_length_oal', 'cutting_length_loc', 'core_diameter',
     'flute_depth', 'ball_radius', 'corner_radius', 'chamfer_size', 'neck_relief_length',
     'coolant_hole_diameter', 'coolant_channel_length', 'edge_radius_mean', 'land_width',
     'post_coating_edge_radius'
   )
ON CONFLICT (field_id, unit_code) DO UPDATE SET is_default = EXCLUDED.is_default;

UPDATE quote_field_units u
SET is_default = false
FROM quote_field_definitions f
WHERE f.field_id = u.field_id
  AND u.unit_code = 'mm'
  AND f.field_code IN (
    'transverse_rupture_strength', 'hardness_hra_hv', 'thermal_conductivity',
    'coating_thickness', 'coating_surface_roughness', 'surface_roughness_ra',
    'minimum_order_quantity', 'purchase_quantity', 'annual_contract_volume'
  );

INSERT INTO quote_field_units (field_id, unit_code, is_default)
SELECT f.field_id, v.unit_code, v.is_default
FROM quote_field_definitions f
JOIN (VALUES
  ('transverse_rupture_strength', 'mpa', true),
  ('transverse_rupture_strength', 'gpa', false),
  ('hardness_hra_hv', 'hra', true),
  ('hardness_hra_hv', 'hv', false),
  ('thermal_conductivity', 'w_mk', true),
  ('coating_thickness', 'um', true),
  ('coating_surface_roughness', 'um', true),
  ('surface_roughness_ra', 'um', true),
  ('minimum_order_quantity', 'piece', true),
  ('purchase_quantity', 'piece', true),
  ('annual_contract_volume', 'piece', true)
) AS v(field_code, unit_code, is_default) ON v.field_code = f.field_code
ON CONFLICT (field_id, unit_code) DO UPDATE SET is_default = EXCLUDED.is_default;

INSERT INTO quote_field_units (field_id, unit_code, is_default)
SELECT f.field_id, v.unit_code, false
FROM quote_field_definitions f
CROSS JOIN (VALUES ('usd'), ('eur')) AS v(unit_code)
WHERE f.value_kind = 'money'
ON CONFLICT (field_id, unit_code) DO UPDATE SET is_default = EXCLUDED.is_default;

INSERT INTO quote_field_validation_rules (field_id, rule_code, rule_type, severity, rule_config, error_message_zh)
SELECT field_id, 'percent_0_100', 'range', 'error', '{"min":0,"max":100}'::jsonb, '百分比必须在 0 到 100 之间。'
FROM quote_field_definitions
WHERE value_kind = 'percent'
ON CONFLICT (field_id, rule_code) DO UPDATE SET rule_type = EXCLUDED.rule_type, severity = EXCLUDED.severity, rule_config = EXCLUDED.rule_config, error_message_zh = EXCLUDED.error_message_zh, updated_at = now();

INSERT INTO quote_field_validation_rules (field_id, rule_code, rule_type, severity, rule_config, error_message_zh)
SELECT field_id, 'nonnegative_numeric', 'min', 'error', '{"min":0}'::jsonb, '数值不能为负。'
FROM quote_field_definitions
WHERE value_kind IN ('number', 'integer', 'money', 'days', 'duration', 'index', 'multiplier')
ON CONFLICT (field_id, rule_code) DO UPDATE SET rule_type = EXCLUDED.rule_type, severity = EXCLUDED.severity, rule_config = EXCLUDED.rule_config, error_message_zh = EXCLUDED.error_message_zh, updated_at = now();

INSERT INTO quote_field_validation_rules (field_id, rule_code, rule_type, severity, rule_config, error_message_zh)
SELECT field_id, 'must_use_option_set', 'option_set', 'error', '{}'::jsonb, '取值必须来自字段枚举表。'
FROM quote_field_definitions
WHERE value_kind = 'enum'
ON CONFLICT (field_id, rule_code) DO UPDATE SET rule_type = EXCLUDED.rule_type, severity = EXCLUDED.severity, rule_config = EXCLUDED.rule_config, error_message_zh = EXCLUDED.error_message_zh, updated_at = now();

INSERT INTO quote_field_options (field_id, option_code, label_zh, label_en, sort_order)
SELECT f.field_id, v.option_code, v.label_zh, v.label_en, v.sort_order
FROM quote_field_definitions f
JOIN (VALUES
  ('stock_availability', 'in_stock', '现货', 'In Stock', 1),
  ('stock_availability', 'made_to_order', '订制', 'Made to Order', 2),
  ('stock_availability', 'limited_stock', '少量库存', 'Limited Stock', 3),
  ('incoterms', 'EXW', 'EXW', 'EXW', 1),
  ('incoterms', 'FOB', 'FOB', 'FOB', 2),
  ('incoterms', 'CIF', 'CIF', 'CIF', 3),
  ('incoterms', 'DDP', 'DDP', 'DDP', 4),
  ('currency', 'CNY', '人民币', 'CNY', 1),
  ('currency', 'USD', '美元', 'USD', 2),
  ('currency', 'EUR', '欧元', 'EUR', 3),
  ('coating_process_pvd_cvd', 'PVD', 'PVD', 'PVD', 1),
  ('coating_process_pvd_cvd', 'CVD', 'CVD', 'CVD', 2),
  ('substrate_material_class', 'solid_carbide', 'Solid carbide', 'Solid carbide', 1),
  ('substrate_material_class', 'cermet', 'Cermet', 'Cermet', 2),
  ('substrate_material_class', 'ceramic', 'Ceramic', 'Ceramic', 3),
  ('substrate_material_class', 'pcd_pcbn', 'PCD/PCBN', 'PCD/PCBN', 4),
  ('carbide_grade', 'ultrafine_wc_co', 'Ultrafine WC-Co', 'Ultrafine WC-Co', 1),
  ('carbide_grade', 'micrograin_wc_co', 'Micrograin WC-Co', 'Micrograin WC-Co', 2),
  ('carbide_grade', 'medium_grain_wc_co', 'Medium grain WC-Co', 'Medium grain WC-Co', 3),
  ('carbide_grade', 'tough_grade_wc_co', 'Tough grade WC-Co', 'Tough grade WC-Co', 4),
  ('additive_phase_type', 'none', 'None', 'None', 1),
  ('additive_phase_type', 'vc', 'VC', 'VC', 2),
  ('additive_phase_type', 'cr3c2', 'Cr3C2', 'Cr3C2', 3),
  ('additive_phase_type', 'tac_nbc', 'TaC/NbC', 'TaC/NbC', 4),
  ('coolant_hole_sealing_process', 'none', 'None', 'None', 1),
  ('coolant_hole_sealing_process', 'plugging', 'Plugging', 'Plugging', 2),
  ('coolant_hole_sealing_process', 'brazing', 'Brazing', 'Brazing', 3),
  ('coolant_hole_sealing_process', 'post_treatment', 'Post treatment', 'Post treatment', 4),
  ('edge_preparation_method', 'brushing', 'Brushing', 'Brushing', 1),
  ('edge_preparation_method', 'drag_finishing', 'Drag finishing', 'Drag finishing', 2),
  ('edge_preparation_method', 'sand_blasting', 'Sand blasting', 'Sand blasting', 3),
  ('edge_preparation_method', 'laser', 'Laser', 'Laser', 4),
  ('coating_type', 'uncoated', 'Uncoated', 'Uncoated', 1),
  ('coating_type', 'tin', 'TiN', 'TiN', 2),
  ('coating_type', 'tialn', 'TiAlN', 'TiAlN', 3),
  ('coating_type', 'alcrn', 'AlCrN', 'AlCrN', 4),
  ('coating_type', 'dlc', 'DLC', 'DLC', 5),
  ('coating_type', 'diamond', 'Diamond', 'Diamond', 6),
  ('fixture_compatibility', 'standard_fixture', 'Standard fixture', 'Standard fixture', 1),
  ('fixture_compatibility', 'minor_adapter', 'Minor adapter', 'Minor adapter', 2),
  ('fixture_compatibility', 'custom_fixture', 'Custom fixture', 'Custom fixture', 3),
  ('inspection_report_requirement', 'none', 'None', 'None', 1),
  ('inspection_report_requirement', 'dimension_report', 'Dimension report', 'Dimension report', 2),
  ('inspection_report_requirement', 'material_certificate', 'Material certificate', 'Material certificate', 3),
  ('inspection_report_requirement', 'full_report', 'Full report', 'Full report', 4),
  ('brand_tier', 'premium', 'Premium', 'Premium', 1),
  ('brand_tier', 'mid_market', 'Mid market', 'Mid market', 2),
  ('brand_tier', 'value', 'Value', 'Value', 3),
  ('brand_tier', 'private_label', 'Private label', 'Private label', 4),
  ('country_of_origin_perception', 'premium_origin', 'Premium origin', 'Premium origin', 1),
  ('country_of_origin_perception', 'standard_origin', 'Standard origin', 'Standard origin', 2),
  ('country_of_origin_perception', 'cost_origin', 'Cost origin', 'Cost origin', 3),
  ('oem_odm_private_label', 'brand', 'Brand', 'Brand', 1),
  ('oem_odm_private_label', 'oem', 'OEM', 'OEM', 2),
  ('oem_odm_private_label', 'odm', 'ODM', 'ODM', 3),
  ('oem_odm_private_label', 'private_label', 'Private label', 'Private label', 4),
  ('customer_validation_status', 'not_validated', 'Not validated', 'Not validated', 1),
  ('customer_validation_status', 'sample_approved', 'Sample approved', 'Sample approved', 2),
  ('customer_validation_status', 'line_validated', 'Line validated', 'Line validated', 3),
  ('customer_validation_status', 'preferred_supplier', 'Preferred supplier', 'Preferred supplier', 4),
  ('customer_label_requirement', 'none', 'None', 'None', 1),
  ('customer_label_requirement', 'standard_label', 'Standard label', 'Standard label', 2),
  ('customer_label_requirement', 'customer_part_label', 'Customer part label', 'Customer part label', 3),
  ('customer_label_requirement', 'barcode_qr_label', 'Barcode/QR label', 'Barcode/QR label', 4),
  ('release_schedule', 'one_time', 'One time', 'One time', 1),
  ('release_schedule', 'monthly', 'Monthly', 'Monthly', 2),
  ('release_schedule', 'quarterly', 'Quarterly', 'Quarterly', 3),
  ('release_schedule', 'call_off', 'Call-off', 'Call-off', 4),
  ('rebate_policy', 'none', 'None', 'None', 1),
  ('rebate_policy', 'annual_rebate', 'Annual rebate', 'Annual rebate', 2),
  ('rebate_policy', 'quarterly_rebate', 'Quarterly rebate', 'Quarterly rebate', 3),
  ('rebate_policy', 'project_rebate', 'Project rebate', 'Project rebate', 4)
) AS v(field_code, option_code, label_zh, label_en, sort_order) ON v.field_code = f.field_code
ON CONFLICT (field_id, option_code) DO UPDATE SET label_zh = EXCLUDED.label_zh, label_en = EXCLUDED.label_en, sort_order = EXCLUDED.sort_order, updated_at = now();

INSERT INTO market_indicator_definitions (indicator_code, name_zh, name_en, category, value_unit, currency, source_name)
VALUES
  ('tungsten_price', '钨价', 'Tungsten Price', 'metal', 'CNY/ton', 'CNY', NULL),
  ('cobalt_price', '钴价', 'Cobalt Price', 'metal', 'CNY/ton', 'CNY', NULL),
  ('wc_powder_price', '碳化钨粉价格', 'Tungsten Carbide Powder Price', 'powder', 'CNY/kg', 'CNY', NULL),
  ('cobalt_powder_price', '钴粉价格', 'Cobalt Powder Price', 'powder', 'CNY/kg', 'CNY', NULL),
  ('usd_cny_fx', '美元兑人民币汇率', 'USD/CNY FX Rate', 'fx', 'CNY per USD', NULL, NULL),
  ('eur_cny_fx', '欧元兑人民币汇率', 'EUR/CNY FX Rate', 'fx', 'CNY per EUR', NULL, NULL),
  ('freight_index', '运费指数', 'Freight Index', 'logistics', 'index', NULL, NULL),
  ('energy_price_index', '能源价格指数', 'Energy Price Index', 'energy', 'index', NULL, NULL),
  ('tariff_rate_cutting_tools', '刀具关税税率', 'Cutting Tool Tariff Rate', 'tariff', 'pct', NULL, NULL)
ON CONFLICT (indicator_code) DO UPDATE SET
  name_zh = EXCLUDED.name_zh,
  name_en = EXCLUDED.name_en,
  category = EXCLUDED.category,
  value_unit = EXCLUDED.value_unit,
  currency = EXCLUDED.currency,
  source_name = EXCLUDED.source_name,
  updated_at = now();

-- Seed advanced index definitions from Datafield.txt, enriched with formulas/source fields from Dashboard.html when available.
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('material_grindability_index', 'Material Grindability Index', '材料磨削难度指数', '物理制造指数', '汇总材料配方、硬度、微量元素和砂轮磨耗对制造成本的影响。', '材料磨削难度 = 材料硬度 + 配方难磨性 + 砂轮磨耗 + 热敏感风险', ARRAY['WC 含量', 'Co 粘结相含量', '晶粒尺寸', '硬度 HRA/HV', '砂轮磨耗系数', '磨削热敏感性']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE i.index_code = 'material_grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE i.index_code = 'material_grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'wc_content' WHERE i.index_code = 'material_grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'cobalt_binder_content' WHERE i.index_code = 'material_grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'grain_size' WHERE i.index_code = 'material_grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'hardness_hra_hv' WHERE i.index_code = 'material_grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'wheel_wear_coefficient' WHERE i.index_code = 'material_grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'grinding_heat_sensitivity' WHERE i.index_code = 'material_grindability_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('geometry_complexity_index', 'Geometry Complexity Index', '几何复杂度指数', '物理制造指数', '汇总直径、刃长、刃数、槽深、螺旋角、芯厚和成形轮廓的非线性难度。', '几何复杂度 = 尺寸比例 + 刃形数量 + 槽型难度 + 轮廓非标程度', ARRAY['刀具直径 D', '刃长 LOC', '长径比 L/D', '刃数 Z', '螺旋角', '槽深', '成形轮廓复杂度']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE i.index_code = 'geometry_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'tool_diameter_d' WHERE i.index_code = 'geometry_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'cutting_length_loc' WHERE i.index_code = 'geometry_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'length_to_diameter_ratio' WHERE i.index_code = 'geometry_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'flute_count_z' WHERE i.index_code = 'geometry_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'helix_angle' WHERE i.index_code = 'geometry_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'flute_depth' WHERE i.index_code = 'geometry_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'form_profile_complexity' WHERE i.index_code = 'geometry_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('coolant_channel_complexity_index', 'Coolant Channel Complexity Index', '内冷通道复杂度指数', '物理制造指数', '汇总内冷孔数量、路径、长度、出水角度和封孔工艺难度。', '内冷复杂度 = 孔数量 + 小孔制造难度 + 路径复杂度 + 检测封孔风险', ARRAY['内冷孔数量', '内冷孔直径', '内冷孔长度', '内冷孔几何路径复杂度', '出水角度', '封孔工艺']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE i.index_code = 'coolant_channel_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE i.index_code = 'coolant_channel_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'coolant_hole_count' WHERE i.index_code = 'coolant_channel_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'coolant_hole_diameter' WHERE i.index_code = 'coolant_channel_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'coolant_channel_length' WHERE i.index_code = 'coolant_channel_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'coolant_channel_geometry_and_length' WHERE i.index_code = 'coolant_channel_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'coolant_exit_angle' WHERE i.index_code = 'coolant_channel_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'coolant_hole_sealing_process' WHERE i.index_code = 'coolant_channel_complexity_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('edge_quality_index', 'Edge Quality Index', '刃口质量指数', '物理制造指数', '汇总刃口半径、K-factor、倒棱、钝化一致性和微观对称度。', '刃口质量 = 锋利性 + 一致性 + 抗崩刃能力 - 缺陷风险', ARRAY['平均刃口半径', '刃口半径离散度', 'K-factor 刃口钝化偏置系数', '倒棱宽度', '齿间负载均衡度', '微崩口数量']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '检测质量' WHERE i.index_code = 'edge_quality_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'edge_radius_mean' WHERE i.index_code = 'edge_quality_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'edge_radius_variation' WHERE i.index_code = 'edge_quality_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'edge_k_factor_bias' WHERE i.index_code = 'edge_quality_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'land_width' WHERE i.index_code = 'edge_quality_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'tooth_to_tooth_load_balance' WHERE i.index_code = 'edge_quality_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'micro_chipping_count' WHERE i.index_code = 'edge_quality_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('reconditioning_value_index', 'Reconditioning Value Index', '可再制造残值指数', '物理制造指数', '汇总修磨、退涂、重涂、钴流失和基体剩余寿命。', '再制造残值 = 剩余强度 + 可重涂次数 - 退涂损伤 - 钴流失风险', ARRAY['基体可重涂寿命', '剥涂层次数限制', '钴流失风险', '退涂后残余强度', '剩余基体寿命']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE i.index_code = 'reconditioning_value_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '材料成本' WHERE i.index_code = 'reconditioning_value_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'recoatable_substrate_life' WHERE i.index_code = 'reconditioning_value_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'stripping_cycle_limit' WHERE i.index_code = 'reconditioning_value_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'cobalt_leaching_risk' WHERE i.index_code = 'reconditioning_value_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'residual_strength_after_stripping' WHERE i.index_code = 'reconditioning_value_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'remaining_substrate_life' WHERE i.index_code = 'reconditioning_value_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('coating_batch_cost_index', 'Coating Batch Cost Index', '涂层批处理成本指数', '物理制造指数', '汇总炉次成本、腔体占用率、装炉密度、混炉兼容性和夹具适配性。', '涂层批处理成本 = 炉次固定成本 / 有效装炉数量 + 夹具与混炉损失', ARRAY['涂层炉次成本', '腔体占用率', '有效装炉密度', '夹具兼容性', '混炉兼容性', '遮蔽风险']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '涂层分摊' WHERE i.index_code = 'coating_batch_cost_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'batch_furnace_cost' WHERE i.index_code = 'coating_batch_cost_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'batch_cavity_occupancy' WHERE i.index_code = 'coating_batch_cost_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'effective_loading_density' WHERE i.index_code = 'coating_batch_cost_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'fixture_compatibility' WHERE i.index_code = 'coating_batch_cost_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'coating_batch_compatibility' WHERE i.index_code = 'coating_batch_cost_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'shadowing_risk' WHERE i.index_code = 'coating_batch_cost_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('setup_loss_index', 'Setup Loss Index', '换线损失指数', '市场商务指数', '汇总调机、首件确认、试磨报废、编程和小批量分摊成本。', '换线损失 = 固定准备成本 + 首件检测 + 试磨报废 + 小批量分摊', ARRAY['换线时间', '换线损失费', '首件确认成本', '试磨数量', '编程成本', '小批量成本倍数']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE i.index_code = 'setup_loss_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '加工难度' WHERE i.index_code = 'setup_loss_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'setup_time' WHERE i.index_code = 'setup_loss_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'set_up_scrapping_risk' WHERE i.index_code = 'setup_loss_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'first_article_cost' WHERE i.index_code = 'setup_loss_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'trial_grinding_quantity' WHERE i.index_code = 'setup_loss_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'programming_cost' WHERE i.index_code = 'setup_loss_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'small_batch_cost_multiplier' WHERE i.index_code = 'setup_loss_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('supply_risk_premium_index', 'Supply Risk Premium Index', '供应链风险溢价指数', '市场商务指数', '汇总地理冗余度、单一来源依赖、出口管制和关键材料供应风险。', '供应风险溢价 = 材料波动 + 来源集中度 + 政策风险 + 到岸成本不确定性', ARRAY['钨价格敏感度', '钴价格敏感度', '供应链地理冗余度', '单一来源依赖度', '出口管制风险', '关税暴露度']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '供应风险' WHERE i.index_code = 'supply_risk_premium_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'tungsten_price_sensitivity' WHERE i.index_code = 'supply_risk_premium_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'cobalt_price_sensitivity' WHERE i.index_code = 'supply_risk_premium_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'supply_chain_geo_redundancy' WHERE i.index_code = 'supply_risk_premium_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'single_source_dependency' WHERE i.index_code = 'supply_risk_premium_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'export_control_risk' WHERE i.index_code = 'supply_risk_premium_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'tariff_exposure' WHERE i.index_code = 'supply_risk_premium_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('packaging_risk_index', 'Packaging Risk Index', '包装无损风险指数', '市场商务指数', '汇总微径刀、重型刀具、真空氮气包装和运输震动风险。', '包装风险 = 刀具脆弱性 + 运输损伤概率 + 特殊包装要求 + 客户标签复杂度', ARRAY['包装保护等级', '微径刀具防护包装', '重型刀具包装结构', '真空包装', '氮气保护包装', '运输震动风险']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE i.index_code = 'packaging_risk_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'packaging_protection_grade' WHERE i.index_code = 'packaging_risk_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'micro_tool_protection' WHERE i.index_code = 'packaging_risk_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'heavy_tool_packaging' WHERE i.index_code = 'packaging_risk_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'vacuum_packaging' WHERE i.index_code = 'packaging_risk_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'nitrogen_packaging' WHERE i.index_code = 'packaging_risk_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'transport_vibration_risk' WHERE i.index_code = 'packaging_risk_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definitions (index_code, name_en, name_zh, layer_zh, description, formula_text, source_field_names)
VALUES ('commercial_friction_index', 'Commercial Friction Index', '商业摩擦成本指数', '市场商务指数', '汇总 VMI、账期、需求碎片化、预测偏差、MOQ 和交付服务成本。', '商业摩擦成本 = 资金占用 + 需求波动 + 交付压力 + 合同条款让利', ARRAY['VMI 资金占用费', '付款周期', '需求碎片化程度', '预测准确率', 'MOQ 最小起订量', '交期', '返利政策']::text[])
ON CONFLICT (index_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_zh = EXCLUDED.name_zh, layer_zh = EXCLUDED.layer_zh, description = EXCLUDED.description, formula_text = EXCLUDED.formula_text, source_field_names = EXCLUDED.source_field_names, updated_at = now();
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '商务摩擦' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_definition_tags (index_id, tag_code)
SELECT i.index_id, t.tag_code FROM quote_index_definitions i JOIN quote_impact_tags t ON t.name_zh = '交付服务' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'financial_carrying_cost_of_vmi' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'payment_terms' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'order_fragmentation' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'forecast_accuracy' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'minimum_order_quantity' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'lead_time' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;
INSERT INTO quote_index_source_fields (index_id, field_id)
SELECT i.index_id, f.field_id FROM quote_index_definitions i JOIN quote_field_definitions f ON f.field_code = 'rebate_policy' WHERE i.index_code = 'commercial_friction_index'
ON CONFLICT DO NOTHING;

CREATE OR REPLACE VIEW v_index_source_fields AS
SELECT
  i.index_id,
  i.index_code,
  i.name_en,
  i.name_zh,
  COALESCE(array_agg(f.field_code ORDER BY s.weight DESC NULLS LAST, f.field_code) FILTER (WHERE f.field_id IS NOT NULL), ARRAY[]::text[]) AS source_field_codes,
  COALESCE(array_agg(f.name_zh ORDER BY s.weight DESC NULLS LAST, f.field_code) FILTER (WHERE f.field_id IS NOT NULL), ARRAY[]::text[]) AS source_field_names,
  COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'field_id', f.field_id,
        'field_code', f.field_code,
        'name_zh', f.name_zh,
        'weight', s.weight,
        'role', s.role
      )
      ORDER BY s.weight DESC NULLS LAST, f.field_code
    ) FILTER (WHERE f.field_id IS NOT NULL),
    '[]'::jsonb
  ) AS source_fields
FROM quote_index_definitions i
LEFT JOIN quote_index_source_fields s ON s.index_id = i.index_id
LEFT JOIN quote_field_definitions f ON f.field_id = s.field_id
GROUP BY i.index_id, i.index_code, i.name_en, i.name_zh;

CREATE OR REPLACE VIEW v_latest_price_output AS
SELECT DISTINCT ON (qpo.quote_item_id)
  qpo.*
FROM quote_price_outputs qpo
JOIN quote_calculation_runs runs ON runs.run_id = qpo.run_id
WHERE runs.status = 'succeeded'
ORDER BY qpo.quote_item_id, qpo.calculated_at DESC, qpo.price_output_id DESC;

CREATE OR REPLACE VIEW v_field_catalog AS
SELECT
  s.section_id, s.title_zh AS section_name,
  g.group_id, g.name_zh AS group_name, g.name_en AS group_name_en,
  f.field_id, f.field_code, f.name_zh, f.name_en, f.description,
  f.value_kind, f.raw_type_zh, f.impact_level, f.metadata,
  COALESCE(array_agg(t.name_zh ORDER BY t.sort_order) FILTER (WHERE t.tag_code IS NOT NULL), ARRAY[]::text[]) AS impact_tags
FROM quote_field_definitions f
JOIN quote_field_groups g ON g.group_id = f.group_id
JOIN quote_sections s ON s.section_id = g.section_id
LEFT JOIN quote_field_definition_tags ft ON ft.field_id = f.field_id
LEFT JOIN quote_impact_tags t ON t.tag_code = ft.tag_code
GROUP BY s.section_id, s.title_zh, s.sort_order, g.group_id, g.name_zh, g.name_en, g.sort_order, f.field_id
ORDER BY s.sort_order, g.sort_order, f.sort_order;

DROP VIEW IF EXISTS v_quote_filter_values;

CREATE OR REPLACE VIEW v_quote_filter_values AS
SELECT
  q.quote_id, q.quote_no, q.customer_name,
  q.customer_id, cst.canonical_name AS customer_canonical_name,
  qi.quote_item_id, qi.line_no, qi.source_file_id AS item_source_file_id,
  qi.supplier_id, s.canonical_name AS supplier_canonical_name, qi.supplier_name, qi.product_name, qi.raw_item_name,
  qi.tool_family, qi.drawing_no, qi.customer_part_no, qi.supplier_part_no,
  qi.quantity, qi.unit, qi.currency, qi.quoted_unit_price, qi.quoted_total_price,
  qi.lead_time_days, qi.moq, qi.tax_included,
  COALESCE(qct.incoterms, qrct.incoterms) AS incoterms,
  COALESCE(qct.payment_terms, qrct.payment_terms) AS payment_terms,
  COALESCE(qct.valid_until, qrct.valid_until) AS valid_until,
  COALESCE(qct.tax_rate, qrct.tax_rate) AS tax_rate,
  qct.discount_rate,
  COALESCE(qct.freight_cost, qrct.freight_cost) AS freight_cost,
  COALESCE(qct.price_basis, qrct.price_basis) AS price_basis,
  tm.tool_id, tm.brand_id, b.canonical_name AS brand_canonical_name, tm.normalized_name, tm.normalized_model, tm.spec_fingerprint, tm.tool_category,
  tm.tool_subcategory, tm.structure_type, tm.standard_or_custom, tm.iso_code,
  tm.application_material_group,
  c.section_name, c.group_name, c.field_code, c.name_zh, c.name_en, c.value_kind, c.impact_level, c.impact_tags,
  v.source_file_id AS field_source_file_id,
  v.value_text, v.value_numeric, v.value_boolean, v.value_json, v.unit AS field_unit, v.unit_code AS field_unit_code
FROM quote_requests q
JOIN quote_items qi ON qi.quote_id = q.quote_id
LEFT JOIN customers cst ON cst.customer_id = q.customer_id
LEFT JOIN suppliers s ON s.supplier_id = qi.supplier_id
LEFT JOIN quote_commercial_terms qct ON qct.quote_item_id = qi.quote_item_id
LEFT JOIN quote_request_commercial_terms qrct ON qrct.quote_id = q.quote_id
LEFT JOIN tool_master tm ON tm.tool_id = qi.tool_id
LEFT JOIN brands b ON b.brand_id = tm.brand_id
JOIN quote_field_values v ON v.quote_item_id = qi.quote_item_id
JOIN v_field_catalog c ON c.field_id = v.field_id;

DROP VIEW IF EXISTS v_quote_item_summary;

CREATE OR REPLACE VIEW v_quote_item_summary AS
SELECT
  q.quote_id,
  q.quote_no,
  q.customer_id,
  cst.canonical_name AS customer_canonical_name,
  q.customer_name,
  qi.quote_item_id,
  qi.line_no,
  qi.supplier_id,
  s.canonical_name AS supplier_canonical_name,
  qi.supplier_name,
  qi.product_name,
  tm.brand_id,
  b.canonical_name AS brand_canonical_name,
  tm.normalized_name,
  tm.normalized_model,
  tm.spec_fingerprint,
  tsn.diameter_mm,
  tsn.flute_count,
  tsn.coating_type,
  tsn.substrate_type,
  qi.quantity,
  qi.currency,
  qi.quoted_unit_price,
  COALESCE(qct.incoterms, qrct.incoterms) AS incoterms,
  COALESCE(qct.payment_terms, qrct.payment_terms) AS payment_terms,
  COALESCE(qct.valid_until, qrct.valid_until) AS valid_until,
  qpo.currency AS calculated_currency,
  qpo.final_unit_price,
  qpo.price_reasonableness,
  qpo.recommendation,
  qi.lead_time_days
FROM quote_requests q
JOIN quote_items qi ON qi.quote_id = q.quote_id
LEFT JOIN customers cst ON cst.customer_id = q.customer_id
LEFT JOIN suppliers s ON s.supplier_id = qi.supplier_id
LEFT JOIN tool_master tm ON tm.tool_id = qi.tool_id
LEFT JOIN brands b ON b.brand_id = tm.brand_id
LEFT JOIN quote_commercial_terms qct ON qct.quote_item_id = qi.quote_item_id
LEFT JOIN quote_request_commercial_terms qrct ON qrct.quote_id = q.quote_id
LEFT JOIN tool_specs_normalized tsn ON tsn.quote_item_id = qi.quote_item_id
LEFT JOIN v_latest_price_output qpo ON qpo.quote_item_id = qi.quote_item_id;

CREATE INDEX IF NOT EXISTS idx_quote_field_groups_section ON quote_field_groups(section_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_quote_fields_group ON quote_field_definitions(group_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_quote_fields_code ON quote_field_definitions(field_code);
CREATE INDEX IF NOT EXISTS idx_quote_fields_name_trgm ON quote_field_definitions USING gin (name_zh gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_quote_field_tags_tag ON quote_field_definition_tags(tag_code, field_id);
CREATE INDEX IF NOT EXISTS idx_quote_field_options_field ON quote_field_options(field_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_quote_field_validation_rules_field ON quote_field_validation_rules(field_id, is_active);
CREATE INDEX IF NOT EXISTS idx_quote_field_values_item ON quote_field_values(quote_item_id);
CREATE INDEX IF NOT EXISTS idx_quote_field_values_source_file ON quote_field_values(source_file_id);
CREATE INDEX IF NOT EXISTS idx_quote_field_values_field_numeric ON quote_field_values(field_id, value_numeric);
CREATE INDEX IF NOT EXISTS idx_quote_field_values_field_boolean ON quote_field_values(field_id, value_boolean);
CREATE INDEX IF NOT EXISTS idx_quote_field_values_text_trgm ON quote_field_values USING gin (value_text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_quote_field_values_unit_code ON quote_field_values(unit_code);
CREATE INDEX IF NOT EXISTS idx_quote_field_value_candidates_item_field ON quote_field_value_candidates(quote_item_id, field_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_quote_field_value_candidates_source_file ON quote_field_value_candidates(source_file_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_quote_field_value_candidates_selected ON quote_field_value_candidates(quote_item_id, field_id) WHERE is_selected;
CREATE INDEX IF NOT EXISTS idx_quote_calculation_runs_quote ON quote_calculation_runs(quote_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_quote_calculation_runs_status ON quote_calculation_runs(status);
CREATE INDEX IF NOT EXISTS idx_quote_index_values_item ON quote_index_values(quote_item_id);
CREATE INDEX IF NOT EXISTS idx_quote_index_values_run ON quote_index_values(run_id);
CREATE INDEX IF NOT EXISTS idx_quote_index_values_index ON quote_index_values(index_id);
CREATE INDEX IF NOT EXISTS idx_quote_index_values_input_snapshot_gin ON quote_index_values USING gin (input_snapshot);
CREATE INDEX IF NOT EXISTS idx_quote_index_source_fields_field ON quote_index_source_fields(field_id);
CREATE INDEX IF NOT EXISTS idx_quote_price_outputs_item ON quote_price_outputs(quote_item_id, calculated_at DESC);
CREATE INDEX IF NOT EXISTS idx_quote_price_outputs_run ON quote_price_outputs(run_id);
CREATE INDEX IF NOT EXISTS idx_quote_price_outputs_final_price ON quote_price_outputs(final_unit_price);
CREATE INDEX IF NOT EXISTS idx_quote_price_outputs_reasonableness ON quote_price_outputs(price_reasonableness);
CREATE INDEX IF NOT EXISTS idx_quote_price_outputs_breakdown_gin ON quote_price_outputs USING gin (breakdown);
CREATE INDEX IF NOT EXISTS idx_quote_price_output_components_output ON quote_price_output_components(price_output_id, component_code);
CREATE UNIQUE INDEX IF NOT EXISTS uq_quote_price_output_components_code ON quote_price_output_components(price_output_id, component_code);
CREATE INDEX IF NOT EXISTS idx_quote_price_output_components_driver ON quote_price_output_components(driver_field_id);
CREATE INDEX IF NOT EXISTS idx_customers_canonical_name_trgm ON customers USING gin (canonical_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_customer_aliases_customer ON customer_aliases(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_aliases_alias_trgm ON customer_aliases USING gin (alias_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_brands_canonical_name_trgm ON brands USING gin (canonical_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_brand_aliases_brand ON brand_aliases(brand_id);
CREATE INDEX IF NOT EXISTS idx_brand_aliases_alias_trgm ON brand_aliases USING gin (alias_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_suppliers_canonical_name_trgm ON suppliers USING gin (canonical_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_supplier_aliases_supplier ON supplier_aliases(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_aliases_alias_trgm ON supplier_aliases USING gin (alias_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_historical_tool_prices_supplier_time ON historical_tool_prices(supplier_id, observed_at DESC);
CREATE INDEX IF NOT EXISTS idx_historical_tool_prices_tool_time ON historical_tool_prices(tool_id, observed_at DESC);
CREATE INDEX IF NOT EXISTS idx_historical_tool_prices_type_time ON historical_tool_prices(price_type, observed_at DESC);
CREATE INDEX IF NOT EXISTS idx_market_price_series_code_date ON market_price_series(commodity_code, price_date DESC);
DROP INDEX IF EXISTS uq_market_price_series_quote_basis;
CREATE UNIQUE INDEX IF NOT EXISTS uq_market_price_series_quote_basis
ON market_price_series (
  commodity_code,
  price_date,
  currency,
  unit,
  (COALESCE(source, '')),
  (COALESCE(market_region, '')),
  price_kind,
  (COALESCE(contract_month, DATE '0001-01-01')),
  (COALESCE(quality_grade, '')),
  (COALESCE(tax_included, false))
);
CREATE INDEX IF NOT EXISTS idx_market_price_series_basis ON market_price_series(commodity_code, market_region, price_kind, quality_grade, price_date DESC);
CREATE INDEX IF NOT EXISTS idx_fx_rates_pair_date ON fx_rates(base_currency, quote_currency, rate_date DESC);
CREATE INDEX IF NOT EXISTS idx_supplier_price_observations_supplier_time ON supplier_price_observations(supplier_id, observed_at DESC);
CREATE INDEX IF NOT EXISTS idx_supplier_price_observations_tool_time ON supplier_price_observations(tool_id, observed_at DESC);
CREATE INDEX IF NOT EXISTS idx_supplier_price_observations_quote_item ON supplier_price_observations(quote_item_id);
CREATE INDEX IF NOT EXISTS idx_market_indicator_values_time ON market_indicator_values(indicator_id, observed_at DESC);
CREATE INDEX IF NOT EXISTS idx_prediction_models_code_version ON prediction_models(model_code, model_version);
CREATE INDEX IF NOT EXISTS idx_quote_feature_snapshots_item ON quote_feature_snapshots(quote_item_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_quote_prediction_results_model ON quote_prediction_results(model_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tool_master_brand ON tool_master(brand_id);
CREATE INDEX IF NOT EXISTS idx_tool_master_model ON tool_master(normalized_model);
CREATE INDEX IF NOT EXISTS idx_tool_master_name_trgm ON tool_master USING gin (normalized_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_tool_master_category ON tool_master(tool_category, tool_subcategory);
CREATE UNIQUE INDEX IF NOT EXISTS uq_tool_master_brand_model
ON tool_master(brand_id, normalized_model)
WHERE brand_id IS NOT NULL AND normalized_model IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_tool_master_spec_fingerprint
ON tool_master(spec_fingerprint)
WHERE spec_fingerprint IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_raw_quote_files_quote ON raw_quote_files(quote_id, upload_time);
CREATE INDEX IF NOT EXISTS idx_raw_quote_files_parse_status ON raw_quote_files(parse_status);
CREATE INDEX IF NOT EXISTS idx_raw_quote_files_name_trgm ON raw_quote_files USING gin (file_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_quote_requests_status_time ON quote_requests(status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_quote_requests_customer_id ON quote_requests(customer_id);
CREATE INDEX IF NOT EXISTS idx_quote_items_quote ON quote_items(quote_id, line_no);
CREATE INDEX IF NOT EXISTS idx_quote_items_status ON quote_items(item_status);
CREATE INDEX IF NOT EXISTS idx_quote_items_tool ON quote_items(tool_id);
CREATE INDEX IF NOT EXISTS idx_quote_items_source_file ON quote_items(source_file_id);
CREATE INDEX IF NOT EXISTS idx_quote_items_supplier_id ON quote_items(supplier_id);
CREATE INDEX IF NOT EXISTS idx_quote_items_supplier ON quote_items(supplier_name);
CREATE INDEX IF NOT EXISTS idx_quote_items_quoted_unit_price ON quote_items(currency, quoted_unit_price);
CREATE INDEX IF NOT EXISTS idx_quote_items_lead_time ON quote_items(lead_time_days);
CREATE INDEX IF NOT EXISTS idx_quote_items_moq ON quote_items(moq);
CREATE INDEX IF NOT EXISTS idx_quote_items_product_trgm ON quote_items USING gin (product_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_quote_items_raw_name_trgm ON quote_items USING gin (raw_item_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_tool_specs_normalized_item ON tool_specs_normalized(quote_item_id);
CREATE INDEX IF NOT EXISTS idx_tool_specs_normalized_tool ON tool_specs_normalized(tool_id);
CREATE INDEX IF NOT EXISTS idx_tool_specs_normalized_category ON tool_specs_normalized(tool_category, tool_subcategory);
CREATE INDEX IF NOT EXISTS idx_tool_specs_normalized_diameter ON tool_specs_normalized(diameter_mm);
CREATE INDEX IF NOT EXISTS idx_tool_specs_normalized_coating ON tool_specs_normalized(coating_type);
CREATE INDEX IF NOT EXISTS idx_quote_requests_customer ON quote_requests(customer_name);
CREATE INDEX IF NOT EXISTS idx_quote_commercial_terms_valid_until ON quote_commercial_terms(valid_until);
CREATE INDEX IF NOT EXISTS idx_quote_request_commercial_terms_valid_until ON quote_request_commercial_terms(valid_until);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_customers_set_updated_at' AND tgrelid = 'customers'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_customers_set_updated_at ON customers';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_customers_set_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_customer_aliases_set_updated_at' AND tgrelid = 'customer_aliases'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_customer_aliases_set_updated_at ON customer_aliases';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_customer_aliases_set_updated_at BEFORE UPDATE ON customer_aliases FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_brands_set_updated_at' AND tgrelid = 'brands'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_brands_set_updated_at ON brands';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_brands_set_updated_at BEFORE UPDATE ON brands FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_brand_aliases_set_updated_at' AND tgrelid = 'brand_aliases'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_brand_aliases_set_updated_at ON brand_aliases';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_brand_aliases_set_updated_at BEFORE UPDATE ON brand_aliases FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_sections_set_updated_at' AND tgrelid = 'quote_sections'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_sections_set_updated_at ON quote_sections';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_sections_set_updated_at BEFORE UPDATE ON quote_sections FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_field_groups_set_updated_at' AND tgrelid = 'quote_field_groups'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_field_groups_set_updated_at ON quote_field_groups';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_field_groups_set_updated_at BEFORE UPDATE ON quote_field_groups FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_impact_tags_set_updated_at' AND tgrelid = 'quote_impact_tags'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_impact_tags_set_updated_at ON quote_impact_tags';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_impact_tags_set_updated_at BEFORE UPDATE ON quote_impact_tags FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_requests_set_updated_at' AND tgrelid = 'quote_requests'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_requests_set_updated_at ON quote_requests';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_requests_set_updated_at BEFORE UPDATE ON quote_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_raw_quote_files_set_updated_at' AND tgrelid = 'raw_quote_files'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_raw_quote_files_set_updated_at ON raw_quote_files';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_raw_quote_files_set_updated_at BEFORE UPDATE ON raw_quote_files FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_tool_master_set_updated_at' AND tgrelid = 'tool_master'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_tool_master_set_updated_at ON tool_master';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_tool_master_set_updated_at BEFORE UPDATE ON tool_master FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_suppliers_set_updated_at' AND tgrelid = 'suppliers'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_suppliers_set_updated_at ON suppliers';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_suppliers_set_updated_at BEFORE UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_supplier_aliases_set_updated_at' AND tgrelid = 'supplier_aliases'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_supplier_aliases_set_updated_at ON supplier_aliases';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_supplier_aliases_set_updated_at BEFORE UPDATE ON supplier_aliases FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_items_set_updated_at' AND tgrelid = 'quote_items'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_items_set_updated_at ON quote_items';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_items_set_updated_at BEFORE UPDATE ON quote_items FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_commercial_terms_set_updated_at' AND tgrelid = 'quote_commercial_terms'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_commercial_terms_set_updated_at ON quote_commercial_terms';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_commercial_terms_set_updated_at BEFORE UPDATE ON quote_commercial_terms FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_request_commercial_terms_set_updated_at' AND tgrelid = 'quote_request_commercial_terms'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_request_commercial_terms_set_updated_at ON quote_request_commercial_terms';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_request_commercial_terms_set_updated_at BEFORE UPDATE ON quote_request_commercial_terms FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_tool_specs_normalized_set_updated_at' AND tgrelid = 'tool_specs_normalized'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_tool_specs_normalized_set_updated_at ON tool_specs_normalized';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_tool_specs_normalized_set_updated_at BEFORE UPDATE ON tool_specs_normalized FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_field_definitions_set_updated_at' AND tgrelid = 'quote_field_definitions'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_field_definitions_set_updated_at ON quote_field_definitions';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_field_definitions_set_updated_at BEFORE UPDATE ON quote_field_definitions FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_field_options_set_updated_at' AND tgrelid = 'quote_field_options'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_field_options_set_updated_at ON quote_field_options';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_field_options_set_updated_at BEFORE UPDATE ON quote_field_options FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_field_validation_rules_set_updated_at' AND tgrelid = 'quote_field_validation_rules'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_field_validation_rules_set_updated_at ON quote_field_validation_rules';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_field_validation_rules_set_updated_at BEFORE UPDATE ON quote_field_validation_rules FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_field_values_set_updated_at' AND tgrelid = 'quote_field_values'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_field_values_set_updated_at ON quote_field_values';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_field_values_set_updated_at BEFORE UPDATE ON quote_field_values FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_calculation_runs_set_updated_at' AND tgrelid = 'quote_calculation_runs'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_calculation_runs_set_updated_at ON quote_calculation_runs';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_calculation_runs_set_updated_at BEFORE UPDATE ON quote_calculation_runs FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_index_definitions_set_updated_at' AND tgrelid = 'quote_index_definitions'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_index_definitions_set_updated_at ON quote_index_definitions';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_index_definitions_set_updated_at BEFORE UPDATE ON quote_index_definitions FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_index_values_set_updated_at' AND tgrelid = 'quote_index_values'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_index_values_set_updated_at ON quote_index_values';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_index_values_set_updated_at BEFORE UPDATE ON quote_index_values FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_quote_price_outputs_set_updated_at' AND tgrelid = 'quote_price_outputs'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_quote_price_outputs_set_updated_at ON quote_price_outputs';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_quote_price_outputs_set_updated_at BEFORE UPDATE ON quote_price_outputs FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_historical_tool_prices_set_updated_at' AND tgrelid = 'historical_tool_prices'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_historical_tool_prices_set_updated_at ON historical_tool_prices';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_historical_tool_prices_set_updated_at BEFORE UPDATE ON historical_tool_prices FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_market_price_series_set_updated_at' AND tgrelid = 'market_price_series'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_market_price_series_set_updated_at ON market_price_series';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_market_price_series_set_updated_at BEFORE UPDATE ON market_price_series FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_supplier_price_observations_set_updated_at' AND tgrelid = 'supplier_price_observations'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_supplier_price_observations_set_updated_at ON supplier_price_observations';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_supplier_price_observations_set_updated_at BEFORE UPDATE ON supplier_price_observations FOR EACH ROW EXECUTE FUNCTION set_updated_at()';

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_market_indicator_definitions_set_updated_at' AND tgrelid = 'market_indicator_definitions'::regclass AND NOT tgisinternal) THEN
    EXECUTE 'DROP TRIGGER trg_market_indicator_definitions_set_updated_at ON market_indicator_definitions';
  END IF;
  EXECUTE 'CREATE TRIGGER trg_market_indicator_definitions_set_updated_at BEFORE UPDATE ON market_indicator_definitions FOR EACH ROW EXECUTE FUNCTION set_updated_at()';
END $$;

