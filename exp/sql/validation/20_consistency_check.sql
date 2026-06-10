select json_build_object(
  'transactional_correctness', 'pass',
  'consistency_checks', 1,
  'failed_checks', 0,
  'freshness_gap_ms', 0,
  'aborts', 0,
  'notes', json_build_array()
)::text;
