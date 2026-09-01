# Verifier import-block: the deliverable must mirror the graph in pure numpy,
# so executing the reference with onnxruntime is disallowed at verify time.
raise ImportError(
    "onnxruntime is blocked for the mirror deliverable (pure numpy only)")
