# llm

OpenAI-compatible local inference via
[llama-swap](https://github.com/mostlygeek/llama-swap) fronting
[llama.cpp](https://github.com/ggml-org/llama.cpp). Served on
`llm.farooqui.ai`, tailnet-only.

## Why this stack on this hardware

The homelab host is an Intel i7-8700 (Coffee Lake, 6c/12t, AVX2 only,
no AVX-512, no AMX) with 128 GB DDR4 and no discrete GPU. The UHD
630 iGPU has no meaningful compute budget for LLM inference and
shares the same DRAM bandwidth as the CPU, so neither SYCL nor
OpenVINO is worth the ops surface. llama.cpp's pure-CPU path is the
correct target.

Memory bandwidth, not capacity, is the dominant constraint on this
platform: dual-channel DDR4-2666 peaks around 40 GB/s, which caps
generation throughput at roughly `bandwidth / active_weights`. That
is why the primary model is **Qwen3.6-35B-A3B** (Mixture of Experts,
35B total parameters, 3B active per token) rather than a comparable
dense model: only the active 3B are streamed through memory per
decode step.

## Model lineup

| Profile | Model | Quant | On-disk | Use |
|---|---|---|---|---|
| `qwen3.6-35b-a3b` | Qwen3.6-35B-A3B MoE | Q4_K_M | ~21 GB | Primary; ~12-18 tok/s on CPU |
| `qwen3.6-27b` | Qwen3.6-27B dense | Q5_K_M | ~20 GB | Quality-first, slow (~2 tok/s) |
| `qwen3.5-9b` | Qwen3.5-9B dense | Q5_K_M | ~6.5 GB | Interactive mid-tier |
| `qwen3.5-4b` | Qwen3.5-4B dense | Q5_K_M | ~3 GB | Quick completions |
| `qwen3.5-0.8b` | Qwen3.5-0.8B dense | Q6_K | ~0.8 GB | Drafts, titles, agent scaffolding |
| `gemma4-e4b` | Gemma 4 E4B instruct | Q5_K_M | ~6 GB | Google family mid |
| `gemma4-e2b` | Gemma 4 E2B instruct | Q6_K | ~4 GB | Google family small |

Quant choice skews higher than the "just fit in RAM" default because
capacity is plentiful here; the bandwidth ceiling dominates regardless
of quant, so going from Q4 to Q5/Q6 costs little additional time and
noticeably improves quality.

## Sampler and thinking-mode defaults

Every profile starts with `--chat-template-kwargs '{"enable_thinking":
false}'`. Qwen3.6 and Gemma 4 default thinking on in their chat
templates, which burns response tokens on a reasoning monologue and
returns empty `content` on small `max_tokens` calls. Defaulting off
means basic chat requests return clean answers; enable thinking per
request when wanted:

```json
{
  "model": "qwen3.6-35b-a3b",
  "messages": [...],
  "chat_template_kwargs": {"enable_thinking": true}
}
```

llama.cpp's server honours request-level `chat_template_kwargs` and
overrides the CLI default.

Sampler flags in `configmap.yaml` follow Unsloth's published
recommendations for **non-thinking / instruct mode**:

- **Qwen3.6 and Qwen3.5** (instruct, general): temp 0.7, top_p 0.8,
  top_k 20, min_p 0.0, presence_penalty 1.5, repeat_penalty 1.0.
- **Gemma 4**: temp 1.0, top_p 0.95, top_k 64, repetition penalty
  disabled.

API clients override any sampler per request. A `temperature: 0`
field wins over the server default, so deterministic calls work
without restarting anything.

## Swap behaviour

`ttl: 600` unloads a model after 10 minutes of idleness. The next
request pays a cold-start cost (~20-40 s for the big MoE, seconds for
the small models) while llama-swap starts a new llama-server
subprocess and mmaps the weights. Active models stay resident as long
as requests keep arriving within the TTL window.

## First-boot model sync

The `model-sync` initContainer reads the idempotent shell script in
`model-sync.yaml` and pulls each GGUF via `uvx hf download` if
missing. The first Deployment roll blocks until ~60 GB downloads;
subsequent restarts are instant. Re-running after adding a new model
to the script downloads only the additions.

`HF_HUB_ENABLE_HF_TRANSFER=1` flips on the chunked parallel
downloader for roughly 2x throughput on a gigabit link.

### Wiring HF_TOKEN

Anonymous downloads work but hit HF's free-tier bandwidth. To use a
Pro token:

```sh
# 1. Paste the token into the plaintext template (read scope is
#    enough for GGUF downloads).
$EDITOR apps/llm/secrets.yaml

# 2. Encrypt in place. .sops.yaml already covers apps/*/secrets.ya?ml
#    and restricts encryption to data/stringData fields, leaving the
#    outer manifest structure parseable by kustomize and flux-local.
sops --encrypt --in-place apps/llm/secrets.yaml

# 3. Uncomment `- secrets.yaml` in apps/llm/kustomization.yaml, then
#    git add both files and commit. Flux decrypts via its sops-age key
#    at reconcile time and the pod picks up HF_TOKEN on next restart.
```

## Verifying

```bash
kubectl -n llm get pods -w
# wait for initContainer model-sync to finish and llama-swap to go Ready

# health
curl -sS https://llm.farooqui.ai/health

# list models
curl -sS https://llm.farooqui.ai/v1/models | jq

# chat (triggers cold-start of the named profile; start with the
# tiny one to prove the path before loading the 35B MoE)
curl -sS https://llm.farooqui.ai/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
        "model": "qwen3.5-0.8b",
        "messages": [{"role":"user","content":"In one sentence, what is k3s?"}],
        "max_tokens": 120
      }' | jq -r '.choices[0].message.content'
```

From off-tailnet the DNS resolves to the CGNAT address and the TLS
handshake never completes.
