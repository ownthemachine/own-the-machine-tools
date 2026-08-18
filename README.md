# own-the-machine-tools

The review machinery for the [own-the-machine](https://github.com/thetwit4u/own-the-machine)
draft EU Regulation: the adversarial gate runner, the six gate prompts and
the mechanical linter. Split out so the law repository stays a civic
artefact (text, evidence, governance and the ledger of its own evolution)
while the workshop lives here.

This is machinery, not policy. The normative documents (GOVERNANCE.md,
DRAFTING-RULES.md, the constraints table) live with the law; the prompts
here enforce them and cite them by path. Review OUTPUTS also live with the
law, under pipeline/reviews/, because a verdict on a statute is part of the
statute's history, not of the tooling.

## Use

    export OPENROUTER_API_KEY=...           # never committed anywhere
    python3 lint-legislation.py             # run from the law repo root
    ./review.sh <bundle.md> <out.md> prompts/<gate>.md

Gate order and model-tier guidance: pipeline/README.md in the law repo.

## Disclosure

Reviews are run adversarially by AI under the editor's responsibility, and
every verdict is committed to the law repository, failed rounds included.
This repo exists so that claim is inspectable, not decorative.

Licence: MIT. Reuse for your own legislation welcome; the prompts are the
interesting part.
