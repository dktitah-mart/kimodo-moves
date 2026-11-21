# Licences

This is a list of what each piece is licensed under, not legal advice. If you ship moves in a commercial product,
have someone who is qualified read the model licences.

| Piece | Licence | Notes |
|---|---|---|
| This repository: the add-on, the Godot scripts and the docs | Apache-2.0 (`LICENSE`) | |
| Kimodo code (nv-tlabs/kimodo), installed by `setup.sh` at a pinned commit | Apache-2.0 | |
| Kimodo SOMA weights, RP v1.1 and SEED v1.1 (`nvidia/…`) | NVIDIA Open Model License | Fetched by `get_weights.sh`. The licence covers the weights and says what you may do with their output. |
| Kimodo SMPL-X models | NVIDIA research licence | **Not used.** The add-on offers the SOMA models only. |
| LLM2Vec adapters (McGill-NLP) | MIT | Built on Llama 3. |
| Meta-Llama-3-8B-Instruct, from Meta or from an open copy such as NousResearch | Meta Llama 3 Community License | Includes an acceptable use policy and a 700-million-monthly-user threshold. |
| AssetFurnace | Apache-2.0 | Not included here; the add-on runs inside it. |

The text encoder runs only on your machine, to turn the prompt into numbers for Kimodo. What you put in a game is
Kimodo's output: joint rotations. Llama 3 is not part of your product. Even so, read both model licences yourself.

Every run writes a `provenance.json` with the prompt, seed, model and licences. Keep these files with the moves you
ship.
