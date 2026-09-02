# Llama

Answer four **true/false** statements about the architecture of Meta's **Llama** family of large language models (Llama 2 / 3 / 3.1). Answer `true` if the statement is correct, `false` if it is incorrect.

1. Llama models use **Grouped-Query Attention (GQA)** for at least some of their layers, which reduces KV-cache memory versus full multi-head attention. *(Llama 2 70B and Llama 3 use GQA in some/all layers.)*
2. Llama models use **Rotary Position Embedding (RoPE)**, not sinusoidal positional encoding tables.
3. Llama models normalize hidden states with **RMSNorm** (root-mean-square layer normalization), not layer normalization.
4. Llama models' pre-decoder attention is **causal/decoder-only**; they do not use a cross-attention encoder-decoder design (unlike T5).

Write the four boolean answers to `/app/answer.json`:

```json
{
  "uses_gqa": true,
  "uses_rope": true,
  "uses_rmsnorm": true,
  "decoder_only": true
}
```

Set each to the correct value.