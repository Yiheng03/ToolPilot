# Tool Quote Benchmark Split

`version/v1/tool_quote_benchmark_v1.json` is the original mixed benchmark and must remain unchanged.

## formula_eval

`formula_eval` is a price formula benchmark. It uses `answer_supplier`, `answer_category`, and `answer_spec` as oracle input, then evaluates the formula prediction against the cleaned target price derived from `answer_price`.

This mode only validates the pricing formula. It does not validate large-model question answering, supplier/category/spec extraction, retrieval, or multi-supplier recommendation ability.

When reporting results, do not describe `formula_eval` as a complete agent benchmark.

## agent_eval

`agent_eval` may only pass `question` to the tested agent.

The agent under test is not allowed to read `answer_supplier`, `answer_category`, `answer_spec`, or `answer_price` as input. Those fields are only expected answers for offline scoring.

## ranking_eval

`ranking_eval` is evaluated separately from single-item price formula metrics.

Ranking tasks evaluate cheapest supplier/category selection and cheapest price error. They are not included in MAPE, MdAPE, interval hit rate, or other single-item formula metrics.
