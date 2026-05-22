CREATE TABLE IF NOT EXISTS market_factor_prices (
  id bigserial PRIMARY KEY,
  factor_code text NOT NULL,
  factor_name text NOT NULL,
  factor_type text NOT NULL,
  price_date date NOT NULL,
  close_price numeric(18,6) NOT NULL,
  source_provider text NOT NULL,
  source_symbol text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT market_factor_prices_type_check CHECK (
    factor_type IN (
      'industrial_metal',
      'energy',
      'fx',
      'precious_metal',
      'equity_index',
      'synthetic_index'
    )
  ),
  CONSTRAINT market_factor_prices_unique UNIQUE (factor_code, price_date, source_provider)
);

CREATE TABLE IF NOT EXISTS market_factor_features (
  id bigserial PRIMARY KEY,
  factor_code text NOT NULL,
  factor_name text NOT NULL,
  factor_type text NOT NULL,
  price_date date NOT NULL,
  close_price numeric(18,6) NOT NULL,
  return_1d double precision,
  return_7d double precision,
  return_30d double precision,
  return_90d double precision,
  rolling_std_30d double precision,
  rolling_std_90d double precision,
  momentum_30d double precision,
  momentum_90d double precision,
  zscore_90d double precision,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT market_factor_features_type_check CHECK (
    factor_type IN (
      'industrial_metal',
      'energy',
      'fx',
      'precious_metal',
      'equity_index',
      'synthetic_index'
    )
  ),
  CONSTRAINT market_factor_features_unique UNIQUE (factor_code, price_date)
);

CREATE TABLE IF NOT EXISTS market_panel_training_dataset (
  id bigserial PRIMARY KEY,
  price_date date NOT NULL,
  metal_code text NOT NULL,
  metal_name text NOT NULL,
  close_price numeric(18,6) NOT NULL,
  pred_lgb_return_7d double precision,
  pred_lgb_return_30d double precision,
  pred_lgb_return_90d double precision,
  metal_return_1d double precision,
  metal_return_7d double precision,
  metal_return_30d double precision,
  metal_return_90d double precision,
  metal_volatility_30d double precision,
  metal_volatility_90d double precision,
  metal_momentum_30d double precision,
  metal_momentum_90d double precision,
  metal_zscore_90d double precision,
  metal_drawdown_90d double precision,
  industrial_metals_return_30d double precision,
  industrial_metals_return_90d double precision,
  energy_return_30d double precision,
  energy_return_90d double precision,
  usd_return_30d double precision,
  usd_return_90d double precision,
  precious_metals_return_30d double precision,
  precious_metals_return_90d double precision,
  risk_asset_return_30d double precision,
  risk_asset_return_90d double precision,
  cu_al_ratio double precision,
  ni_co_ratio double precision,
  co_cu_ratio double precision,
  ni_cu_ratio double precision,
  sn_cu_ratio double precision,
  zn_al_ratio double precision,
  pb_al_ratio double precision,
  iron_ore_cu_ratio double precision,
  target_return_7d double precision,
  target_return_30d double precision,
  target_return_90d double precision,
  target_excess_return_7d double precision,
  target_excess_return_30d double precision,
  target_excess_return_90d double precision,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT market_panel_training_dataset_unique UNIQUE (price_date, metal_code)
);

CREATE TABLE IF NOT EXISTS market_production_model_versions (
  model_name text NOT NULL,
  model_version text NOT NULL,
  model_type text NOT NULL,
  horizon_day integer NOT NULL,
  target_type text NOT NULL,
  train_start_date date,
  train_end_date date,
  feature_count integer,
  sample_count integer,
  metal_count integer,
  factor_count integer,
  model_path text,
  feature_config_path text,
  train_status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT market_production_model_versions_unique UNIQUE (model_name, model_version, horizon_day, target_type)
);

CREATE TABLE IF NOT EXISTS market_production_forecasts (
  id bigserial PRIMARY KEY,
  model_version text NOT NULL,
  forecast_date date NOT NULL,
  metal_code text NOT NULL,
  metal_name text NOT NULL,
  base_price numeric(18,6) NOT NULL,
  horizon_day integer NOT NULL,
  pred_lgb_return double precision,
  pred_catboost_excess_return double precision,
  pred_market_factor_return double precision,
  pred_pair_adjustment double precision,
  final_predicted_return double precision,
  final_predicted_price numeric(18,6),
  predicted_direction text,
  predicted_return_p10 double precision,
  predicted_return_p50 double precision,
  predicted_return_p90 double precision,
  predicted_price_p10 numeric(18,6),
  predicted_price_p50 numeric(18,6),
  predicted_price_p90 numeric(18,6),
  signal_strength double precision,
  relative_strength_rank integer,
  volatility_level text,
  risk_level text,
  procurement_signal text,
  procurement_advice text,
  key_drivers jsonb,
  data_quality_score double precision,
  model_reliability_level text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT market_production_forecasts_unique UNIQUE (model_version, forecast_date, metal_code, horizon_day)
);

CREATE INDEX IF NOT EXISTS idx_market_factor_prices_code_date ON market_factor_prices(factor_code, price_date DESC);
CREATE INDEX IF NOT EXISTS idx_market_factor_features_code_date ON market_factor_features(factor_code, price_date DESC);
CREATE INDEX IF NOT EXISTS idx_market_panel_training_dataset_date ON market_panel_training_dataset(price_date DESC, metal_code);
CREATE INDEX IF NOT EXISTS idx_market_production_forecasts_date ON market_production_forecasts(forecast_date DESC, horizon_day);
CREATE INDEX IF NOT EXISTS idx_market_production_forecasts_metal ON market_production_forecasts(metal_code, forecast_date DESC);

